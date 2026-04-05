# Reference Environment

This directory is a complete starting point for a new Countly deployment.

## Quick Start

1. Copy this directory:
   ```bash
   cp -r environments/reference environments/my-deployment
   ```

2. Edit `global.yaml`:
  - Set `ingress.hostname` to your domain
  - Choose `global.sizing`: `local`, `small`, `tier1`, or `production`
  - Choose `global.tls`: `none`, `letsencrypt`, `provided`, or `selfSigned`
  - Choose `global.observability`: `disabled`, `full`, `external-grafana`, or `external`
  - Choose `global.kafkaConnect`: `throughput`, `balanced`, or `low-latency`
  - Optionally set `global.kafkaConnectSizing` to `local`, `small`, `tier1`, or `production` when you need a validated Kafka Connect override for that hardware tier
  - Choose `global.security`: `open` or `hardened`
  - Choose backing service modes (bundled or external)
  - For GAR, set `global.imageSource`, `global.imagePullSecrets`, and optionally `global.imagePullSecretExternalSecret`
  - For `global.tls: provided`, either point Countly at a pre-created TLS secret or enable `ingress.tls.externalSecret` in `countly.yaml`

3. Fill in required secrets in the chart-specific files:
  - `credentials-countly.yaml` → `secrets.common.*` and `secrets.clickhouse.password`, `secrets.mongodb.password`
  - `credentials-mongodb.yaml` → `users.app.password`, `users.metrics.password`
  - `credentials-clickhouse.yaml` → `auth.defaultUserPassword.password`
  - `credentials-kafka.yaml` → `kafkaConnect.clickhouse.password`
  - `image-pull-secrets.example.yaml` → private registry pull secret manifests for `countly` and `kafka`

   Use one shared ClickHouse password value for:
   - Countly
   - ClickHouse default user
   - Kafka Connect

   Or use `secrets.example.yaml` as a complete reference.

4. Register your environment in `helmfile.yaml.gotmpl`:
   ```yaml
   environments:
     my-deployment:
       values:
         - environments/my-deployment/global.yaml
   ```

5. Deploy:
   ```bash
   helmfile -e my-deployment apply
   ```

## Secret Management

See `secrets.example.yaml` for a complete list of all required secrets.

For production, choose one of:
- **Direct values**: Fill credentials in chart-specific YAML files (split into `credentials-countly.yaml`, `credentials-mongodb.yaml`, etc.)
- **existingSecret**: Pre-create Kubernetes secrets and reference them
- **externalSecret**: Use External Secrets Operator and Secret Manager-backed remote refs in the same `credentials-*.yaml` files
- **SOPS**: Encrypt secret files with SOPS (see `secrets.sops.example.yaml`)

For private registries such as GAR, also create namespaced image pull secrets.
Use `image-pull-secrets.example.yaml` as a starting point, then encrypt it with SOPS or manage it through your GitOps secret workflow.
If you use External Secrets Operator with Google Secret Manager, point `global.imagePullSecretExternalSecret.remoteRef.key` at a secret whose value is the Docker config JSON content for `us-docker.pkg.dev`.
You can use the same External Secrets pattern for Countly ingress TLS when `global.tls` is `provided`; see `countly.yaml` and `external-secrets.example.yaml`.

## Files

| File | Purpose |
|------|---------|
| `global.yaml` | Profile selectors, ingress, backing service modes |
| `countly.yaml` | All Countly chart values (components, config, ingress, network policy) |
| `mongodb.yaml` | MongoDB chart values (replica set, resources, exporter) |
| `clickhouse.yaml` | ClickHouse chart values (topology, auth, keeper) |
| `kafka.yaml` | Kafka chart values (brokers, controllers, connect, connectors) |
| `observability.yaml` | Observability chart values (signals, backends, Grafana, Alloy) |
| `credentials-countly.yaml` | Countly secrets (encryption keys, DB passwords) |
| `credentials-mongodb.yaml` | MongoDB user passwords |
| `credentials-clickhouse.yaml` | ClickHouse auth password |
| `credentials-kafka.yaml` | Kafka Connect ClickHouse password |
| `credentials-observability.yaml` | Observability secrets (external backend creds if needed) |
| `countly-tls.env` | Manual TLS secret helper for bring-your-own certificate workflows |
| `secrets.example.yaml` | Combined secrets reference (all charts in one file) |
| `secrets.sops.example.yaml` | SOPS encryption guide |
| `external-secrets.example.yaml` | External Secrets Operator guide |
| `image-pull-secrets.example.yaml` | Example GAR/private registry image pull secrets for `countly` and `kafka` |
| `cluster-secret-store.gcp.example.yaml` | Example `ClusterSecretStore` for Google Secret Manager with Workload Identity |
