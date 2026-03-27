# Countly Migration Helm Chart

Deploys the MongoDB-to-ClickHouse batch migration service for Countly drill events. Reads `drill_events*` collections from MongoDB, transforms documents, and inserts them into the ClickHouse `drill_events` table. Includes a bundled Redis instance for migration state tracking.

**Chart version:** 0.1.0
**App version:** 1.0.0

---

## Architecture

```mermaid
flowchart LR
    subgraph source["Source"]
        mongo["MongoDB\ncountly_drill.drill_events*"]
    end

    subgraph migration["countly-migration namespace"]
        svc["Migration Service\n:8080"]
        redis["Redis\n:6379"]
    end

    subgraph target["Target"]
        ch["ClickHouse\ncountly_drill.drill_events"]
    end

    mongo -->|read batches| svc
    svc -->|insert rows| ch
    svc <-->|hot state, bitmaps,\nerror buffers| redis
    svc -->|run manifests| mongo
```

The migration service is a **singleton Deployment** with `Recreate` strategy. It processes collections sequentially in batches, with full crash recovery and resume support. State is stored in MongoDB (run manifests) and Redis (hot state, processed document bitmaps, error buffers).

---

## Quick Start

**Alongside sibling charts** (default — auto-discovers MongoDB and ClickHouse via DNS):

```bash
helm install countly-migration ./charts/countly-migration \
  -n countly-migration --create-namespace \
  --set backingServices.mongodb.password="YOUR_MONGODB_APP_PASSWORD" \
  --set backingServices.clickhouse.password="YOUR_CLICKHOUSE_PASSWORD"
```

Only two values required. Everything else is auto-detected from the sibling `countly-mongodb` and `countly-clickhouse` charts. Redis is bundled automatically.

**Standalone** (external MongoDB and ClickHouse):

```bash
helm install countly-migration ./charts/countly-migration \
  -n countly-migration --create-namespace \
  --set backingServices.mongodb.mode=external \
  --set backingServices.mongodb.uri="mongodb://app:PASSWORD@mongodb-host:27017/admin?replicaSet=rs0&ssl=false" \
  --set backingServices.clickhouse.mode=external \
  --set backingServices.clickhouse.url="http://clickhouse-host:8123" \
  --set backingServices.clickhouse.password="PASSWORD"
```

> **Production deployment:** Use the profile-based approach from the [root README](../../README.md#manual-installation-without-helmfile) instead of `--set` flags.

The migration service auto-discovers all `drill_events*` collections in the source MongoDB database and begins migrating.

---

## Prerequisites

- **MongoDB** — Source database with `drill_events*` collections in `countly_drill` database
- **ClickHouse** — Target with `drill_events` table in `countly_drill` database
- **Redis** — Bundled by default (Bitnami subchart), or provide an external URL

If deploying alongside other Countly charts, MongoDB and ClickHouse are already available via their respective namespaces.

---

## Configuration

### Backing Services

The chart connects to MongoDB, ClickHouse, and Redis. Each can be configured in **bundled** or **external** mode.

#### MongoDB

| Mode | Description |
|------|-------------|
| `bundled` (default) | Auto-constructs URI from sibling `countly-mongodb` chart using in-cluster DNS |
| `external` | Provide a full connection URI via `backingServices.mongodb.uri` |

```yaml
# Bundled mode (default — alongside countly-mongodb chart)
backingServices:
  mongodb:
    password: "app-user-password"   # Only required field

# External mode
backingServices:
  mongodb:
    mode: external
    uri: "mongodb://app:pass@host:27017/admin?replicaSet=rs0&ssl=false"
```

In bundled mode, the chart constructs the URI as:
`mongodb://app:{password}@{releaseName}-mongodb-svc.{namespace}.svc.cluster.local:27017/admin?replicaSet={releaseName}-mongodb`

Override `releaseName` if your sibling charts use a non-standard prefix (default: `"countly"`).

#### ClickHouse

| Mode | Description |
|------|-------------|
| `bundled` (default) | Auto-constructs URL from sibling `countly-clickhouse` chart using in-cluster DNS |
| `external` | Provide a full HTTP URL via `backingServices.clickhouse.url` |

```yaml
# Bundled mode (default — alongside countly-clickhouse chart)
backingServices:
  clickhouse:
    password: "default-password"    # Only required field

# External mode
backingServices:
  clickhouse:
    mode: external
    url: "http://clickhouse-host:8123"
    password: "default-password"
```

In bundled mode, the chart constructs the URL as:
`http://{releaseName}-clickhouse-clickhouse-headless.{namespace}.svc:8123`

#### Redis

Redis is **enabled by default** as a Bitnami subchart with AOF persistence.

```yaml
# Default: bundled Redis (already enabled)
redis:
  enabled: true

# External Redis: disable subchart and provide URL
redis:
  enabled: false
backingServices:
  redis:
    url: "redis://my-external-redis:6379"
```

### Redis Configuration

The bundled Redis defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| `redis.architecture` | `standalone` | Single-node Redis |
| `redis.auth.enabled` | `false` | No password (internal cluster traffic) |
| `redis.master.persistence.enabled` | `true` | Persistent volume for data |
| `redis.master.persistence.size` | `8Gi` | PVC size |
| `redis.commonConfiguration` | AOF + RDB | `appendonly yes`, `appendfsync everysec`, RDB snapshots |
| `redis.master.resources.requests.cpu` | `500m` | CPU request |
| `redis.master.resources.requests.memory` | `2Gi` | Memory request |
| `redis.master.resources.limits.cpu` | `1` | CPU limit |
| `redis.master.resources.limits.memory` | `2Gi` | Memory limit |

To disable persistence (dev/test only):

```yaml
redis:
  master:
    persistence:
      enabled: false
```

### Secrets

Three modes for managing credentials:

| Mode | Description | Use Case |
|------|-------------|----------|
| `values` (default) | Secret created from Helm values | Development, testing |
| `existingSecret` | Reference a pre-created Kubernetes Secret | Production with manual secret management |
| `externalSecret` | External Secrets Operator (AWS SM, Azure KV) | Production with vault integration |

The Secret must contain these keys: `MONGO_URI`, `CLICKHOUSE_URL`, `CLICKHOUSE_PASSWORD`, `REDIS_URL`.

```yaml
# Production: use pre-created secret
secrets:
  mode: existingSecret
  existingSecret:
    name: countly-migration-secrets
```

### Migration Config

Key environment variables (set via `config.*`):

| Variable | Default | Description |
|----------|---------|-------------|
| `RERUN_MODE` | `resume` | `resume` (crash recovery), `new-run`, `clone-run` |
| `LOG_LEVEL` | `info` | `fatal`, `error`, `warn`, `info`, `debug`, `trace` |
| `MONGO_DB` | `countly_drill` | Source MongoDB database |
| `MONGO_COLLECTION_PREFIX` | `drill_events` | Collection name prefix to discover |
| `MONGO_BATCH_ROWS_TARGET` | `10000` | Documents per batch |
| `CLICKHOUSE_DB` | `countly_drill` | Target ClickHouse database |
| `CLICKHOUSE_TABLE` | `drill_events` | Target table |
| `CLICKHOUSE_USE_DEDUP_TOKEN` | `true` | Deduplication on insert |
| `BACKPRESSURE_ENABLED` | `true` | Monitor ClickHouse compaction pressure |
| `GC_ENABLED` | `true` | Automatic garbage collection |
| `GC_RSS_SOFT_LIMIT_MB` | `1536` | Trigger GC at this RSS |
| `GC_RSS_HARD_LIMIT_MB` | `2048` | Force exit at this RSS |

### ArgoCD Integration

Enable sync-wave annotations and external progress link:

```yaml
argocd:
  enabled: true

externalLink:
  enabled: true
  url: "https://migration.example.internal/runs/current"
```

Sync-wave ordering (within this chart):
- Wave 0: Redis subchart resources, ConfigMap
- Wave 1: Secret
- Wave 10: Deployment, Service, Ingress, ServiceMonitor

At the **stack level** (in `countly-argocd`), migration deploys **last** at wave 20 — after all other charts (databases, Kafka, Countly, observability) are healthy. This ensures the full system is stable before migration begins.

Namespace is created by the ArgoCD Application (`CreateNamespace=true`), not by the chart.

---

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/healthz` | Liveness probe — always returns 200 |
| GET | `/readyz` | Readiness probe — checks MongoDB, ClickHouse, Redis, ManifestStore, BatchRunner |
| GET | `/stats` | Comprehensive JSON stats (throughput, integrity, memory, backpressure) |
| GET | `/runs/current` | Current active run details |
| GET | `/runs` | Paginated list of all runs (`?status=active\|completed\|failed&limit=20`) |
| GET | `/runs/:id` | Single run details |
| GET | `/runs/:id/batches` | Batches for a run (`?status=done\|failed&limit=50`) |
| GET | `/runs/:id/failures` | Failure analysis (errors, mismatches, retries) |
| GET | `/runs/:id/timeline` | Historical timeline snapshots |
| GET | `/runs/:id/coverage` | Coverage percentage and batch counts |
| POST | `/control/pause` | Pause after current batch |
| POST | `/control/resume` | Resume processing |
| POST | `/control/stop-after-batch` | Graceful stop |
| POST | `/control/gc` | Trigger garbage collection (`{"mode":"now\|after-batch\|force"}`) |
| DELETE | `/runs/:id/cache` | Cleanup Redis cache for a completed run |

---

## Verifying the Deployment

### 1. Check pods are running

```bash
kubectl get pods -n countly-migration
```

Expected: migration pod `1/1 Running`, redis-master pod `1/1 Running`.

### 2. Check health

```bash
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/healthz').then(r=>r.text()).then(console.log)"
```

Expected: `{"status":"alive"}`

### 3. Check readiness

```bash
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/readyz').then(r=>r.text()).then(console.log)"
```

Expected: `{"ready":true,"checks":{"mongo":true,"clickhouse":true,"redis":true,"manifestStore":true,"batchRunner":true}}`

### 4. Check migration stats

```bash
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/stats').then(r=>r.json()).then(d=>console.log(JSON.stringify(d,null,2)))"
```

### 5. Check run status

```bash
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/runs?limit=5').then(r=>r.text()).then(console.log)"
```

### 6. Verify data in ClickHouse

```bash
kubectl exec -n clickhouse <clickhouse-pod> -- \
  clickhouse-client --password <password> \
  --query "SELECT count() FROM countly_drill.drill_events"
```

### 7. Port-forward for browser access

```bash
kubectl port-forward -n countly-migration svc/<release>-countly-migration 8080:8080
# Then open: http://localhost:8080/stats
```

---

## Operations

### Pause / Resume

```bash
# Pause after current batch completes
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/control/pause',{method:'POST'}).then(r=>r.text()).then(console.log)"

# Resume
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/control/resume',{method:'POST'}).then(r=>r.text()).then(console.log)"
```

### Check failures

```bash
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/runs/RUNID/failures').then(r=>r.text()).then(console.log)"
```

### Cleanup Redis cache after a completed run

```bash
kubectl exec -n countly-migration deploy/<release>-countly-migration -- \
  node -e "fetch('http://localhost:8080/runs/RUNID/cache',{method:'DELETE'}).then(r=>r.text()).then(console.log)"
```

### View logs

```bash
kubectl logs -n countly-migration -l app.kubernetes.io/name=countly-migration -f
```

---

## Multi-Pod Mode

Scale the migration across multiple pods for faster throughput. Pods coordinate via Redis-based collection locking and range splitting.

```yaml
deployment:
  replicas: 3
  strategy:
    type: RollingUpdate

pdb:
  enabled: true
  minAvailable: 1
```

When `replicas > 1`, the chart automatically:
- Switches to `RollingUpdate` strategy support
- Adds pod anti-affinity (spread across nodes)
- Injects `POD_ID` from pod name for coordination
- Configures preStop drain hook

### Worker settings

| Value | Default | Description |
|-------|---------|-------------|
| `worker.enabled` | `true` | Enable multi-pod coordination |
| `worker.lockTtlSec` | `300` | Collection lock TTL (seconds) |
| `worker.lockRenewMs` | `60000` | Lock renewal interval (ms) |
| `worker.podHeartbeatMs` | `30000` | Heartbeat interval (ms) |
| `worker.podDeadAfterSec` | `180` | Dead pod threshold (seconds) |
| `worker.rangeParallelThreshold` | `500000` | Doc count to trigger range splitting |
| `worker.rangeCount` | `100` | Time ranges per collection |
| `worker.rangeLeaseTtlSec` | `300` | Range lease TTL (seconds) |

For a comprehensive guide on multi-pod operations, scaling, and troubleshooting, see [docs/migration-guide.md](../../docs/migration-guide.md#multi-pod-mode).

---

## Schema Guardrails

The chart includes `values.schema.json` that enforces:

- **`deployment.replicas`** must be `>= 1` — set to 1 for single-pod, or higher for multi-pod
- **`deployment.strategy.type`** must be `Recreate` or `RollingUpdate` — use `RollingUpdate` for multi-pod
- **`secrets.mode`** must be one of: `values`, `existingSecret`, `externalSecret`
- **Worker settings** have minimum value constraints (e.g., `lockTtlSec >= 30`, `podHeartbeatMs >= 1000`)

---

## Examples

See the `examples/` directory:

- **`values-development.yaml`** — Minimal development setup with bundled backing services
- **`values-production.yaml`** — Production setup with `existingSecret` mode
- **`values-multipod.yaml`** — Multi-pod setup with 3 replicas, RollingUpdate, PDB
- **`argocd-application.yaml`** — ArgoCD Application manifest with `CreateNamespace=true`

---

## Full Documentation

For architecture details, configuration reference, operations playbook, API reference, and troubleshooting, see [docs/migration-guide.md](../../docs/migration-guide.md).
