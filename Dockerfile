# Multi-stage build for Azure SQL DB Chat with Semantic Kernel

# ============================================
# Stage 1: Build
# ============================================
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy project file and restore dependencies (for layer caching)
COPY *.csproj ./
RUN dotnet restore

# Copy source code, SQL scripts, and services
COPY *.cs ./
COPY sql/ ./sql/
COPY Services/ ./Services/

# Build the application in Release mode
RUN dotnet publish -c Release -o /app/publish --no-restore

# ============================================
# Stage 2: Runtime
# ============================================
FROM mcr.microsoft.com/dotnet/runtime:9.0-alpine AS runtime
WORKDIR /app

# Install dependencies: ICU for .NET globalization, bash and curl for scripts
RUN apk add --no-cache icu-libs bash curl

# Set environment variables
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
ENV DAPR_ENABLED=true

# Create directories for Dapr components
RUN mkdir -p /dapr/components

# Create non-root user for security
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

# Copy published application from build stage
COPY --from=build /app/publish ./

# Copy SQL migration scripts (required by DbUp)
COPY --from=build /src/sql ./sql/

# Copy scripts
COPY scripts/ ./scripts/

# Copy entrypoint script
COPY docker-entrypoint.sh ./

# Make scripts executable and set ownership to non-root user
RUN chmod +x docker-entrypoint.sh && \
    chmod +x scripts/generate-dapr-components.sh && \
    chown -R appuser:appgroup /app && \
    chown -R appuser:appgroup /dapr

# Switch to non-root user
USER appuser

# Set entrypoint to the script (automatically runs deploy then chat)
ENTRYPOINT ["./docker-entrypoint.sh"]

# Default command (can be overridden with: chat --debug, or other arguments)
CMD ["chat"]

# Health check (optional - verifies the application can start)
# Uncomment if you want Docker to monitor container health
# HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
#   CMD dotnet azure-sql-sk.dll --help || exit 1

# Labels for metadata
LABEL maintainer="Azure SQL DB Chat Team"
LABEL description="Insurance chatbot demo with Semantic Kernel, RAG, and NL2SQL with Dapr support"
LABEL version="2.0"
