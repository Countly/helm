# ArgoCD Bootstrap For Customer Deployments

This folder bootstraps Countly for multiple customers using ArgoCD `ApplicationSet`.

## What This Layout Does

- `operators/` bootstraps required platform operators into the target cluster.
- `projects/` creates one ArgoCD `AppProject` per customer.
- `applicationsets/` generates one ArgoCD `Application` per component per customer.
- `environments/<customer>/` stores the Helm values used by those Applications.
- `root-application.yaml` creates one parent ArgoCD Application that syncs this whole `argocd/` folder.

For the initial rollout, ArgoCD is scoped to:

- `helm-argocd`

## Before You Sync

1. Install ArgoCD and the ApplicationSet controller.
2. Register each target cluster in ArgoCD.
3. Update the cluster API servers in:
   - `argocd/projects/customers.yaml`
   - `argocd/applicationsets/*.yaml`
   - `argocd/operators/*.yaml`
   - The `server:` value must match the cluster entry registered in ArgoCD.
4. Replace the environment hostname in:
   - `environments/helm-argocd/global.yaml`
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

- Wave `-30` to `-25`: cert-manager, MongoDB CRDs/operator, ClickHouse operator, Strimzi operator, NGINX ingress
- Wave `0`: MongoDB, ClickHouse
- Wave `5`: Kafka
- Wave `10`: Countly
- Wave `15`: Observability

## Add A New Customer Later

1. Copy `environments/reference` to `environments/<customer>`.
2. Add the customer entry to each `ApplicationSet` list.
3. Add a matching `AppProject` to `argocd/projects/customers.yaml`.
4. Add that customer's Google Secret Manager keys.
5. Commit and let ArgoCD reconcile.
