# ArgoCD Bootstrap For Customer Deployments

This folder bootstraps Countly for multiple customers using ArgoCD `ApplicationSet`.

## What This Layout Does

- `operators/` bootstraps required platform operators into the target cluster.
- `projects/` defines the shared ArgoCD `AppProject` used by customer apps.
- `customers/` contains one metadata file per customer/cluster.
- `applicationsets/` generates one ArgoCD `Application` per component per customer.
- `environments/<customer>/` stores the Helm values used by those Applications.
- `root-application.yaml` creates one parent ArgoCD Application that syncs this whole `argocd/` folder.

For the initial rollout, ArgoCD is scoped to one customer metadata file:

- `argocd/customers/helm-argocd.yaml`

## Before You Sync

1. Install ArgoCD and the ApplicationSet controller.
2. Register each target cluster in ArgoCD.
3. Create or update one customer metadata file in:
   - `argocd/customers/<customer>.yaml`
   - The `server:` value must match the cluster entry registered in ArgoCD.
   - Set `hostname:` to the customer domain.
4. Replace the environment hostname in:
   - `environments/<customer>/global.yaml`
5. Populate the direct values in the customer `secrets-*.yaml` files before the first deploy.
6. Configure ArgoCD custom health checks for MongoDB, ClickHouse, and Strimzi CRs.

## Apply Order

```bash
kubectl apply -f argocd/projects/customers.yaml -n argocd
kubectl apply -f argocd/applicationsets/ -n argocd
```

Or bootstrap everything with one parent app:

```bash
kubectl apply -f argocd/root-application.yaml -n argocd
```

## Generated Application Order

- Wave `-30` to `-24`: per-customer cert-manager, MongoDB CRDs/operator, ClickHouse operator, Strimzi operator, NGINX ingress, Let’s Encrypt ClusterIssuer
- Wave `0`: MongoDB, ClickHouse
- Wave `5`: Kafka
- Wave `10`: Countly
- Wave `15`: Observability

## Add A New Customer Later

1. Run:
   ```bash
   ./scripts/new-argocd-customer.sh <customer> <server> <hostname>
   ```
2. Fill in `environments/<customer>/secrets-*.yaml`.
3. Adjust any customer-specific overrides in `environments/<customer>/*.yaml`.
4. Commit and let ArgoCD reconcile.

Only two Git-managed inputs are required per new customer:
- `environments/<customer>/`
- `argocd/customers/<customer>.yaml`

Customer metadata is the source of truth for:
- `server`
- `hostname`
- `sizing`
- `security`
- `tls`
- `observability`
- `kafkaConnect`
- `migration`
