# Chart Verification Guide

All Countly Helm charts published to `ghcr.io/countly` are cryptographically signed, include a Software Bill of Materials (SBOM), and carry SLSA provenance attestations.

## What Is Verified

| Artifact | Tool | What It Proves |
|----------|------|---------------|
| OCI chart signature | Cosign (keyless/Sigstore) | Chart was built by the official Countly GitHub Actions workflow |
| SBOM (CycloneDX) | Syft + Cosign | Complete list of chart contents for vulnerability scanning |
| SLSA provenance | GitHub Artifact Attestation | Build inputs, environment, and source commit are auditable |

The signing identity is the GitHub Actions OIDC token for the `publish-oci.yml` workflow in the `Countly/helm` repository. No private keys are stored — signing uses Sigstore's keyless flow with short-lived certificates.

## Prerequisites

```bash
# Install Cosign (macOS)
brew install cosign

# Install Cosign (Linux)
curl -sSL https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o /usr/local/bin/cosign
chmod +x /usr/local/bin/cosign

# Optional: Install GitHub CLI (for provenance verification)
brew install gh   # or: https://cli.github.com
```

## Verify Chart Signature

Verify that a chart was signed by the Countly publish workflow:

```bash
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github\.com/Countly/helm/\.github/workflows/publish-oci\.yml@.*' \
  ghcr.io/countly/countly:0.1.0
```

Expected output includes a Sigstore transparency log entry confirming the signing certificate and OIDC identity.

To verify any of the five charts, replace `countly` with:
- `countly-mongodb`
- `countly-clickhouse`
- `countly-kafka`
- `countly-observability`

## Verify and Download SBOM

Verify the SBOM signature:

```bash
cosign verify --attachment sbom \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github\.com/Countly/helm/\.github/workflows/publish-oci\.yml@.*' \
  ghcr.io/countly/countly:0.1.0
```

Download the SBOM for local inspection or scanning:

```bash
cosign download sbom ghcr.io/countly/countly:0.1.0 > countly-sbom.cdx.json
```

The SBOM is in CycloneDX JSON format. You can feed it into vulnerability scanners:

```bash
# Example: scan with Grype
grype sbom:countly-sbom.cdx.json

# Example: scan with Trivy
trivy sbom countly-sbom.cdx.json
```

## Verify Provenance

SLSA provenance attestations are stored in the GitHub attestation store and can be verified with the GitHub CLI:

```bash
gh attestation verify oci://ghcr.io/countly/countly:0.1.0 \
  --owner Countly
```

This confirms the chart was built from a specific commit in the `Countly/helm` repository by the official GitHub Actions workflow.

## Policy Enforcement

For automated verification at deployment time, use a Kubernetes admission controller.

### Kyverno

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-countly-charts
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds: ["Pod"]
      verifyImages:
        - imageReferences: ["ghcr.io/countly/*"]
          attestors:
            - entries:
                - keyless:
                    issuer: https://token.actions.githubusercontent.com
                    subject: "https://github.com/Countly/helm/.github/workflows/publish-oci.yml@*"
```

### OPA Gatekeeper

Use the [Sigstore Policy Controller](https://docs.sigstore.dev/policy-controller/overview/) to enforce signature verification for OCI artifacts pulled from `ghcr.io/countly`.

## Offline Verification

If your environment cannot reach the Sigstore transparency log, you can verify using the bundled Rekor log entry:

```bash
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github\.com/Countly/helm/\.github/workflows/publish-oci\.yml@.*' \
  --offline \
  ghcr.io/countly/countly:0.1.0
```

This works because Cosign embeds the Rekor transparency log entry in the OCI artifact at signing time.
