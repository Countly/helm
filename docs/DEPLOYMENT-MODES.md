# Deployment Modes

## TLS Modes

Set in `global.yaml` -> `ingress.tls.mode`:

| Mode | Description | Requirements |
|------|-------------|-------------|
| `http` | No TLS (default) | None |
| `letsencrypt` | Auto-provisioned via cert-manager | cert-manager + ClusterIssuer, DNS pointing to ingress |
| `existingSecret` | Pre-created TLS secret or ExternalSecret-created TLS secret | Kubernetes TLS secret in countly namespace |
| `selfSigned` | Self-signed CA via cert-manager | cert-manager (dev/local only) |

### Let's Encrypt Example
```yaml
ingress:
  hostname: analytics.example.com
  tls:
    mode: letsencrypt
    clusterIssuer: letsencrypt-prod
```

### Existing Certificate Example
```yaml
ingress:
  hostname: analytics.example.com
  tls:
    mode: existingSecret
    secretName: my-tls-cert    # Must exist in countly namespace
```

### Existing Certificate From Secret Manager Example
```yaml
ingress:
  hostname: analytics.example.com
  tls:
    mode: existingSecret
    secretName: my-tls-cert
    externalSecret:
      enabled: true
      secretStoreRef:
        name: gcp-secrets
        kind: ClusterSecretStore
      remoteRefs:
        # Shared TLS keys for all customers by default.
        # Override only for customer-specific certificates.
        tlsCrt: countly-prod-tls-crt
        tlsKey: countly-prod-tls-key
```

## Backing Service Modes

Set in `global.yaml` -> `backingServices.<service>.mode`:

| Mode | Description |
|------|-------------|
| `bundled` | Deployed in-cluster via operator (default) |
| `external` | Use existing external service |

Each service (mongodb, clickhouse, kafka) can be independently set to bundled or external.

### External MongoDB Example
```yaml
# global.yaml
backingServices:
  mongodb:
    mode: external

# countly.yaml
backingServices:
  mongodb:
    mode: external
    connectionString: "mongodb://user:pass@mongo.example.com:27017/admin?replicaSet=rs0&ssl=true"
```

### External ClickHouse Example
```yaml
# global.yaml
backingServices:
  clickhouse:
    mode: external

# countly.yaml — credentials under backingServices auto-populate the K8s Secret
backingServices:
  clickhouse:
    mode: external
    host: clickhouse.example.com
    port: "8443"
    tls: "true"
    username: default
    password: "my-password"
    database: countly_drill
```

## Observability Modes

Set in `global.yaml` -> `observability.mode`:

| Mode | Backends | Grafana | Collectors | Use Case |
|------|----------|---------|------------|----------|
| `full` | In-cluster | Deployed | Deployed | Self-contained (default) |
| `hybrid` | In-cluster | Not deployed | Deployed | External Grafana |
| `external` | None | None | Deployed | Forward to cloud provider |
| `disabled` | None | None | None | No observability |

Per-signal toggles (metrics, traces, logs, profiling) can be set in `observability.yaml`.

## Secret Modes

Set in `countly.yaml` -> `secrets.mode`:

| Mode | Description |
|------|-------------|
| `values` | Provide secrets directly in values files (default) |
| `existingSecret` | Reference pre-created Kubernetes secrets |
| `externalSecret` | Use External Secrets Operator |

See [SECRET-MANAGEMENT.md](SECRET-MANAGEMENT.md) for details.
