#!/bin/bash
set -e

echo "Generating Dapr components from Radius connection environment variables..."

COMPONENTS_DIR="/dapr/components"
mkdir -p "$COMPONENTS_DIR"

# Function to determine provider type from endpoint
determine_provider_type() {
    local endpoint=$1
    if [[ "$endpoint" == *"azure"* ]] || [[ "$endpoint" == *"openai.azure.com"* ]]; then
        echo "azure-openai"
    elif [[ "$endpoint" == *":8080"* ]] || [[ "$endpoint" == *":11434"* ]] || [[ "$endpoint" == *"llama"* ]]; then
        echo "openai"  # llama.cpp and Ollama are OpenAI-compatible
    elif [[ "$endpoint" == *"api.openai.com"* ]]; then
        echo "openai"
    else
        echo "openai"  # Default fallback
    fi
}

# Generate CHAT component from CONNECTION_AICHAT_* variables
echo "Processing CONNECTION_AICHAT_* variables..."
CHAT_PROVIDER=$(determine_provider_type "$CONNECTION_AICHAT_ENDPOINT")
echo "Detected chat provider: $CHAT_PROVIDER"

cat > "$COMPONENTS_DIR/conversation-chat.yaml" <<EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-chat
spec:
  type: conversation.${CHAT_PROVIDER}
  version: v1
  metadata:
  - name: endpoint
    value: "${CONNECTION_AICHAT_ENDPOINT}"
EOF

# Add provider-specific metadata for chat
if [[ "$CHAT_PROVIDER" == "azure-openai" ]]; then
    cat >> "$COMPONENTS_DIR/conversation-chat.yaml" <<EOF
  - name: apiKey
    value: "${CONNECTION_AICHAT_APIKEY}"
  - name: deploymentName
    value: "${CONNECTION_AICHAT_DEPLOYMENT}"
  - name: apiVersion
    value: "${CONNECTION_AICHAT_APIVERSION:-2024-02-15-preview}"
EOF
else
    # For OpenAI-compatible endpoints (llama.cpp, Ollama, OpenAI)
    if [[ -n "$CONNECTION_AICHAT_APIKEY" ]]; then
        cat >> "$COMPONENTS_DIR/conversation-chat.yaml" <<EOF
  - name: apiKey
    value: "${CONNECTION_AICHAT_APIKEY}"
EOF
    fi
    cat >> "$COMPONENTS_DIR/conversation-chat.yaml" <<EOF
  - name: model
    value: "${CONNECTION_AICHAT_MODEL:-${CONNECTION_AICHAT_DEPLOYMENT}}"
EOF
fi

# Generate EMBEDDING component from CONNECTION_AIEMBEDDING_* variables
echo "Processing CONNECTION_AIEMBEDDING_* variables..."
EMBEDDING_PROVIDER=$(determine_provider_type "$CONNECTION_AIEMBEDDING_ENDPOINT")
echo "Detected embedding provider: $EMBEDDING_PROVIDER"

cat > "$COMPONENTS_DIR/conversation-embedding.yaml" <<EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-embedding
spec:
  type: conversation.${EMBEDDING_PROVIDER}
  version: v1
  metadata:
  - name: endpoint
    value: "${CONNECTION_AIEMBEDDING_ENDPOINT}"
EOF

# Add provider-specific metadata for embedding
if [[ "$EMBEDDING_PROVIDER" == "azure-openai" ]]; then
    cat >> "$COMPONENTS_DIR/conversation-embedding.yaml" <<EOF
  - name: apiKey
    value: "${CONNECTION_AIEMBEDDING_APIKEY}"
  - name: deploymentName
    value: "${CONNECTION_AIEMBEDDING_DEPLOYMENT}"
  - name: apiVersion
    value: "${CONNECTION_AIEMBEDDING_APIVERSION:-2024-02-15-preview}"
EOF
else
    # For OpenAI-compatible endpoints
    if [[ -n "$CONNECTION_AIEMBEDDING_APIKEY" ]]; then
        cat >> "$COMPONENTS_DIR/conversation-embedding.yaml" <<EOF
  - name: apiKey
    value: "${CONNECTION_AIEMBEDDING_APIKEY}"
EOF
    fi
    cat >> "$COMPONENTS_DIR/conversation-embedding.yaml" <<EOF
  - name: model
    value: "${CONNECTION_AIEMBEDDING_MODEL:-${CONNECTION_AIEMBEDDING_DEPLOYMENT}}"
EOF
fi

echo "Generated Dapr components:"
ls -la "$COMPONENTS_DIR"
echo ""
echo "Chat component:"
cat "$COMPONENTS_DIR/conversation-chat.yaml"
echo ""
echo "Embedding component:"
cat "$COMPONENTS_DIR/conversation-embedding.yaml"
