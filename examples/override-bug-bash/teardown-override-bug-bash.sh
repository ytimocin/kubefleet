#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

###############################################################################
# Resource Override Bug Bash - Teardown Script
#
# Deletes the entire resource group created by setup-override-bug-bash.sh.
#
# Usage:
#   export SUBSCRIPTION="<your-subscription-id>"
#   ./teardown-override-bug-bash.sh
###############################################################################

if [ -z "${SUBSCRIPTION:-}" ]; then
    echo "ERROR: SUBSCRIPTION env var is not set."
    exit 1
fi

RG="${RG:-override-bug-bash-rg}"
FLEET_NAME="${FLEET_NAME:-override-bug-bash-fleet}"
MEMBER_1_NAME="${MEMBER_1_NAME:-member-westus2-1}"
MEMBER_2_NAME="${MEMBER_2_NAME:-member-westus2-2}"
MEMBER_3_NAME="${MEMBER_3_NAME:-member-centralus-1}"

echo "============================================="
echo " Resource Override Bug Bash Teardown"
echo "============================================="
echo " Resource Group: $RG"
echo "============================================="
echo ""

az account set --subscription "$SUBSCRIPTION"

# Check if resource group exists
if ! az group show --name "$RG" --output none 2>/dev/null; then
    echo "Resource group $RG does not exist. Nothing to delete."
else
    echo "This will DELETE the entire resource group: $RG"
    echo "This includes the Fleet, all AKS clusters, and all resources."
    read -p "Are you sure? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi

    echo "Deleting resource group $RG (this may take several minutes)..."
    az group delete --name "$RG" --yes --no-wait

    echo ""
    echo "Resource group deletion initiated (running in background)."
    echo "Monitor with: az group show -n $RG --query properties.provisioningState -o tsv"
fi

# Clean up kubectl contexts
echo ""
echo "Cleaning up local kubectl contexts..."
for CTX in "hub" "$FLEET_NAME" "${MEMBER_1_NAME}-admin" "${MEMBER_2_NAME}-admin" "${MEMBER_3_NAME}-admin"; do
    kubectl config delete-context "$CTX" 2>/dev/null && echo "  Removed context: $CTX" || true
done

for CLUSTER in "hub" "$FLEET_NAME" "$MEMBER_1_NAME" "$MEMBER_2_NAME" "$MEMBER_3_NAME"; do
    kubectl config delete-cluster "$CLUSTER" 2>/dev/null || true
    kubectl config delete-user "clusterUser_${RG}_${CLUSTER}" 2>/dev/null || true
done

echo ""
echo "Teardown complete."
