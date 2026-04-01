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
| Alloy | DaemonSet | Log collection only | 12345 (UI) |
| Alloy-OTLP | Deployment | OTLP trace receive, profile forwarding | 4317 (gRPC), 4318 (HTTP), 9999 (Pyroscope), 12345 (UI) |
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

Only Alloy collectors (Alloy DaemonSet for logs, Alloy-OTLP Deployment for traces/profiling, Alloy-Metrics for scraping) are deployed. All telemetry is forwarded to external endpoints. You must configure the external URLs for each enabled signal.

```yaml
mode: external

prometheus:
  external:
    remoteWriteUrl: "https://mimir.corp.com/api/v1/push"

loki:
  external:
    pushUrl: "https://loki.corp.com/loki/api/v1/push"

tempo:
  external:
    otlpGrpcEndpoint: "tempo.corp.com:4317"

pyroscope:
  external:
    ingestUrl: "https://pyroscope.corp.com"
```

> **Note:** External endpoints must accept unauthenticated pushes or use network-level auth. Auth header injection is planned for a future release.

---

## Per-Signal Toggles

Each observability signal can be enabled or disabled independently:

```yaml
metrics:
  enabled: true    # Prometheus, kube-state-metrics, node-exporter, Alloy-Metrics
traces:
  enabled: true    # Tempo, OTLP pipeline in Alloy-OTLP
logs:
  enabled: true    # Loki, log collection pipeline in Alloy DaemonSet
profiling:
  enabled: true    # Pyroscope, profile forwarding in Alloy-OTLP
```

| Signal | Components affected when disabled |
|---|---|
| `metrics.enabled: false` | Prometheus, kube-state-metrics, node-exporter, Alloy-Metrics not deployed |
| `traces.enabled: false` | Tempo not deployed, OTLP pipeline removed from Alloy-OTLP |
| `logs.enabled: false` | Loki not deployed, Alloy DaemonSet not deployed |
| `profiling.enabled: false` | Pyroscope not deployed, profiling pipeline removed from Alloy-OTLP |

Alloy-OTLP is deployed when either `traces.enabled` or `profiling.enabled` is true. The Alloy DaemonSet is deployed only when `logs.enabled` is true.

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
    strategy: "AlwaysOn"    # AlwaysOn | TraceIdRatio | ParentBased | TailBased
    ratio: 1.0              # 0.0 - 1.0, used when strategy is TraceIdRatio or ParentBased
    tailSampling:           # Only used when strategy == TailBased
      waitDuration: "10s"
      numTraces: 50000
      policies:
        keepErrors: true          # Keep 100% of ERROR traces
        latencyThresholdMs: 2000  # Keep traces above this latency
        baselineRatio: 0.1        # Sample 10% of remaining traces
```

When `TailBased` is active, the Alloy-OTLP Deployment is forced to 1 replica because tail sampling requires all spans for a trace to hit the same collector instance.

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
    OTEL_EXPORTER_OTLP_ENDPOINT: "http://<release>-countly-observability-alloy-otlp.observability.svc.cluster.local:4318"
    PYROSCOPE_ENABLED: "true"
    PYROSCOPE_ENDPOINT: "http://<release>-countly-observability-alloy-otlp.observability.svc.cluster.local:9999"
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

> **GitOps note:** When using ArgoCD or Flux with `helm template`, set `grafana.admin.existingSecret` to a pre-created Secret. Without it, the admin password regenerates on every render, causing drift.

### External endpoint auth

Auth header injection for external endpoints is planned for a future release. Currently, external endpoints must accept unauthenticated pushes or use network-level authentication (VPN, mTLS at the load balancer, etc.).

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
| Prometheus | `prom/prometheus` | v3.8.1 |
| Grafana | `grafana/grafana` | 12.3.5 |
| Loki | `grafana/loki` | 3.6.3 |
| Tempo | `grafana/tempo` | 2.8.1 |
| Pyroscope | `grafana/pyroscope` | 1.16.0 |
| Alloy | `grafana/alloy` | v1.14.0 |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics` | v2.17.0 |
| node-exporter | `prom/node-exporter` | v1.10.2 |

---

## Architecture

Data flows through the stack as follows:

```
Applications (Countly, etc.)
    |
    |--- OTLP (gRPC/HTTP :4317/:4318) ---> Alloy-OTLP Deployment ---> Tempo (traces)
    |--- Profiles (:9999) ----------------> Alloy-OTLP Deployment ---> Pyroscope
    |--- stdout/stderr (container logs) --> Alloy DaemonSet ---------> Loki
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

- **Alloy DaemonSet** runs on every node. It collects container logs and forwards them to Loki. It does not handle OTLP or profiling traffic.
- **Alloy-OTLP Deployment** receives OTLP traces (forwarded to Tempo) and profiles (forwarded to Pyroscope). It runs as a centralized Deployment, enabling independent scaling and tail sampling support.
- **Alloy-Metrics Deployment** scrapes all Prometheus targets (kube-state-metrics, node-exporter, kubelet, application metrics) and writes to Prometheus via remote write.
- **Grafana** queries all four backends and serves the pre-built dashboards. Cross-signal correlation (trace-to-log, trace-to-profile, trace-to-metrics, service map) is pre-wired.
- **Tempo** generates span metrics and service graph metrics, writing them to Prometheus when metrics are enabled.

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
| `traces.sampling.strategy` | `AlwaysOn` | Sampling strategy: `AlwaysOn`, `TraceIdRatio`, `ParentBased`, `TailBased` |
| `prometheus.retention.time` | `30d` | How long to keep metrics |
| `prometheus.retention.size` | `50GB` | Max TSDB size on disk |
| `prometheus.storage.size` | `100Gi` | PVC size for Prometheus |
| `loki.retention` | `30d` | Log retention period |
| `loki.storage.backend` | `filesystem` | Storage backend: `filesystem`, `s3`, `gcs`, `azure` |
| `loki.storage.size` | `100Gi` | PVC size for Loki |
| `loki.storage.bucket` | `""` | Bucket/container name (required for object backends) |
| `loki.storage.forcePathStyle` | `false` | S3 path-style access for MinIO |
| `loki.storage.existingSecret` | `""` | Mount credential file from K8s Secret |
| `loki.storage.envFromSecret` | `""` | Inject env vars from K8s Secret |
| `loki.config.maxStreamsPerUser` | `10000` | Max active streams per tenant |
| `tempo.retention` | `12h` | Trace retention period |
| `tempo.storage.backend` | `local` | Storage backend: `local`, `s3`, `gcs`, `azure` |
| `tempo.storage.size` | `150Gi` | PVC size for Tempo |
| `tempo.storage.bucket` | `""` | Bucket/container name (required for object backends) |
| `tempo.config.maxTracesPerUser` | `50000` | Max live traces per tenant |
| `pyroscope.retention` | `72h` | Profile retention period (Go duration: `h`, `m`, `s`) |
| `pyroscope.storage.backend` | `filesystem` | Storage backend: `filesystem`, `s3`, `gcs`, `azure`, `swift` |
| `pyroscope.storage.size` | `20Gi` | PVC size for Pyroscope |
| `pyroscope.storage.bucket` | `""` | Bucket/container name (required for object backends) |
| `grafana.persistence.enabled` | `false` | Grafana PVC (ephemeral by default -- config is declarative) |
| `grafana.plugins.install` | `grafana-pyroscope-datasource` | Plugins installed on startup |
| `alloyOtlp.replicas` | `1` | Number of OTLP collector replicas (forced to 1 when TailBased) |
| `alloyOtlp.memoryLimiter.limit` | `1600MiB` | OTEL pipeline memory limit (must be < resources.limits.memory) |
| `alloyMetrics.replicas` | `1` | Number of metrics collector replicas |

---

## Sizing Profiles

The chart is designed to support two resource tiers. Override the resource blocks per component to match your environment.

### small (development / small clusters)

Suitable for development, testing, and small-scale deployments. Uses the default resource values from `values.yaml`:

| Component | CPU request | Memory request | CPU limit | Memory limit |
|---|---|---|---|---|
| Prometheus | 2 | 3Gi | 2 | 4Gi |
| Loki | 500m | 1Gi | 1 | 2Gi |
| Tempo | 3 | 6Gi | 4 | 10Gi |
| Pyroscope | 500m | 1Gi | 1 | 2Gi |
| Grafana | 1 | 1Gi | 2 | 2Gi |
| Alloy (logs) | 500m | 1Gi | 2 | 2Gi |
| Alloy-OTLP (traces/profiling) | 500m | 1Gi | 2 | 2Gi |
| Alloy-Metrics | 500m | 512Mi | 500m | 512Mi |
| kube-state-metrics | 10m | 32Mi | 100m | 256Mi |
| node-exporter | 100m | 180Mi | 250m | 300Mi |

### production

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

## Object Storage

By default, Loki, Tempo, and Pyroscope use filesystem/local storage on PVCs. For production deployments, multiple cloud object storage providers are supported.

### S3 (AWS)

```yaml
loki:
  storage:
    backend: "s3"
    bucket: "my-loki-bucket"
    region: "us-east-1"
    # Uses IRSA for auth (no credentials needed)
```

### S3-compatible (MinIO)

```yaml
tempo:
  storage:
    backend: "s3"
    bucket: "tempo-traces"
    endpoint: "http://minio:9000"
    insecure: true
    forcePathStyle: true
    envFromSecret: "minio-credentials"  # contains ACCESS_KEY, SECRET_KEY
```

### GCS (with Workload Identity -- no credentials)

```yaml
pyroscope:
  storage:
    backend: "gcs"
    bucket: "my-pyroscope-bucket"
```

### GCS (with service account JSON key file)

```yaml
loki:
  storage:
    backend: "gcs"
    bucket: "my-loki-bucket"
    existingSecret: "gcs-credentials"
    secretKey: "key.json"
```

### Azure Blob Storage

```yaml
tempo:
  storage:
    backend: "azure"
    bucket: "tempo-container"  # maps to container_name
    envFromSecret: "azure-storage-creds"
    # Secret should contain: AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_KEY
```

### Credential Model

Three authentication mechanisms are supported:

1. **Credential file secret** (`existingSecret` + `secretKey` + `secretMountPath`) -- Mounts a K8s Secret as a file. Primary use: GCS service account JSON key. Sets `GOOGLE_APPLICATION_CREDENTIALS` automatically for GCS.

2. **Env-based credentials** (`envFromSecret`) -- Injects all keys from a K8s Secret as env vars. Primary use: AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), Azure (`AZURE_STORAGE_ACCOUNT`, `AZURE_STORAGE_KEY`). Works with Tempo/Pyroscope's `-config.expand-env=true`.

3. **No credentials** (default) -- Pod relies on platform-native auth: GKE Workload Identity, AWS IRSA, Azure Managed Identity. Recommended for production.

### Provider-specific passthrough

Use the `config` key to pass additional provider-specific settings directly into the storage config block:

```yaml
loki:
  storage:
    backend: "azure"
    bucket: "my-container"
    config:
      use_managed_identity: true
      user_assigned_id: "my-identity-id"
```

---

## Helm Tests

Run basic backend reachability tests after deploy:

```bash
helm test countly-observability -n observability
```

This validates readiness of Prometheus, Loki, Tempo, Grafana, and Alloy-OTLP (conditional on which signals/modes are enabled).

For end-to-end validation (traces flowing through to Loki, Prometheus metrics generated), use the smoke test script:

```bash
./scripts/smoke-test.sh observability countly-observability
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

- Alloy-OTLP Deployment to receive OTLP traces (4317/4318) and profiles (9999) from application pods
- Alloy DaemonSet to push logs to Loki
- Alloy-OTLP to push traces to Tempo and profiles to Pyroscope
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

2. Check that collector pods are running:
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/component=alloy
   kubectl get pods -n observability -l app.kubernetes.io/component=alloy-otlp
   ```

3. Confirm the application is sending to the correct OTLP endpoint (alloy-otlp):
   ```bash
   kubectl logs -n observability -l app.kubernetes.io/component=alloy-otlp --tail=50
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
