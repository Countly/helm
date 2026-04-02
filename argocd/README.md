# Argo CD Customer Deployment Guide

This folder contains the GitOps setup used to deploy Countly to many customer clusters with Argo CD.

The short version:

1. Register the customer cluster in Argo CD.
2. Create a customer scaffold with the helper script.
3. Fill in the customer secrets and profile choices.
4. Commit the customer files.
5. Sync `countly-bootstrap`.
6. Argo CD creates the per-customer apps automatically.

For a slower, step-by-step walkthrough, see [ONBOARDING.md](/Users/admin/cly/helm/argocd/ONBOARDING.md).

## Folder Overview

- `root-application.yaml`
  - The parent Argo CD application.
  - Sync this when you want Argo CD to pick up Git changes in `argocd/`.
- `projects/customers.yaml`
  - Shared Argo CD project for customer apps.
- `operators/`
  - Per-customer platform apps such as cert-manager, ingress, MongoDB operator, ClickHouse operator, and Strimzi.
- `applicationsets/`
  - Generates one Argo CD `Application` per component per customer.
- `customers/`
  - One small metadata file per customer.
- `../environments/<customer>/`
  - Helm values and secrets for that customer.

## What Gets Created For Each Customer

Core apps:
- MongoDB
- ClickHouse
- Kafka
- Countly

Optional apps:
- Observability
- Migration

Platform apps:
- cert-manager
- MongoDB CRDs/operator
- ClickHouse operator
- Strimzi Kafka operator
- NGINX ingress
- Let’s Encrypt issuer
- ClusterSecretStore for Google Secret Manager

## Before You Start

Make sure these are already true:

1. Argo CD is installed in the tools cluster.
2. `countly-bootstrap` exists and is healthy.
3. The target customer cluster is registered in Argo CD.
4. DNS for the customer hostname points to the ingress load balancer you expect to use.

Helpful checks:

```bash
argocd app list
argocd cluster list
```

## Add A New Customer

### 1. Create the customer scaffold

Run:

```bash
./scripts/new-argocd-customer.sh <customer> <server> <hostname>
```

Example:

```bash
./scripts/new-argocd-customer.sh acme https://1.2.3.4 acme.count.ly
```

This creates:

- `argocd/customers/<customer>.yaml`
- `environments/<customer>/`

### 2. Edit the customer metadata

File:

- `argocd/customers/<customer>.yaml`

This file is the source of truth for:

- `server`
- `gcpServiceAccountEmail`
- `secretManagerProjectID`
- `clusterProjectID`
- `clusterName`
- `clusterLocation`
- `hostname`
- `sizing`
- `security`
- `tls`
- `observability`
- `kafkaConnect`
- `migration`

Typical example:

```yaml
customer: acme
environment: acme
project: countly-customers
server: https://1.2.3.4
gcpServiceAccountEmail: eso-acme@my-project.iam.gserviceaccount.com
secretManagerProjectID: countly-tools
clusterProjectID: countly-dev-313620
clusterName: acme-prod
clusterLocation: us-central1
hostname: acme.count.ly
sizing: tier1
security: open
tls: letsencrypt
observability: disabled
kafkaConnect: balanced
migration: disabled
```

### 3. Fill in the customer secrets

Files to review:

- `environments/<customer>/credentials-countly.yaml`
- `environments/<customer>/credentials-clickhouse.yaml`
- `environments/<customer>/credentials-kafka.yaml`
- `environments/<customer>/credentials-mongodb.yaml`
- `environments/<customer>/credentials-observability.yaml`
- `environments/<customer>/credentials-migration.yaml`

For direct-value deployments:

- set `secrets.mode: values` where used
- fill in the real passwords and secrets
- keep matching passwords consistent across Countly, ClickHouse, Kafka, and MongoDB

For external secret deployments:

- use your external secret setup instead of committing direct values
- set `gcpServiceAccountEmail` in the customer metadata so the per-customer External Secrets operator can use Workload Identity
- for GAR image pulls, store Docker config JSON in Google Secret Manager and point `global.imagePullSecretExternalSecret.remoteRef.key` to that secret
- use the flat secret naming convention `<customer>-<component>-<secret>`

Recommended secret names:

- `<customer>-gar-dockerconfig`
- `<customer>-countly-encryption-reports-key`
- `<customer>-countly-web-session-secret`
- `<customer>-countly-password-secret`
- `<customer>-countly-clickhouse-password`
- `<customer>-kafka-connect-clickhouse-password`
- `<customer>-clickhouse-default-user-password`
- `<customer>-mongodb-admin-password`
- `<customer>-mongodb-app-password`
- `<customer>-mongodb-metrics-password`

Use the same Secret Manager key for:
- Countly MongoDB password
- MongoDB `app` user password

That means new customers should point both charts at:
- `<customer>-mongodb-app-password`

Note:
- existing customer environments may still use older secret names
- use the new convention for all new customers
- migrate older customers only as a planned change

## Important Rules

### Customer metadata wins

The customer file in `argocd/customers/` is the source of truth for:

- cluster destination
- domain
- sizing
- TLS mode
- observability mode
- migration mode

### Do not set these in `environments/<customer>/countly.yaml`

Do not manually set:

- `ingress.hostname`
- `ingress.tls.mode`

These are passed from customer metadata by the Countly `ApplicationSet`.

### Kafka when migration is disabled

If `migration: disabled`, make sure the drill ClickHouse sink connector is not enabled in:

- `environments/<customer>/kafka.yaml`

This avoids creating a Kafka connector that depends on migration-owned tables.

## Commit And Deploy

After the customer files are ready:

```bash
git add argocd/customers/<customer>.yaml environments/<customer>
git commit -m "Add <customer> customer"
git push origin <branch>
```

Then tell Argo CD to pick it up:

```bash
argocd app get countly-bootstrap --refresh
argocd app sync countly-bootstrap
kubectl get applications -n argocd | grep <customer>
```

## Expected App Order

The apps are designed to settle roughly in this order:

1. Platform operators and ingress
2. MongoDB and ClickHouse
3. Kafka
4. Countly
5. Observability
6. Migration

It is normal for some apps to show `Progressing` for a while during first rollout.

## Quick Verification

After sync, useful checks are:

```bash
kubectl get applications -n argocd | grep <customer>
kubectl get pods -A
kubectl get ingress -n countly
kubectl get certificate -n countly
curl -Ik https://<hostname>
```

## Removing A Customer

1. Delete:
   - `argocd/customers/<customer>.yaml`
   - `environments/<customer>/`
2. Commit and push.
3. Sync `countly-bootstrap`.
4. Confirm the customer apps disappear from Argo CD.

## Common Problems

### Countly still renders `countly.example.com`

Cause:
- stale customer env overrides, or the `countly-app` `ApplicationSet` has not refreshed yet

Fix:
- sync `countly-bootstrap`
- make sure the generated Countly app includes `ingress.hostname` and `ingress.tls.mode`

### Kafka fails because of the drill sink connector

Cause:
- migration is disabled, but the connector is still enabled

Fix:
- disable `ch-sink-drill-events` in `environments/<customer>/kafka.yaml`

### Bootstrap changes are not reaching generated apps

Cause:
- `countly-bootstrap` was not refreshed or synced

Fix:

```bash
argocd app get countly-bootstrap --refresh
argocd app sync countly-bootstrap
```

## Recommended Workflow For Engineers

For each new customer:

1. Register the cluster in Argo CD.
2. Run the scaffold script.
3. Edit `argocd/customers/<customer>.yaml`.
4. Fill in `environments/<customer>/credentials-*.yaml`.
5. Review `environments/<customer>/kafka.yaml` if migration is disabled.
6. Commit and push.
7. Sync `countly-bootstrap`.
8. Verify the generated apps, ingress, and certificate.

If you follow that flow, you should not need to manually create Argo CD apps one by one.
