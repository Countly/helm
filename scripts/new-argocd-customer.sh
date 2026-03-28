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

cat > "${customer_file}" <<EOF
customer: ${customer}
environment: ${customer}
project: ${project}
server: ${server}
sizing: production
security: open
tls: letsencrypt
observability: full
kafkaConnect: balanced
EOF

cat <<EOF
Created:
  ${env_dir}
  ${customer_file}

Next:
  1. Fill in environments/${customer}/secrets-*.yaml
  2. Review environments/${customer}/*.yaml for customer-specific overrides
  3. Commit and sync countly-bootstrap
EOF
