#!/bin/bash
# =============================================================================
# TRAEFIK STACK HEALTH CHECK SCRIPT
# =============================================================================
# Usage: ./check-traefik.sh
# =============================================================================

echo "=========================================="
echo "TRAEFIK STACK HEALTH CHECK"
echo "=========================================="
echo ""

# Check Traefik service status
echo "=== TRAEFIK SERVICE STATUS ==="
docker service ls --filter name=traefik_traefik
echo ""

# Check Traefik replicas
echo "=== TRAEFIK REPLICAS ==="
docker service ps traefik_traefik --format "table {{.Name}}\t{{.CurrentState}}\t{{.Error}}" 2>/dev/null || echo "Service not found"
echo ""

# Check Traefik container
TRAEFIK_CONTAINER=$(docker ps --filter name=traefik_traefik --format "{{.ID}}" | head -n 1)

if [ -n "$TRAEFIK_CONTAINER" ]; then
    echo "=== TRAEFIK CONTAINER INFO ==="
    docker inspect "$TRAEFIK_CONTAINER" --format 'Image: {{.Config.Image}}' 2>/dev/null
    docker inspect "$TRAEFIK_CONTAINER" --format 'Status: {{.State.Status}}' 2>/dev/null
    echo ""

    echo "=== TRAEFIK ROUTERS (from logs) ==="
    docker logs "$TRAEFIK_CONTAINER" 2>&1 | grep -oP '"routers":\{[^}]+\}' | tail -1 | python3 -m json.tool 2>/dev/null || echo "Unable to parse routers"
    echo ""

    echo "=== RECENT ERRORS ==="
    docker logs "$TRAEFIK_CONTAINER" 2>&1 | grep -E "(ERR|error)" | tail -10
    echo ""

    echo "=== CERTIFICATE STATUS ==="
    docker logs "$TRAEFIK_CONTAINER" 2>&1 | grep -i "certificate" | tail -5
    echo ""
else
    echo "ERROR: Traefik container not running"
fi

# Check service labels
echo "=== TRAEFIK SERVICE LABELS ==="
docker service inspect traefik_traefik --format '{{range $k, $v := .Spec.Labels}}{{$k}}={{$v}}{{println}}{{end}}' 2>/dev/null | grep traefik
echo ""

# Check Odoo service labels  
echo "=== ODOO SERVICE LABELS ==="
docker service inspect odoo-stack_odoo-web --format '{{range $k, $v := .Spec.Labels}}{{$k}}={{$v}}{{println}}{{end}}' 2>/dev/null | grep traefik
echo ""

# Test endpoints
echo "=== HTTP ENDPOINT TESTS ==="
DOMAIN="odoo.naseira.com"
TRAEFIK_DOMAIN="traefik-sg.naseira.com"

# Test Odoo HTTP redirect
echo -n "Odoo HTTP -> HTTPS redirect: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN}" --max-time 5 2>/dev/null || echo "000")
if [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "308" ]; then
    echo "✓ (HTTP ${HTTP_CODE})"
else
    echo "✗ (HTTP ${HTTP_CODE})"
fi

# Test Odoo HTTPS
echo -n "Odoo HTTPS: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/web/database/selector" --max-time 10 -k 2>/dev/null || echo "000")
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "303" ]; then
    echo "✓ (HTTP ${HTTP_CODE})"
else
    echo "✗ (HTTP ${HTTP_CODE})"
fi

# Test HTTPS Certificate
echo -n "Odoo SSL Certificate: "
CERT_ISSUER=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | cut -d= -f2-)
if echo "$CERT_ISSUER" | grep -qi "Let's Encrypt"; then
    echo "✓ Let's Encrypt"
elif echo "$CERT_ISSUER" | grep -qi "TRAEFIK"; then
    echo "⚠ Self-signed (Traefik default)"
else
    echo "? ${CERT_ISSUER:-Unknown}"
fi

# Test Traefik Dashboard
echo -n "Traefik Dashboard: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${TRAEFIK_DOMAIN}" --max-time 5 2>/dev/null || echo "000")
if [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "308" ] || [ "$HTTP_CODE" == "401" ]; then
    echo "✓ (HTTP ${HTTP_CODE})"
else
    echo "✗ (HTTP ${HTTP_CODE})"
fi

echo ""
echo "=========================================="
echo "TRAEFIK HEALTH CHECK COMPLETE"
echo "=========================================="
