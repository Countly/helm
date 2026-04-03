#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/new-argocd-customer.sh [--secret-mode values|gcp-secrets] <customer> <server> <hostname> [project]

Example:
  scripts/new-argocd-customer.sh acme https://1.2.3.4 acme.count.ly
  scripts/new-argocd-customer.sh --secret-mode gcp-secrets acme https://1.2.3.4 acme.count.ly

This command:
  1. copies environments/reference to environments/<customer>
  2. updates environments/<customer>/global.yaml with the hostname and default profiles
  3. writes credentials files for either direct values or GCP Secret Manager
  4. creates argocd/customers/<customer>.yaml for the ApplicationSets

Defaults:
  project       countly-customers
  secretMode    values
  sizing        production
  security      open
  tls           letsencrypt
  observability full
  kafkaConnect  balanced
  kafkaConnectSizing auto
  migration     disabled
  gcpSA         set after scaffold for External Secrets Workload Identity
EOF
}

secret_mode="values"
positionals=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secret-mode)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --secret-mode" >&2
        exit 1
      fi
      secret_mode="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positionals+=("$1")
        shift
      done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

case "${secret_mode}" in
  values|direct)
    secret_mode="values"
    ;;
  gcp-secrets)
    ;;
  *)
    echo "Unsupported --secret-mode: ${secret_mode}" >&2
    echo "Supported values: values, gcp-secrets" >&2
    exit 1
    ;;
esac

if [[ ${#positionals[@]} -lt 3 || ${#positionals[@]} -gt 4 ]]; then
  usage
  exit 1
fi

customer="${positionals[0]}"
server="${positionals[1]}"
hostname="${positionals[2]}"
project="${positionals[3]:-countly-customers}"

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

mkdir -p "$(dirname "${customer_file}")"

cp -R "${repo_root}/environments/reference" "${env_dir}"

cat > "${env_dir}/global.yaml" <<EOF
# =============================================================================
# Countly Deployment — Global Configuration
# =============================================================================

global:
  sizing: production
  observability: full
  kafkaConnect: balanced
  kafkaConnectSizing: auto
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

if [[ "${secret_mode}" == "gcp-secrets" ]]; then
  cat > "${env_dir}/countly.yaml" <<'EOF'
# Customer-specific Countly overrides only.
# TLS Secret Manager support is prewired below and becomes active only when:
#   - argocd/customers/<customer>.yaml sets tls: provided
#   - the shared Secret Manager keys exist
# By default this reuses one shared certificate for every customer:
#   - countly-prod-tls-crt
#   - countly-prod-tls-key
# Override these remoteRefs only if a specific customer needs its own cert.
ingress:
  tls:
    externalSecret:
      enabled: true
      refreshInterval: "1h"
      secretStoreRef:
        name: gcp-secrets
        kind: ClusterSecretStore
      remoteRefs:
        tlsCrt: countly-prod-tls-crt
        tlsKey: countly-prod-tls-key
EOF

  cat > "${env_dir}/credentials-countly.yaml" <<EOF
# Countly secrets sourced from Google Secret Manager through External Secrets.
secrets:
  mode: externalSecret
  clickhouse:
    username: "default"
    database: "countly_drill"
  kafka:
    securityProtocol: "PLAINTEXT"
  externalSecret:
    refreshInterval: "1h"
    secretStoreRef:
      name: gcp-secrets
      kind: ClusterSecretStore
    remoteRefs:
      common:
        encryptionReportsKey: "${customer}-countly-encryption-reports-key"
        webSessionSecret: "${customer}-countly-web-session-secret"
        passwordSecret: "${customer}-countly-password-secret"
      clickhouse:
        password: "${customer}-countly-clickhouse-password"
      mongodb:
        password: "${customer}-mongodb-app-password"
EOF

  cat > "${env_dir}/credentials-kafka.yaml" <<EOF
# Kafka secrets sourced from Google Secret Manager through External Secrets.
secrets:
  mode: externalSecret
  externalSecret:
    refreshInterval: "1h"
    secretStoreRef:
      name: gcp-secrets
      kind: ClusterSecretStore
    remoteRefs:
      clickhouse:
        password: "${customer}-kafka-connect-clickhouse-password"
EOF

  cat > "${env_dir}/credentials-clickhouse.yaml" <<EOF
# ClickHouse secrets sourced from Google Secret Manager through External Secrets.
secrets:
  mode: externalSecret
  externalSecret:
    refreshInterval: "1h"
    secretStoreRef:
      name: gcp-secrets
      kind: ClusterSecretStore
    remoteRefs:
      defaultUserPassword: "${customer}-clickhouse-default-user-password"
EOF

  cat > "${env_dir}/credentials-mongodb.yaml" <<EOF
# MongoDB secrets sourced from Google Secret Manager through External Secrets.
secrets:
  mode: externalSecret
  externalSecret:
    refreshInterval: "1h"
    secretStoreRef:
      name: gcp-secrets
      kind: ClusterSecretStore
    remoteRefs:
      admin:
        password: "${customer}-mongodb-admin-password"
      app:
        password: "${customer}-mongodb-app-password"
      metrics:
        password: "${customer}-mongodb-metrics-password"

users:
  admin:
    enabled: true
  metrics:
    enabled: true
EOF
else
  cat > "${env_dir}/countly.yaml" <<'EOF'
# Customer-specific Countly overrides only.
# Leave this file minimal so sizing / TLS / observability / security profiles apply cleanly.
EOF

  cat > "${env_dir}/credentials-countly.yaml" <<'EOF'
# Countly secrets — FILL IN before first deploy
# Passwords must match across charts (see secrets.example.yaml)
secrets:
  mode: values
  common:
    encryptionReportsKey: ""     # REQUIRED: min 8 chars
    webSessionSecret: ""         # REQUIRED: min 8 chars
    passwordSecret: ""           # REQUIRED: min 8 chars
  clickhouse:
    username: "default"
    password: ""                 # REQUIRED: must match credentials-clickhouse.yaml
    database: "countly_drill"
  kafka:
    securityProtocol: "PLAINTEXT"
  mongodb:
    password: ""                 # REQUIRED: must match credentials-mongodb.yaml users.app.password
EOF

  cat > "${env_dir}/credentials-kafka.yaml" <<'EOF'
# Kafka secrets — FILL IN before first deploy
secrets:
  mode: values

kafkaConnect:
  clickhouse:
    password: ""                 # REQUIRED: must match ClickHouse default user password
EOF

  cat > "${env_dir}/credentials-clickhouse.yaml" <<'EOF'
# ClickHouse secrets — FILL IN before first deploy
secrets:
  mode: values

auth:
  defaultUserPassword:
    password: ""                 # REQUIRED: must match credentials-countly.yaml secrets.clickhouse.password
EOF

  cat > "${env_dir}/credentials-mongodb.yaml" <<'EOF'
# MongoDB secrets — FILL IN before first deploy
secrets:
  mode: values

users:
  admin:
    enabled: true
    password: ""                 # REQUIRED: MongoDB super admin/root-style user
  app:
    password: ""                 # REQUIRED: must match credentials-countly.yaml secrets.mongodb.password
  metrics:
    enabled: true
    password: ""                 # REQUIRED: metrics exporter password
EOF
fi

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
kafkaConnectSizing: auto
migration: disabled
nginxIngress:
  service:
    loadBalancerIP: ""              # Optional: reserve a static GCP IP and set it here for the nginx LoadBalancer
EOF

cat <<EOF
Created:
  ${env_dir}
  ${customer_file}

Important:
  - This scaffold creates safe generic defaults, not final production values.
  - Before syncing Argo, you still must update:
    * argocd/customers/${customer}.yaml
    * environments/${customer}/global.yaml
    * environments/${customer}/credentials-*.yaml
  - Set server to the actual cluster endpoint Argo knows, not an arbitrary IP.
  - The generated credentials files are already shaped for secret mode: ${secret_mode}

Next:
  1. Fill in or confirm environments/${customer}/credentials-*.yaml
  2. Set argocd/customers/${customer}.yaml cluster metadata
  3. Review environments/${customer}/*.yaml for customer-specific overrides
  4. If using GCP Secret Manager, create secrets using the ${customer}-<component>-<secret> convention
  5. Commit and sync countly-bootstrap
EOF
