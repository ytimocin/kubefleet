# Resource Override Bug Bash - Test Results (USER_TAG=yti)

**Date:** April 14, 2026
**Fleet:** override-bug-bash-fleet (southcentralus)
**Clusters:**

| Name | Labels |
|------|--------|
| member-southcentralus-1 | env=prod, region=southcentralus, tier=frontend |
| member-southcentralus-2 | env=staging, region=southcentralus, tier=backend |
| member-southcentralus-3 | env=prod, region=southcentralus, tier=frontend |

Run alongside (and compared to) `override-bug-bash-test-results.md` from 2026-03-23.

---

## Test 1: CRO — Add annotation to all clusters

**Scenario:** `01-cro-add-annotation-all.yaml` — CRO with empty `clusterSelectorTerms` adds `environment: fleet-managed` to `secret-reader-yti` ClusterRole.

**Result: PASS**

- Hub: `OverriddenSucceeded` on all 3 clusters; snapshot `example-cro-yti-0` listed for each.
- All 3 members had `environment: fleet-managed` annotation.

---

## Test 2: RO — Replace image on env=prod clusters only

**Scenario:** `04-ro-replace-image-prod.yaml` — RO patches nginx image to `nginx:1.27.3` where `env=prod`.

**Result: PASS**

- Hub: `OverriddenSucceeded`; `ro-prod-image-yti-0` listed for member-southcentralus-1 and -3 only.
- member-southcentralus-1 (prod): `nginx:1.27.3`
- member-southcentralus-2 (staging): `nginx:1.27.0` (unchanged)
- member-southcentralus-3 (prod): `nginx:1.27.3`

---

## Test 3: CRO — Wrong PlacementRef (silent skip)

**Scenario:** `11-cro-wrong-placement-ref-negative.yaml` — `placement.name: non-existent-crp-yti`.

**Result: PASS**

- CRO accepted by API server.
- `should-not-appear` annotation absent on all member namespaces.
- CRP status listed no applicable overrides for any cluster.

---

## Test 4: CRO — Delete Override Type

**Scenario:** `10-cro-delete-type.yaml` — annotate on `env=prod`, delete on `tier=backend`. (The `test-ns-yti` namespace is the target.)

**Result: PASS**

- Hub: `OverriddenSucceeded` on all clusters; `cro-delete-backend-yti-0` listed for all three.
- member-southcentralus-1 (env=prod): namespace present with `managed-by: fleet` annotation.
- member-southcentralus-2 (tier=backend): namespace NOT FOUND (deleted, correct).
- member-southcentralus-3 (env=prod): namespace present with `managed-by: fleet` annotation.

Cleanup restored the namespace on member-2 before subsequent tests.

---

## Test 5: RO — Reserved Variable `${MEMBER-CLUSTER-NAME}`

**Scenario:** `07-ro-member-cluster-name.yaml` — injects `fleet-${MEMBER-CLUSTER-NAME}` into a Service annotation.

**Result: PASS**

- All 3 members received their own name:
  - member-southcentralus-1: `fleet-member-southcentralus-1`
  - member-southcentralus-2: `fleet-member-southcentralus-2`
  - member-southcentralus-3: `fleet-member-southcentralus-3`

*(Prior run skipped one cluster because Test 4 had deleted its namespace. This run cleaned up Test 4 first, so all three were verified.)*

---

## Test 6: RO — Multiple Override Rules per Environment

**Scenario:** `06-ro-per-env.yaml` — prod clusters get `nginx:1.27.3`, staging gets `nginx:latest`.

**Result: PASS**

- member-southcentralus-1 (prod): `nginx:1.27.3`
- member-southcentralus-2 (staging): `nginx:latest`
- member-southcentralus-3 (prod): `nginx:1.27.3`

*(Same note as Test 5 — all three verified this run vs. a skip last time.)*

---

## Test 7: Validation — Two CROs selecting the same resource

**Scenario:** Apply one CRO on `secret-reader-yti`, then a second CRO on the same resource. Repeat for both `v1` and `v1beta1` API versions.

**Result: PASS (bug from prior run is now FIXED)**

- `v1`: second CRO rejected with webhook error `"the resource has been selected by both cro-second-v1-yti and cro-first-v1-yti, which is not supported"`.
- `v1beta1`: second CRO rejected with the same webhook error.

**Comparison to prior run:** The 2026-03-23 results documented `v1` bypassing the webhook entirely (`BUG FOUND`). That bug is no longer reproducible — both API versions now trigger the validating webhook. Presumably the webhook `apiVersions` list was extended to include `v1` (the recommendation from the prior report).

---

## Test 8: Validation — Invalid JSON patch paths

**Scenario:** `/metadata/name`, `/kind`, `/status`.

**Result: PASS (all 3 rejected)**

Error messages, verbatim:
- `/metadata/name`: `cannot override metadata fields except annotations and labels`
- `/kind`: `cannot override typeMeta fields`
- `/status`: `cannot override status fields`

---

## Test 9: Validation — `op: remove` with a value

**Scenario:** Apply CRO with `op: remove` + `value` on `/rules/0/verbs/0`.

**Result: PASS (rejected)**

- Webhook error: `remove operation cannot have value`.

---

## Test 10: Validation — Immutable placement field

**Scenario:** Create CRO, then `apply` an update that changes `placement.name`.

**Result: PASS (rejected on update)**

- Create: success.
- Update rejected: `spec: Invalid value: "object": The placement field is immutable`.

---

## Test 11: Validation — Invalid path on resource (runtime)

**Scenario:** RO with `replace` on `/spec/nonExistentField` against nginx Deployment.

**Result: PASS**

- RO accepted by webhook (valid syntax, target doesn't exist yet).
- Per-cluster `Overridden` condition on member-southcentralus-1: `False`, reason `OverriddenFailed`, message `Failed to apply the override rules on the resources: replace operation does not apply: doc is missing key: /spec/nonExistentField: missing value`.
- Members 2 and 3 have no Overridden condition — Fleet's rolling update held after the first failure, which is expected behavior.

---

## Test 12: Advanced — matchExpressions (`In` operator)

**Scenario:** `13-ro-match-expressions.yaml` — target clusters where `env In (prod, staging)`.

**Result: PASS**

- All 3 clusters matched; `fleet-managed: true` annotation present on all.

---

## Test 13: Override cleanup (delete → finalizer fires)

**Scenario:** Create CRO, confirm snapshot + annotation, delete CRO, confirm cleanup.

**Result: PASS**

- Before: snapshot `cro-cleanup-test-yti-0` existed, annotation `cleanup-test: should-disappear` on member-1.
- After delete: `No resources found` for snapshots, CRP applicable overrides empty on all clusters, annotation gone from member-1.

---

## Test 14: Snapshot versioning + hash dedup

**Scenario:** Create CRO, update spec (expect new snapshot), no-op annotate-only update (expect no new snapshot).

**Result: PASS**

- After create: one snapshot `cro-snapshot-test-yti-0` (latest=true).
- After spec change: two snapshots; `-0` latest=false, `-1` latest=true.
- After annotation-only update: still exactly two snapshots (hash dedup worked).

---

## Summary

| Test | Scenario | 2026-03-23 | 2026-04-14 (yti) |
|------|----------|------------|------------------|
| 1 | CRO add annotation to all | PASS | PASS |
| 2 | RO replace image on env=prod | PASS | PASS |
| 3 | CRO with wrong PlacementRef | PASS | PASS |
| 4 | CRO Delete override type | PASS | PASS |
| 5 | Reserved variable MEMBER-CLUSTER-NAME | PASS (1 skipped) | PASS (all 3 verified) |
| 6 | Multiple override rules per env | PASS (1 skipped) | PASS (all 3 verified) |
| 7 | Two CROs selecting same resource | **BUG** (v1 bypassed webhook) | **PASS** (both API versions reject) |
| 8 | Invalid JSON patch paths | PASS | PASS |
| 9 | Remove op with value | PASS | PASS |
| 10 | Immutable placement field | PASS | PASS |
| 11 | Invalid path on resource (runtime) | PASS | PASS |
| 12 | matchExpressions In | PASS | PASS |
| 13 | Override cleanup | PASS | PASS |
| 14 | Snapshot versioning + hash dedup | PASS | PASS |

**Diffs from prior run:**
1. **Test 7 bug is fixed.** The `v1` API now triggers the same validating webhook as `v1beta1`.
2. **Tests 5 and 6** ran on all three members this time because Test 4's namespace-delete was cleaned up before running them. The prior run left Test 4 active and lost coverage on one cluster.
3. Environment differences: region is now `southcentralus` (was `westus2` + `centralus`); member naming matches. Per-user isolation via `USER_TAG=yti` kept this run from colliding with any shared objects.
