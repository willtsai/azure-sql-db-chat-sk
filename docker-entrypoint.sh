#!/bin/bash
set -e

echo "================================"
echo "Azure SQL Chat - Starting up..."
echo "================================"

# Generate and apply Dapr components if DAPR_ENABLED is true
if [ "${DAPR_ENABLED}" = "true" ]; then
    echo ""
    echo "[0/3] Generating and applying Dapr components..."
    ./scripts/generate-dapr-components.sh
    
    if [ $? -eq 0 ]; then
        echo "[0/3] Dapr components applied successfully"
    else
        echo "[0/3] Warning: Dapr component generation failed, continuing anyway..."
    fi
fi

# Run database deployment/initialization
echo ""
if [ "${DAPR_ENABLED}" = "true" ]; then
    echo "[1/3] Running database deployment..."
else
    echo "[1/2] Running database deployment..."
fi
dotnet azure-sql-sk.dll deploy

if [ $? -eq 0 ]; then
    if [ "${DAPR_ENABLED}" = "true" ]; then
        echo "[1/3] Database deployment completed successfully"
    else
        echo "[1/2] Database deployment completed successfully"
    fi
else
    echo "Database deployment failed!"
    exit 1
fi

# Display configuration
echo ""
if [ "${DAPR_ENABLED}" = "true" ]; then
    echo "[2/3] Configuration:"
    echo "  Mode: Dapr (platform-agnostic)"
    echo "  DAPR_HTTP_PORT: ${DAPR_HTTP_PORT:-3500}"
else
    echo "[2/2] Configuration:"
    echo "  Mode: Legacy (Direct Azure OpenAI)"
fi
echo "  Chat Endpoint: ${CONNECTION_AICHAT_ENDPOINT}"
echo "  Embedding Endpoint: ${CONNECTION_AIEMBEDDING_ENDPOINT}"

# Run the main application command (passed as arguments)
echo ""
if [ "${DAPR_ENABLED}" = "true" ]; then
    echo "[3/3] Starting chat application..."
else
    echo "[2/2] Starting chat application..."
fi
echo "================================"
echo ""

# Execute the command passed to docker run (or default CMD from Dockerfile)
exec dotnet azure-sql-sk.dll "$@"
