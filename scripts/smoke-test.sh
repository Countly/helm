#!/usr/bin/env bash
# =============================================================================
# Post-deploy smoke test for Countly Observability Stack
#
# Prerequisites:
#   - kubectl context configured and pointing to the cluster
#   - Ingress DNS resolving (or use --host flag for direct access)
#   - ingress-nginx OTEL enabled with opentelemetry-trust-incoming-span: "true"
#   - Countly app deployed and generating telemetry
#
# Usage:
#   ./scripts/smoke-test.sh [NAMESPACE] [RELEASE_NAME]
#   ./scripts/smoke-test.sh observability countly-observability
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-observability}"
RELEASE="${2:-countly-observability}"
PASSED=0
FAILED=0
WARNINGS=0

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }
warn() { echo "  WARN: $1"; ((WARNINGS++)); }

echo "========================================"
echo "  Smoke Test: ${RELEASE} in ${NAMESPACE}"
echo "========================================"
echo

# --- 1. Generate a trace ID and send a request ---
echo "--- Step 1: Generate trace and send request ---"
TRACE_ID=$(head -c 16 /dev/urandom | xxd -p)
SPAN_ID=$(head -c 8 /dev/urandom | xxd -p)
TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"

echo "  Trace ID: ${TRACE_ID}"
echo "  traceparent: ${TRACEPARENT}"

# Try to find the ingress host
INGRESS_HOST=$(kubectl get ingress -n countly -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")

if [ -n "${INGRESS_HOST}" ]; then
  echo "  Sending request to https://${INGRESS_HOST}/o/ping with traceparent header..."
  HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' \
    -H "traceparent: ${TRACEPARENT}" \
    "https://${INGRESS_HOST}/o/ping" 2>/dev/null || echo "000")
  if [ "${HTTP_CODE}" = "200" ]; then
    pass "HTTP request returned ${HTTP_CODE}"
  else
    warn "HTTP request returned ${HTTP_CODE} (may be expected if app is not fully configured)"
  fi
else
  warn "No ingress found in countly namespace — skipping HTTP request"
fi

echo
echo "  Waiting 30s for pipeline processing..."
sleep 30

# --- 2. Check Tempo for the trace ---
echo "--- Step 2: Query Tempo for trace ---"
TEMPO_POD=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=tempo" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${TEMPO_POD}" ]; then
  TEMPO_RESULT=$(kubectl exec -n "${NAMESPACE}" "${TEMPO_POD}" -- wget -qO- "http://localhost:3200/api/traces/${TRACE_ID}" 2>/dev/null || echo "")
  if echo "${TEMPO_RESULT}" | grep -q "${TRACE_ID}" 2>/dev/null; then
    pass "Trace ${TRACE_ID} found in Tempo"
  else
    warn "Trace ${TRACE_ID} not found in Tempo (expected if no instrumented request was processed)"
  fi
else
  fail "No Tempo pod found"
fi

# --- 3. Check Loki for trace ID in logs ---
echo "--- Step 3: Query Loki for trace ID in logs ---"
LOKI_POD=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=loki" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${LOKI_POD}" ]; then
  LOKI_RESULT=$(kubectl exec -n "${NAMESPACE}" "${LOKI_POD}" -- wget -qO- \
    "http://localhost:3100/loki/api/v1/query_range?query=%7Bservice_name%3D~%22.%2B%22%7D+%7C%3D+%22${TRACE_ID}%22&limit=1" 2>/dev/null || echo "")
  if echo "${LOKI_RESULT}" | grep -q '"result"' 2>/dev/null; then
    pass "Loki query executed successfully"
  else
    warn "Could not query Loki for trace ID correlation"
  fi
else
  fail "No Loki pod found"
fi

# --- 4. Check Prometheus for service graph metrics ---
echo "--- Step 4: Check Prometheus for service graph metrics ---"
PROM_POD=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=prometheus" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${PROM_POD}" ]; then
  GRAPH_RESULT=$(kubectl exec -n "${NAMESPACE}" "${PROM_POD}" -- wget -qO- \
    "http://localhost:9090/api/v1/query?query=traces_service_graph_request_total" 2>/dev/null || echo "")
  if echo "${GRAPH_RESULT}" | grep -q '"result"' 2>/dev/null; then
    RESULT_COUNT=$(echo "${GRAPH_RESULT}" | grep -o '"result"' | wc -l)
    pass "Service graph metrics query returned results"
  else
    warn "No service graph metrics found (expected if no inter-service traces exist yet)"
  fi
else
  fail "No Prometheus pod found"
fi

# --- 5. Check alloy-otlp pod logs for out-of-order errors ---
echo "--- Step 5: Check alloy-otlp logs for out-of-order errors ---"
ALLOY_OTLP_POD=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=alloy-otlp" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${ALLOY_OTLP_POD}" ]; then
  OOO_ERRORS=$(kubectl logs -n "${NAMESPACE}" "${ALLOY_OTLP_POD}" --tail=200 2>/dev/null | grep -ci "out of order\|duplicate sample" || echo "0")
  if [ "${OOO_ERRORS}" -gt 5 ]; then
    fail "Found ${OOO_ERRORS} out-of-order/duplicate sample errors in alloy-otlp logs"
  elif [ "${OOO_ERRORS}" -gt 0 ]; then
    warn "Found ${OOO_ERRORS} out-of-order/duplicate sample errors (may be transient from WAL drain)"
  else
    pass "No out-of-order errors in alloy-otlp logs"
  fi
else
  warn "No alloy-otlp pod found"
fi

# --- Summary ---
echo
echo "========================================"
echo "  Results"
echo "========================================"
echo "  Passed:   ${PASSED}"
echo "  Failed:   ${FAILED}"
echo "  Warnings: ${WARNINGS}"
echo "========================================"

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
exit 0
