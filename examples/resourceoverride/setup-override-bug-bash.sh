#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

###############################################################################
# Resource Override Bug Bash - Fleet Setup Script
#
# Creates an Azure Fleet Manager with 3 member AKS clusters, labels them,
# deploys target resources, and creates baseline CRP/RP for override testing.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - kubectl installed
#   - SUBSCRIPTION env var set (Azure subscription ID)
#
# Usage:
#   export SUBSCRIPTION="<your-subscription-id>"
#   ./setup-override-bug-bash.sh
#
# Teardown:
#   ./teardown-override-bug-bash.sh
###############################################################################

# --- Required ---
if [ -z "${SUBSCRIPTION:-}" ]; then
    echo "ERROR: SUBSCRIPTION env var is not set."
    echo "Usage: export SUBSCRIPTION=<your-subscription-id> && ./setup-override-bug-bash.sh"
    exit 1
fi

# --- Configuration (override via env vars) ---
RG="${RG:-override-bug-bash-rg}"
LOCATION="${LOCATION:-southcentralus}"
FLEET_NAME="${FLEET_NAME:-override-bug-bash-fleet}"
MEMBER_1_NAME="${MEMBER_1_NAME:-member-southcentralus-1}"
MEMBER_2_NAME="${MEMBER_2_NAME:-member-southcentralus-2}"
MEMBER_3_NAME="${MEMBER_3_NAME:-member-southcentralus-3}"
MEMBER_1_LOCATION="${MEMBER_1_LOCATION:-southcentralus}"
MEMBER_2_LOCATION="${MEMBER_2_LOCATION:-southcentralus}"
MEMBER_3_LOCATION="${MEMBER_3_LOCATION:-southcentralus}"
VM_SIZE="${VM_SIZE:-Standard_D2s_v3}"
NODE_COUNT="${NODE_COUNT:-1}"
K8S_VERSION="${K8S_VERSION:-1.34}"

echo "============================================="
echo " Resource Override Bug Bash Setup"
echo "============================================="
echo " Subscription:  $SUBSCRIPTION"
echo " Resource Group: $RG"
echo " Location:       $LOCATION"
echo " Fleet:          $FLEET_NAME"
echo " Members:        $MEMBER_1_NAME, $MEMBER_2_NAME, $MEMBER_3_NAME"
echo "============================================="
echo ""

# --- Step 1: Set subscription ---
echo "[1/9] Setting Azure subscription..."
az account set --subscription "$SUBSCRIPTION"

# --- Step 2: Create resource group ---
echo "[2/9] Creating resource group $RG..."
az group create --name "$RG" --location "$LOCATION" --output none

# --- Step 3: Create Fleet with hub ---
echo "[3/9] Creating Fleet Manager $FLEET_NAME with hub cluster..."
if az fleet show --resource-group "$RG" --name "$FLEET_NAME" --output none 2>/dev/null; then
    echo "  Fleet already exists, skipping creation."
else
    az fleet create \
        --resource-group "$RG" \
        --name "$FLEET_NAME" \
        --location "$LOCATION" \
        --enable-hub \
        --vm-size "$VM_SIZE" \
        --output none

    echo "  Waiting for Fleet hub to be ready..."
    az fleet wait \
        --resource-group "$RG" \
        --fleet-name "$FLEET_NAME" \
        --created \
        --interval 30 \
        --timeout 600 2>/dev/null || true
fi

# --- Step 4: Create AKS member clusters ---
echo "[4/9] Creating AKS member clusters (this takes ~5-10 minutes)..."

for MEMBER_NAME in "$MEMBER_1_NAME" "$MEMBER_2_NAME" "$MEMBER_3_NAME"; do
    if [ "$MEMBER_NAME" = "$MEMBER_1_NAME" ]; then MEMBER_LOC="$MEMBER_1_LOCATION";
    elif [ "$MEMBER_NAME" = "$MEMBER_2_NAME" ]; then MEMBER_LOC="$MEMBER_2_LOCATION";
    else MEMBER_LOC="$MEMBER_3_LOCATION"; fi

    if az aks show --resource-group "$RG" --name "$MEMBER_NAME" --output none 2>/dev/null; then
        echo "  $MEMBER_NAME already exists, skipping creation."
    else
        echo "  Creating $MEMBER_NAME in $MEMBER_LOC..."
        az aks create \
            --resource-group "$RG" \
            --name "$MEMBER_NAME" \
            --location "$MEMBER_LOC" \
            --node-count "$NODE_COUNT" \
            --node-vm-size "$VM_SIZE" \
            --kubernetes-version "$K8S_VERSION" \
            --generate-ssh-keys \
            --enable-managed-identity \
            --output none \
            --no-wait
    fi
done

echo "  Waiting for all clusters to finish provisioning..."
az aks wait --resource-group "$RG" --name "$MEMBER_1_NAME" --created --interval 30 --timeout 900
az aks wait --resource-group "$RG" --name "$MEMBER_2_NAME" --created --interval 30 --timeout 900
az aks wait --resource-group "$RG" --name "$MEMBER_3_NAME" --created --interval 30 --timeout 900

echo "  Verifying all clusters are in Succeeded state..."
for CLUSTER in "$MEMBER_1_NAME" "$MEMBER_2_NAME" "$MEMBER_3_NAME"; do
    STATE=$(az aks show --resource-group "$RG" --name "$CLUSTER" --query "provisioningState" --output tsv)
    echo "    $CLUSTER: $STATE"
    if [ "$STATE" != "Succeeded" ]; then
        echo "  ERROR: $CLUSTER is not in Succeeded state. Waiting for it..."
        az aks wait --resource-group "$RG" --name "$CLUSTER" --updated --interval 15 --timeout 600
    fi
done
echo "  All clusters provisioned."

# --- Step 5: Join clusters to fleet ---
echo "[5/9] Joining member clusters to fleet..."

for MEMBER_NAME in "$MEMBER_1_NAME" "$MEMBER_2_NAME" "$MEMBER_3_NAME"; do
    if az fleet member show --resource-group "$RG" --fleet-name "$FLEET_NAME" --name "$MEMBER_NAME" --output none 2>/dev/null; then
        echo "  $MEMBER_NAME already joined, skipping."
    else
        # Ensure AKS is in a terminal state before joining — background updates
        # (node image rotation, identity propagation) can flip it to Updating
        # shortly after create-complete, which rejects `az fleet member create`.
        JOIN_ATTEMPTS=0
        MAX_JOIN_ATTEMPTS=5
        while true; do
            STATE=$(az aks show --resource-group "$RG" --name "$MEMBER_NAME" --query "provisioningState" --output tsv)
            if [ "$STATE" = "Succeeded" ] || [ "$STATE" = "Canceled" ] || [ "$STATE" = "Failed" ]; then
                break
            fi
            JOIN_ATTEMPTS=$((JOIN_ATTEMPTS + 1))
            if [ "$JOIN_ATTEMPTS" -ge "$MAX_JOIN_ATTEMPTS" ]; then
                echo "  ERROR: $MEMBER_NAME stuck in $STATE after $MAX_JOIN_ATTEMPTS checks."
                exit 1
            fi
            echo "  $MEMBER_NAME is in $STATE state, waiting for terminal state..."
            az aks wait --resource-group "$RG" --name "$MEMBER_NAME" --updated --interval 15 --timeout 600 || true
        done

        MEMBER_ID=$(az aks show --resource-group "$RG" --name "$MEMBER_NAME" --query id --output tsv)
        az fleet member create \
            --resource-group "$RG" \
            --fleet-name "$FLEET_NAME" \
            --name "$MEMBER_NAME" \
            --member-cluster-id "$MEMBER_ID" \
            --output none
        echo "  $MEMBER_NAME joined."
    fi
done

echo "  All members joined."

# --- Step 6: Label member clusters ---
echo "[6/9] Labeling member clusters..."

az fleet member update \
    --resource-group "$RG" \
    --fleet-name "$FLEET_NAME" \
    --name "$MEMBER_1_NAME" \
    --member-labels "env=prod region=$MEMBER_1_LOCATION tier=frontend" \
    --output none

az fleet member update \
    --resource-group "$RG" \
    --fleet-name "$FLEET_NAME" \
    --name "$MEMBER_2_NAME" \
    --member-labels "env=staging region=$MEMBER_2_LOCATION tier=backend" \
    --output none

az fleet member update \
    --resource-group "$RG" \
    --fleet-name "$FLEET_NAME" \
    --name "$MEMBER_3_NAME" \
    --member-labels "env=prod region=$MEMBER_3_LOCATION tier=frontend" \
    --output none

echo "  Labels applied:"
echo "    $MEMBER_1_NAME: env=prod, region=$MEMBER_1_LOCATION, tier=frontend"
echo "    $MEMBER_2_NAME: env=staging, region=$MEMBER_2_LOCATION, tier=backend"
echo "    $MEMBER_3_NAME: env=prod, region=$MEMBER_3_LOCATION, tier=frontend"

# --- Step 7: Get fleet hub credentials ---
echo "[7/9] Getting fleet hub credentials and ensuring RBAC access..."

FLEET_ID=$(az fleet show --resource-group "$RG" --name "$FLEET_NAME" --query id --output tsv)
USER_UPN=$(az account show --query "user.name" --output tsv)

echo "  Assigning Fleet RBAC Cluster Admin role to $USER_UPN..."
az role assignment create \
    --assignee "$USER_UPN" \
    --role "Azure Kubernetes Fleet Manager RBAC Cluster Admin" \
    --scope "$FLEET_ID" \
    --output none 2>/dev/null || echo "  Role already assigned or requires portal assignment (see README)."

az fleet get-credentials \
    --resource-group "$RG" \
    --name "$FLEET_NAME" \
    --overwrite-existing

# Wait for member clusters to be ready in the hub
echo "  Waiting for MemberCluster objects to appear in hub..."
RETRIES=0
MAX_RETRIES=30
while true; do
    READY_COUNT=$(kubectl get memberclusters --no-headers 2>/dev/null | grep -c "True" || true)
    if [ "$READY_COUNT" -ge 3 ]; then
        echo "  All 3 member clusters joined and ready."
        break
    fi
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
        echo "  WARNING: Timed out waiting for all members. Current ready: $READY_COUNT/3"
        echo "  Continuing anyway - check 'kubectl get memberclusters' manually."
        break
    fi
    echo "  Ready: $READY_COUNT/3 - waiting 20s... (attempt $RETRIES/$MAX_RETRIES)"
    sleep 20
done

# --- Step 8: Deploy target resources on hub ---
echo "[8/9] Deploying target resources on hub cluster..."

# Namespace
kubectl create namespace test-namespace --dry-run=client -o yaml | kubectl apply -f -

# ClusterRole (for CRO testing)
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secret-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "watch", "list"]
EOF

# Deployment (for RO testing)
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: test-namespace
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27.0
          ports:
            - containerPort: 80
EOF

# ConfigMap (for RO + RP testing)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
  namespace: test-namespace
data:
  environment: "default"
  log-level: "info"
EOF

# Service (for reserved variable testing)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: test-namespace
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
EOF

echo "  Target resources created: Namespace, ClusterRole, Deployment, ConfigMap, Service"

# --- Step 9: Create baseline CRP and RP ---
echo "[9/9] Creating baseline ClusterResourcePlacement and ResourcePlacement..."

# CRP - selects the test-namespace and its resources + the ClusterRole
kubectl apply -f - <<'EOF'
apiVersion: placement.kubernetes-fleet.io/v1
kind: ClusterResourcePlacement
metadata:
  name: example-crp
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      version: v1
      name: test-namespace
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
      version: v1
      name: secret-reader
  policy:
    placementType: PickAll
EOF

# RP - selects resources within test-namespace (for namespace-scoped placement testing)
kubectl apply -f - <<'EOF'
apiVersion: placement.kubernetes-fleet.io/v1beta1
kind: ResourcePlacement
metadata:
  name: example-rp
  namespace: test-namespace
spec:
  resourceSelectors:
    - group: ""
      kind: ConfigMap
      version: v1
      name: my-config
  policy:
    placementType: PickAll
EOF

echo "  Placements created: example-crp (cluster-scope), example-rp (namespace-scope)"

# --- Wait for placement to propagate ---
echo ""
echo "Waiting for resource placement to propagate (up to 2 minutes)..."
RETRIES=0
MAX_RETRIES=12
while true; do
    CRP_STATUS=$(kubectl get crp example-crp -o jsonpath='{.status.conditions[?(@.type=="ClusterResourcePlacementApplied")].status}' 2>/dev/null || true)
    if [ "$CRP_STATUS" = "True" ]; then
        echo "  CRP resources successfully placed on member clusters."
        break
    fi
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
        echo "  WARNING: CRP placement not yet confirmed. Check 'kubectl describe crp example-crp'."
        break
    fi
    echo "  Placement pending - waiting 10s... (attempt $RETRIES/$MAX_RETRIES)"
    sleep 10
done

# --- Summary ---
echo ""
echo "============================================="
echo " Setup Complete!"
echo "============================================="
echo ""
echo "Fleet hub context is active. Verify with:"
echo "  kubectl get memberclusters --show-labels"
echo "  kubectl describe crp example-crp"
echo "  kubectl describe rp example-rp -n test-namespace"
echo ""
echo "Member cluster credentials (for verification on members):"
echo "  az aks get-credentials -g $RG -n $MEMBER_1_NAME --admin"
echo "  az aks get-credentials -g $RG -n $MEMBER_2_NAME --admin"
echo "  az aks get-credentials -g $RG -n $MEMBER_3_NAME --admin"
echo ""
echo "Labels:"
echo "  $MEMBER_1_NAME: env=prod, region=$MEMBER_1_LOCATION, tier=frontend"
echo "  $MEMBER_2_NAME: env=staging, region=$MEMBER_2_LOCATION, tier=backend"
echo "  $MEMBER_3_NAME: env=prod, region=$MEMBER_3_LOCATION, tier=frontend"
echo ""
echo "Target resources on hub:"
echo "  - ClusterRole: secret-reader"
echo "  - Namespace: test-namespace"
echo "  - Deployment: test-namespace/nginx (image: nginx:1.27.0, replicas: 2)"
echo "  - ConfigMap: test-namespace/my-config"
echo "  - Service: test-namespace/my-service"
echo ""
echo "Placements:"
echo "  - example-crp (CRP) -> selects test-namespace + secret-reader ClusterRole"
echo "  - example-rp (RP)   -> selects test-namespace/my-config ConfigMap"
echo ""
echo "You're ready to run the bug bash scenarios!"
echo "============================================="
