# Deploying Countly

## Prerequisites

Install the required operators before deploying. See [PREREQUISITES.md](PREREQUISITES.md) for versions and installation commands.

Required:
1. cert-manager
2. ClickHouse Operator
3. Strimzi Kafka Operator
4. MongoDB Community Operator
5. F5 NGINX Ingress Controller

## Step 1: Create Your Environment

```bash
cp -r environments/reference environments/my-deployment
```

## Step 2: Configure Global Settings

Edit `environments/my-deployment/global.yaml`:

```yaml
global:
  profile: production               # Sizing: local | small | production
  storageClass: gp3                  # Your cluster's storage class

ingress:
  hostname: analytics.example.com   # Your domain
  tls:
    mode: letsencrypt               # TLS strategy
    clusterIssuer: letsencrypt-prod
```

See [DEPLOYMENT-MODES.md](DEPLOYMENT-MODES.md) for all mode options.

## Step 3: Configure Secrets

Fill in the required passwords in per-chart secret files (`secrets-<chart>.yaml`), which are gitignored to prevent accidental credential commits. Every chart needs credentials on first install:

| Secret File | Required Secrets |
|-------------|-----------------|
| `secrets-countly.yaml` | `secrets.common.*` (3 keys), `secrets.clickhouse.password`, `secrets.mongodb.password` |
| `secrets-mongodb.yaml` | `users.app.password`, `users.metrics.password` |
| `secrets-clickhouse.yaml` | `auth.defaultUserPassword.password` |
| `secrets-kafka.yaml` | `kafkaConnect.clickhouse.password` |

See `environments/reference/secrets.example.yaml` for a complete template you can copy.

**Important:** The ClickHouse password must match across `secrets-countly.yaml`, `secrets-clickhouse.yaml`, and `secrets-kafka.yaml`. The MongoDB password must match across `secrets-countly.yaml` and `secrets-mongodb.yaml`.

For production secret management options, see [SECRET-MANAGEMENT.md](SECRET-MANAGEMENT.md).

## Step 4: Register and Deploy

Add your environment to `helmfile.yaml.gotmpl`:

```yaml
environments:
  my-deployment:
    values:
      - environments/my-deployment/global.yaml
```

Deploy:
```bash
helmfile -e my-deployment apply
```

This installs all charts in dependency order with a 10-minute timeout per chart.

## Step 5: Verify

```bash
# Check all pods are running
kubectl get pods -n countly
kubectl get pods -n mongodb
kubectl get pods -n clickhouse
kubectl get pods -n kafka

# Run smoke test
./scripts/smoke-test.sh
```

## Upgrades

```bash
helmfile -e my-deployment apply
```

Secrets are preserved automatically on upgrades via the lookup-or-create pattern. Change `secrets.rotationId` to trigger a secret rotation (see [SECRET-MANAGEMENT.md](SECRET-MANAGEMENT.md)).

## Uninstall

```bash
helmfile -e my-deployment destroy
```

Note: PVCs are not deleted by default. Clean up manually if needed.
