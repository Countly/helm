# Version Matrix

Known-good operator and image version combinations.

| Strimzi | Apache Kafka | CH Sink Connector | ClickHouse | ClickHouse Operator | cert-manager | MongoDB | MCK | NGINX IC | NGINX IC Chart | Status |
|---------|-------------|-------------------|------------|---------------------|--------------|---------|-----|----------|----------------|--------|
| 0.51.0 | 4.2.0 | 1.3.5 | 26.2 | 0.0.2 | 1.17.2 | 8.2.5 | 1.7.0 | 5.3.4 | 2.1.0 | **Current** |

## Observability Stack

| Component | Image | Version | Status |
|-----------|-------|---------|--------|
| Prometheus | `prom/prometheus` | `v3.10.0` | **Current** |
| Grafana | `grafana/grafana` | `12.4.0` | **Current** |
| Loki | `grafana/loki` | `3.6.7` | **Current** |
| Tempo | `grafana/tempo` | `2.10.1` | **Current** |
| Pyroscope | `grafana/pyroscope` | `1.2.0` | **Current** |
| Alloy | `grafana/alloy` | `v1.13.2` | **Current** |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics` | `v2.18.0` | **Current** |
| node-exporter | `prom/node-exporter` | `v1.10.2` | **Current** |

These versions are pinned in `charts/countly-observability/values.yaml` and can be overridden per-component.

## Notes

- **Strimzi** moves fast and may drop older Kafka version support. Pin deliberately and test upgrades.
- **ClickHouse Operator** uses `clickhouse.com/v1alpha1` CRDs. The `clickhouseOperator.apiVersion` value allows overriding when the operator graduates.
- **MCK** (MongoDB Controllers for Kubernetes) manages `MongoDBCommunity` CRDs and generates connection string secrets automatically.
- CR `apiVersion` fields are configurable in each chart's values for forward compatibility.
- **NGINX IC** is the F5 NGINX Ingress Controller (OSS), replacing the retired community ingress-nginx. Chart `nginx-stable/nginx-ingress`.
