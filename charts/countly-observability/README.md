# Countly Observability Helm Chart

Deploys a four-pillar observability stack (metrics, logs, traces, profiling) purpose-built for monitoring Countly and its dependencies. All components are pre-configured with dashboards, datasources, and collection pipelines -- ready to use out of the box.

**Chart version:** 0.1.0
**App version:** 1.0.0

---

## Components

| Component | Kind | Purpose | Port(s) |
|---|---|---|---|
| Prometheus | StatefulSet | Metrics storage and querying (TSDB) | 9090 |
| Grafana | Deployment | Visualization and dashboards | 3000 |
| Loki | StatefulSet | Log aggregation and querying | 3100, 9096 |
| Tempo | StatefulSet | Distributed trace storage | 3200, 4317 (gRPC), 4318 (HTTP), 9095 |
| Pyroscope | StatefulSet | Continuous profiling backend | 4040, 4041, 4317, 4318 |
| Alloy | DaemonSet | Log collection, OTLP receive, profile forwarding | 4317 (gRPC), 4318 (HTTP), 9999 (Pyroscope), 12345 (UI) |
| Alloy-Metrics | Deployment | Prometheus scraping and remote write | 12345 (UI) |
| kube-state-metrics | Deployment | Kubernetes object metrics | 8080, 8081 |
| node-exporter | DaemonSet | Host-level hardware/OS metrics | 9100 |

---

## Quick Start

```bash
helm install countly-observability ./charts/countly-observability \
  -n observability --create-namespace
```

Access Grafana:

```bash
kubectl port-forward -n observability svc/<release>-countly-observability-grafana 3000:3000
```

Then open `http://localhost:3000`. The default admin password is auto-generated; retrieve it with:

```bash
kubectl get secret -n observability <release>-countly-observability-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## Deployment Modes

The chart supports three modes via the `mode` value:

| Mode | Backends | Grafana | Collectors | Use Case |
|---|---|---|---|---|
| `full` (default) | In-cluster | Deployed | Deployed | Self-contained dev/staging/prod |
| `hybrid` | In-cluster | Not deployed | Deployed | Use your own Grafana instance |
| `external` | Not deployed | Not deployed | Deployed | Forward to Grafana Cloud, Mimir, etc. |

### full (default)

All components are deployed. Nothing extra to configure.

```yaml
mode: full
```

### hybrid

Backends (Prometheus, Loki, Tempo, Pyroscope) run in-cluster but Grafana is not deployed. Point your external Grafana at the in-cluster datasource URLs shown in the helm install notes.

```yaml
mode: hybrid
grafana:
  external:
    url: "https://grafana.corp.com"
```

### external

Only Alloy collectors are deployed. All telemetry is forwarded to external endpoints. You must configure the external URLs for each enabled signal.

```yaml
mode: external

prometheus:
  external:
    remoteWriteUrl: "https://mimir.corp.com/api/v1/push"
    auth:
      existingSecret: "prom-auth"
      bearerTokenKey: "token"

loki:
  external:
    pushUrl: "https://loki.corp.com/loki/api/v1/push"
    auth:
      existingSecret: "loki-auth"
      bearerTokenKey: "token"

tempo:
  external:
    otlpGrpcEndpoint: "tempo.corp.com:4317"
    auth:
      existingSecret: "tempo-auth"
      headerKey: "Authorization"

pyroscope:
  external:
    ingestUrl: "https://pyroscope.corp.com"
    auth:
      existingSecret: "pyroscope-auth"
      headerKey: "Authorization"
```

---

## Per-Signal Toggles

Each observability signal can be enabled or disabled independently:

```yaml
metrics:
  enabled: true    # Prometheus, kube-state-metrics, node-exporter, Alloy-Metrics
traces:
  enabled: true    # Tempo, OTLP pipelines in Alloy
logs:
  enabled: true    # Loki, log collection pipeline in Alloy
profiling:
  enabled: true    # Pyroscope, profile forwarding in Alloy
```

| Signal | Components affected when disabled |
|---|---|
| `metrics.enabled: false` | Prometheus, kube-state-metrics, node-exporter, Alloy-Metrics not deployed |
| `traces.enabled: false` | Tempo not deployed, OTLP forwarding removed from Alloy |
| `logs.enabled: false` | Loki not deployed, log collection removed from Alloy |
| `profiling.enabled: false` | Pyroscope not deployed, profile forwarding removed from Alloy |

Example -- traces and profiling only:

```yaml
metrics:
  enabled: false
logs:
  enabled: false
traces:
  enabled: true
profiling:
  enabled: true
```

---

## Sampling Configuration

### Metrics

```yaml
metrics:
  sampling:
    interval: "15s"   # Prometheus global scrape_interval
```

### Traces

```yaml
traces:
  sampling:
    strategy: "AlwaysOn"    # AlwaysOn | TraceIdRatio | ParentBased
    ratio: 1.0              # 0.0 - 1.0, used when strategy != AlwaysOn
```

### Logs

```yaml
logs:
  sampling:
    enabled: false    # Set to true to enable log sampling
    dropRate: 0       # 0.0 - 1.0, fraction of logs to drop
```

### Profiling

```yaml
profiling:
  sampling:
    rate: "100"   # Advisory only -- shown in NOTES.txt for SDK config, not server-enforced
```

---

## Integration with Countly

To send telemetry from the Countly application chart, add the following overrides to your Countly chart values:

```yaml
config:
  otel:
    OTEL_ENABLED: "true"
    OTEL_EXPORTER_OTLP_ENDPOINT: "http://<release>-countly-observability-alloy.observability.svc.cluster.local:4318"
    PYROSCOPE_ENABLED: "true"
    PYROSCOPE_ENDPOINT: "http://<release>-countly-observability-alloy.observability.svc.cluster.local:9999"
```

Replace `<release>` with the Helm release name used when installing the observability chart. If you installed into a different namespace, update the `.observability.` portion of the FQDN accordingly.

---

## Secret Management

### Grafana admin credentials

By default, the chart auto-generates a random admin password and stores it in a Secret named `<release>-countly-observability-grafana`. To use your own Secret:

```yaml
grafana:
  admin:
    existingSecret: "my-grafana-secret"
    userKey: "admin-user"
    passwordKey: "admin-password"
```

### External endpoint auth

Each backend's `external.auth` block references an existing Secret. Credentials are never stored in `values.yaml` or ConfigMaps.

```yaml
prometheus:
  external:
    auth:
      existingSecret: "prom-remote-write-auth"
      bearerTokenKey: "token"
```

The same pattern applies to `loki.external.auth`, `tempo.external.auth`, and `pyroscope.external.auth`.

### TLS

For external endpoints that require custom CA certificates:

```yaml
prometheus:
  external:
    tls:
      insecureSkipVerify: false
      caSecretName: "custom-ca"
      caKey: "ca.crt"
```

---

## Grafana Dashboards

14 pre-built dashboards are organized in 3 groups. Each group can be toggled independently.

```yaml
grafana:
  dashboards:
    enabled: true       # Master switch for all dashboards
    core: true          # Core observability dashboards
    data: true          # Data infrastructure dashboards
    clickhouse: true    # ClickHouse-specific dashboards
```

### Core dashboards (7)

| Dashboard | Description |
|---|---|
| combined-observability | Unified view across all signals |
| comprehensive-observability | Deep-dive observability overview |
| http-metrics | HTTP request/response metrics |
| infrastructure-metrics | System-level resource metrics |
| nodejs-metrics | Node.js runtime metrics |
| otel-validation | OpenTelemetry pipeline health |
| kubernetes-infrastructure | Kubernetes cluster state and resources |

### Data dashboards (4)

| Dashboard | Description |
|---|---|
| mongodb-comprehensive | MongoDB operations, connections, replication |
| kafka-cluster-comprehensive | Kafka broker and topic metrics |
| kafka-connect-comprehensive | Kafka Connect worker and connector metrics |
| kafka-consumer-lag | Consumer group lag tracking |

### ClickHouse dashboards (3)

| Dashboard | Description |
|---|---|
| clickhouse-comprehensive | ClickHouse server overview |
| clickhouse-query-performance | Query latency and throughput |
| http-traffic-comprehensive | HTTP traffic analysis via ClickHouse |

---

## Version Matrix

| Component | Image | Version |
|---|---|---|
| Prometheus | `prom/prometheus` | v3.10.0 |
| Grafana | `grafana/grafana` | 12.4.0 |
| Loki | `grafana/loki` | 3.6.7 |
| Tempo | `grafana/tempo` | 2.10.1 |
| Pyroscope | `grafana/pyroscope` | 1.2.0 |
| Alloy | `grafana/alloy` | v1.13.2 |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics` | v2.18.0 |
| node-exporter | `prom/node-exporter` | v1.10.2 |

---

## Architecture

Data flows through the stack as follows:

```
Applications (Countly, etc.)
    |
    |--- OTLP (gRPC/HTTP :4317/:4318) ---> Alloy DaemonSet ---> Tempo (traces)
    |--- Profiles (:9999) ----------------> Alloy DaemonSet ---> Pyroscope
    |--- stdout/stderr (container logs) --> Alloy DaemonSet ---> Loki
    |
Kubernetes cluster
    |
    |--- kube-state-metrics, node-exporter, kubelet, cAdvisor
    |         |
    |         +---> Alloy-Metrics Deployment ---> Prometheus (remote write)
    |
Grafana
    |--- queries Prometheus (metrics)
    |--- queries Loki (logs)
    |--- queries Tempo (traces)
    |--- queries Pyroscope (profiles)
```

- **Alloy DaemonSet** runs on every node. It collects container logs (forwarded to Loki), receives OTLP data (forwarded to Tempo), and receives profiles (forwarded to Pyroscope).
- **Alloy-Metrics Deployment** scrapes all Prometheus targets (kube-state-metrics, node-exporter, kubelet, application metrics) and writes to Prometheus via remote write.
- **Grafana** queries all four backends and serves the pre-built dashboards.
- **Tempo** can optionally generate span metrics and write them to Prometheus when metrics are enabled.

---

## Configuration Reference

Below are the most important configuration knobs. See `values.yaml` for the full reference.

| Key | Default | Description |
|---|---|---|
| `mode` | `full` | Deployment mode: `full`, `hybrid`, `external` |
| `clusterName` | `countly-local` | Cluster label injected into Prometheus external_labels |
| `countlyNamespace` | `countly` | Namespace where the Countly app is deployed |
| `clickhouseNamespace` | `clickhouse` | Namespace for ClickHouse scrape targets |
| `mongodbNamespace` | `mongodb` | Namespace for MongoDB scrape targets |
| `kafkaNamespace` | `kafka` | Namespace for Kafka scrape targets |
| `global.storageClass` | `""` | Default StorageClass for all PVCs |
| `global.scheduling.nodeSelector` | `{}` | Default nodeSelector for all workloads |
| `prometheus.retention.time` | `30d` | How long to keep metrics |
| `prometheus.retention.size` | `50GB` | Max TSDB size on disk |
| `prometheus.storage.size` | `100Gi` | PVC size for Prometheus |
| `loki.retention` | `30d` | Log retention period |
| `loki.storage.size` | `100Gi` | PVC size for Loki |
| `loki.config.maxStreamsPerUser` | `10000` | Max active streams per tenant |
| `tempo.retention` | `12h` | Trace retention period |
| `tempo.storage.size` | `150Gi` | PVC size for Tempo |
| `tempo.config.maxTracesPerUser` | `50000` | Max live traces per tenant |
| `pyroscope.storage.size` | `20Gi` | PVC size for Pyroscope |
| `grafana.persistence.enabled` | `false` | Grafana PVC (ephemeral by default -- config is declarative) |
| `grafana.plugins.install` | `grafana-pyroscope-datasource` | Plugins installed on startup |
| `alloyMetrics.replicas` | `1` | Number of metrics collector replicas |

---

## Tier Profiles

The chart is designed to support two resource tiers. Override the resource blocks per component to match your environment.

### tier1 (development / small clusters)

Suitable for development, testing, and small-scale deployments. Uses the default resource values from `values.yaml`:

| Component | CPU request | Memory request | CPU limit | Memory limit |
|---|---|---|---|---|
| Prometheus | 2 | 3Gi | 2 | 4Gi |
| Loki | 500m | 1Gi | 1 | 2Gi |
| Tempo | 3 | 6Gi | 4 | 10Gi |
| Pyroscope | 500m | 1Gi | 1 | 2Gi |
| Grafana | 1 | 1Gi | 2 | 2Gi |
| Alloy | 500m | 1Gi | 2 | 2Gi |
| Alloy-Metrics | 500m | 512Mi | 500m | 512Mi |
| kube-state-metrics | 10m | 32Mi | 100m | 256Mi |
| node-exporter | 102m | 180Mi | 250m | 300Mi |

### tier2 (production)

For production deployments with higher throughput, increase resources. Example overrides:

```yaml
prometheus:
  resources:
    requests:
      cpu: "4"
      memory: "8Gi"
    limits:
      cpu: "4"
      memory: "12Gi"
  storage:
    size: 500Gi

loki:
  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "4"
      memory: "8Gi"
  storage:
    size: 500Gi

tempo:
  resources:
    requests:
      cpu: "4"
      memory: "12Gi"
    limits:
      cpu: "8"
      memory: "16Gi"
  storage:
    size: 500Gi

alloyMetrics:
  replicas: 2
  resources:
    requests:
      cpu: "1"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "2Gi"
```

---

## Ingress

Ingress is available for Grafana in `full` mode only.

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: obs.example.com
  tls:
    - secretName: obs-tls
      hosts:
        - obs.example.com
```

When `mode` is not `full`, Grafana is not deployed and the ingress resource will not be created regardless of this setting.

---

## Network Policy

Enable the NetworkPolicy to restrict traffic to only what the observability stack requires.

```yaml
networkPolicy:
  enabled: true
  additionalIngress: []
```

When enabled, the policy allows:

- Alloy DaemonSet to receive OTLP (4317/4318) and profiles (9999) from application pods
- Alloy to push to Loki, Tempo, and Pyroscope
- Alloy-Metrics to scrape targets and remote-write to Prometheus
- Grafana to query all backends (Prometheus, Loki, Tempo, Pyroscope)
- Prometheus to receive remote write from Alloy-Metrics

Use `additionalIngress` to add custom rules for other namespaces or external systems that need access.

---

## Troubleshooting

### No data in Grafana

1. Verify signals are enabled:
   ```bash
   helm get values <release> -n observability | grep enabled
   ```

2. Check that Alloy pods are running on all nodes:
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/component=alloy
   ```

3. Confirm the application is sending to the correct OTLP endpoint:
   ```bash
   kubectl logs -n observability -l app.kubernetes.io/component=alloy --tail=50
   ```

4. Verify datasources in Grafana are reachable (Configuration > Data sources > Test).

### Permission errors on PVCs

If pods are stuck in `Pending` with PVC-related events:

```bash
kubectl get pvc -n observability
kubectl describe pvc <pvc-name> -n observability
```

Ensure `global.storageClass` or the per-component `storageClass` matches an available StorageClass:

```bash
kubectl get storageclass
```

### Duplicate metrics

If you see duplicate time series in Prometheus:

- Ensure only one `alloyMetrics` replica is running (default is 1). Multiple replicas scraping the same targets will produce duplicates.
- Check that no other Prometheus instance is also scraping the same targets.

### Alloy-Metrics not scraping targets

Check the Alloy-Metrics UI for active targets:

```bash
kubectl port-forward -n observability svc/<release>-countly-observability-alloy-metrics 12345:12345
```

Open `http://localhost:12345` and inspect the targets page.

### Loki rejecting logs

If logs are being dropped, check Loki limits:

```bash
kubectl logs -n observability -l app.kubernetes.io/component=loki --tail=100 | grep -i "rate limit\|max"
```

Increase limits if needed:

```yaml
loki:
  config:
    maxStreamsPerUser: 20000
    ingestionRateMb: 128
    ingestionBurstSizeMb: 256
```

### Tempo rejecting traces

Check Tempo logs for ingestion errors:

```bash
kubectl logs -n observability -l app.kubernetes.io/component=tempo --tail=100 | grep -i "rate\|limit\|reject"
```

Increase limits if needed:

```yaml
tempo:
  config:
    ingestionRateLimitBytes: 200000000
    ingestionBurstSizeBytes: 300000000
    maxTracesPerUser: 100000
```

### Useful commands

```bash
# Overview of all observability pods
kubectl get pods -n observability -o wide

# Check resource usage
kubectl top pods -n observability

# View Prometheus targets (via port-forward)
kubectl port-forward -n observability svc/<release>-countly-observability-prometheus 9090:9090

# View Alloy DaemonSet config
kubectl get configmap -n observability -l app.kubernetes.io/component=alloy -o yaml

# Restart a component
kubectl rollout restart -n observability statefulset/<release>-countly-observability-prometheus
```
