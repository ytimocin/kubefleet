# Resource Override Bug Bash - Test Results

**Date:** March 23, 2026
**Fleet:** override-bug-bash-fleet (westus2)
**Clusters:**

| Name | Labels |
|------|--------|
| member-westus2-1 | env=prod, region=westus2, tier=frontend |
| member-westus2-2 | env=staging, region=westus2, tier=backend |
| member-centralus-1 | env=prod, region=centralus, tier=frontend |

---

## Test 1: CRO - Add annotation to all clusters (empty clusterSelectorTerms)

**Scenario:** CRO with `clusterSelectorTerms: []` adds `environment: fleet-managed` to `secret-reader` ClusterRole.

**Result: PASS**

- Hub: `OverriddenSucceeded` on all 3 clusters, snapshot `example-cro-0` listed for all
- Member verification:
  - member-westus2-1: `environment: fleet-managed`
  - member-westus2-2: `environment: fleet-managed`
  - member-centralus-1: `environment: fleet-managed`

---

## Test 2: RO - Replace image on env=prod clusters only

**Scenario:** RO with `matchLabels: env: prod` replaces nginx image to `nginx:1.27.3`.

**Result: PASS**

- Hub: `OverriddenSucceeded` on all clusters, `ro-prod-image-0` listed for both prod clusters only
- Member verification:
  - member-westus2-1 (env=prod): `nginx:1.27.3`
  - member-centralus-1 (env=prod): `nginx:1.27.3`
  - member-westus2-2 (env=staging): `nginx:1.27.0` (unchanged, correct)

**Note from earlier run:** The bug bash doc originally used `nginx:1.30.0` which does not exist on Docker Hub. This caused `ImagePullBackOff` on the first cluster, which made Fleet mark it `Available=False`, which blocked the rolling update to the second prod cluster. Doc has been fixed to use `nginx:1.27.3`.

---

## Test 3: CRO - Wrong PlacementRef (should be silently skipped)

**Scenario:** CRO with `placement.name: non-existent-crp` should not apply to any cluster.

**Result: PASS**

- CRO accepted by API server
- `should-not-appear` annotation absent on all member clusters
- CRP status did not list `cro-wrong-ref` under any cluster's applicable overrides

---

## Test 4: CRO - Delete Override Type

**Scenario:** CRO with `overrideType: Delete` targeting `region=centralus` clusters. The `test-namespace` should be deleted on matching clusters but remain on others.

**Result: PASS**

- Hub: `OverriddenSucceeded` on all clusters, `cro-delete-centralus-0` listed for member-centralus-1
- Member verification:
  - member-centralus-1 (region=centralus): `test-namespace` NOT FOUND (deleted, correct)
  - member-westus2-1: `test-namespace` Active
  - member-westus2-2: `test-namespace` Active

---

## Test 5: RO - Reserved Variable `${MEMBER-CLUSTER-NAME}`

**Scenario:** RO adds `source-cluster` annotation to `my-service` using `${MEMBER-CLUSTER-NAME}`. Each cluster should get its own name substituted.

**Result: PASS**

- Hub: `OverriddenSucceeded` on all clusters, `ro-cluster-name-0` listed for all
- Member verification:
  - member-westus2-1: `source-cluster: member-westus2-1`
  - member-westus2-2: `source-cluster: member-westus2-2`
  - member-centralus-1: skipped (namespace deleted by Test 4)

---

## Test 6: RO - Multiple Override Rules (different overrides per environment)

**Scenario:** Single RO with two `overrideRules`: prod clusters get `replicas: 3`, staging clusters get `replicas: 1`.

**Result: PASS**

- Hub: `OverriddenSucceeded` on all clusters, `ro-per-env-0` listed for all
- Member verification:
  - member-westus2-1 (env=prod): `replicas: 3`
  - member-westus2-2 (env=staging): `replicas: 1`
  - member-centralus-1: skipped (namespace deleted by Test 4)

---

## Test 7: Validation - Two CROs selecting the same resource

**Scenario:** Create two CROs both selecting `secret-reader` ClusterRole. Webhook should reject the second.

**Result: BUG FOUND - Webhook bypass via v1 API**

- Using `apiVersion: placement.kubernetes-fleet.io/v1`: both CROs were accepted (no rejection)
- Using `apiVersion: placement.kubernetes-fleet.io/v1beta1`: second CRO correctly rejected with `"the resource has been selected by both cro-second-beta and cro-first-beta, which is not supported"`

**Root cause:** The validating webhook `fleet.clusterresourceoverride.validating` is configured with `apiVersions: ["v1beta1"]` only. Requests using the `v1` API version bypass the webhook entirely. Despite `matchPolicy: Equivalent`, the conversion does not trigger validation.

**Impact:** All webhook validations (duplicate resource selectors, invalid paths, etc.) can be bypassed by using `v1` instead of `v1beta1`. In our tests, the invalid path tests (Test 8, 9) used `v1` and were still rejected — likely because those validations are also enforced via CEL/CRD-level validation, not just the webhook. But the duplicate resource selector check is webhook-only and is fully bypassed.

**Recommendation:** Update the webhook configuration to include `apiVersions: ["v1", "v1beta1"]`.

---

## Test 8: Validation - Invalid JSON patch paths

**Scenario:** Try creating CROs with invalid paths: `/metadata/name`, `/kind`, `/status`.

**Result: PASS (all 3 rejected)**

- `/metadata/name`: `"cannot override metadata fields except annotations and labels"`
- `/kind`: `"cannot override typeMeta fields"`
- `/status`: `"cannot override status fields"`

---

## Test 9: Validation - Remove operation with a value

**Scenario:** Create CRO with `op: remove` and a `value` field.

**Result: PASS (rejected)**

- Webhook error: `"remove operation cannot have value"`

---

## Test 10: Validation - Immutable placement field

**Scenario:** Create CRO, then try to change `placement.name`.

**Result: PASS (rejected on update)**

- Initial create succeeded
- Update rejected with: `"The placement field is immutable"`

---

## Test 11: Validation - Incorrect JSON patch path on the resource (runtime failure)

**Scenario:** Create RO with `replace` on `/spec/nonExistentField`. Should be accepted by webhook but fail at runtime.

**Result: PASS**

- RO was accepted by webhook (no rejection)
- CRP status showed `Overridden=False`, `Reason: OverriddenFailed`
- Message: `"replace operation does not apply: doc is missing key: /spec/nonExistentField: missing value"`

---

## Test 12: Advanced - matchExpressions (In operator)

**Scenario:** RO using `matchExpressions` with `key: env, operator: In, values: ["prod", "staging"]` to add annotation to nginx Deployment.

**Result: PASS**

- All 3 clusters matched (both `env=prod` and `env=staging` satisfy the `In` expression)
- Annotation `fleet-managed: true` present on all clusters

---

## Test 13: Override Cleanup (snapshots deleted, resources revert)

**Scenario:** Create CRO, verify snapshot and annotation on member, delete CRO, verify cleanup.

**Result: PASS**

- Before deletion: snapshot `cro-cleanup-test-0` existed, annotation `cleanup-test: should-disappear` present on member
- After deletion:
  - Snapshots: `No resources found`
  - CRP: no applicable overrides listed
  - Member cluster: annotation gone

---

## Test 14: Snapshot Versioning

**Scenario:** Create CRO, update spec, verify new snapshot. Then no-op update, verify no new snapshot.

**Result: PASS**

- Initial: snapshot `cro-snapshot-test-0` (index=0, latest=true)
- After spec update: `cro-snapshot-test-0` (latest=false), `cro-snapshot-test-1` (index=1, latest=true)
- After no-op metadata annotation: still 2 snapshots (hash dedup worked)

---

## Summary

| Test | Scenario | Result |
|------|----------|--------|
| 1 | CRO add annotation to all clusters | PASS |
| 2 | RO replace image on env=prod only | PASS |
| 3 | CRO with wrong PlacementRef | PASS |
| 4 | Delete override type | PASS |
| 5 | Reserved variable `${MEMBER-CLUSTER-NAME}` | PASS |
| 6 | Multiple override rules per environment | PASS |
| 7 | Two CROs selecting same resource | **BUG** (v1 bypasses webhook, v1beta1 correctly rejects) |
| 8 | Invalid JSON patch paths | PASS |
| 9 | Remove with value | PASS |
| 10 | Immutable placement field | PASS |
| 11 | Invalid path on resource (runtime) | PASS |
| 12 | matchExpressions In operator | PASS |
| 13 | Override cleanup | PASS |
| 14 | Snapshot versioning + hash dedup | PASS |
