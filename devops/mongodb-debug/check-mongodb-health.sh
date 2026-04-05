#!/bin/bash

# MongoDB Health Checker
# Detects whether MongoDB is choking under migration load

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
NAMESPACE_MONGODB="mongodb"
MONGO_POD="app-mongodb-0"
MONGO_CONTAINER="mongod"
KEYFILE="/var/lib/mongodb-mms-automation/authentication/keyfile"

# Thresholds
QUEUE_WARN=5          # queued ops before warning
QUEUE_CRIT=20         # queued ops before critical
DIRTY_WARN=20         # WiredTiger dirty cache % before warning
DIRTY_CRIT=40         # WiredTiger dirty cache % before critical
SLOW_OPS_WARN=3       # long-running ops (>5s) before warning

mongosh_exec() {
    local script="$1"
    # Base64-encode to avoid all shell quoting issues when passing JS to the container
    local encoded
    encoded=$(printf '%s' "$script" | base64 -w0)
    kubectl exec -n "$NAMESPACE_MONGODB" "$MONGO_POD" -c "$MONGO_CONTAINER" -- \
        bash -c "echo $encoded | base64 -d > /tmp/_mhc.js && \
                 mongosh --authenticationDatabase local -u __system -p \"\$(cat $KEYFILE)\" --quiet --norc /tmp/_mhc.js 2>&1; \
                 rm -f /tmp/_mhc.js" \
        2>/dev/null | grep -v "Could not access" | grep -v "^$" | tail -1
}

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  MONGODB HEALTH CHECK${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ── 1. Global lock queue depth ─────────────────────────────────────────────
HEALTH_RAW=$(mongosh_exec "
var s = db.serverStatus();
var q = s.globalLock.currentQueue;
var c = s.connections;
var wt = s.wiredTiger.cache;
var maxCache = wt['maximum bytes configured'];
var dirtyPct = maxCache > 0
    ? (wt['tracked dirty bytes in the cache'] * 100 / maxCache).toFixed(1) : '0';
var cachePct = maxCache > 0
    ? (wt['bytes currently in the cache'] * 100 / maxCache).toFixed(1) : '0';
var opcnt = s.opcounters;
print([q.readers, q.writers, c.current, c.available, dirtyPct, cachePct,
       opcnt.insert, opcnt.query, opcnt.update, opcnt.delete].join(','));
")

if [ -z "$HEALTH_RAW" ] || ! echo "$HEALTH_RAW" | grep -qE '^[0-9]'; then
    echo -e "${RED}[X] Failed to get serverStatus${NC}"
else
    QUEUE_READERS=$(echo "$HEALTH_RAW" | cut -d',' -f1)
    QUEUE_WRITERS=$(echo "$HEALTH_RAW" | cut -d',' -f2)
    CONNS_CURRENT=$(echo "$HEALTH_RAW" | cut -d',' -f3)
    CONNS_AVAILABLE=$(echo "$HEALTH_RAW" | cut -d',' -f4)
    DIRTY_PCT=$(echo "$HEALTH_RAW" | cut -d',' -f5)
    CACHE_PCT=$(echo "$HEALTH_RAW" | cut -d',' -f6)
    OPS_INSERT=$(echo "$HEALTH_RAW" | cut -d',' -f7)
    OPS_QUERY=$(echo "$HEALTH_RAW" | cut -d',' -f8)
    OPS_UPDATE=$(echo "$HEALTH_RAW" | cut -d',' -f9)
    OPS_DELETE=$(echo "$HEALTH_RAW" | cut -d',' -f10)
    QUEUE_TOTAL=$((QUEUE_READERS + QUEUE_WRITERS))

    echo -e "${YELLOW}Global Lock Queue:${NC}"
    if [ "$QUEUE_TOTAL" -ge "$QUEUE_CRIT" ]; then
        echo -e "  Readers waiting: ${RED}$QUEUE_READERS${NC}"
        echo -e "  Writers waiting: ${RED}$QUEUE_WRITERS${NC}"
        echo -e "  ${RED}CRITICAL: $QUEUE_TOTAL operations queued — MongoDB is choking${NC}"
    elif [ "$QUEUE_TOTAL" -ge "$QUEUE_WARN" ]; then
        echo -e "  Readers waiting: ${YELLOW}$QUEUE_READERS${NC}"
        echo -e "  Writers waiting: ${YELLOW}$QUEUE_WRITERS${NC}"
        echo -e "  ${YELLOW}WARNING: $QUEUE_TOTAL operations queued${NC}"
    else
        echo -e "  Readers waiting: ${GREEN}$QUEUE_READERS${NC}"
        echo -e "  Writers waiting: ${GREEN}$QUEUE_WRITERS${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Connections:${NC}"
    echo -e "  Current: $CONNS_CURRENT"
    echo -e "  Available: $CONNS_AVAILABLE"

    echo ""
    echo -e "${YELLOW}WiredTiger Cache:${NC}"
    DIRTY_INT=$(echo "$DIRTY_PCT / 1" | bc 2>/dev/null || echo "0")
    if [ "$DIRTY_INT" -ge "$DIRTY_CRIT" ]; then
        echo -e "  Used:  ${CACHE_PCT}%"
        echo -e "  Dirty: ${RED}${DIRTY_PCT}%${NC}  ← ${RED}CRITICAL: write pressure, eviction may stall operations${NC}"
    elif [ "$DIRTY_INT" -ge "$DIRTY_WARN" ]; then
        echo -e "  Used:  ${CACHE_PCT}%"
        echo -e "  Dirty: ${YELLOW}${DIRTY_PCT}%${NC}  ← ${YELLOW}WARNING: elevated write pressure${NC}"
    else
        echo -e "  Used:  ${CACHE_PCT}%"
        echo -e "  Dirty: ${GREEN}${DIRTY_PCT}%${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Operation Counters (cumulative since start):${NC}"
    echo -e "  Inserts: $OPS_INSERT"
    echo -e "  Queries: $OPS_QUERY"
    echo -e "  Updates: $OPS_UPDATE"
    echo -e "  Deletes: $OPS_DELETE"
fi

# ── 3. Long-running operations on countly_drill ────────────────────────────
echo ""
echo -e "${YELLOW}Slow Operations on countly_drill (>5s):${NC}"
SLOW_RAW=$(mongosh_exec "
var ops = db.currentOp({ secs_running: { \$gt: 5 }, ns: /^countly_drill/ });
var lines = ops.inprog.map(function(op){
    return op.secs_running + 's|' + op.op + '|' + op.ns;
}).join('\n');
print(ops.inprog.length + '|' + lines);
")

if [ -z "$SLOW_RAW" ]; then
    echo -e "  ${RED}Unable to get currentOp${NC}"
else
    SLOW_COUNT=$(echo "$SLOW_RAW" | head -1 | cut -d'|' -f1)
    if [ "$SLOW_COUNT" -eq 0 ] 2>/dev/null; then
        echo -e "  ${GREEN}None${NC}"
    elif [ "$SLOW_COUNT" -ge "$SLOW_OPS_WARN" ] 2>/dev/null; then
        echo -e "  ${YELLOW}WARNING: $SLOW_COUNT slow ops running${NC}"
        echo "$SLOW_RAW" | tail -n +2 | while IFS='|' read -r secs op ns; do
            [ -n "$secs" ] && echo -e "    ${secs}  ${op}  ${ns}"
        done
    else
        echo -e "  $SLOW_COUNT slow op(s) running:"
        echo "$SLOW_RAW" | tail -n +2 | while IFS='|' read -r secs op ns; do
            [ -n "$secs" ] && echo -e "    ${secs}  ${op}  ${ns}"
        done
    fi
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${BLUE}Report generated at: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
