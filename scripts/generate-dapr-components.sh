#!/bin/bash
set -e

echo "Generating Dapr components from Radius connection environment variables..."

COMPONENTS_DIR="/dapr/components"
mkdir -p "$COMPONENTS_DIR"

# Auto-detect namespace from pod metadata or environment
NAMESPACE="${POD_NAMESPACE}"
if [ -z "$NAMESPACE" ] && [ -f /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
    NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
fi
if [ -z "$NAMESPACE" ]; then
    NAMESPACE="default-insurance-chat"
fi

echo "Using namespace: $NAMESPACE"

# Function to determine provider type from endpoint
determine_provider_type() {
    local endpoint=$1
    if [[ "$endpoint" == *"azure"* ]] || [[ "$endpoint" == *"openai.azure.com"* ]]; then
        echo "azure.openai"
    else
        echo "openai"  # llama.cpp, Ollama, and OpenAI are all OpenAI-compatible
    fi
}

# Generate CHAT component
echo "Processing CONNECTION_AICHAT_* variables..."
CHAT_PROVIDER=$(determine_provider_type "$CONNECTION_AICHAT_ENDPOINT")
echo "Detected chat provider: conversation.$CHAT_PROVIDER"

cat > "$COMPONENTS_DIR/conversation-chat.yaml" <<EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-chat
  namespace: ${NAMESPACE}
spec:
  type: conversation.${CHAT_PROVIDER}
  version: v1
  metadata:
  - name: endpoint
    value: "${CONNECTION_AICHAT_ENDPOINT}"
EOF

# Add provider-specific metadata for chat
if [[ "$CHAT_PROVIDER" == "azure.openai" ]]; then
    cat >> "$COMPONENTS_DIR/conversation-chat.yaml" <<EOF
  - name: apiKey
    value: "${CONNECTION_AICHAT_APIKEY}"
  - name: deploymentName
    value: "${CONNECTION_AICHAT_DEPLOYMENT}"
EOF
    if [[ -n "$CONNECTION_AICHAT_APIVERSION" ]]; then
        cat >> "$COMPONENTS_DIR/conversation-chat.yaml" <<EOF
  - name: apiVersion
    value: "${CONNECTION_AICHAT_APIVERSION}"
EOF
    fi
else
    # For OpenAI-compatible endpoints
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

# Generate EMBEDDING component
echo "Processing CONNECTION_AIEMBEDDING_* variables..."
EMBEDDING_PROVIDER=$(determine_provider_type "$CONNECTION_AIEMBEDDING_ENDPOINT")
echo "Detected embedding provider: conversation.$EMBEDDING_PROVIDER"

cat > "$COMPONENTS_DIR/conversation-embedding.yaml" <<EOF
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-embedding
  namespace: ${NAMESPACE}
spec:
  type: conversation.${EMBEDDING_PROVIDER}
  version: v1
  metadata:
  - name: endpoint
    value: "${CONNECTION_AIEMBEDDING_ENDPOINT}"
EOF

# Add provider-specific metadata for embedding
if [[ "$EMBEDDING_PROVIDER" == "azure.openai" ]]; then
    cat >> "$COMPONENTS_DIR/conversation-embedding.yaml" <<EOF
  - name: apiKey
    value: "${CONNECTION_AIEMBEDDING_APIKEY}"
  - name: deploymentName
    value: "${CONNECTION_AIEMBEDDING_DEPLOYMENT}"
EOF
    if [[ -n "$CONNECTION_AIEMBEDDING_APIVERSION" ]]; then
        cat >> "$COMPONENTS_DIR/conversation-embedding.yaml" <<EOF
  - name: apiVersion
    value: "${CONNECTION_AIEMBEDDING_APIVERSION}"
EOF
    fi
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

echo ""
echo "Generated component files in $COMPONENTS_DIR"

# Apply components to Kubernetes
echo ""
echo "Applying Dapr components to Kubernetes..."

if command -v kubectl &> /dev/null; then
    kubectl apply -f "$COMPONENTS_DIR/conversation-chat.yaml" 2>&1
    kubectl apply -f "$COMPONENTS_DIR/conversation-embedding.yaml" 2>&1
    echo "✓ Components applied successfully"
else
    echo "⚠️  kubectl not available - components generated but not applied"
    echo "   Components saved to: $COMPONENTS_DIR"
    exit 1
fi

echo ""
echo "Component details:"
echo "---"
cat "$COMPONENTS_DIR/conversation-chat.yaml"
echo "---"
cat "$COMPONENTS_DIR/conversation-embedding.yaml"
echo "---"
