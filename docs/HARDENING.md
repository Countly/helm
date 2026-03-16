# Security Hardening Guide

This guide covers security hardening for Countly Helm deployments in regulated environments (healthcare, financial services, government).

## Network Isolation

### Enable Network Policies

All five charts ship with `networkPolicy.enabled: false` by default. **Enable them in production:**

```yaml
# In each chart's environment file
networkPolicy:
  enabled: true
  allowedNamespaces:
    - countly
    - kafka
    - clickhouse
    - mongodb
    - observability
  monitoring:
    namespace: observability
```

Network policies restrict pod-to-pod communication to only the namespaces that need it. Without them, any pod in the cluster can reach your databases.

### Ingress

- Use TLS in production (`global.tls: letsencrypt` or `global.tls: provided`)
- The `none` (HTTP) profile should only be used for local development
- For internal-only deployments, consider `selfSigned` with your own CA

## Encryption

### In Transit

| Path | Default | Hardened |
|------|---------|---------|
| Client to Ingress | Depends on `global.tls` | `letsencrypt` or `provided` |
| Ingress to Countly pods | HTTP (in-cluster) | Enable NGINX backend TLS if required |
| Countly to MongoDB | Plaintext | Set `mongodb.tls.enabled: true` in mongodb.yaml |
| Countly to ClickHouse | Plaintext | Configure ClickHouse TLS via operator settings |
| Countly to Kafka | Plaintext | Configure Strimzi TLS listeners |
| Observability collectors | HTTP | Configure mTLS on Alloy endpoints |

### At Rest

Storage encryption depends on your Kubernetes cluster's StorageClass:

- **AWS EKS**: Use `gp3` StorageClass with EBS encryption enabled (default in most configurations)
- **GKE**: Uses Google-managed encryption by default; enable CMEK for customer-managed keys
- **Azure AKS**: Uses Azure Disk Encryption by default; enable SSE with customer-managed keys
- **Self-managed**: Configure your CSI driver to use LUKS or dm-crypt

Set `global.storageClass` to an encryption-enabled StorageClass:

```yaml
global:
  storageClass: encrypted-gp3
```

## Secret Management

For regulated environments, avoid storing secrets as plain values:

| Method | Compliance Level | Setup |
|--------|-----------------|-------|
| `values` (default) | Development only | Secrets in gitignored YAML files |
| `existingSecret` | Acceptable | Pre-create K8s Secrets via your secrets pipeline |
| `externalSecret` | Recommended | External Secrets Operator + AWS Secrets Manager / Vault / GCP Secret Manager |

See [SECRET-MANAGEMENT.md](SECRET-MANAGEMENT.md) for setup instructions.

### Secret Rotation

Change `secrets.rotationId` to a new value to trigger secret rotation on the next deploy. This recreates all secrets without changing passwords (the lookup-or-create pattern preserves existing values).

To rotate actual passwords:
1. Update passwords in your secret source (Vault, AWS SM, etc.)
2. Bump `secrets.rotationId`
3. Run `helmfile apply`
4. Restart affected pods

## Pod Security

### Security Contexts

The observability chart's alloy-otlp deployment runs with restricted security contexts:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault
```

The alloy DaemonSet (log collector) requires elevated privileges (`SYS_PTRACE`, root) to read container logs from host paths. This is expected. If log collection is not needed, disable it by setting `global.observability: disabled` or `global.observability: external`.

### Pod Disruption Budgets

The production sizing profile enables PDBs for:
- All Countly components (api, frontend, ingestor, aggregator)
- ClickHouse server and keeper
- MongoDB replica set

Verify PDBs are active: `kubectl get pdb --all-namespaces`

### Anti-Affinity

The production profile uses `preferred` anti-affinity by default. For stricter guarantees (e.g., pods MUST be on separate nodes), override in your environment:

```yaml
# environments/my-deployment/countly.yaml
api:
  scheduling:
    antiAffinity:
      type: required
```

## Audit and Observability

### Application Audit Trail

Countly maintains internal audit logs. Ensure the aggregator and API components have sufficient resources to avoid dropped events.

### Infrastructure Observability

Use `global.observability: full` to deploy the complete monitoring stack. Key dashboards:
- **Overview**: Cluster health, pod status, resource utilization
- **Platform**: Node metrics, network I/O, disk pressure
- **Data**: ClickHouse query performance, Kafka consumer lag
- **Countly**: Application-level metrics, request rates, error rates

### Log Retention

Configure retention periods based on your compliance requirements:

```yaml
# In observability.yaml
prometheus:
  retention:
    time: "90d"      # Metrics retention
loki:
  retention: "90d"   # Log retention
tempo:
  retention: "336h"  # Trace retention (Go duration format, no 'd')
```

## Backup and Disaster Recovery

### What to Back Up

| Component | Data | Method |
|-----------|------|--------|
| MongoDB | Application data, user accounts | `mongodump` or volume snapshots |
| ClickHouse | Analytics/drill data | ClickHouse backup tool or volume snapshots |
| Kafka | Event stream (transient) | Usually not backed up; replay from source |
| Helm releases | Release state | `helm get all` or GitOps (helmfile in git) |
| Secrets | Credentials | External secret store (Vault, AWS SM) |

### Volume Snapshots

If your StorageClass supports `VolumeSnapshot`:

```bash
# Create snapshot of MongoDB PVC
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mongodb-backup-$(date +%Y%m%d)
  namespace: mongodb
spec:
  source:
    persistentVolumeClaimName: data-volume-countly-mongodb-0
EOF
```

### Recovery Procedure

1. Restore PVCs from snapshots or backups
2. Deploy with `helmfile apply` (same environment config)
3. Verify data integrity with `./scripts/smoke-test.sh`

## Upgrade Safety

### Pre-Upgrade Checklist

1. Back up all databases (MongoDB, ClickHouse)
2. Review CHANGELOG.md for breaking changes
3. Test upgrade in a staging environment first
4. Ensure PDBs are healthy: `kubectl get pdb --all-namespaces`
5. Verify sufficient cluster capacity for rolling updates

### Upgrade Command

```bash
helmfile -e my-deployment apply
```

Helmfile handles dependency ordering. Each chart waits for health checks before proceeding to the next.

### Rollback

```bash
helm rollback <release-name> <revision> -n <namespace>
```

Or rollback all charts:

```bash
helmfile -e my-deployment apply  # with previous git commit checked out
```

## Artifact Signing and Supply Chain Security

All Helm charts published to `ghcr.io/countly` are signed and attested at build time:

| Control | Implementation |
|---------|---------------|
| Artifact signing | Cosign keyless (Sigstore OIDC) — identity bound to GitHub Actions workflow |
| SBOM | CycloneDX JSON generated by Syft, attached to each OCI artifact |
| Provenance | SLSA provenance via GitHub Artifact Attestation API |
| Transparency | All signatures logged in the Sigstore Rekor transparency log |

Consumers can verify chart authenticity before deployment. See [VERIFICATION.md](VERIFICATION.md) for step-by-step instructions including:

- `cosign verify` for signature verification
- `cosign download sbom` for SBOM inspection and vulnerability scanning
- `gh attestation verify` for SLSA provenance auditing
- Kyverno/Gatekeeper policy examples for admission-time enforcement

## Compliance Checklist

| Requirement | How Addressed |
|-------------|---------------|
| Encryption in transit | TLS profiles (`letsencrypt`, `provided`) |
| Encryption at rest | StorageClass with encryption |
| Access control | NetworkPolicy, RBAC (operator-managed) |
| Secret management | External Secrets Operator integration |
| Audit logging | Application audit trail, observability stack |
| High availability | Production sizing profile (PDBs, anti-affinity, multi-replica) |
| Backup/recovery | Volume snapshots, database dump tools |
| Monitoring | Full observability stack (metrics, logs, traces, profiling) |
| Vulnerability scanning | CI/CD integration (add Trivy/Snyk to your pipeline) |
| Supply chain integrity | Cosign keyless signing, SLSA provenance, CycloneDX SBOM |
| Change management | GitOps via helmfile, CHANGELOG.md, release-gated OCI publishing |
