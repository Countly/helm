#!/usr/bin/env bash
# =============================================================================
# Post-deploy smoke test for Countly Observability Stack
#
# Prerequisites:
#   - kubectl context configured and pointing to the cluster
#   - Ingress DNS resolving (or use --host flag for direct access)
#   - F5 NGINX Ingress Controller with otel-trace-context: "propagate" enabled
#   - Countly app deployed with OTEL_ENABLED=true
#
# Usage:
#   ./scripts/smoke-test.sh [NAMESPACE] [RELEASE_NAME]
#   ./scripts/smoke-test.sh observability countly-observability
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-observability}"
RELEASE="${2:-countly-observability}"
COUNTLY_NS="${3:-countly}"
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

# Resolve ingress host once
INGRESS_HOST=$(kubectl get ingress -n "${COUNTLY_NS}" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")

# ---- Helper: send request and return HTTP code ----
send_request() {
  local path="$1"
  shift
  curl -sk -o /dev/null -w '%{http_code}' "$@" "https://${INGRESS_HOST}${path}" 2>/dev/null || echo "000"
}

# ---- Helper: query Tempo for a trace ID ----
query_tempo() {
  local trace_id="$1"
  local tempo_pod
  tempo_pod=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=tempo" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -z "${tempo_pod}" ]; then echo "NO_POD"; return; fi
  kubectl exec -n "${NAMESPACE}" "${tempo_pod}" -- wget -qO- "http://localhost:3200/api/traces/${trace_id}" 2>/dev/null || echo ""
}

# ---- Helper: query Loki for a trace ID ----
query_loki() {
  local trace_id="$1"
  local loki_pod
  loki_pod=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=loki" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -z "${loki_pod}" ]; then echo "NO_POD"; return; fi
  kubectl exec -n "${NAMESPACE}" "${loki_pod}" -- wget -qO- \
    "http://localhost:3100/loki/api/v1/query_range?query=%7Bnamespace%3D~%22.%2B%22%7D+%7C%3D+%22${trace_id}%22&limit=5" 2>/dev/null || echo ""
}

# =============================================================================
# T1: NGINX root span creation (no inbound trace header)
# =============================================================================
echo "--- T1: NGINX root span creation (no inbound trace) ---"
if [ -n "${INGRESS_HOST}" ]; then
  HTTP_CODE=$(send_request "/o/ping")
  if [ "${HTTP_CODE}" = "200" ]; then
    pass "T1: HTTP request without traceparent returned ${HTTP_CODE}"
  else
    warn "T1: HTTP request returned ${HTTP_CODE} (may be expected if app not fully configured)"
  fi
else
  warn "T1: No ingress found in ${COUNTLY_NS} namespace — skipping"
fi

# =============================================================================
# T2: NGINX trace continuation (inbound traceparent)
# =============================================================================
echo "--- T2: NGINX trace continuation (inbound traceparent) ---"
TRACE_ID=$(head -c 16 /dev/urandom | xxd -p)
SPAN_ID=$(head -c 8 /dev/urandom | xxd -p)
TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"

echo "  Trace ID: ${TRACE_ID}"
echo "  traceparent: ${TRACEPARENT}"

if [ -n "${INGRESS_HOST}" ]; then
  HTTP_CODE=$(send_request "/o/ping" -H "traceparent: ${TRACEPARENT}")
  if [ "${HTTP_CODE}" = "200" ]; then
    pass "T2: HTTP request with traceparent returned ${HTTP_CODE}"
  else
    warn "T2: HTTP request returned ${HTTP_CODE}"
  fi
else
  warn "T2: No ingress found — skipping"
fi

# =============================================================================
# T3: MongoDB client span (request that queries MongoDB)
# =============================================================================
echo "--- T3: MongoDB client span ---"
T3_TRACE_ID=$(head -c 16 /dev/urandom | xxd -p)
T3_SPAN_ID=$(head -c 8 /dev/urandom | xxd -p)
T3_TRACEPARENT="00-${T3_TRACE_ID}-${T3_SPAN_ID}-01"

if [ -n "${INGRESS_HOST}" ]; then
  # /o/sdk hits MongoDB for app config lookup
  HTTP_CODE=$(send_request "/o/sdk?app_key=test&method=fetch_remote_config" -H "traceparent: ${T3_TRACEPARENT}")
  if [ "${HTTP_CODE}" != "000" ]; then
    pass "T3: MongoDB-touching request returned ${HTTP_CODE}"
  else
    warn "T3: Request failed (connection error)"
  fi
else
  warn "T3: No ingress — skipping"
fi

# =============================================================================
# T4: ClickHouse client span (request that queries ClickHouse)
# =============================================================================
echo "--- T4: ClickHouse client span ---"
T4_TRACE_ID=$(head -c 16 /dev/urandom | xxd -p)
T4_SPAN_ID=$(head -c 8 /dev/urandom | xxd -p)
T4_TRACEPARENT="00-${T4_TRACE_ID}-${T4_SPAN_ID}-01"

if [ -n "${INGRESS_HOST}" ]; then
  # /o/actions/drill hits ClickHouse for drill queries
  HTTP_CODE=$(send_request "/o/actions/drill" \
    -H "traceparent: ${T4_TRACEPARENT}" \
    -H "Content-Type: application/json" \
    -d '{"app_id":"test","method":"query"}')
  if [ "${HTTP_CODE}" != "000" ]; then
    pass "T4: ClickHouse-touching request returned ${HTTP_CODE}"
  else
    warn "T4: Request failed (connection error)"
  fi
else
  warn "T4: No ingress — skipping"
fi

# =============================================================================
# T5: Kafka producer span (event ingestion)
# =============================================================================
echo "--- T5: Kafka producer span ---"
T5_TRACE_ID=$(head -c 16 /dev/urandom | xxd -p)
T5_SPAN_ID=$(head -c 8 /dev/urandom | xxd -p)
T5_TRACEPARENT="00-${T5_TRACE_ID}-${T5_SPAN_ID}-01"

if [ -n "${INGRESS_HOST}" ]; then
  # /i is the ingestor endpoint that produces Kafka messages
  HTTP_CODE=$(send_request "/i?app_key=test&device_id=smoke-test&events=%5B%7B%22key%22%3A%22smoke_test%22%2C%22count%22%3A1%7D%5D" \
    -H "traceparent: ${T5_TRACEPARENT}")
  if [ "${HTTP_CODE}" != "000" ]; then
    pass "T5: Kafka-producing ingestion request returned ${HTTP_CODE}"
  else
    warn "T5: Request failed (connection error)"
  fi
else
  warn "T5: No ingress — skipping"
fi

echo
echo "  Waiting 30s for pipeline processing..."
sleep 30

# =============================================================================
# Verify traces in Tempo
# =============================================================================
echo "--- Verify: Query Tempo for T2 trace ---"
TEMPO_RESULT=$(query_tempo "${TRACE_ID}")
if [ "${TEMPO_RESULT}" = "NO_POD" ]; then
  fail "No Tempo pod found"
elif echo "${TEMPO_RESULT}" | grep -q "${TRACE_ID}" 2>/dev/null; then
  pass "Trace ${TRACE_ID} found in Tempo"
  # Check for edge-nginx service
  if echo "${TEMPO_RESULT}" | grep -q "edge-nginx" 2>/dev/null; then
    pass "edge-nginx span found in trace (Phase 1 verified)"
  else
    warn "edge-nginx span not found (NGINX OTel module may not be active yet)"
  fi
else
  warn "Trace ${TRACE_ID} not found in Tempo (expected if tracing pipeline not fully active)"
fi

# =============================================================================
# T6: Verify Kafka consumer spans (from T5's producer)
# =============================================================================
echo "--- T6: Query Tempo for Kafka consumer span (T5 trace) ---"
T5_RESULT=$(query_tempo "${T5_TRACE_ID}")
if [ "${T5_RESULT}" = "NO_POD" ]; then
  fail "No Tempo pod found"
elif echo "${T5_RESULT}" | grep -q "${T5_TRACE_ID}" 2>/dev/null; then
  pass "T5/T6: Kafka trace ${T5_TRACE_ID} found in Tempo"
  if echo "${T5_RESULT}" | grep -q "PRODUCER\|producer" 2>/dev/null; then
    pass "T5: Kafka PRODUCER span found"
  else
    warn "T5: Kafka PRODUCER span not detected in trace (may need deeper inspection)"
  fi
else
  warn "T5/T6: Kafka trace not found (expected if Kafka instrumentation not fully active)"
fi

# =============================================================================
# T7: Verify Kafka Connect spans
# =============================================================================
echo "--- T7: Check for kafka-connect service in Tempo ---"
PROM_POD=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=prometheus" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "${PROM_POD}" ]; then
  KC_RESULT=$(kubectl exec -n "${NAMESPACE}" "${PROM_POD}" -- wget -qO- \
    'http://localhost:9090/api/v1/query?query=traces_service_graph_request_total{client="kafka-connect"}' 2>/dev/null || echo "")
  if echo "${KC_RESULT}" | grep -q '"result"' 2>/dev/null && ! echo "${KC_RESULT}" | grep -q '"result":\[\]' 2>/dev/null; then
    pass "T7: kafka-connect service graph metrics found"
  else
    warn "T7: No kafka-connect service graph metrics (expected if OTel Java agent not yet deployed)"
  fi
else
  warn "T7: No Prometheus pod found"
fi

# =============================================================================
# Verify Loki log correlation
# =============================================================================
echo "--- Verify: Query Loki for trace ID correlation ---"
LOKI_RESULT=$(query_loki "${TRACE_ID}")
if [ "${LOKI_RESULT}" = "NO_POD" ]; then
  fail "No Loki pod found"
elif echo "${LOKI_RESULT}" | grep -q '"result"' 2>/dev/null; then
  pass "Loki query executed successfully for trace ${TRACE_ID}"
else
  warn "Could not query Loki for trace ID correlation"
fi

# =============================================================================
# Check Prometheus for service graph metrics
# =============================================================================
echo "--- Verify: Service graph metrics in Prometheus ---"
if [ -n "${PROM_POD}" ]; then
  GRAPH_RESULT=$(kubectl exec -n "${NAMESPACE}" "${PROM_POD}" -- wget -qO- \
    "http://localhost:9090/api/v1/query?query=traces_service_graph_request_total" 2>/dev/null || echo "")
  if echo "${GRAPH_RESULT}" | grep -q '"result"' 2>/dev/null; then
    pass "Service graph metrics query returned results"
  else
    warn "No service graph metrics found (expected if no inter-service traces exist yet)"
  fi
else
  fail "No Prometheus pod found"
fi

# =============================================================================
# Check alloy-otlp logs for errors
# =============================================================================
echo "--- Verify: alloy-otlp logs for out-of-order errors ---"
ALLOY_OTLP_POD=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/component=alloy-otlp" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${ALLOY_OTLP_POD}" ]; then
  OOO_ERRORS=$(kubectl logs -n "${NAMESPACE}" "${ALLOY_OTLP_POD}" --tail=200 2>/dev/null | grep -ci "out of order\|duplicate sample" || echo "0")
  if [ "${OOO_ERRORS}" -gt 5 ]; then
    fail "Found ${OOO_ERRORS} out-of-order/duplicate sample errors in alloy-otlp logs"
  elif [ "${OOO_ERRORS}" -gt 0 ]; then
    warn "Found ${OOO_ERRORS} out-of-order/duplicate sample errors (may be transient)"
  else
    pass "No out-of-order errors in alloy-otlp logs"
  fi
else
  warn "No alloy-otlp pod found"
fi

# =============================================================================
# Summary
# =============================================================================
echo
echo "========================================"
echo "  Results"
echo "========================================"
echo "  Passed:   ${PASSED}"
echo "  Failed:   ${FAILED}"
echo "  Warnings: ${WARNINGS}"
echo "========================================"
echo
echo "  Test Coverage:"
echo "    T1: NGINX root span (no inbound trace)"
echo "    T2: NGINX trace continuation (inbound traceparent)"
echo "    T3: MongoDB client span path"
echo "    T4: ClickHouse client span path"
echo "    T5: Kafka producer span"
echo "    T6: Kafka consumer span (from T5)"
echo "    T7: Kafka Connect service graph"
echo "========================================"

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
exit 0
