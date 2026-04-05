# Secret Management

## Secret Modes

Set `secrets.mode` in your `countly.yaml`:

### Mode: `values` (default)

Provide secrets directly in your values files:

```yaml
secrets:
  mode: values
  common:
    encryptionReportsKey: "my-key"
    webSessionSecret: "my-session"
    passwordSecret: "my-password"
  clickhouse:
    password: "ch-password"
  mongodb:
    password: "mongo-password"
```

For production, encrypt these files with [SOPS](https://github.com/getsops/sops) and use the [helm-secrets](https://github.com/jkroepke/helm-secrets) plugin.

### Mode: `existingSecret`

Reference pre-created Kubernetes secrets:

```yaml
secrets:
  mode: existingSecret
  common:
    existingSecret: my-countly-common
  clickhouse:
    existingSecret: my-countly-clickhouse
  kafka:
    existingSecret: my-countly-kafka
  mongodb:
    existingSecret: my-countly-mongodb
```

### Mode: `externalSecret`

Use External Secrets Operator to sync from external secret stores:

```yaml
secrets:
  mode: externalSecret
  externalSecret:
    refreshInterval: "1h"
    secretStoreRef:
      name: my-secret-store
      kind: ClusterSecretStore
    remoteRefs:
      common:
        encryptionReportsKey: "countly/encryption-reports-key"
        webSessionSecret: "countly/web-session-secret"
        passwordSecret: "countly/password-secret"
      clickhouse:
        url: "countly/clickhouse-url"
        username: "countly/clickhouse-username"
        password: "countly/clickhouse-password"
        database: "countly/clickhouse-database"
      kafka:
        brokers: "countly/kafka-brokers"
        securityProtocol: "countly/kafka-security-protocol"
      mongodb:
        connectionString: "countly/mongodb-connection-string"
```

## Required Secrets

All secrets are required on first install. On upgrades, existing values are preserved automatically.

| Chart | Secret | Key | Purpose |
|-------|--------|-----|---------|
| countly | common | encryptionReportsKey | Report encryption (min 8 chars) |
| countly | common | webSessionSecret | Session cookie signing (min 8 chars) |
| countly | common | passwordSecret | Password hashing (min 8 chars) |
| countly | clickhouse | password | ClickHouse default user auth |
| countly | mongodb | password | MongoDB app user auth |
| countly-mongodb | users.app | password | Must match countly secrets.mongodb.password |
| countly-mongodb | users.metrics | password | Prometheus exporter auth |
| countly-clickhouse | auth.defaultUserPassword | password | Must match countly secrets.clickhouse.password |
| countly-kafka | kafkaConnect.clickhouse | password | Must match ClickHouse password |

## Secret Rotation

1. Update the password in your values files
2. Change `secrets.rotationId` to trigger pod rollouts:
   ```yaml
   secrets:
     rotationId: "2026-03-08"
   ```
3. Apply charts in order: ClickHouse -> Kafka -> Countly

## Cross-Chart Password Consistency

The ClickHouse password must be identical across three charts:
- `countly.yaml` -> `secrets.clickhouse.password`
- `clickhouse.yaml` -> `auth.defaultUserPassword.password`
- `kafka.yaml` -> `kafkaConnect.clickhouse.password`

For External Secrets / Secret Manager, use one shared secret name for all three
references by default, for example `acme-clickhouse-password`.

The MongoDB password must match across two charts:
- `countly.yaml` -> `secrets.mongodb.password`
- `mongodb.yaml` -> `users.app.password`
