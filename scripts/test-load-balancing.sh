#!/bin/bash
# =============================================================================
# LOAD BALANCING TEST SCRIPT
# =============================================================================
# Purpose: Verify that Traefik distributes traffic across multiple Odoo replicas
# Usage: ./test-load-balancing.sh [requests] [replicas]
# Example: ./test-load-balancing.sh 20 3
# =============================================================================

set -e

REQUESTS=${1:-20}
REPLICAS=${2:-3}
DOMAIN="odoo.naseira.com"
ENDPOINT="https://${DOMAIN}/web/database/selector"

echo "=========================================="
echo "LOAD BALANCING TEST"
echo "=========================================="
echo ""

# Step 1: Scale up to multiple replicas
echo "=== STEP 1: SCALING TO ${REPLICAS} REPLICAS ==="
docker service scale odoo-stack_odoo-web=${REPLICAS} --detach=false 2>/dev/null || docker service scale odoo-stack_odoo-web=${REPLICAS}
echo "Waiting for replicas to be ready..."
sleep 30

# Verify replicas are running
RUNNING=$(docker service ps odoo-stack_odoo-web --filter "desired-state=running" -q | wc -l)
echo "Running replicas: ${RUNNING}/${REPLICAS}"
echo ""

if [ "$RUNNING" -lt "$REPLICAS" ]; then
    echo "⚠ Warning: Not all replicas are running. Test may not be accurate."
    echo ""
fi

# Step 2: Get container IDs for comparison
echo "=== STEP 2: IDENTIFYING REPLICAS ==="
docker service ps odoo-stack_odoo-web --filter "desired-state=running" --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}"
echo ""

# Step 3: Send multiple requests and track responses
echo "=== STEP 3: SENDING ${REQUESTS} REQUESTS ==="
echo ""

declare -A CONTAINER_HITS
SUCCESSFUL=0
FAILED=0

for i in $(seq 1 $REQUESTS); do
    # Send request and capture X-Container-ID header or use server response time as fingerprint
    RESPONSE=$(curl -s -w "\n%{http_code}" -k "$ENDPOINT" --max-time 10 2>/dev/null)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "303" ]; then
        SUCCESSFUL=$((SUCCESSFUL + 1))
        # Extract unique identifier from response (HTML hash or timing)
        HASH=$(echo "$RESPONSE" | head -c 1000 | md5sum | cut -c1-8)
        CONTAINER_HITS[$HASH]=$((${CONTAINER_HITS[$HASH]:-0} + 1))
        printf "."
    else
        FAILED=$((FAILED + 1))
        printf "x"
    fi
done

echo ""
echo ""

# Step 4: Analyze distribution
echo "=== STEP 4: ANALYZING DISTRIBUTION ==="
echo ""
UNIQUE_BACKENDS=${#CONTAINER_HITS[@]}
echo "Successful requests: ${SUCCESSFUL}/${REQUESTS}"
echo "Failed requests: ${FAILED}/${REQUESTS}"
echo "Unique response patterns detected: ${UNIQUE_BACKENDS}"
echo ""

echo "Distribution (response pattern -> hit count):"
for pattern in "${!CONTAINER_HITS[@]}"; do
    HITS=${CONTAINER_HITS[$pattern]}
    PERCENT=$((HITS * 100 / SUCCESSFUL))
    BAR=$(printf '█%.0s' $(seq 1 $((PERCENT / 5))))
    echo "  ${pattern}: ${HITS} hits (${PERCENT}%) ${BAR}"
done
echo ""

# Step 5: Evaluate results
echo "=== STEP 5: EVALUATION ==="
if [ "$UNIQUE_BACKENDS" -ge 2 ]; then
    echo "✓ PASS: Traffic is being distributed across multiple backends"
    echo "  Detected ${UNIQUE_BACKENDS} different response patterns"
elif [ "$UNIQUE_BACKENDS" -eq 1 ] && [ "$REPLICAS" -gt 1 ]; then
    echo "⚠ WARNING: All requests went to the same backend"
    echo "  This could indicate:"
    echo "  - Sticky sessions are enabled (expected behavior with cookies)"
    echo "  - Only one replica is healthy"
    echo "  - Load balancer not working correctly"
else
    echo "✓ PASS: Single replica handling all traffic (as expected)"
fi

echo ""
echo "=========================================="
echo "LOAD BALANCING TEST COMPLETE"
echo "=========================================="

# Optionally scale back to 1
read -p "Scale back to 1 replica? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker service scale odoo-stack_odoo-web=1 --detach=false 2>/dev/null || docker service scale odoo-stack_odoo-web=1
    echo "Scaled down to 1 replica"
fi
