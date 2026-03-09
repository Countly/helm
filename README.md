# Countly Helm Charts

Helm charts for deploying Countly analytics on Kubernetes.

## Architecture

Five charts, each in its own namespace:

| Chart | Namespace | Purpose |
|-------|-----------|---------|
| `countly` | countly | Application (API, Frontend, Ingestor, Aggregator, JobServer) |
| `countly-mongodb` | mongodb | MongoDB via MongoDB Community Operator |
| `countly-clickhouse` | clickhouse | ClickHouse via ClickHouse Operator |
| `countly-kafka` | kafka | Kafka via Strimzi Operator |
| `countly-observability` | observability | Prometheus, Grafana, Loki, Tempo, Pyroscope |

## Quick Start

### Prerequisites

Install required operators before deploying Countly. See [docs/PREREQUISITES.md](docs/PREREQUISITES.md).

### Deploy

1. **Copy the reference environment:**
   ```bash
   cp -r environments/reference environments/my-deployment
   ```

2. **Edit `environments/my-deployment/global.yaml`:**
   - Set `ingress.hostname` to your domain
   - Choose `global.profile`: `local`, `small`, or `production`
   - Choose `ingress.tls.mode`: `letsencrypt`, `existingSecret`, `selfSigned`, or `http`

3. **Fill in required secrets** in the chart-specific files. See `environments/reference/secrets.example.yaml` for a complete reference.

4. **Register your environment** in `helmfile.yaml.gotmpl`:
   ```yaml
   environments:
     my-deployment:
       values:
         - environments/my-deployment/global.yaml
   ```

5. **Deploy:**
   ```bash
   helmfile -e my-deployment apply
   ```

### Manual Installation (without Helmfile)

```bash
helm install countly-mongodb ./charts/countly-mongodb -n mongodb --create-namespace \
  -f profiles/production/mongodb.yaml \
  -f environments/my-deployment/mongodb.yaml

helm install countly-clickhouse ./charts/countly-clickhouse -n clickhouse --create-namespace \
  -f profiles/production/clickhouse.yaml \
  -f environments/my-deployment/clickhouse.yaml

helm install countly-kafka ./charts/countly-kafka -n kafka --create-namespace \
  -f profiles/production/kafka.yaml \
  -f environments/my-deployment/kafka.yaml

helm install countly ./charts/countly -n countly --create-namespace \
  -f profiles/production/countly.yaml \
  -f environments/my-deployment/countly.yaml

helm install countly-observability ./charts/countly-observability -n observability --create-namespace \
  -f profiles/production/observability.yaml \
  -f environments/my-deployment/observability.yaml
```

## Configuration Model

```
chart defaults -> profile (sizing) -> environment (choices) -> secrets
```

### Profiles (`profiles/`)

Profiles control sizing and high-availability settings:
- **`local`** — Minimal resources, single replicas, no HA
- **`small`** — Development/staging, moderate resources
- **`production`** — Full HA with PDBs, anti-affinity, multiple replicas

### Environments (`environments/`)

Environments contain customer-specific choices:
- `global.yaml` — Profile selection, hostname, TLS mode, backing service modes
- `<chart>.yaml` — Per-chart overrides (secrets, network policy, OTEL)
- `secrets-<chart>.yaml` — Per-chart secrets (gitignored)

### Deployment Modes

| Mode | Options | Documentation |
|------|---------|---------------|
| TLS | `http`, `letsencrypt`, `existingSecret`, `selfSigned` | [DEPLOYMENT-MODES.md](docs/DEPLOYMENT-MODES.md) |
| Backing Services | `bundled`, `external` (per service) | [DEPLOYMENT-MODES.md](docs/DEPLOYMENT-MODES.md) |
| Secrets | `values`, `existingSecret`, `externalSecret` | [SECRET-MANAGEMENT.md](docs/SECRET-MANAGEMENT.md) |
| Observability | `full`, `hybrid`, `external`, `disabled` | [DEPLOYMENT-MODES.md](docs/DEPLOYMENT-MODES.md) |

## Documentation

- [DEPLOYING.md](docs/DEPLOYING.md) — Step-by-step deployment guide
- [DEPLOYMENT-MODES.md](docs/DEPLOYMENT-MODES.md) — TLS, observability, backing service modes
- [SECRET-MANAGEMENT.md](docs/SECRET-MANAGEMENT.md) — Secret modes, rotation, ESO integration
- [PREREQUISITES.md](docs/PREREQUISITES.md) — Required operators and versions
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Common issues and fixes
- [VERSION-MATRIX.md](docs/VERSION-MATRIX.md) — Pinned operator and image versions

## Repository Structure

```
helm/
  charts/                           # Helm charts
    countly/
    countly-mongodb/
    countly-clickhouse/
    countly-kafka/
    countly-observability/
  profiles/                         # Sizing profiles
    local/
    small/
    production/
  environments/                     # Customer environments
    reference/                      # Copy this to start
    local/                          # Local development
    customer-small/                 # Example: small deployment
    customer-production/            # Example: production deployment
  docs/                             # Documentation
  helmfile.yaml.gotmpl              # Helmfile orchestration
```
