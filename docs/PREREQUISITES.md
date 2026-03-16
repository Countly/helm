# Prerequisites

Before deploying the Countly Helm charts, install the required operators. All versions are pinned — see [VERSION-MATRIX.md](VERSION-MATRIX.md) for known-good combinations.

## 0. cert-manager

Required by the ClickHouse Operator for webhook TLS certificates.

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --version v1.17.2 \
  --set crds.enabled=true \
  --create-namespace -n cert-manager
```

## 1. Official ClickHouse Operator

```bash
CLICKHOUSE_OPERATOR_VERSION=0.0.2
helm install clickhouse-operator \
  oci://ghcr.io/clickhouse/clickhouse-operator-helm \
  --version ${CLICKHOUSE_OPERATOR_VERSION} \
  --set certManager.install=false \
  --create-namespace -n clickhouse-operator-system
```

## 2. Strimzi Kafka Operator

```bash
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --version 0.51.0 \
  --create-namespace -n kafka
```

## 3. MongoDB Controllers for Kubernetes (MCK)

```bash
MCK_VERSION=1.7.0
helm repo add mongodb https://mongodb.github.io/helm-charts
helm repo update

# Apply CRDs (Helm does not upgrade CRDs — manual apply required on install and upgrade)
kubectl apply -f "https://raw.githubusercontent.com/mongodb/mongodb-kubernetes/${MCK_VERSION}/public/crds.yaml"

# Install MCK (watchedResources limits scope to community CRs only)
helm upgrade --install mongodb-kubernetes-operator mongodb/mongodb-kubernetes \
  --version ${MCK_VERSION} \
  --set operator.watchedResources[0]=mongodbcommunity \
  --create-namespace -n mongodb
```

## 4. F5 NGINX Ingress Controller (OSS)

```bash
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm upgrade --install nginx-ingress nginx-stable/nginx-ingress \
  --version 2.1.0 \
  -f nginx-ingress-values.yaml \
  --create-namespace -n ingress-nginx
```

Configuration is in `nginx-ingress-values.yaml` — includes global ConfigMap (worker tuning, buffers, timeouts, OTEL), HPA, resources, and Prometheus metrics.

## Verification

Confirm all operator pods are running:

```bash
kubectl get pods -n cert-manager
kubectl get pods -n clickhouse-operator-system
kubectl get pods -n kafka
kubectl get pods -n mongodb
kubectl get pods -n ingress-nginx
```

## 5. Observability Stack (optional)

The `countly-observability` chart does **not** require any operators — it deploys standard Kubernetes workloads (Deployments, StatefulSets, DaemonSets). No additional prerequisites are needed.

See [charts/countly-observability/README.md](../charts/countly-observability/README.md) for configuration.
