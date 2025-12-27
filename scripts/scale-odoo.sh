#!/bin/bash
# =============================================================================
# ODOO SCALING SCRIPT
# =============================================================================
# Usage: ./scale-odoo.sh <replicas>
# Example: ./scale-odoo.sh 3
# =============================================================================

set -e

REPLICAS=${1:-2}

if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [ "$REPLICAS" -lt 1 ]; then
    echo "ERROR: Invalid replica count. Must be a positive integer."
    echo "Usage: $0 <replicas>"
    exit 1
fi

echo "=========================================="
echo "SCALING ODOO SERVICE"
echo "=========================================="

echo "Scaling odoo-stack_odoo-web to ${REPLICAS} replicas..."
docker service scale odoo-stack_odoo-web="${REPLICAS}"

echo ""
echo "Waiting for scaling to complete..."
sleep 5

echo ""
echo "Current service status:"
docker service ls --filter name=odoo-stack

echo ""
echo "Replica details:"
docker service ps odoo-stack_odoo-web --format "table {{.ID}}\t{{.Name}}\t{{.Node}}\t{{.CurrentState}}"
