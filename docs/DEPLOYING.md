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
  --set image.tag=latest \
  --set secrets.common.encryptionReportsKey=<key> \
  --set secrets.common.webSessionSecret=<secret> \
  --set secrets.common.passwordSecret=<secret> \
  --set secrets.clickhouse.password=<clickhouse-password> \
  -n countly --create-namespace
```

## Tier Profiles

| Profile | Use Case | Approx Resources |
|---------|----------|------------------|
| `tier1` | Development / small deployments | ~8 CPU req / ~20Gi RAM req |
| `tier2` | Production | Full resources, HA replicas, PDBs |

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
helm uninstall countly-kafka -n kafka
helm uninstall countly-clickhouse -n clickhouse
helm uninstall countly-mongodb -n mongodb
```

> **Note:** Secrets with `helm.sh/resource-policy: keep` survive uninstall. Delete manually if needed.
