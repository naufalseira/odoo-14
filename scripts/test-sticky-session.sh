#!/bin/bash
# =============================================================================
# STICKY SESSION TEST SCRIPT
# =============================================================================
# Purpose: Verify that Traefik sticky sessions keep users on the same replica
# Usage: ./test-sticky-session.sh [requests]
# Example: ./test-sticky-session.sh 10
# =============================================================================

set -e

REQUESTS=${1:-10}
DOMAIN="odoo.naseira.com"
ENDPOINT="https://${DOMAIN}/web/database/selector"
COOKIE_JAR="/tmp/odoo_sticky_test_cookies.txt"

echo "=========================================="
echo "STICKY SESSION TEST"
echo "=========================================="
echo ""

# Clean up previous cookies
rm -f "$COOKIE_JAR"

# Step 1: Ensure multiple replicas are running
echo "=== STEP 1: CHECKING REPLICAS ==="
RUNNING=$(docker service ps odoo-stack_odoo-web --filter "desired-state=running" -q 2>/dev/null | wc -l)
echo "Running replicas: ${RUNNING}"

if [ "$RUNNING" -lt 2 ]; then
    echo ""
    echo "Scaling to 2 replicas for testing..."
    docker service scale odoo-stack_odoo-web=2 --detach=false 2>/dev/null || docker service scale odoo-stack_odoo-web=2
    echo "Waiting for replicas..."
    sleep 30
    RUNNING=$(docker service ps odoo-stack_odoo-web --filter "desired-state=running" -q 2>/dev/null | wc -l)
    echo "Running replicas: ${RUNNING}"
fi
echo ""

# Step 2: Make initial request to get sticky cookie
echo "=== STEP 2: INITIAL REQUEST (GET COOKIE) ==="
INITIAL_RESPONSE=$(curl -s -k -c "$COOKIE_JAR" -w "\nHTTP_CODE:%{http_code}" "$ENDPOINT" --max-time 10 2>/dev/null)
INITIAL_CODE=$(echo "$INITIAL_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
INITIAL_HASH=$(echo "$INITIAL_RESPONSE" | head -c 500 | md5sum | cut -c1-16)

echo "Initial response code: ${INITIAL_CODE}"
echo "Initial response hash: ${INITIAL_HASH}"
echo ""

# Check for sticky cookie
echo "=== STEP 3: CHECKING STICKY COOKIE ==="
if [ -f "$COOKIE_JAR" ]; then
    echo "Cookie jar contents:"
    cat "$COOKIE_JAR" | grep -v "^#" | grep -v "^$" || echo "  (no cookies found)"
    echo ""
    
    if grep -q "odoo_session" "$COOKIE_JAR" 2>/dev/null; then
        echo "✓ Sticky session cookie 'odoo_session' found!"
        COOKIE_VALUE=$(grep "odoo_session" "$COOKIE_JAR" | awk '{print $NF}')
        echo "  Cookie value: ${COOKIE_VALUE:0:32}..."
    else
        echo "⚠ Sticky session cookie 'odoo_session' NOT found"
        echo "  This could mean sticky sessions are not configured correctly"
    fi
else
    echo "⚠ No cookies received"
fi
echo ""

# Step 4: Send multiple requests WITH the cookie
echo "=== STEP 4: SENDING ${REQUESTS} REQUESTS WITH COOKIE ==="
echo ""

declare -A SESSION_RESPONSES
CONSISTENT=0
INCONSISTENT=0

for i in $(seq 1 $REQUESTS); do
    RESPONSE=$(curl -s -k -b "$COOKIE_JAR" -w "\n%{http_code}" "$ENDPOINT" --max-time 10 2>/dev/null)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    HASH=$(echo "$RESPONSE" | head -c 500 | md5sum | cut -c1-16)
    
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "303" ]; then
        if [ "$HASH" == "$INITIAL_HASH" ]; then
            CONSISTENT=$((CONSISTENT + 1))
            printf "✓"
        else
            INCONSISTENT=$((INCONSISTENT + 1))
            printf "✗"
        fi
        SESSION_RESPONSES[$HASH]=$((${SESSION_RESPONSES[$HASH]:-0} + 1))
    else
        printf "x"
    fi
done

echo ""
echo ""

# Step 5: Analyze session consistency
echo "=== STEP 5: ANALYZING SESSION CONSISTENCY ==="
echo ""
UNIQUE_RESPONSES=${#SESSION_RESPONSES[@]}
echo "Total requests: ${REQUESTS}"
echo "Consistent responses (same as initial): ${CONSISTENT}"
echo "Inconsistent responses: ${INCONSISTENT}"
echo "Unique response patterns: ${UNIQUE_RESPONSES}"
echo ""

# Step 6: Test WITHOUT cookie (should distribute)
echo "=== STEP 6: CONTROL TEST (NO COOKIE) ==="
echo "Sending 5 requests WITHOUT sticky cookie..."
declare -A NO_COOKIE_RESPONSES
for i in $(seq 1 5); do
    RESPONSE=$(curl -s -k -w "\n%{http_code}" "$ENDPOINT" --max-time 10 2>/dev/null)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    HASH=$(echo "$RESPONSE" | head -c 500 | md5sum | cut -c1-16)
    
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "303" ]; then
        NO_COOKIE_RESPONSES[$HASH]=$((${NO_COOKIE_RESPONSES[$HASH]:-0} + 1))
    fi
done
NO_COOKIE_UNIQUE=${#NO_COOKIE_RESPONSES[@]}
echo "Unique patterns without cookie: ${NO_COOKIE_UNIQUE}"
echo ""

# Step 7: Evaluation
echo "=== STEP 7: EVALUATION ==="
if [ "$CONSISTENT" -eq "$REQUESTS" ]; then
    echo "✓ PASS: All ${REQUESTS} requests with cookie went to the SAME backend"
    echo "  Sticky sessions are working correctly!"
elif [ "$CONSISTENT" -ge $((REQUESTS * 80 / 100)) ]; then
    echo "⚠ PARTIAL PASS: ${CONSISTENT}/${REQUESTS} requests went to the same backend"
    echo "  Some inconsistency detected (may be due to backend restarts)"
else
    echo "✗ FAIL: Sticky sessions not working"
    echo "  Only ${CONSISTENT}/${REQUESTS} requests were consistent"
fi

echo ""
echo "=========================================="
echo "STICKY SESSION TEST COMPLETE"
echo "=========================================="

# Cleanup
rm -f "$COOKIE_JAR"
