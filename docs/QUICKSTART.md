# Quickstart: Local Deployment (Without Helmfile)

Deploy Countly to Kubernetes using plain `helm install` commands with values files from the `environments/local/` directory.

## Prerequisites

Run from the `helm/` directory. Install operators in any order:

```bash
# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --version v1.17.2 --set crds.enabled=true \
  --create-namespace -n cert-manager

# ClickHouse Operator
helm install clickhouse-operator \
  oci://ghcr.io/clickhouse/clickhouse-operator-helm \
  --version 0.0.2 --set certManager.install=false \
  --create-namespace -n clickhouse-operator-system

# Strimzi Kafka Operator
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --version 0.51.0 --create-namespace -n kafka

# MongoDB Controllers (MCK)
helm repo add mongodb https://mongodb.github.io/helm-charts && helm repo update
kubectl apply -f "https://raw.githubusercontent.com/mongodb/mongodb-kubernetes/1.7.0/public/crds.yaml"
helm upgrade --install mongodb-kubernetes-operator mongodb/mongodb-kubernetes \
  --version 1.7.0 --set 'operator.watchedResources[0]=mongodbcommunity' \
  --create-namespace -n mongodb

# F5 NGINX Ingress Controller
helm repo add nginx-stable https://helm.nginx.com/stable && helm repo update
helm upgrade --install nginx-ingress nginx-stable/nginx-ingress \
  --version 2.1.0 -f nginx-ingress-values.yaml \
  --create-namespace -n ingress-nginx
```

Verify all operators are running:

```bash
kubectl get pods -n cert-manager
kubectl get pods -n clickhouse-operator-system
kubectl get pods -n kafka
kubectl get pods -n mongodb
kubectl get pods -n ingress-nginx
```

## Configuration Model

Each chart layers values files in order:

```
environments/local/global.yaml                    # Global settings (profile selectors)
profiles/sizing/local/<chart>.yaml                # Sizing (resources, replicas, HA)
profiles/<dimension>/<value>/<chart>.yaml          # Optional dimension profiles
environments/local/<chart>.yaml                   # Environment choices (ingress, OTEL, etc.)
environments/local/credentials-<chart>.yaml       # Credentials overrides
```

Important:
- the repo does not ship real local secret files
- create them before installing by copying from `environments/reference/`

Recommended setup:

```bash
cp environments/reference/credentials-countly.yaml environments/local/credentials-countly.yaml
cp environments/reference/credentials-mongodb.yaml environments/local/credentials-mongodb.yaml
cp environments/reference/credentials-clickhouse.yaml environments/local/credentials-clickhouse.yaml
cp environments/reference/credentials-kafka.yaml environments/local/credentials-kafka.yaml
cp environments/reference/credentials-observability.yaml environments/local/credentials-observability.yaml
```

Then fill in the required passwords.

## Install Charts

Run from the `helm/` directory. Order matters — each chart must complete before the next starts.

### 1. MongoDB

```bash
helm install countly-mongodb ./charts/countly-mongodb \
  -n mongodb --create-namespace \
  --wait --timeout 10m \
  -f environments/local/global.yaml \
  -f profiles/sizing/local/mongodb.yaml \
  -f profiles/security/open/mongodb.yaml \
  -f environments/local/mongodb.yaml \
  -f environments/local/credentials-mongodb.yaml
```

### 2. ClickHouse

```bash
helm install countly-clickhouse ./charts/countly-clickhouse \
  -n clickhouse --create-namespace \
  --wait --timeout 10m \
  -f environments/local/global.yaml \
  -f profiles/sizing/local/clickhouse.yaml \
  -f profiles/security/open/clickhouse.yaml \
  -f environments/local/clickhouse.yaml \
  -f environments/local/credentials-clickhouse.yaml
```

### 3. Kafka

```bash
helm install countly-kafka ./charts/countly-kafka \
  -n kafka --create-namespace \
  --wait --timeout 10m \
  -f environments/local/global.yaml \
  -f profiles/sizing/local/kafka.yaml \
  -f profiles/kafka-connect/balanced/kafka.yaml \
  -f profiles/observability/full/kafka.yaml \
  -f profiles/security/open/kafka.yaml \
  -f environments/local/kafka.yaml \
  -f environments/local/credentials-kafka.yaml
```

### 4. Countly

```bash
helm install countly ./charts/countly \
  -n countly --create-namespace \
  --wait --timeout 10m \
  -f environments/local/global.yaml \
  -f profiles/sizing/local/countly.yaml \
  -f profiles/tls/selfSigned/countly.yaml \
  -f profiles/observability/full/countly.yaml \
  -f profiles/security/open/countly.yaml \
  -f environments/local/countly.yaml \
  -f environments/local/credentials-countly.yaml
```

### 5. Observability

```bash
helm install countly-observability ./charts/countly-observability \
  -n observability --create-namespace \
  --wait --timeout 10m \
  -f environments/local/global.yaml \
  -f profiles/sizing/local/observability.yaml \
  -f profiles/observability/full/observability.yaml \
  -f profiles/security/open/observability.yaml \
  -f environments/local/observability.yaml \
  -f environments/local/credentials-observability.yaml
```

## Verify

```bash
kubectl get pods -n mongodb
kubectl get pods -n clickhouse
kubectl get pods -n kafka
kubectl get pods -n countly
kubectl get pods -n observability
```

Application: https://countly.local
Grafana: https://grafana.local

## Upgrade

Replace `helm install` with `helm upgrade` (same flags, omit `--create-namespace`).

If you install the optional migration chart directly, first run:

```bash
helm dependency build ./charts/countly-migration
```

## Uninstall

Reverse order:

```bash
helm uninstall countly-observability -n observability
helm uninstall countly -n countly
helm uninstall countly-kafka -n kafka
helm uninstall countly-clickhouse -n clickhouse
helm uninstall countly-mongodb -n mongodb
```

Note: PVCs and operator-managed resources with `helm.sh/resource-policy: keep` are not deleted. Clean up manually if needed.

## Local Environment Files

```
environments/local/
  global.yaml               # sizing: local
  countly.yaml              # Ingress (countly.local, selfSigned TLS) + OTEL config
  mongodb.yaml              # Empty stub (no local-specific overrides)
  clickhouse.yaml           # ServiceMonitor disabled (no Prometheus Operator CRD)
  kafka.yaml                # JMX metrics disabled (KafkaNodePool CRD limitation)
  observability.yaml        # mode: full, Grafana ingress (grafana.local, selfSigned TLS)
  credentials-countly.yaml       # Create from environments/reference/
  credentials-mongodb.yaml       # Create from environments/reference/
  credentials-clickhouse.yaml    # Create from environments/reference/
  credentials-kafka.yaml         # Create from environments/reference/
  credentials-observability.yaml # Create from environments/reference/
```

## Known Issues (Local)

- **ClickHouse ServiceMonitor**: Disabled because the observability stack uses raw Prometheus (not Prometheus Operator), so the `ServiceMonitor` CRD is not installed.
- **Kafka JMX metrics**: Disabled because `metricsConfig` is not supported on `KafkaNodePool` in Strimzi 0.51.0.
- **Tempo retention**: Must use Go `time.Duration` format (`168h`, not `7d`).
- **TLS certificates**: cert-manager creates the self-signed CA on first install — expect brief `ErrInitIssuer` warnings that resolve within seconds.
