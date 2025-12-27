#!/bin/bash
# =============================================================================
# ODOO STACK DEPLOYMENT SCRIPT
# =============================================================================
# Usage: ./deploy-stack.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "ODOO STACK DEPLOYMENT"
echo "=========================================="

# Check if swarm is initialized
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "ERROR: Docker Swarm is not initialized"
    echo "Run: ./scripts/init-swarm.sh first"
    exit 1
fi

# Check if .env exists
if [ ! -f "${PROJECT_DIR}/.env" ]; then
    echo "ERROR: .env file not found"
    echo "Copy .env.example to .env and configure it"
    exit 1
fi

# Check if secrets exist
if [ ! -f "${PROJECT_DIR}/secrets/pg_password.txt" ]; then
    echo "ERROR: secrets/pg_password.txt not found"
    exit 1
fi

# Load environment variables
export $(grep -v '^#' "${PROJECT_DIR}/.env" | xargs)

echo "Deploying Odoo stack..."
echo "  Domain: ${SUB_DOMAIN}"
echo "  Replicas: 2 (default)"

# Deploy stack
docker stack deploy -c "${PROJECT_DIR}/odoo-swarm.yaml" odoo-stack

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "Useful commands:"
echo "  View services:  docker service ls"
echo "  View logs:      docker service logs -f odoo-stack_odoo-web"
echo "  Scale up:       docker service scale odoo-stack_odoo-web=3"
echo "  Check health:   ./scripts/check-health.sh"
echo ""
