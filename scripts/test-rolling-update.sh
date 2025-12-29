#!/bin/bash
# =============================================================================
# ROLLING UPDATE TEST SCRIPT
# =============================================================================
# Purpose: Verify zero-downtime deployments during service updates
# Usage: ./test-rolling-update.sh
# =============================================================================

set -e

DOMAIN="odoo.naseira.com"
ENDPOINT="https://${DOMAIN}/web/database/selector"
LOG_FILE="/tmp/rolling_update_test.log"
PID_FILE="/tmp/rolling_update_monitor.pid"

echo "=========================================="
echo "ROLLING UPDATE TEST"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    if [ -f "$PID_FILE" ]; then
        MONITOR_PID=$(cat "$PID_FILE")
        kill $MONITOR_PID 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
}
trap cleanup EXIT

# Step 1: Ensure service is running
echo "=== STEP 1: VERIFYING SERVICE ==="
RUNNING=$(docker service ps odoo-stack_odoo-web --filter "desired-state=running" -q 2>/dev/null | wc -l)
echo "Current running replicas: ${RUNNING}"

if [ "$RUNNING" -lt 1 ]; then
    echo "ERROR: Odoo service is not running"
    exit 1
fi
echo ""

# Step 2: Start background monitoring
echo "=== STEP 2: STARTING AVAILABILITY MONITOR ==="
echo "Monitoring endpoint: ${ENDPOINT}"
rm -f "$LOG_FILE"

# Background monitoring function
monitor_availability() {
    local count=0
    local success=0
    local fail=0
    local start_time=$(date +%s)
    
    while true; do
        local timestamp=$(date +"%H:%M:%S")
        local response_time=$(curl -s -k -o /dev/null -w "%{time_total}" "$ENDPOINT" --max-time 5 2>/dev/null || echo "FAIL")
        
        if [[ "$response_time" != "FAIL" ]] && (( $(echo "$response_time < 5" | bc -l) )); then
            success=$((success + 1))
            echo "${timestamp} | ✓ OK (${response_time}s)" >> "$LOG_FILE"
        else
            fail=$((fail + 1))
            echo "${timestamp} | ✗ FAIL" >> "$LOG_FILE"
        fi
        
        count=$((count + 1))
        sleep 1
    done
}

# Start monitor in background
monitor_availability &
MONITOR_PID=$!
echo $MONITOR_PID > "$PID_FILE"
echo "Monitor started (PID: ${MONITOR_PID})"
echo ""

# Wait for initial monitoring
echo "Collecting baseline for 10 seconds..."
sleep 10

# Step 3: Trigger rolling update
echo "=== STEP 3: TRIGGERING ROLLING UPDATE ==="
echo "Forcing service update..."

# Force update by adding/changing an environment variable
TIMESTAMP=$(date +%s)
docker service update \
    --env-add "UPDATE_TIMESTAMP=${TIMESTAMP}" \
    --update-parallelism 1 \
    --update-delay 10s \
    --update-order start-first \
    odoo-stack_odoo-web &

UPDATE_PID=$!
echo "Update triggered (PID: ${UPDATE_PID})"
echo ""

# Step 4: Monitor during update
echo "=== STEP 4: MONITORING DURING UPDATE ==="
echo "Watching for downtime... (this will take ~60 seconds)"
echo ""

# Wait for update to complete
wait $UPDATE_PID 2>/dev/null || true

echo "Update command completed. Continuing monitoring for 20 more seconds..."
sleep 20

# Step 5: Stop monitoring and analyze
echo ""
echo "=== STEP 5: ANALYZING RESULTS ==="
kill $MONITOR_PID 2>/dev/null || true
rm -f "$PID_FILE"

if [ -f "$LOG_FILE" ]; then
    TOTAL=$(wc -l < "$LOG_FILE")
    SUCCESS=$(grep -c "✓ OK" "$LOG_FILE" 2>/dev/null || echo "0")
    FAIL=$(grep -c "✗ FAIL" "$LOG_FILE" 2>/dev/null || echo "0")
    
    echo ""
    echo "Monitoring Results:"
    echo "  Total requests: ${TOTAL}"
    echo "  Successful: ${SUCCESS}"
    echo "  Failed: ${FAIL}"
    
    if [ "$TOTAL" -gt 0 ]; then
        UPTIME=$((SUCCESS * 100 / TOTAL))
        echo "  Uptime: ${UPTIME}%"
        echo ""
        
        # Show timeline of failures if any
        if [ "$FAIL" -gt 0 ]; then
            echo "Failure timeline:"
            grep "✗ FAIL" "$LOG_FILE" | head -10
            echo ""
        fi
        
        # Evaluation
        echo "=== STEP 6: EVALUATION ==="
        if [ "$UPTIME" -eq 100 ]; then
            echo "✓ PERFECT: Zero downtime! All ${TOTAL} requests succeeded during update"
        elif [ "$UPTIME" -ge 99 ]; then
            echo "✓ EXCELLENT: ${UPTIME}% uptime - near-zero downtime deployment"
        elif [ "$UPTIME" -ge 95 ]; then
            echo "⚠ GOOD: ${UPTIME}% uptime - minimal downtime detected"
            echo "  ${FAIL} requests failed during the update window"
        elif [ "$UPTIME" -ge 90 ]; then
            echo "⚠ ACCEPTABLE: ${UPTIME}% uptime - some downtime during update"
        else
            echo "✗ NEEDS IMPROVEMENT: Only ${UPTIME}% uptime"
            echo "  Consider adjusting update-delay or using more replicas"
        fi
    fi
else
    echo "ERROR: No monitoring data collected"
fi

echo ""
echo "=========================================="
echo "ROLLING UPDATE TEST COMPLETE"
echo "=========================================="

# Show full log option
echo ""
read -p "Show full monitoring log? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "=== FULL LOG ==="
    cat "$LOG_FILE" 2>/dev/null || echo "Log file not found"
fi

rm -f "$LOG_FILE"
