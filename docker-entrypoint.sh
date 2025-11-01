#!/bin/sh
set -e

echo "================================"
echo "Azure SQL Chat - Starting up..."
echo "================================"

# Run database deployment/initialization
echo ""
echo "[1/2] Running database deployment..."
dotnet azure-sql-sk.dll deploy

if [ $? -eq 0 ]; then
    echo "[1/2] Database deployment completed successfully"
else
    echo "[1/2] Database deployment failed!"
    exit 1
fi

# Run the main application command (passed as arguments)
echo ""
echo "[2/2] Starting chat application..."
echo "================================"
echo ""

# Execute the command passed to docker run (or default CMD from Dockerfile)
exec dotnet azure-sql-sk.dll "$@"
