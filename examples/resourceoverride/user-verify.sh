#!/bin/bash
set -o nounset
set -o pipefail

###############################################################################
# Verifies that user-setup.sh ran successfully for your USER_TAG and that the
# baseline CRP/RP have rolled out to at least one member cluster.
#
#   export USER_TAG=<your-initials>
#   ./user-verify.sh
###############################################################################

USER_TAG="${USER_TAG:?USER_TAG not set — run: export USER_TAG=<your-initials>}"
NS="test-ns-${USER_TAG}"
CR="secret-reader-${USER_TAG}"
CRP="example-crp-${USER_TAG}"
RP="example-rp-${USER_TAG}"

FAILED=0

check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  OK   $label"
    else
        echo "  FAIL $label"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== Hub objects (USER_TAG=${USER_TAG}) ==="
check "namespace $NS"              kubectl get ns "$NS"
check "clusterrole $CR"            kubectl get clusterrole "$CR"
check "deployment nginx in $NS"    kubectl get deploy nginx -n "$NS"
check "configmap my-config in $NS" kubectl get cm my-config -n "$NS"
check "service my-service in $NS"  kubectl get svc my-service -n "$NS"
check "CRP $CRP"                   kubectl get crp "$CRP"
check "RP $RP in $NS"              kubectl get rp "$RP" -n "$NS"

echo ""
echo "=== CRP rollout status ==="
CRP_APPLIED=$(kubectl get crp "$CRP" -o jsonpath='{.status.conditions[?(@.type=="ClusterResourcePlacementApplied")].status}' 2>/dev/null || true)
CRP_REASON=$(kubectl get crp "$CRP" -o jsonpath='{.status.conditions[?(@.type=="ClusterResourcePlacementApplied")].reason}' 2>/dev/null || true)
echo "  Applied=${CRP_APPLIED:-<unknown>} Reason=${CRP_REASON:-<none>}"
if [ "$CRP_APPLIED" != "True" ]; then
    echo "  (If this stays non-True for >60s, check 'kubectl describe crp $CRP'.)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Member clusters seen by the CRP ==="
kubectl get crp "$CRP" -o jsonpath='{range .status.placementStatuses[*]}{.clusterName}{"\n"}{end}' 2>/dev/null \
    | sed 's/^/  /' || echo "  <no placement statuses yet>"

echo ""
echo "=== Quick member-side check (first -admin context found) ==="
MEMBER_CTX=$(kubectl config get-contexts -o name 2>/dev/null | grep -- '-admin$' | head -1 || true)
if [ -z "$MEMBER_CTX" ]; then
    echo "  SKIP — no <member>-admin kubectl context found."
    echo "  Fetch one with: az aks get-credentials -g <RG> -n <member-name> --admin"
else
    echo "  Using context: $MEMBER_CTX"
    check "namespace $NS on member"         kubectl --context="$MEMBER_CTX" get ns "$NS"
    check "deployment nginx on member"      kubectl --context="$MEMBER_CTX" get deploy nginx -n "$NS"
    check "clusterrole $CR on member"       kubectl --context="$MEMBER_CTX" get clusterrole "$CR"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "All checks passed."
else
    echo "$FAILED check(s) failed. See above."
    exit 1
fi
