# Countly Migration Guide

Migrate Countly drill events from MongoDB to ClickHouse. This guide covers architecture, deployment, operations, and troubleshooting.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Multi-Pod Mode](#multi-pod-mode)
- [Configuration Reference](#configuration-reference)
- [Operations](#operations)
- [API Reference](#api-reference)
- [Troubleshooting](#troubleshooting)

---

## Overview

The migration service reads `drill_events*` collections from MongoDB, transforms documents into ClickHouse rows, and inserts them into the `drill_events` table. It handles:

- **Multi-collection discovery** — automatically finds all collections matching the prefix
- **Crash recovery** — resumes from the last committed batch after restart
- **Idempotent inserts** — deduplication tokens prevent duplicate rows on retry
- **Backpressure** — pauses when ClickHouse is under compaction pressure
- **Multi-pod coordination** — distribute work across multiple pods with Redis-based locking

### Data Flow

```
MongoDB                     Migration Service              ClickHouse
(drill_events*)             (1+ pods)                      (drill_events)

 collections ──discover──▶ CollectionOrchestrator
                                │
              ◀──read page──  BatchRunner  ──insert batch──▶
                                │
                            ManifestStore ──state──▶ MongoDB (mig_runs, mig_batches)
                            RedisHotState ──cache──▶ Redis (bitmaps, stats, commands)
```

### Batch Processing Loop

Each batch follows this sequence:

1. **Check commands** — pause, resume, stop-after-batch
2. **Sample backpressure** — query ClickHouse parts count, pause if high
3. **Read page** — cursor-paginated read from MongoDB (`cd`, `_id` compound index)
4. **Transform** — normalize timestamps, derive event names, validate fields
5. **Persist manifest** — write batch metadata to MongoDB with SHA-256 digest
6. **Insert to ClickHouse** — with dedup token and exponential backoff retry
7. **Checkpoint** — atomically mark batch done and advance cursor
8. **Update Redis** — stats, bitmap, timeline (best-effort, non-blocking)
9. **Conditional GC** — trigger if heap/RSS thresholds exceeded

### State Model

| Store | Purpose | Durability |
|-------|---------|------------|
| MongoDB (`mig_runs`, `mig_batches`) | Authoritative run/batch state, cursors, digests | Durable (write concern: majority) |
| Redis | Hot state, completion bitmaps, commands, timeline | Rebuildable from manifest |
| ClickHouse | Target data (append-only with dedup tokens) | Durable |

**Core principle:** MongoDB manifest is authoritative. Redis is rebuildable. ClickHouse is append-only with dedup tokens.

---

## Architecture

### Components

| Component | Responsibility |
|-----------|---------------|
| **CollectionOrchestrator** | Discovers collections, processes them sequentially (single-pod) or coordinates via locks (multi-pod) |
| **BatchRunner** | Core batch loop — read, transform, insert, checkpoint |
| **MongoReader** | Cursor-based pagination on `(cd, _id)` compound index |
| **ClickHouseWriter** | Batch insertion with retry and dedup tokens |
| **ClickHousePressure** | Monitors ClickHouse parts/merges for backpressure |
| **ManifestStore** | MongoDB-backed authoritative state (runs, batches, events) |
| **RedisHotState** | Fast rebuildable cache (bitmaps, stats, commands) |
| **GcController** | Manual V8 garbage collection based on heap/RSS thresholds |
| **HTTP Server** | Health checks, stats, control endpoints, run management |

### Run Modes

| Mode | Behavior |
|------|----------|
| `resume` (default) | Resume active/paused/stopped run, or create new if none exists |
| `new-run` | Mark any active run as completed, start fresh |
| `clone-run` | Clone active run's upper bound, start new run with same boundary |

### Crash Recovery

The service recovers from crashes at any point:

- **Before insert**: Re-reads source data, verifies SHA-256 digest, retries insert
- **After insert, before checkpoint**: Re-inserts with same dedup token (ClickHouse ignores duplicate)
- **After checkpoint**: Resumes from next batch normally

---

## Prerequisites

- **MongoDB** with `drill_events*` collections in `countly_drill` database
- **ClickHouse** with `drill_events` table in `countly_drill` database
- **Redis** for state tracking (bundled by default in the Helm chart)
- **Kubernetes** cluster with the `countly-mongodb` and `countly-clickhouse` charts deployed

The ClickHouse `drill_events` table must exist before starting the migration. The migration service does **not** create the target table.

---

## Deployment

### Minimal (alongside sibling charts)

The chart defaults to **bundled mode** — it auto-discovers MongoDB and ClickHouse from sibling charts via DNS. Only passwords are required:

```bash
helm install countly-migration ./charts/countly-migration \
  -n countly-migration --create-namespace \
  --set backingServices.mongodb.password="YOUR_MONGODB_APP_PASSWORD" \
  --set backingServices.clickhouse.password="YOUR_CLICKHOUSE_PASSWORD"
```

### File-based (recommended)

Create environment files for repeatable deploys:

**`environments/my-env/migration.yaml`:**
```yaml
# Override defaults as needed (empty file uses all defaults)
{}
```

**`environments/my-env/secrets-migration.yaml`:**
```yaml
backingServices:
  mongodb:
    password: "your-mongodb-password"
  clickhouse:
    password: "your-clickhouse-password"
```

Deploy:
```bash
helm install countly-migration ./charts/countly-migration \
  -n countly-migration --create-namespace \
  --wait --timeout 5m \
  -f environments/my-env/global.yaml \
  -f environments/my-env/migration.yaml \
  -f environments/my-env/secrets-migration.yaml
```

### External MongoDB/ClickHouse

If MongoDB and ClickHouse are not deployed via sibling charts:

```bash
helm install countly-migration ./charts/countly-migration \
  -n countly-migration --create-namespace \
  --set backingServices.mongodb.mode=external \
  --set backingServices.mongodb.uri="mongodb://app:PASS@host:27017/admin?replicaSet=rs0&ssl=false" \
  --set backingServices.clickhouse.mode=external \
  --set backingServices.clickhouse.url="http://clickhouse-host:8123" \
  --set backingServices.clickhouse.password="PASS"
```

### Verify deployment

```bash
# 1. Check pods
kubectl get pods -n countly-migration

# 2. Check health (liveness)
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/healthz').then(r=>r.text()).then(console.log)"

# 3. Check readiness (all backing services)
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/readyz').then(r=>r.text()).then(console.log)"

# 4. Check migration progress
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/stats').then(r=>r.json()).then(d=>console.log(JSON.stringify(d,null,2)))"

# 5. View logs
kubectl logs -n countly-migration -l app.kubernetes.io/name=countly-migration -f
```

---

## Multi-Pod Mode

Scale the migration across multiple pods for faster throughput. Each pod picks up collections (or time ranges within large collections) via Redis-based locking.

### How it works

1. **Collection-level locking**: Each pod acquires a Redis lock before processing a collection. Other pods skip locked collections and pick up the next available one.
2. **Range splitting**: Collections larger than `rangeParallelThreshold` documents are split into time ranges. Multiple pods process different ranges of the same collection in parallel.
3. **Heartbeat & dead pod detection**: Pods send heartbeats every `podHeartbeatMs`. If a pod misses heartbeats for `podDeadAfterSec`, its locks are released for other pods to claim.
4. **Lock renewal**: Active locks are renewed every `lockRenewMs` to prevent expiration during long batches.

### Enable multi-pod mode

```yaml
deployment:
  replicas: 3
  strategy:
    type: RollingUpdate

pdb:
  enabled: true
  minAvailable: 1
```

Or via helm:
```bash
helm upgrade countly-migration ./charts/countly-migration \
  -n countly-migration --reuse-values \
  --set deployment.replicas=3 \
  --set deployment.strategy.type=RollingUpdate \
  --set pdb.enabled=true
```

### Worker configuration

| Value | Env Var | Default | Description |
|-------|---------|---------|-------------|
| `worker.enabled` | `MULTI_POD_ENABLED` | `true` | Enable coordination (auto-activates when replicas > 1) |
| `worker.lockTtlSec` | `LOCK_TTL_SECONDS` | `300` | Collection lock TTL (seconds) |
| `worker.lockRenewMs` | `LOCK_RENEW_MS` | `60000` | Lock renewal interval (ms) |
| `worker.podHeartbeatMs` | `POD_HEARTBEAT_MS` | `30000` | Heartbeat interval (ms) |
| `worker.podDeadAfterSec` | `POD_DEAD_AFTER_SEC` | `180` | Dead pod threshold (seconds) |
| `worker.rangeParallelThreshold` | `RANGE_PARALLEL_THRESHOLD` | `500000` | Doc count to trigger range splitting |
| `worker.rangeCount` | `RANGE_COUNT` | `100` | Number of time ranges per collection |
| `worker.rangeLeaseTtlSec` | `RANGE_LEASE_TTL_SEC` | `300` | Range lease TTL (seconds) |
| `worker.progressUpdateMs` | `PROGRESS_UPDATE_MS` | `5000` | Progress report interval (ms) |

### Multi-pod operations

```bash
# Global pause (all pods)
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/global/pause',{method:'POST'}).then(r=>r.text()).then(console.log)"

# Global resume
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/global/resume',{method:'POST'}).then(r=>r.text()).then(console.log)"

# List collection locks
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/locks').then(r=>r.text()).then(console.log)"

# List all pods and their status
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/pods').then(r=>r.text()).then(console.log)"

# Scale up/down
kubectl scale deploy/countly-migration -n countly-migration --replicas=5
```

### When to use multi-pod

- **Many collections**: Multiple pods each take a different collection
- **Large collections** (>500K docs): Range splitting distributes work within a single collection
- **Time-sensitive migrations**: Reduce total wall-clock time by parallelizing

### When single-pod is enough

- Few collections with moderate size
- ClickHouse is the bottleneck (backpressure), not MongoDB reads
- Simpler operations and debugging

---

## Configuration Reference

### Service

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVICE_NAME` | `countly-migration` | Service identifier |
| `SERVICE_PORT` | `8080` | HTTP server port |
| `SERVICE_HOST` | `0.0.0.0` | Bind address |
| `GRACEFUL_SHUTDOWN_TIMEOUT_MS` | `60000` | Shutdown grace period (ms) |
| `RERUN_MODE` | `resume` | `resume`, `new-run`, or `clone-run` |
| `LOG_LEVEL` | `info` | `fatal`, `error`, `warn`, `info`, `debug`, `trace` |

### MongoDB Source

| Variable | Default | Description |
|----------|---------|-------------|
| `MONGO_URI` | *(required)* | Full connection string |
| `MONGO_DB` | `countly_drill` | Source database |
| `MONGO_COLLECTION_PREFIX` | `drill_events` | Prefix to discover collections |
| `MONGO_READ_PREFERENCE` | `primary` | Read preference |
| `MONGO_READ_CONCERN` | `majority` | Read concern level |
| `MONGO_RETRY_READS` | `true` | Retry transient read failures |
| `MONGO_APP_NAME` | `countly-migration` | Driver app name |
| `MONGO_BATCH_ROWS_TARGET` | `10000` | Documents per batch |
| `MONGO_CURSOR_BATCH_SIZE` | `2000` | MongoDB cursor fetch size |
| `MONGO_MAX_TIME_MS` | `120000` | Cursor timeout (ms) |

### ClickHouse Target

| Variable | Default | Description |
|----------|---------|-------------|
| `CLICKHOUSE_URL` | *(required)* | HTTP endpoint |
| `CLICKHOUSE_DB` | `countly_drill` | Target database |
| `CLICKHOUSE_TABLE` | `drill_events` | Target table |
| `CLICKHOUSE_USERNAME` | `default` | Username |
| `CLICKHOUSE_PASSWORD` | *(empty)* | Password |
| `CLICKHOUSE_QUERY_TIMEOUT_MS` | `120000` | Query timeout (ms) |
| `CLICKHOUSE_MAX_RETRIES` | `8` | Max insert retry attempts |
| `CLICKHOUSE_RETRY_BASE_DELAY_MS` | `1000` | Backoff base delay (ms) |
| `CLICKHOUSE_RETRY_MAX_DELAY_MS` | `30000` | Backoff max delay (ms) |
| `CLICKHOUSE_USE_DEDUP_TOKEN` | `true` | Insert deduplication tokens |

### Backpressure

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKPRESSURE_ENABLED` | `true` | Monitor ClickHouse parts |
| `BACKPRESSURE_PARTS_TO_THROW_INSERT` | `300` | Parts threshold to pause |
| `BACKPRESSURE_MAX_PARTS_IN_TOTAL` | `500` | Max total parts |
| `BACKPRESSURE_PARTITION_PCT_HIGH` | `0.50` | Partition high watermark (pause) |
| `BACKPRESSURE_PARTITION_PCT_LOW` | `0.35` | Partition low watermark (resume) |
| `BACKPRESSURE_TOTAL_PCT_HIGH` | `0.50` | Total high watermark (pause) |
| `BACKPRESSURE_TOTAL_PCT_LOW` | `0.40` | Total low watermark (resume) |
| `BACKPRESSURE_POLL_INTERVAL_MS` | `15000` | Polling interval (ms) |
| `BACKPRESSURE_MAX_PAUSE_EPISODE_MS` | `180000` | Max pause duration before force resume (ms) |

### Garbage Collection

| Variable | Default | Description |
|----------|---------|-------------|
| `GC_ENABLED` | `true` | Enable manual V8 GC |
| `GC_RSS_SOFT_LIMIT_MB` | `1536` | RSS threshold to trigger GC |
| `GC_RSS_HARD_LIMIT_MB` | `2048` | RSS threshold to log warning |
| `GC_HEAP_USED_RATIO` | `0.70` | Heap usage ratio trigger |
| `GC_EVERY_N_BATCHES` | `10` | GC every N batches |

### State Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `MANIFEST_DB` | `countly_drill` | MongoDB database for run manifests |
| `REDIS_URL` | *(auto)* | Redis URL (auto-wired from bundled subchart) |
| `REDIS_KEY_PREFIX` | `mig` | Redis key namespace |

### Transform

| Variable | Default | Description |
|----------|---------|-------------|
| `TRANSFORM_VERSION` | `v1` | Transform version tag stored in manifest |

---

## Operations

### Port-forward for browser access

```bash
kubectl port-forward -n countly-migration svc/countly-migration 8080:8080
# Open: http://localhost:8080/stats
```

### Pause and resume

```bash
# Pause after current batch
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/pause',{method:'POST'}).then(r=>r.text()).then(console.log)"

# Resume
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/resume',{method:'POST'}).then(r=>r.text()).then(console.log)"
```

### Graceful stop

```bash
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/stop-after-batch',{method:'POST'}).then(r=>r.text()).then(console.log)"
```

### Check progress

```bash
# Overall stats
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/stats').then(r=>r.json()).then(d=>console.log(JSON.stringify(d,null,2)))"

# Current run
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/runs/current').then(r=>r.text()).then(console.log)"

# All runs
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/runs?limit=10').then(r=>r.text()).then(console.log)"
```

### Check failures

```bash
# Get failure analysis for a run
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/runs/RUN_ID/failures').then(r=>r.text()).then(console.log)"
```

### Cleanup Redis cache

After a run completes, free Redis memory:

```bash
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/runs/RUN_ID/cache',{method:'DELETE'}).then(r=>r.text()).then(console.log)"
```

### Trigger garbage collection

```bash
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/control/gc',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mode:'now'})}).then(r=>r.text()).then(console.log)"
```

### Verify data in ClickHouse

```bash
kubectl exec -n clickhouse <clickhouse-pod> -- \
  clickhouse-client --password <password> \
  --query "SELECT count() FROM countly_drill.drill_events"
```

### View logs

```bash
# All pods
kubectl logs -n countly-migration -l app.kubernetes.io/name=countly-migration -f

# Specific pod
kubectl logs -n countly-migration countly-migration-<pod-id> -f
```

---

## API Reference

### Health

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Liveness probe — always 200 if server is up |
| GET | `/readyz` | Readiness probe — checks MongoDB, ClickHouse, Redis, ManifestStore, BatchRunner |

### Stats

| Method | Path | Description |
|--------|------|-------------|
| GET | `/stats` | Comprehensive JSON: throughput, skip reasons, integrity, memory, backpressure, orchestrator progress |

### Control

| Method | Path | Description |
|--------|------|-------------|
| POST | `/control/pause` | Pause after current batch completes |
| POST | `/control/resume` | Resume from pause |
| POST | `/control/stop-after-batch` | Graceful stop — finish batch, persist state, exit |
| POST | `/control/gc` | Trigger GC. Body: `{"mode": "now"|"force"|"after-batch"}` |
| POST | `/control/drain` | Graceful drain (called by preStop hook) |

### Multi-Pod Control

| Method | Path | Description |
|--------|------|-------------|
| POST | `/control/global/pause` | Pause all pods |
| POST | `/control/global/resume` | Resume all pods |
| POST | `/control/global/stop` | Stop all pods |
| GET | `/control/locks` | List collection locks |
| GET | `/control/pods` | List all pods and their status |

### Run Management

| Method | Path | Description |
|--------|------|-------------|
| GET | `/runs` | List runs. Query: `?status=active\|completed\|failed&limit=20&offset=0` |
| GET | `/runs/current` | Current active run |
| GET | `/runs/:id` | Single run details |
| GET | `/runs/:id/batches` | Batches for a run. Query: `?status=done\|failed&limit=50` |
| GET | `/runs/:id/failures` | Failure analysis — errors, digest mismatches, retries |
| GET | `/runs/:id/timeline` | Performance timeline snapshots |
| GET | `/runs/:id/coverage` | Document range coverage percentage |
| DELETE | `/runs/:id/cache` | Cleanup Redis cache for a completed run |

---

## Troubleshooting

### Pod crashes with "No collections found"

```
Error: No collections found matching prefix "drill_events" in database "countly_drill"
```

**Cause**: The source MongoDB database has no collections matching the prefix.

**Fix**: Ensure `countly_drill` database exists with `drill_events*` collections. Check the MongoDB connection and database name:
```bash
kubectl exec -n countly-migration deploy/countly-migration -- env | grep MONGO
```

### ImagePullBackOff

**Cause**: The container image doesn't exist or registry credentials are missing.

**Fix**: Verify the image exists:
```bash
docker pull countly/countly-migration:latest
```

If using a private registry, set `image.pullSecrets` in values.

### Pod not ready (readiness probe failing)

**Cause**: One or more backing services are unreachable.

**Fix**: Check which service is failing:
```bash
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/readyz').then(r=>r.text()).then(console.log)"
```

Verify MongoDB, ClickHouse, and Redis connectivity from the pod:
```bash
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "console.log(process.env.MONGO_URI, process.env.CLICKHOUSE_URL, process.env.REDIS_URL)"
```

### Backpressure stall (migration paused for a long time)

**Cause**: ClickHouse has too many active parts, likely from a compaction backlog.

**Check**:
```bash
kubectl exec -n countly-migration deploy/countly-migration -- \
  node -e "fetch('http://localhost:8080/stats').then(r=>r.json()).then(d=>console.log(d.clickhouse))"
```

**Fix options**:
- Wait for ClickHouse merges to complete
- Increase `BACKPRESSURE_PARTS_TO_THROW_INSERT` threshold
- Reduce batch size (`MONGO_BATCH_ROWS_TARGET`)
- If truly stuck, the service auto-resumes after `BACKPRESSURE_MAX_PAUSE_EPISODE_MS` (default 3 minutes)

### High memory / OOM kills

**Cause**: Batch processing accumulates memory faster than GC reclaims it.

**Fix**:
- Reduce `MONGO_BATCH_ROWS_TARGET` (smaller batches = less memory per cycle)
- Lower `GC_RSS_SOFT_LIMIT_MB` and `GC_EVERY_N_BATCHES` for more aggressive GC
- Increase container memory limits in `resources.limits.memory`
- Trigger manual GC via `POST /control/gc {"mode":"force"}`

### Digest mismatch warnings

```
Digest mismatch for batch N — source data may have changed between crash and recovery
```

**Cause**: Source MongoDB data was modified between the original insert attempt and the crash recovery re-read.

**Impact**: Low — ClickHouse dedup tokens prevent duplicates. The warning is informational.

**Fix**: No action needed unless mismatches are frequent, which would indicate concurrent writes to the source collections during migration.

### Multi-pod: pods stuck waiting for locks

**Cause**: A pod crashed without releasing its collection lock, and `podDeadAfterSec` hasn't elapsed yet.

**Fix**: Wait for the dead pod threshold (default 180s), then locks are automatically released. To speed up:
```yaml
worker:
  podDeadAfterSec: 60  # Reduce dead pod threshold
```

### Wrong MongoDB/ClickHouse endpoint (bundled mode)

If the sibling charts use non-standard release names:

```yaml
backingServices:
  mongodb:
    releaseName: "my-custom-prefix"  # Default: "countly"
  clickhouse:
    releaseName: "my-custom-prefix"
```

This controls the DNS hostname construction:
- MongoDB: `{releaseName}-mongodb-svc.{namespace}.svc.cluster.local`
- ClickHouse: `{releaseName}-clickhouse-clickhouse-headless.{namespace}.svc`
