#!/bin/bash
# =============================================================================
# ODOO STACK HEALTH CHECK SCRIPT
# =============================================================================
# Usage: ./check-health.sh
# =============================================================================

echo "=========================================="
echo "ODOO STACK HEALTH CHECK"
echo "=========================================="
echo ""

# Check Docker Swarm status
echo "=== DOCKER SWARM STATUS ==="
docker node ls 2>/dev/null || echo "Swarm not initialized"
echo ""

# Check services
echo "=== SERVICES STATUS ==="
docker service ls --filter name=odoo-stack
echo ""

# Check replicas
echo "=== ODOO WEB REPLICAS ==="
docker service ps odoo-stack_odoo-web --format "table {{.Name}}\t{{.CurrentState}}\t{{.Error}}" 2>/dev/null || echo "Service not found"
echo ""

# Check database
echo "=== DATABASE STATUS ==="
docker service ps odoo-stack_odoo-db --format "table {{.Name}}\t{{.CurrentState}}\t{{.Error}}" 2>/dev/null || echo "Service not found"
echo ""

# Check resource usage
echo "=== CONTAINER RESOURCES ==="
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps -qf "name=odoo-stack") 2>/dev/null || echo "No containers running"
echo ""

# Test HTTP endpoint
echo "=== HTTP HEALTH CHECK ==="
DOMAIN="${SUB_DOMAIN:-odoo.naseira.com}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/web/database/selector" --max-time 10 2>/dev/null || echo "000")
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "303" ]; then
    echo "✓ HTTPS endpoint healthy (HTTP ${HTTP_CODE})"
else
    echo "✗ HTTPS endpoint check failed (HTTP ${HTTP_CODE})"
fi
echo ""

echo "=========================================="
echo "HEALTH CHECK COMPLETE"
echo "=========================================="
