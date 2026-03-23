# Resource Override GA Bug Bash Guide
@<Yetkin Timocin>
**Last updated:** March 19, 2026

> ⚠️ **Multi-user heads-up:** If multiple people run scenarios against the same fleet without per-user names, overrides collide — `kubectl apply` overwrites same-named objects and overrides from different people stack on the same target resource. Follow the [Multi-user setup](#multi-user-setup) section below (takes ~30s) or run your own fleet.

For a deeper dive into the feature, see the [Cluster Resource Override & Resource Override Summary Document](https://msazure.visualstudio.com/CloudNativeCompute/_wiki/wikis/CloudNativeCompute.wiki/XXXXXX/Cluster-Resource-Override-Resource-Override-Summary-Document). Public documentation links are listed below.
[[_TOC_]]


[File Bugs Here](https://msazure.visualstudio.com/CloudNativeCompute/_workitems/create/Bug?templateId=f6cb566d-7faf-4d48-985d-acd9ef627a57&ownerId=b9af3a2a-9ed4-45c5-9c2d-3186f7a13819)

When filing a bug please be sure to provide:

*   Steps to reproduce the issue or the scenario you were testing
*   Screenshot or relevant YAML/output showing the problem
*   If documentation related, include the document link or name (Azure or Upstream) and what needs to be corrected
::: query-table 6a3bf597-5622-44e7-9cf0-4dd44350e4f5
:::


____

Reference Documentation:
------------------------

The following resources cover the override APIs and how to use them:

*   **Concept Docs:**
    *   **Upstream:** [Override | KubeFleet](https://kubefleet.dev/docs/concepts/override/)
        *   _Source code:_ [website/content/en/docs/concepts/override.md at main · kubefleet-dev/website](https://github.com/kubefleet-dev/website/blob/main/content/en/docs/concepts/override.md?plain=1)
*   **How-to Docs:**
    *   **Azure:** [Use Resource Overrides to customize resources deployed by Azure Kubernetes Fleet Manager resource placement | Microsoft Learn](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/howto-use-overrides-customize-resources-placement)
        *   _Source code:_ [azure-aks-docs-pr/articles/kubernetes-fleet/howto-use-overrides-customize-resources-placement.md at main · MicrosoftDocs/azure-aks-docs-pr](https://github.com/MicrosoftDocs/azure-aks-docs/blob/main/articles/kubernetes-fleet/howto-use-overrides-customize-resources-placement.md?plain=1)
    *   **Upstream:** [How to use ClusterResourceOverride | KubeFleet](https://kubefleet.dev/docs/how-tos/cluster-resource-override/)
        *   _Source code:_ [website/content/en/docs/how-tos/cluster-resource-override.md at main · kubefleet-dev/website](https://github.com/kubefleet-dev/website/blob/main/content/en/docs/how-tos/cluster-resource-override.md)
    *   **Upstream:** [How to use ResourceOverride | KubeFleet](https://kubefleet.dev/docs/how-tos/resource-override/)
        *   _Source code:_ [website/content/en/docs/how-tos/resource-override.md at main · kubefleet-dev/website](https://github.com/kubefleet-dev/website/blob/main/content/en/docs/how-tos/resource-override.md)
*   **Troubleshooting Guides:**
    *   **Upstream:** [Placement Overridden TSG | KubeFleet](https://kubefleet.dev/docs/troubleshooting/placementoverridden/)
        *   _Source code:_ [website/content/en/docs/troubleshooting/PlacementOverridden.md at main · kubefleet-dev/website](https://github.com/kubefleet-dev/website/blob/main/content/en/docs/troubleshooting/PlacementOverridden.md?plain=1)
    *   **Azure (coming soon, PR merged, pending prod deployment):**
        *   [How to Debug ClusterResourceOverride and ResourceOverride Failures | AKS TSG](https://eng.ms/docs/cloud-ai-platform/azure-core/azure-cloud-native-and-management-platform/containers-bburns/azure-kubernetes-service/tsg-for-azure-kubernetes-service/doc/fleet/fleethow-to-debug-resource-overrides)
        *   [ClusterResourceOverride and ResourceOverride Reference | AKS TSG](https://eng.ms/docs/cloud-ai-platform/azure-core/azure-cloud-native-and-management-platform/containers-bburns/azure-kubernetes-service/tsg-for-azure-kubernetes-service/doc/fleet/fleetoverride-reference)


Scenarios:
----------

Override rules use `clusterSelector` with label selectors to target specific clusters. If you need to apply custom labels to your member clusters instead of relying on the Azure-provided ones, you can use the following script:

    label="<label>=<value>"
    count=<count>
    fleet=<fleet-name>
    resourceGroup=<resource-group>

    # Retrieve all member clusters
    clusters=($(kubectl get memberclusters -A -o jsonpath='{.items[*].metadata.name}'))

    # Randomize the order
    shuffled_indices=($(shuf -i 0-$((${#clusters[@]} - 1))))

    # Apply the label to the desired number of clusters
    for index in "${shuffled_indices[@]:0:$count}"; do
      cluster=${clusters[$index]}
      az fleet member update -g $resourceGroup -f $fleet -n $cluster --member-labels $label
      echo "Labeled $cluster with label: $label"
    done

See [az fleet member update](https://learn.microsoft.com/en-us/cli/azure/fleet/member?view=azure-cli-latest#az-fleet-member-update-optional-parameters) for more details on member cluster labels.

To view the current labels on your member clusters, run `kubectl get memberclusters --show-labels`.



### Helper Scripts:

Setup and teardown scripts are available in [ytimocin/kubefleet](https://github.com/ytimocin/kubefleet/tree/resource-override-bug-bash/examples/resourceoverride):

*   **[setup-override-bug-bash.sh](https://github.com/ytimocin/kubefleet/blob/resource-override-bug-bash/examples/resourceoverride/setup-override-bug-bash.sh)** — Creates a Fleet with 3 labeled AKS member clusters (shared infrastructure; run once per bug bash).
*   **[teardown-override-bug-bash.sh](https://github.com/ytimocin/kubefleet/blob/resource-override-bug-bash/examples/resourceoverride/teardown-override-bug-bash.sh)** — Deletes the resource group and cleans up kubectl contexts.
*   **[user-setup.sh](https://github.com/ytimocin/kubefleet/blob/resource-override-bug-bash/examples/resourceoverride/user-setup.sh)** — Creates **your** per-user namespace, target resources, and baseline CRP/RP so your scenarios don't collide with others'. Requires `USER_TAG`.
*   **[user-teardown.sh](https://github.com/ytimocin/kubefleet/blob/resource-override-bug-bash/examples/resourceoverride/user-teardown.sh)** — Deletes everything your `USER_TAG` created.
*   **[override-bug-bash-test-results.md](https://github.com/ytimocin/kubefleet/blob/resource-override-bug-bash/examples/resourceoverride/override-bug-bash-test-results.md)** — Test results from running these scenarios.
*   **Scenario YAMLs** (`01-…` through `15-…`) — Each is a parameterized template using `${USER_TAG}`. Apply with `envsubst`.



### Multi-user setup:

Each bug basher runs `user-setup.sh` once with a unique `USER_TAG` (lowercase initials work well). This creates an isolated namespace `test-ns-<USER_TAG>`, per-user target resources, and per-user baseline `example-crp-<USER_TAG>` + `example-rp-<USER_TAG>`. You then apply the scenario YAMLs with `envsubst` so every override and placement reference is scoped to your tag.

```bash
# First time — create your personal baseline on the shared fleet
export USER_TAG=yti          # <-- change to your own initials
./user-setup.sh

# Apply any scenario YAML
envsubst < 04-ro-replace-image-prod.yaml | kubectl apply -f -

# Clean up when done
./user-teardown.sh
```

> **Note:** The reserved variables `${MEMBER-CLUSTER-NAME}` and `${MEMBER-CLUSTER-LABEL-KEY-…}` contain dashes, so `envsubst` leaves them alone — only `${USER_TAG}` is substituted. No escaping needed.

If you prefer full isolation instead (separate fleet), re-run `setup-override-bug-bash.sh` with a unique `RG` and `FLEET_NAME`:

```bash
export SUBSCRIPTION=<id>
export RG=override-bug-bash-rg-yti
export FLEET_NAME=override-bug-bash-fleet-yti
./setup-override-bug-bash.sh
```



### Prerequisites:

Before running override scenarios, make sure you have:

*   A CRP or RP already created and resources placed on member clusters.
*   Member clusters labeled appropriately for cluster selector tests (e.g., `env=prod`, `env=staging`, `tier=frontend`, `tier=backend`, `region=<your-region>`).



### Basic JSON Patch Operations:

**1. Add annotation to all clusters**

Create a CRO or RO that adds an annotation to all clusters using an empty `clusterSelectorTerms` (matches all clusters).

  **Example:**
  ```bash
   ## If using cluster-scope (ClusterResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ClusterResourceOverride
   metadata:
     name: example-cro-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     clusterResourceSelectors:
       - group: rbac.authorization.k8s.io
         kind: ClusterRole
         version: v1
         name: secret-reader-${USER_TAG}
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms: []
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"environment": "fleet-managed"}
   EOF

   ------

   # If using namespace-scope (ResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: example-ro-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: apps
         kind: Deployment
         version: v1
         name: nginx
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms: []
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"environment": "fleet-managed"}
   EOF

   ```

Verify the override is applied by checking the CRP/RP status:

```bash
kubectl describe crp example-crp
```

Look for the `ClusterResourcePlacementOverridden` condition with `Status: "True"` and `Reason: OverriddenSucceeded`. Each cluster's placement status should list the applicable override snapshot under `Applicable Cluster Resource Overrides` or `Applicable Resource Overrides`.

Then verify the resource on a member cluster has the annotation:

```bash
## For CRO (ClusterRole)
kubectl get clusterrole secret-reader -o yaml --context <member-cluster-context>

## For RO (Deployment)
kubectl get deployment nginx -n test-namespace -o yaml --context <member-cluster-context>
```

**2. Patch a field on specific clusters**

Create a CRO or RO that patches (e.g., replaces or removes) a field only on clusters matching a label selector.

  **Example:**
  ```bash
   ## If using cluster-scope (ClusterResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ClusterResourceOverride
   metadata:
     name: cro-prod-restrict-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     clusterResourceSelectors:
       - group: rbac.authorization.k8s.io
         kind: ClusterRole
         version: v1
         name: secret-reader-${USER_TAG}
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     env: prod
           jsonPatchOverrides:
             - op: remove
               path: /rules/0/verbs/2
   EOF

   ------

   # If using namespace-scope (ResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-prod-image-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: apps
         kind: Deployment
         version: v1
         name: nginx
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     env: prod
           jsonPatchOverrides:
             - op: replace
               path: /spec/template/spec/containers/0/image
               value: "nginx:1.27.3"
   EOF

   ```

Verify that only clusters with the `env=prod` label have the override applied. Clusters without the label should have the original resource unchanged.

**3. Multiple JSON patch operations in a single rule**

Create a CRO or RO with multiple `jsonPatchOverrides` within one rule to apply several changes at once.

  **Example:**
  ```bash
   ## If using namespace-scope (ResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-multi-patch-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: apps
         kind: Deployment
         version: v1
         name: nginx
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     env: prod
           jsonPatchOverrides:
             - op: replace
               path: /spec/template/spec/containers/0/image
               value: "nginx:1.27.3"
             - op: replace
               path: /spec/replicas
               value: 5
   EOF

   ```

Verify on `env=prod` clusters that both the image is `nginx:1.27.3` and replicas is `5`.



### Multiple Override Rules (Different Clusters, Different Overrides):

**1. Different overrides per environment**

Create a CRO or RO with multiple `overrideRules`, each targeting different clusters via label selectors.

  **Example:**
  ```bash
   ## If using namespace-scope (ResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-per-env-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: apps
         kind: Deployment
         version: v1
         name: nginx
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     env: prod
           jsonPatchOverrides:
             - op: replace
               path: /spec/template/spec/containers/0/image
               value: "nginx:1.27.3"
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     env: staging
           jsonPatchOverrides:
             - op: replace
               path: /spec/template/spec/containers/0/image
               value: "nginx:latest"
   EOF

   ```

Verify on `env=prod` clusters that the image is `nginx:1.27.3` and on `env=staging` clusters that the image is `nginx:latest`.



### Reserved Variables:

**1. Using `${MEMBER-CLUSTER-NAME}`**

Create a CRO or RO that injects the member cluster name into the resource.

  **Example:**
  ```bash
   ## If using namespace-scope (ResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-cluster-name-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: ""
         kind: Service
         version: v1
         name: my-service
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms: []
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"service.beta.kubernetes.io/azure-dns-label-name": "fleet-${MEMBER-CLUSTER-NAME}"}
   EOF

   ```

Verify on each member cluster that the annotation value contains the actual cluster name (e.g., `fleet-member-1`, `fleet-member-2`).

**2. Using `${MEMBER-CLUSTER-LABEL-KEY-<key>}`**

Create a CRO or RO that injects a member cluster label value into the resource.

  **Example:**
  ```bash
   ## If using namespace-scope (ResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-cluster-label-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: apps
         kind: Deployment
         version: v1
         name: nginx
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms: []
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"region": "${MEMBER-CLUSTER-LABEL-KEY-fleet.azure.com/location}"}
   EOF

   ```

Verify on each member cluster that the annotation value contains the actual label value from the member cluster (e.g., `eastus`, `westus`).

**3. Missing label variable (negative case)**

Create a CRO or RO that references a label key that does not exist on the member clusters.

Use the same example as above but reference a label key like `non-existent-label`. The override should fail and the CRP/RP status should show the per-cluster `Overridden` condition with `Status: "False"` and `Reason: OverriddenFailed`.

Please reference **_"Investigate Placement Overridden"_** in the [TSG](https://kubefleet.dev/docs/troubleshooting/placementoverridden/) to troubleshoot failure.



### Delete Override Type:

**1. Delete resources on specific clusters**

Create a CRO or RO that deletes resources on specific clusters while keeping them on others. This is useful when you want a resource to NOT exist on certain clusters.

  **Example:**
  ```bash
   ## If using cluster-scope (ClusterResourceOverride)

   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ClusterResourceOverride
   metadata:
     name: cro-delete-backend-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     clusterResourceSelectors:
       - group: ""
         kind: Namespace
         version: v1
         name: test-ns-${USER_TAG}
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     env: prod
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"managed-by": "fleet"}
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     tier: backend
           overrideType: Delete
   EOF

   ```

Verify that:
*   Clusters with `env=prod` (and not `tier=backend`) have the resource with the annotation.
*   Clusters with `tier=backend` do **not** have the resource at all.
*   The CRP status still shows `OverriddenSucceeded` for all clusters.



### PlacementRef:

**1. CRO/RO with correct PlacementRef**

Create a CRO or RO with `placement.name` pointing to the correct CRP/RP name. The override should apply.

This is already demonstrated in the examples above. Verify the `Applicable Cluster Resource Overrides` or `Applicable Resource Overrides` list is populated in the placement status.

**2. CRO/RO with incorrect PlacementRef (should NOT apply)**

Create a CRO or RO with `placement.name` pointing to a CRP/RP that does not exist or is different from the actual placement.

  **Example:**
  ```bash
   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ClusterResourceOverride
   metadata:
     name: cro-wrong-ref-${USER_TAG}
   spec:
     placement:
       name: non-existent-crp
     clusterResourceSelectors:
       - group: ""
         kind: Namespace
         version: v1
         name: test-ns-${USER_TAG}
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms: []
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"should-not-appear": "true"}
   EOF

   ```

Verify that the override is **silently skipped** — the CRP status should show no applicable overrides for any cluster, and the resource on member clusters should not have the annotation.

**3. RO with namespace-scoped PlacementRef**

Create a RO with `placement.scope: Namespaced` pointing to a `ResourcePlacement` (RP).

  **Example:**
  ```bash
   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-with-rp-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-rp-${USER_TAG}
       scope: Namespaced
     resourceSelectors:
       - group: ""
         kind: ConfigMap
         version: v1
         name: my-config
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms: []
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"managed": "true"}
   EOF

   ```

Verify that the override applies to the ConfigMap on member clusters and the RP status shows the applicable override snapshot.



### Override Snapshot Versioning:

**1. Update override and verify new snapshot**

Create a CRO or RO, verify the initial snapshot is created (index 0), then update the override and verify a new snapshot is created (index 1).

```bash
## Check override snapshots
# cluster-scope
kubectl get clusterresourceoverridesnapshot \
  -l kubernetes-fleet.io/parent-resource-override=<cro-name>

# namespace-scope
kubectl get resourceoverridesnapshot -n <namespace> \
  -l kubernetes-fleet.io/parent-resource-override=<ro-name>
```

After updating the override, verify:
*   A new snapshot with incremented index exists.
*   Only the new snapshot has the label `kubernetes-fleet.io/is-latest-snapshot=true`.
*   The CRP/RP status references the new snapshot name.

**2. No-op update (hash deduplication)**

Update the CRO or RO **without changing the spec** (e.g., add/remove a metadata annotation on the override object itself). Verify that **no new snapshot** is created because the spec hash has not changed.

**3. Snapshot revision limit**

Update the CRO or RO more than 10 times with different spec changes. Verify that only 10 snapshots are retained. Older snapshots should be automatically deleted.

```bash
## Check total snapshot count
# cluster-scope
kubectl get clusterresourceoverridesnapshot \
  -l kubernetes-fleet.io/parent-resource-override=<cro-name> --no-headers | wc -l

# namespace-scope
kubectl get resourceoverridesnapshot -n <namespace> \
  -l kubernetes-fleet.io/parent-resource-override=<ro-name> --no-headers | wc -l
```



### CRO + RO Conflict Resolution:

**1. Both CRO and RO targeting the same namespaced resource**

Create both a CRO (via namespace selection) and a RO that target the same namespaced resource (e.g., a ConfigMap). Have them both patch the same field with different values.

CRO patches are applied first, then RO patches. **RO wins on field conflicts.**

Verify on member clusters that the RO's value is the one present on the resource.



### Validation (Negative Cases):

**1. Two CROs selecting the same resource**

Create two CROs that both select the same cluster-scoped resource. The webhook should **reject** the second CRO with an error message like `"the resource has been selected by both X and Y"`.

> **Note:** Use `apiVersion: placement.kubernetes-fleet.io/v1beta1` for this test. There is a known issue where the `v1` API bypasses the validating webhook.

**2. Invalid JSON patch path**

Try creating a CRO or RO with an invalid path such as `/metadata/name`, `/kind`, `/apiVersion`, or `/status`. The webhook should **reject** the override.

**3. Remove operation with a value**

Try creating a CRO or RO with `op: remove` and a `value` field. The webhook should **reject** the override.

**4. Immutable placement field**

Try updating the `placement.name` on an existing CRO or RO. The webhook should **reject** the update — the placement reference is immutable once set (enforced via CEL validation).

**5. CRO/RO count limit (100 per scope)**

The webhook enforces a maximum of 100 CROs per cluster and 100 ROs per namespace. If you have the capacity to test, try creating a 101st CRO or RO. The webhook should **reject** it.

**6. Incorrect JSON patch path on the resource**

Create a CRO or RO with a valid-looking path that does not actually exist on the target resource (e.g., `replace` on `/spec/nonExistentField`). The override will be created successfully, but when applied, the CRP/RP status should show `Overridden` with `Status: "False"` and `Reason: OverriddenFailed`.

Please reference **_"Investigate Placement Overridden"_** in the [TSG](https://kubefleet.dev/docs/troubleshooting/placementoverridden/) to troubleshoot failure.



### Advanced Cluster Selectors:

**1. Using `matchExpressions` (In / NotIn)**

Create a CRO or RO that uses `matchExpressions` instead of `matchLabels` to target clusters.

  **Example:**
  ```bash
   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-match-expr-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: apps
         kind: Deployment
         version: v1
         name: nginx
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchExpressions:
                     - key: env
                       operator: In
                       values: ["prod", "staging"]
           jsonPatchOverrides:
             - op: add
               path: /metadata/annotations
               value:
                 {"fleet-managed": "true"}
   EOF

   ```

Verify that all clusters matching the expression have the annotation. Try `NotIn` and `Exists` operators as well.

**2. Multiple `clusterSelectorTerms` (OR logic)**

Create a CRO or RO with multiple `clusterSelectorTerms` in a single rule. Terms are OR'd — a cluster matching **any** term gets the override.

  **Example:**
  ```bash
   kubectl apply -f - << EOF
   apiVersion: placement.kubernetes-fleet.io/v1
   kind: ResourceOverride
   metadata:
     name: ro-or-selector-${USER_TAG}
     namespace: test-ns-${USER_TAG}
   spec:
     placement:
       name: example-crp-${USER_TAG}
     resourceSelectors:
       - group: apps
         kind: Deployment
         version: v1
         name: nginx
     policy:
       overrideRules:
         - clusterSelector:
             clusterSelectorTerms:
               - labelSelector:
                   matchLabels:
                     env: staging
               - labelSelector:
                   matchLabels:
                     tier: backend
           jsonPatchOverrides:
             - op: replace
               path: /spec/replicas
               value: 1
   EOF

   ```

Verify that clusters with `env=staging` **or** `tier=backend` have replicas set to 1, while other clusters keep the original value.



### Override Cleanup:

**1. Delete the override**

Delete the CRO or RO and verify:
*   All associated override snapshots are cleaned up (the finalizer `kubernetes-fleet.io/override-cleanup` handles this).
*   The CRP/RP status no longer lists any applicable overrides.
*   The resource on member clusters reverts to its original state (the override annotation/patch is removed).

```bash
## cluster-scope
kubectl delete cro <cro-name>

## namespace-scope
kubectl delete ro <ro-name> -n <namespace>
```

After deletion, verify:
```bash
## Snapshots should be gone
kubectl get clusterresourceoverridesnapshot \
  -l kubernetes-fleet.io/parent-resource-override=<cro-name>

## CRP status should show no overrides
kubectl describe crp <crp-name>
```
