#!/bin/bash

# Helper script to load environment variables from .env file
# Usage: source tests/acceptance/load-env.sh

ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/../../.env"

if [ -f "$ENV_FILE" ]; then
    echo "Loading environment variables from .env file..."
    
    # Export variables from .env file
    set -a
    source "$ENV_FILE"
    set +a
    
    echo "✅ Environment variables loaded successfully"
    echo ""
    echo "Loaded variables:"
    echo "  BOUNDARY_ADDR: ${BOUNDARY_ADDR:-<not set>}"
    echo "  BOUNDARY_LOGIN_NAME: ${BOUNDARY_LOGIN_NAME:-<not set>}"
    echo "  BOUNDARY_PASSWORD: ${BOUNDARY_PASSWORD:+<set>}"
    echo "  BOUNDARY_CLUSTER_ID: ${BOUNDARY_CLUSTER_ID:-<not set>}"
else
    echo "⚠️  .env file not found at: $ENV_FILE"
    echo ""
    echo "Please create a .env file from the template:"
    echo "  cp .env.example .env"
    echo ""
    echo "Then edit .env with your actual Boundary credentials."
    return 1
fi

# Made with Bob
