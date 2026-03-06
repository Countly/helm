# Countly Helm Charts

Helm-based deployment for Countly across 4 namespaces, each managed by its own chart.

> **Quick Start:** Install [operators](#1-prerequisites), [build the Kafka Connect image](#2-build-kafka-connect-image), then run `helmfile -e tier1 apply`. For production, use `tier2`. See [docs/DEPLOYING.md](docs/DEPLOYING.md) for the full guide.

| Chart | Namespace | What it deploys |
|-------|-----------|-----------------|
| `countly` | countly | API, Frontend, Ingestor, Aggregator, JobServer + Ingress |
| `countly-mongodb` | mongodb | MongoDBCommunity ReplicaSet (operator CR) |
| `countly-clickhouse` | clickhouse | ClickHouseCluster + KeeperCluster (operator CRs) |
| `countly-kafka` | kafka | Kafka cluster (KRaft) + KafkaConnect + Connectors (Strimzi CRs) |

Charts render **operator Custom Resources** — they do not install the operators themselves.

---

## 1. Prerequisites

### Tools

- [Helm](https://helm.sh/) v3.12+
- [Helmfile](https://github.com/helmfile/helmfile) (recommended for multi-chart deploy)
- Docker (to build the Kafka Connect image)
- `kubectl` configured for the target cluster

### Operators

Install these **before** deploying the charts. Versions are pinned — see [docs/VERSION-MATRIX.md](docs/VERSION-MATRIX.md).

**cert-manager** (required by ClickHouse Operator):

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --version v1.17.2 \
  --set crds.enabled=true \
  --create-namespace -n cert-manager
```

**ClickHouse Operator:**

```bash
helm install clickhouse-operator \
  oci://ghcr.io/clickhouse/clickhouse-operator-helm \
  --version 0.0.2 \
  --set certManager.install=false \
  --create-namespace -n clickhouse-operator-system
```

**Strimzi Kafka Operator:**

```bash
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --version 0.49.1 \
  --create-namespace -n kafka
```

**MongoDB Community Operator:**

```bash
helm repo add mongodb https://mongodb.github.io/helm-charts
helm install mongodb-operator mongodb/community-operator \
  --version 0.13.0 \
  --create-namespace -n mongodb
```

**NGINX Ingress Controller** (if not already present):

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --create-namespace -n ingress-nginx
```

Verify all operators are running:

```bash
kubectl get pods -n cert-manager
kubectl get pods -n clickhouse-operator-system
kubectl get pods -n kafka
kubectl get pods -n mongodb
```

---

## 2. Build Kafka Connect Image

A custom image bundles the ClickHouse Sink Connector plugin into Strimzi's Kafka Connect base.

```bash
cd helm/kafka-connect-build
docker build -t <your-registry>/kafka-connect-clickhouse:1.3.5 .
docker push <your-registry>/kafka-connect-clickhouse:1.3.5
```

---

## 3. Configuration

### Values hierarchy

Values are layered (last file wins):

```
values-common.yaml          # Shared defaults (image registry, storage class, etc.)
  └─ environments/<tier>/values.yaml   # Tier profile (tier1 = dev, tier2 = production)
       └─ customer-overlay.yaml        # Customer-specific overrides (ingress host, secrets, resources)
```

### Tier profiles

| Tier | Use case | Approx resources |
|------|----------|------------------|
| `tier1` | Development / small | ~8 CPU / ~20 Gi RAM |
| `tier2` | Production | Full HA, PDBs, anti-affinity |

### Required secrets

On **first install**, these must be provided (via `--set`, overlay file, or external secret manager):

| Secret | Flag | Notes |
|--------|------|-------|
| Encryption key | `secrets.common.encryptionReportsKey` | Min 8 chars |
| Session secret | `secrets.common.webSessionSecret` | Min 8 chars |
| Password secret | `secrets.common.passwordSecret` | Min 8 chars |
| ClickHouse password | `secrets.clickhouse.password` | Used by app + Connect |
| MongoDB app password | `users.app.password` | In countly-mongodb chart |
| MongoDB metrics password | `users.metrics.password` | In countly-mongodb chart |
| MongoDB password (app side) | `secrets.mongodb.password` | In countly chart (must match `users.app.password`) |

On **upgrades**, existing secrets are preserved automatically (lookup-or-create pattern).

To use externally managed secrets instead, set `existingSecret` per component — see [docs/SECRET-MANAGEMENT.md](docs/SECRET-MANAGEMENT.md).

---

## 4. Deploy

### Option A: Helmfile (recommended)

```bash
cd helm
helmfile -e tier1 apply
```

Helmfile installs charts in dependency order: MongoDB + ClickHouse first, then Kafka, then Countly.

### Option B: Manual (per-chart)

Install in this exact order:

```bash
cd helm

# 1. MongoDB
helm install countly-mongodb ./charts/countly-mongodb \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set users.app.password='<mongo-password>' \
  --set users.metrics.password='<metrics-password>' \
  -n mongodb --create-namespace

# 2. ClickHouse
helm install countly-clickhouse ./charts/countly-clickhouse \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set auth.defaultUserPassword.password='<ch-password>' \
  -n clickhouse --create-namespace

# 3. Kafka
helm install countly-kafka ./charts/countly-kafka \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set kafkaConnect.image='<your-registry>/kafka-connect-clickhouse:1.3.5' \
  --set kafkaConnect.clickhouse.password='<ch-password>' \
  -n kafka --create-namespace

# 4. Countly (last — depends on all three)
helm install countly ./charts/countly \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  --set image.tag='<version>' \
  --set secrets.common.encryptionReportsKey='<key>' \
  --set secrets.common.webSessionSecret='<secret>' \
  --set secrets.common.passwordSecret='<secret>' \
  --set secrets.clickhouse.password='<ch-password>' \
  --set secrets.mongodb.password='<mongo-password>' \
  -n countly --create-namespace
```

---

## 5. Customer Overlays

Create a YAML file with customer-specific overrides and layer it on top of a tier:

```yaml
# customer-acme.yaml
global:
  storageClass: gp3

image:
  repository: myregistry.example.com/countly-unified
  tag: "24.11.1"

ingress:
  hosts:
    - host: analytics.acme.com
  tls:
    - hosts: [analytics.acme.com]
      secretName: acme-tls

api:
  hpa:
    maxReplicas: 10
  scheduling:
    nodeSelector:
      workload: countly
```

### Apply with Helmfile

Add a new environment in `helmfile.yaml`:

```yaml
environments:
  acme:
```

Create `environments/acme/values.yaml` with your tier base + customer overrides, then:

```bash
helmfile -e acme apply
```

### Apply manually

```bash
helm install countly ./charts/countly \
  -f values-common.yaml \
  -f environments/tier2/values.yaml \
  -f customer-acme.yaml \
  -n countly --create-namespace
```

Repeat for each chart that needs the overlay. See `examples/` for more overlay examples.

---

## 6. Upgrade

```bash
# Helmfile
helmfile -e tier1 apply

# Or per-chart
helm upgrade countly ./charts/countly \
  -f values-common.yaml \
  -f environments/tier1/values.yaml \
  -n countly
```

---

## 7. Uninstall

```bash
# Helmfile
helmfile -e tier1 destroy

# Or per-chart (reverse order)
helm uninstall countly -n countly
helm uninstall countly-kafka -n kafka
helm uninstall countly-clickhouse -n clickhouse
helm uninstall countly-mongodb -n mongodb
```

Secrets with `helm.sh/resource-policy: keep` survive uninstall. Delete manually if needed.

---

## Further Reading

- [docs/PREREQUISITES.md](docs/PREREQUISITES.md) — Detailed operator installation
- [docs/DEPLOYING.md](docs/DEPLOYING.md) — Extended deployment guide
- [docs/SECRET-MANAGEMENT.md](docs/SECRET-MANAGEMENT.md) — Secret rotation, external secrets, cross-chart credentials
- [docs/VERSION-MATRIX.md](docs/VERSION-MATRIX.md) — Pinned operator/image version combinations
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Common issues and fixes
- [examples/](examples/) — Customer overlay, secrets overlay, and Helmfile examples
