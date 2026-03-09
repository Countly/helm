# Reference Environment

This directory is a complete starting point for a new Countly deployment.

## Quick Start

1. Copy this directory:
   ```bash
   cp -r environments/reference environments/my-deployment
   ```

2. Edit `global.yaml`:
   - Set `ingress.hostname` to your domain
   - Choose a `global.profile` (local, small, production)
   - Choose `ingress.tls.mode` (letsencrypt, existingSecret, selfSigned, http)
   - Choose backing service modes (bundled or external)
   - Choose observability mode (full, hybrid, external, disabled)

3. Fill in required secrets in the chart-specific files:
   - `countly.yaml` → `secrets.common.*` and `secrets.clickhouse.password`, `secrets.mongodb.password`
   - `mongodb.yaml` → `users.app.password`, `users.metrics.password`
   - `clickhouse.yaml` → `auth.defaultUserPassword.password`
   - `kafka.yaml` → `kafkaConnect.clickhouse.password`

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
- **Direct values**: Fill secrets in chart-specific YAML files (split into `secrets-countly.yaml`, `secrets-mongodb.yaml`, etc.)
- **existingSecret**: Pre-create Kubernetes secrets and reference them
- **externalSecret**: Use External Secrets Operator (see `external-secrets.example.yaml`)
- **SOPS**: Encrypt secret files with SOPS (see `secrets.sops.example.yaml`)

## Files

| File | Purpose |
|------|---------|
| `global.yaml` | Profile, ingress, TLS, backing services, observability mode |
| `countly.yaml` | Countly app secrets, OTEL config, network policy |
| `mongodb.yaml` | MongoDB user passwords |
| `clickhouse.yaml` | ClickHouse authentication |
| `kafka.yaml` | Kafka Connect credentials |
| `observability.yaml` | Observability signal toggles, external endpoints, storage |
| `secrets.example.yaml` | Complete secrets reference (DO NOT COMMIT with real values) |
| `secrets.sops.example.yaml` | SOPS encryption guide |
| `external-secrets.example.yaml` | ESO configuration guide |
