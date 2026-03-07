# Secret Management

## Overview

Each chart manages secrets in its own namespace. Secrets use a **lookup-or-create** pattern: if a secret already exists in the cluster and no new value is provided, the existing value is preserved on upgrade.

## Secret Ownership

| Secret | Chart | Namespace | Description |
|--------|-------|-----------|-------------|
| `<release>-common` | countly | countly | Encryption key, session secret, password secret |
| `<release>-clickhouse` | countly | countly | ClickHouse URL, credentials |
| `<release>-kafka` | countly | countly | Kafka brokers, SASL credentials |
| `<release>-mongodb` | countly | countly | MongoDB connection string for the app |
| `app-user-password` | countly-mongodb | mongodb | MongoDB app user password (operator) |
| `metrics-user-password` | countly-mongodb | mongodb | MongoDB metrics user password (operator) |
| `clickhouse-default-password` | countly-clickhouse | clickhouse | ClickHouse default user password |
| `clickhouse-auth` | countly-kafka | kafka | ClickHouse creds for Kafka Connect |
| `countly-tls` | countly | countly | TLS certificate for ingress (cert-manager or user-provided) |

## Using External Secrets

Each secret section supports `existingSecret` to reference a pre-created secret:

```yaml
secrets:
  common:
    existingSecret: my-external-common-secret
  clickhouse:
    existingSecret: my-external-clickhouse-secret
  kafka:
    existingSecret: my-external-kafka-secret
```

## Retention

By default, `secrets.keep: true` adds `helm.sh/resource-policy: keep` so secrets survive `helm uninstall`. Set to `false` to allow deletion.

## Rotation Procedure

1. Update password + `secrets.rotationId` in your values overlay
2. Apply in order (Helmfile `needs:` enforces this automatically):
   - `countly-clickhouse` FIRST — updates ClickHouse auth
   - `countly-kafka` SECOND — updates Connect credentials
   - `countly` LAST — updates app credentials
3. Verify: `kubectl exec -n countly <pod> -- curl -s localhost:3001/o/ping`

The `rotationId` change triggers pod rollouts via annotation checksum.

## TLS Certificates

The ingress TLS secret can be managed in two ways:

1. **cert-manager (recommended):** Use `overlay-tls-letsencrypt.yaml` to add cert-manager annotations. cert-manager provisions and renews the certificate automatically. Requires a ClusterIssuer -- see `k8s/cert-manager/letsencrypt-clusterissuer.yaml`.
2. **Pre-existing secret:** Create a `kubernetes.io/tls` secret externally and use `overlay-tls-custom.yaml` to reference it in `ingress.tls[].secretName`.

See the [TLS Certificates](../README.md#5-tls-certificates) section in the main README for full instructions.

## Cross-Chart Credential Sharing

ClickHouse password appears in 3 namespaces. Use `values-common.yaml` to set it once:

```yaml
# values-common.yaml (or overlay)
secrets:
  clickhouse:
    password: "new-password"
  rotationId: "2024-01-15-rotation"
```
