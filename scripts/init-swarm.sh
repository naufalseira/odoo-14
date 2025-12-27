#!/bin/bash
# =============================================================================
# DOCKER SWARM INITIALIZATION SCRIPT
# =============================================================================
# Usage: ./init-swarm.sh
# =============================================================================

set -e

echo "=========================================="
echo "DOCKER SWARM INITIALIZATION"
echo "=========================================="

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "Server IP: ${SERVER_IP}"

# Check if already in swarm mode
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "✓ Docker Swarm is already initialized"
else
    echo "Initializing Docker Swarm..."
    docker swarm init --advertise-addr "${SERVER_IP}"
    echo "✓ Docker Swarm initialized"
fi

# Create overlay network if not exists
if docker network ls | grep -q "traefik-public"; then
    echo "✓ Network 'traefik-public' already exists"
else
    echo "Creating overlay network 'traefik-public'..."
    docker network create --driver overlay --attachable traefik-public
    echo "✓ Network created"
fi

echo ""
echo "=========================================="
echo "SWARM INITIALIZATION COMPLETE"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Deploy Traefik: docker stack deploy -c traefik-swarm.yaml traefik"
echo "  2. Deploy Odoo:    docker stack deploy -c odoo-swarm.yaml odoo-stack"
echo ""
