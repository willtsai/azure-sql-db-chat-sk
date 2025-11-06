#!/bin/bash
set -e

echo "=========================================="
echo "Applying Dapr Conversation Components"
echo "=========================================="
echo ""
echo "This script reads your deployed services and creates"
echo "the appropriate Dapr conversation components."
echo ""

# Get namespace
NAMESPACE="${1:-default-insurance-chat}"

echo "Using namespace: $NAMESPACE"
echo ""

# Get the chat service details
echo "Finding chat AI service..."
CHAT_SVC=$(kubectl get svc -n $NAMESPACE -l 'radapp.io/resource=ai-chat-model' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$CHAT_SVC" ]; then
    echo "❌ Error: Could not find chat AI service in namespace $NAMESPACE"
    echo "   Expected label: radapp.io/resource=ai-chat-model"
    exit 1
fi

CHAT_ENDPOINT="http://${CHAT_SVC}.${NAMESPACE}.svc.cluster.local:80/v1"
echo "✓ Found chat service: $CHAT_SVC"
echo "  Endpoint: $CHAT_ENDPOINT"

# Get the embedding service details
echo ""
echo "Finding embedding AI service..."
EMBED_SVC=$(kubectl get svc -n $NAMESPACE -l 'radapp.io/resource=ai-embedding-model' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$EMBED_SVC" ]; then
    echo "❌ Error: Could not find embedding AI service in namespace $NAMESPACE"
    echo "   Expected label: radapp.io/resource=ai-embedding-model"
    exit 1
fi

EMBED_ENDPOINT="http://${EMBED_SVC}.${NAMESPACE}.svc.cluster.local:80/v1"
echo "✓ Found embedding service: $EMBED_SVC"
echo "  Endpoint: $EMBED_ENDPOINT"

# Determine provider type (check if it's Azure OpenAI or llama.cpp)
echo ""
echo "Determining provider type..."

# Check if it's llama.cpp (service name starts with "llama-")
if [[ "$CHAT_SVC" == llama-* ]]; then
    PROVIDER_TYPE="openai"
    CHAT_MODEL="llama3.2"  # Default, should match what's deployed
    EMBED_MODEL="nomic-embed-text"  # Default, should match what's deployed
    echo "✓ Detected provider: OpenAI-compatible (llama.cpp)"
else
    # Assume Azure OpenAI
    PROVIDER_TYPE="azure.openai"
    CHAT_MODEL="gpt-4"
    EMBED_MODEL="text-embedding-3-small"
    echo "✓ Detected provider: Azure OpenAI"
fi

# Create chat component
echo ""
echo "Creating conversation-chat component..."

if [ "$PROVIDER_TYPE" == "openai" ]; then
    cat <<EOF | kubectl apply -f -
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-chat
  namespace: $NAMESPACE
spec:
  type: conversation.openai
  version: v1
  metadata:
  - name: endpoint
    value: "$CHAT_ENDPOINT"
  - name: model
    value: "$CHAT_MODEL"
EOF
else
    echo "⚠️  For Azure OpenAI, you need to provide API key and deployment name"
    echo "   Please set these environment variables and re-run:"
    echo "   export AZURE_OPENAI_CHAT_KEY='your-key'"
    echo "   export AZURE_OPENAI_CHAT_DEPLOYMENT='your-deployment'"
    
    if [ -z "$AZURE_OPENAI_CHAT_KEY" ] || [ -z "$AZURE_OPENAI_CHAT_DEPLOYMENT" ]; then
        echo "❌ Missing required environment variables for Azure OpenAI"
        exit 1
    fi
    
    cat <<EOF | kubectl apply -f -
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-chat
  namespace: $NAMESPACE
spec:
  type: conversation.azure.openai
  version: v1
  metadata:
  - name: endpoint
    value: "$CHAT_ENDPOINT"
  - name: apiKey
    value: "$AZURE_OPENAI_CHAT_KEY"
  - name: deploymentName
    value: "$AZURE_OPENAI_CHAT_DEPLOYMENT"
EOF
fi

echo "✓ conversation-chat component created"

# Create embedding component
echo ""
echo "Creating conversation-embedding component..."

if [ "$PROVIDER_TYPE" == "openai" ]; then
    cat <<EOF | kubectl apply -f -
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-embedding
  namespace: $NAMESPACE
spec:
  type: conversation.openai
  version: v1
  metadata:
  - name: endpoint
    value: "$EMBED_ENDPOINT"
  - name: model
    value: "$EMBED_MODEL"
EOF
else
    if [ -z "$AZURE_OPENAI_EMBED_KEY" ] || [ -z "$AZURE_OPENAI_EMBED_DEPLOYMENT" ]; then
        echo "❌ Missing required environment variables for Azure OpenAI"
        echo "   export AZURE_OPENAI_EMBED_KEY='your-key'"
        echo "   export AZURE_OPENAI_EMBED_DEPLOYMENT='your-deployment'"
        exit 1
    fi
    
    cat <<EOF | kubectl apply -f -
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: conversation-embedding
  namespace: $NAMESPACE
spec:
  type: conversation.azure.openai
  version: v1
  metadata:
  - name: endpoint
    value: "$EMBED_ENDPOINT"
  - name: apiKey
    value: "$AZURE_OPENAI_EMBED_KEY"
  - name: deploymentName
    value: "$AZURE_OPENAI_EMBED_DEPLOYMENT"
EOF
fi

echo "✓ conversation-embedding component created"

echo ""
echo "=========================================="
echo "✓ Dapr components successfully applied!"
echo "=========================================="
echo ""
echo "To verify, run:"
echo "  kubectl get components -n $NAMESPACE"
echo ""
echo "To restart the chatbot and pick up the components:"
echo "  kubectl rollout restart deployment/chatbot -n $NAMESPACE"
