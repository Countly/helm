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
  sizing: production                # Sizing: local | small | production
  observability: full               # Observability: disabled | full | external-grafana | external
  kafkaConnect: balanced            # Kafka Connect: throughput | balanced | low-latency
  tls: letsencrypt                  # TLS: none | letsencrypt | provided | selfSigned
  security: hardened                # Security: open | hardened
  storageClass: gp3                 # Your cluster's storage class

ingress:
  hostname: analytics.example.com   # Your domain
```

See [DEPLOYMENT-MODES.md](DEPLOYMENT-MODES.md) for all mode options.

## Step 3: Configure Secrets

Your copied environment already includes the chart-specific secret files from `environments/reference/`.

Fill in the required passwords in the per-chart credential files (`credentials-<chart>.yaml`). Every chart needs credentials on first install:

| Secret File | Required Secrets |
|-------------|-----------------|
| `credentials-countly.yaml` | `secrets.common.*` (3 keys), `secrets.clickhouse.password`, `secrets.mongodb.password` |
| `credentials-mongodb.yaml` | `users.app.password`, `users.metrics.password` |
| `credentials-clickhouse.yaml` | `auth.defaultUserPassword.password` |
| `credentials-kafka.yaml` | `kafkaConnect.clickhouse.password` |

See `environments/reference/secrets.example.yaml` for a complete reference.

**Important:** The ClickHouse password must match across `credentials-countly.yaml`, `credentials-clickhouse.yaml`, and `credentials-kafka.yaml`. The MongoDB password must match across `credentials-countly.yaml` and `credentials-mongodb.yaml`.

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

If you prefer plain Helm instead of Helmfile, use the same values layering shown in [README.md](/Users/admin/cly/helm/README.md) under manual installation.

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

## Troubleshooting

### Helmfile is not installed locally

If `helmfile` is not available on your machine, either:

- install Helmfile and keep using this document, or
- run plain `helm install` / `helm upgrade` commands using the same values files

The charts themselves do not require Argo CD.

### Migration chart fails with missing `redis` dependency

The `countly-migration` chart includes a Redis dependency.

Before rendering or installing it directly with Helm, run:

```bash
helm dependency build ./charts/countly-migration
```

If you are not deploying migration, you can ignore this.

### Kafka startup: UNKNOWN_TOPIC_OR_PARTITION errors

On a fresh deployment, Countly pods (aggregator, ingestor) may log `UNKNOWN_TOPIC_OR_PARTITION` errors for the first 2-5 minutes. This is expected behavior:

- `auto.create.topics.enable` is `false` by default for safety.
- Kafka topics are created by the Countly application during its initialization cycle, which depends on Kafka Connect being ready.
- The consumers retry every 30 seconds and self-heal once topics are available.
- The startup probe allows up to 5 minutes (failureThreshold=30, periodSeconds=10) for the app to become ready.

No action is needed — the errors are transient and resolve automatically.

### GKE: kube-state-metrics duplicate timestamp warnings

On GKE clusters, Alloy-Metrics may log `Error on ingesting samples with different value but same timestamp` for kube-state-metrics. This is caused by GKE's managed kube-state-metrics (in `gke-managed-cim` namespace) producing the same metrics as the observability chart's kube-state-metrics. The data loss is cosmetic (duplicate samples are dropped). To resolve, either:

- Disable the chart's kube-state-metrics: set `kubeStateMetrics.enabled: false` in your observability values.
- Or accept the warnings — core metrics are unaffected.
