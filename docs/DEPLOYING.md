# Deploying Countly

## Quick Start

### 1. Build the Kafka Connect image

```bash
cd helm/kafka-connect-build
docker build -t myregistry/kafka-connect-clickhouse:1.3.5 .
docker push myregistry/kafka-connect-clickhouse:1.3.5
```

### 2. Deploy with Helmfile (recommended)

```bash
cd helm
helmfile -e tier1 apply
```

### 3. Deploy manually (per-chart)

```bash
cd helm

# MongoDB (first — no dependencies)
helm install countly-mongodb ./charts/countly-mongodb \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set users.app.password=<app-password> \
  --set users.metrics.password=<metrics-password> \
  -n mongodb --create-namespace

# ClickHouse
helm install countly-clickhouse ./charts/countly-clickhouse \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set auth.defaultUserPassword.password=<clickhouse-password> \
  -n clickhouse --create-namespace

# Kafka (after MongoDB + ClickHouse)
helm install countly-kafka ./charts/countly-kafka \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set kafkaConnect.image=myregistry/kafka-connect-clickhouse:1.3.5 \
  --set kafkaConnect.clickhouse.password=<clickhouse-password> \
  -n kafka --create-namespace

# Countly app (last)
helm install countly ./charts/countly \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set image.tag=26.01 \
  --set secrets.common.encryptionReportsKey=<key> \
  --set secrets.common.webSessionSecret=<secret> \
  --set secrets.common.passwordSecret=<secret> \
  --set secrets.clickhouse.password=<clickhouse-password> \
  --set secrets.mongodb.password=<app-password> \
  -n countly --create-namespace
```

### 4. Deploy observability (optional)

```bash
# Full mode (all in-cluster — Prometheus, Grafana, Loki, Tempo, Pyroscope)
helm install countly-observability ./charts/countly-observability \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  -n observability --create-namespace
```

Three deployment modes are available:

| Mode | What it does |
|------|-------------|
| `full` (default) | All backends + Grafana in-cluster |
| `hybrid` | Local backends, external Grafana |
| `external` | Only collectors, send to external endpoints |

```bash
# Hybrid mode (external Grafana)
helm install countly-observability ./charts/countly-observability \
  --set mode=hybrid \
  -n observability --create-namespace

# External mode
helm install countly-observability ./charts/countly-observability \
  --set mode=external \
  --set prometheus.external.remoteWriteUrl=https://prom.example.com/api/v1/write \
  --set loki.external.pushUrl=https://loki.example.com/loki/api/v1/push \
  --set tempo.external.otlpGrpcEndpoint=tempo.example.com:4317 \
  --set pyroscope.external.ingestUrl=https://pyroscope.example.com \
  -n observability --create-namespace
```

To connect Countly to the observability stack, add to your Countly chart values:

```yaml
config:
  otel:
    OTEL_ENABLED: "true"
    OTEL_EXPORTER_OTLP_ENDPOINT: "http://countly-observability-alloy.observability.svc.cluster.local:4318"
    PYROSCOPE_ENABLED: "true"
    PYROSCOPE_ENDPOINT: "http://countly-observability-alloy.observability.svc.cluster.local:9999"
```

## Tier Profiles

| Profile | Use Case | Approx Resources |
|---------|----------|------------------|
| `tier1` | Development / small deployments | ~8 CPU req / ~20Gi RAM req |
| `tier2` | Production | Full resources, HA replicas, PDBs |

## TLS Certificates

For production, use the Let's Encrypt overlay:

```bash
kubectl apply -f k8s/cert-manager/letsencrypt-clusterissuer.yaml
helm install countly ./charts/countly \
  -f examples/overlay-tls-letsencrypt.yaml \
  --set ingress.tls[0].hosts[0]=my-countly.example.com \
  ...
```

For custom certificates or no TLS, see the [TLS Certificates](../README.md#5-tls-certificates) section in the main README.

## Custom Overlays

Create a custom values file for your environment:

```bash
helm install countly ./charts/countly \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  -f my-overlay.yaml \
  -n countly
```

## Upgrading

```bash
helmfile -e tier1 apply
# or per-chart:
helm upgrade countly ./charts/countly -f values-common.yaml -f environments/tier1/values.yaml -n countly
```

## Uninstalling

```bash
helmfile -e tier1 destroy
# or per-chart (reverse order):
helm uninstall countly -n countly
helm uninstall countly-observability -n observability
helm uninstall countly-kafka -n kafka
helm uninstall countly-clickhouse -n clickhouse
helm uninstall countly-mongodb -n mongodb
```

> **Note:** Secrets with `helm.sh/resource-policy: keep` survive uninstall. Delete manually if needed.
