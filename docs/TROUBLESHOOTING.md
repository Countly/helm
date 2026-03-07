# Troubleshooting

Common issues encountered during deployment and their solutions.

---

## ClickHouse

### IPv6 listen failure (GKE / clusters without IPv6)

**Error:** `Listen [::]:9009 failed: Address family for hostname not supported`

**Fix:** Add `listen_host: "0.0.0.0"` and `interserver_listen_host: "0.0.0.0"` to ClickHouse `extraConfig`. The default chart values already include this for GKE compatibility.

### Prometheus port conflict

**Error:** `Listen [0.0.0.0]:9363 failed: Address already in use`

**Cause:** The ClickHouse Operator configures Prometheus independently. Do not add a `prometheus` block in `extraConfig` — it conflicts with the operator's own configuration.

### Service DNS name mismatch

**Error:** `getaddrinfo ENOTFOUND countly-clickhouse.clickhouse.svc`

**Cause:** The official ClickHouse Operator creates services with the pattern `<cr-name>-clickhouse-headless`, not `<cr-name>`. The correct service name is `countly-clickhouse-clickhouse-headless.clickhouse.svc`.

**Fix:** Already handled in the chart helpers. If you override `secrets.clickhouse.host`, use the full service name.

---

## MongoDB

### Exporter container bootstrap deadlock

**Error:** Exporter container `CreateContainerConfigError` — secret not found.

**Cause:** The MongoDB operator creates connection string secrets only after the replica set is ready, but pod readiness requires all containers to be running.

**Fix:** The chart uses `optional: true` on the exporter's `secretKeyRef`. The exporter container starts without the secret and stabilizes once the operator creates it.

### User roles too restrictive

**Symptom:** Countly fails to create or access databases beyond `countly` and `countly_drill`.

**Fix:** The `app` user needs `readWriteAnyDatabase` on `admin` (default in the chart). If you've overridden the roles, ensure they match:

```yaml
users:
  app:
    roles:
      - { name: readWriteAnyDatabase, db: admin }
      - { name: dbAdmin, db: countly }
```

---

## Kafka

### Topic creation fails — replication factor exceeds broker count

**Error:** `Failed to create topic drill-events: Topic creation errors`

**Cause:** Default `COUNTLY_CONFIG__KAFKA_REPLICATIONFACTOR: "2"` but tier1 deploys only 1 broker.

**Fix:** The tier1 values already set `config.kafka.COUNTLY_CONFIG__KAFKA_REPLICATIONFACTOR: "1"`. If you use a custom tier with fewer than 2 brokers, override this value.

### Kafka Connect connector 400 — consumer override policy

**Error:** `The 'None' policy does not allow 'max.poll.records' to be overridden`

**Cause:** `connector.client.config.override.policy` was set to `None`. The ClickHouse sink connector needs to tune consumer settings for high-throughput batching.

**Fix:** Already set to `All` in chart defaults. If you've overridden `kafkaConnect.workerConfig`, ensure:

```yaml
kafkaConnect:
  workerConfig:
    connector.client.config.override.policy: All
```

### Countly cannot reach Kafka Connect REST API

**Symptom:** Countly health manager reports Kafka Connect unreachable on port 8083.

**Cause:** Strimzi auto-creates a NetworkPolicy on Kafka Connect pods that only allows traffic from other Connect pods and the cluster-operator.

**Fix:** The chart creates an additional NetworkPolicy allowing the `countly` namespace to reach port 8083. Ensure `networkPolicy.allowedNamespaces` includes your Countly namespace.

---

## Countly Application

### Pods fail health probes — listening on localhost

**Error:** `Startup probe failed: dial tcp <pod-ip>:3020: connect: connection refused`

**Cause:** Missing `HOST: "0.0.0.0"` config for the component. Kubernetes probes connect via the pod IP, not localhost.

**Fix:** Already included in chart defaults. All components have `COUNTLY_CONFIG__<COMPONENT>_HOST: "0.0.0.0"` in their config sections.

### Cross-namespace secret reference fails

**Error:** Countly pods reference a secret that exists in a different namespace.

**Cause:** Kubernetes secrets are namespace-scoped. The MongoDB operator creates secrets in the `mongodb` namespace, but Countly runs in the `countly` namespace.

**Fix:** The chart computes the MongoDB connection string from service DNS and creates its own secret in the `countly` namespace. Do not set `secrets.mongodb.existingSecret` to a cross-namespace secret — instead provide `secrets.mongodb.password` or `secrets.mongodb.connectionString`.

---

## F5 NGINX Ingress Controller

### Ingress rejected — invalid annotations

**Symptom:** `kubectl describe ingress countly -n countly` shows `AddedOrUpdatedWithError` events.

**Cause:** F5 NIC validates annotations strictly and rejects invalid ones. Common mistakes:
- Using `"on"`/`"off"` instead of `"True"`/`"False"` for `nginx.org/proxy-buffering`
- Missing `s` suffix on timeouts (e.g., `"60"` instead of `"60s"`)
- Using old `nginx.ingress.kubernetes.io/*` annotations (community ingress-nginx)

**Fix:** Check the events section of `kubectl describe ingress` — F5 NIC logs the reason for rejection. Update annotations to use `nginx.org/*` format.

### Duplicate `proxy_http_version` directive

**Error:** `nginx reload failed: "proxy_http_version" directive is duplicate`

**Cause:** F5 NIC auto-injects `proxy_http_version 1.1` when `nginx.org/keepalive` > 0. If your `location-snippets` also include `proxy_http_version 1.1`, it duplicates.

**Fix:** Remove `proxy_http_version 1.1` from `nginx.org/location-snippets`. The chart defaults already exclude it.

### OTEL export failures

**Error:** `OTel export failure: DNS resolution failed for alloy.observability.svc.cluster.local:4317`

**Cause:** The OTEL exporter endpoint is configured in `f5-nginx-values.yaml` but the Alloy collector is not deployed.

**Fix:** Either deploy the observability stack (`kubectl apply -k observability/`) or remove the `otel-exporter-endpoint` from `f5-nginx-values.yaml`. This error is benign and does not affect traffic.

### TLS secret missing

**Error:** `TLS secret countly-tls is invalid: secret doesn't exist or of an unsupported type`

**Cause:** The ingress references a TLS secret that doesn't exist. By default, TLS is disabled (`tls: []`). If you added a TLS overlay but the secret hasn't been created yet, this error appears.

**Fix:** Use cert-manager (`overlay-tls-letsencrypt.yaml`) which creates the secret automatically, create the secret manually (`overlay-tls-custom.yaml`), or disable TLS entirely (`overlay-tls-none.yaml`). See the [TLS Certificates](../README.md#5-tls-certificates) section.

---

## General

### cert-manager must be installed before ClickHouse Operator

**Error:** `no matches for kind "Certificate" in version "cert-manager.io/v1"`

**Fix:** Install cert-manager first. See [PREREQUISITES.md](PREREQUISITES.md).

### Helm install order matters

Charts must be installed in this order:

1. `countly-mongodb` + `countly-clickhouse` (no dependencies between them)
2. `countly-kafka` (depends on ClickHouse for the sink connector)
3. `countly` (depends on all three)

Helmfile's `needs:` configuration enforces this automatically.
