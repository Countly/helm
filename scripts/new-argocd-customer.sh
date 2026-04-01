#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/new-argocd-customer.sh <customer> <server> <hostname> [project]

Example:
  scripts/new-argocd-customer.sh acme https://1.2.3.4 acme.count.ly

This command:
  1. copies environments/reference to environments/<customer>
  2. updates environments/<customer>/global.yaml with the hostname and default profiles
  3. creates argocd/customers/<customer>.yaml for the ApplicationSets

Defaults:
  project       countly-customers
  sizing        production
  security      open
  tls           letsencrypt
  observability full
  kafkaConnect  balanced
  migration     disabled
  gcpSA         set after scaffold for External Secrets Workload Identity
EOF
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 1
fi

customer="$1"
server="$2"
hostname="$3"
project="${4:-countly-customers}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_dir="${repo_root}/environments/${customer}"
customer_file="${repo_root}/argocd/customers/${customer}.yaml"

if [[ -e "${env_dir}" ]]; then
  echo "Environment already exists: ${env_dir}" >&2
  exit 1
fi

if [[ -e "${customer_file}" ]]; then
  echo "Customer metadata already exists: ${customer_file}" >&2
  exit 1
fi

cp -R "${repo_root}/environments/reference" "${env_dir}"

cat > "${env_dir}/global.yaml" <<EOF
# =============================================================================
# Countly Deployment — Global Configuration
# =============================================================================

global:
  sizing: production
  observability: full
  kafkaConnect: balanced
  tls: letsencrypt
  security: open

  imageRegistry: ""
  imageSource:
    mode: direct
    gcpArtifactRegistry:
      repositoryPrefix: ""
  imagePullSecretExternalSecret:
    enabled: false
    refreshInterval: "1h"
    secretStoreRef:
      name: ""
      kind: ClusterSecretStore
    remoteRef:
      key: ""
  storageClass: ""
  imagePullSecrets: []

ingress:
  hostname: ${hostname}
  className: nginx

backingServices:
  mongodb:
    mode: bundled
  clickhouse:
    mode: bundled
  kafka:
    mode: bundled
EOF

cat > "${env_dir}/countly.yaml" <<'EOF'
# Customer-specific Countly overrides only.
# Leave this file minimal so sizing / TLS / observability / security profiles apply cleanly.
EOF

cat > "${env_dir}/kafka.yaml" <<'EOF'
# Customer-specific Kafka overrides only.
# Leave this file minimal so sizing / kafka-connect / observability / security profiles apply cleanly.
EOF

cat > "${env_dir}/clickhouse.yaml" <<'EOF'
# Customer-specific ClickHouse overrides only.
# Leave this file minimal so sizing / security profiles apply cleanly.
EOF

cat > "${env_dir}/mongodb.yaml" <<'EOF'
# Customer-specific MongoDB overrides only.
# Leave this file minimal so sizing / security profiles apply cleanly.
EOF

cat > "${env_dir}/observability.yaml" <<'EOF'
# Customer-specific observability overrides only.
EOF

cat > "${env_dir}/migration.yaml" <<'EOF'
# Customer-specific migration overrides only.
EOF

cat > "${customer_file}" <<EOF
customer: ${customer}
environment: ${customer}
project: ${project}
server: ${server}
gcpServiceAccountEmail: change-me@your-project.iam.gserviceaccount.com
secretManagerProjectID: change-me-secret-manager-project
clusterProjectID: change-me-cluster-project
clusterName: change-me-cluster-name
clusterLocation: change-me-cluster-location
hostname: ${hostname}
sizing: production
security: open
tls: letsencrypt
observability: full
kafkaConnect: balanced
migration: disabled
EOF

cat <<EOF
Created:
  ${env_dir}
  ${customer_file}

Next:
  1. Fill in environments/${customer}/credentials-*.yaml
  2. Set argocd/customers/${customer}.yaml GCP and cluster metadata for External Secrets
  3. Review environments/${customer}/*.yaml for customer-specific overrides
  4. Create Secret Manager secrets using the ${customer}-<component>-<secret> convention
  5. Commit and sync countly-bootstrap
EOF
