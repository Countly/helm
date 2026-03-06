# Secret Management

## Overview

Each chart manages secrets in its own namespace. Secrets use a **lookup-or-create** pattern: if a secret already exists in the cluster and no new value is provided, the existing value is preserved on upgrade.

## Secret Ownership

| Secret | Chart | Namespace | Description |
|--------|-------|-----------|-------------|
| `<release>-common` | countly | countly | Encryption key, session secret, password secret |
| `<release>-clickhouse` | countly | countly | ClickHouse URL, credentials |
| `<release>-kafka` | countly | countly | Kafka brokers, SASL credentials |
| `app-mongodb-conn` | countly-mongodb (operator) | mongodb | MongoDB connection string |
| `app-user-password` | countly-mongodb | mongodb | MongoDB user passwords |
| `clickhouse-default-password` | countly-clickhouse | clickhouse | ClickHouse default user password |
| `clickhouse-auth` | countly-kafka | kafka | ClickHouse creds for Kafka Connect |

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

## Cross-Chart Credential Sharing

ClickHouse password appears in 3 namespaces. Use `values-common.yaml` to set it once:

```yaml
# values-common.yaml (or overlay)
secrets:
  clickhouse:
    password: "new-password"
  rotationId: "2024-01-15-rotation"
```
