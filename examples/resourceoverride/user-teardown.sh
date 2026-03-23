#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

###############################################################################
# Deletes per-user objects created by user-setup.sh. Leaves the shared fleet
# and its member clusters alone.
#
#   export USER_TAG=<your-initials>
#   ./user-teardown.sh
###############################################################################

USER_TAG="${USER_TAG:?USER_TAG not set — run: export USER_TAG=<your-initials>}"
NS="test-ns-${USER_TAG}"
CR="secret-reader-${USER_TAG}"
CRP="example-crp-${USER_TAG}"
RP="example-rp-${USER_TAG}"

echo "Removing per-user objects for USER_TAG=${USER_TAG}..."

# Delete any overrides the user may have left behind. Labels aren't set on
# our example YAMLs, so match by name suffix in cluster-scope and by
# namespace for namespace-scope.
kubectl get clusterresourceoverride -o name 2>/dev/null \
    | grep -- "-${USER_TAG}$" \
    | xargs -r kubectl delete --ignore-not-found || true

kubectl delete resourceoverride --all -n "$NS" --ignore-not-found || true

kubectl delete crp "$CRP" --ignore-not-found || true
kubectl delete rp "$RP" -n "$NS" --ignore-not-found || true
kubectl delete clusterrole "$CR" --ignore-not-found || true
kubectl delete namespace "$NS" --ignore-not-found || true

echo "Done."
