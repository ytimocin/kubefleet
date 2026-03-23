#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

###############################################################################
# Per-user bug bash setup. Requires the shared fleet to already exist (via
# setup-override-bug-bash.sh) and your kubeconfig to point at the hub.
#
# Creates isolated per-user copies of the baseline objects so multiple people
# can run scenarios against the same fleet without colliding on names or
# target resources.
#
#   export USER_TAG=<your-initials>   # lowercase, e.g. "yti"
#   ./user-setup.sh
#
# Teardown: ./user-teardown.sh
###############################################################################

USER_TAG="${USER_TAG:?USER_TAG not set — run: export USER_TAG=<your-initials>}"
NS="test-ns-${USER_TAG}"
CR="secret-reader-${USER_TAG}"
CRP="example-crp-${USER_TAG}"
RP="example-rp-${USER_TAG}"

if ! kubectl get memberclusters >/dev/null 2>&1; then
    echo "ERROR: kubectl can't list memberclusters — kubeconfig isn't pointing at the fleet hub,"
    echo "       or you don't have the 'Azure Kubernetes Fleet Manager RBAC Cluster Admin' role."
    echo ""
    echo "Fetch hub credentials with:"
    echo "  az fleet get-credentials -g override-bug-bash-rg -n override-bug-bash-fleet"
    echo ""
    echo "Adjust -g and -n if the shared fleet was created with different names."
    exit 1
fi

echo "Creating per-user objects for USER_TAG=${USER_TAG}..."

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${CR}
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "watch", "list"]
EOF

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: ${NS}
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

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
  namespace: ${NS}
data:
  environment: "default"
  log-level: "info"
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: ${NS}
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
EOF

kubectl apply -f - <<EOF
apiVersion: placement.kubernetes-fleet.io/v1
kind: ClusterResourcePlacement
metadata:
  name: ${CRP}
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      version: v1
      name: ${NS}
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
      version: v1
      name: ${CR}
  policy:
    placementType: PickAll
EOF

kubectl apply -f - <<EOF
apiVersion: placement.kubernetes-fleet.io/v1beta1
kind: ResourcePlacement
metadata:
  name: ${RP}
  namespace: ${NS}
spec:
  resourceSelectors:
    - group: ""
      kind: ConfigMap
      version: v1
      name: my-config
  policy:
    placementType: PickAll
EOF

echo "Done. Your namespace is ${NS}, your CRP is ${CRP}, your RP is ${RP}."
echo "Apply scenarios with: envsubst < <file>.yaml | kubectl apply -f -"
