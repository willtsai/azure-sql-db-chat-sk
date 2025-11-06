# Kubernetes RBAC for Dapr Component Management

This directory contains Kubernetes RBAC resources that allow the chatbot pod to automatically create Dapr conversation components during startup.

## Setup (One-time)

Apply the RBAC resources before deploying with Radius:

```bash
kubectl apply -f k8s/chatbot-rbac.yaml
```

This creates:
- **ServiceAccount**: `chatbot-sa` 
- **Role**: Permissions to create/update Dapr components in the namespace
- **RoleBinding**: Links the ServiceAccount to the Role

## How It Works

1. You apply the RBAC once (before first Radius deployment)
2. Radius deploys the chatbot container (which will use this ServiceAccount)
3. Container starts and runs `generate-dapr-components.sh`
4. Script uses kubectl with the ServiceAccount's permissions to create Dapr components
5. Dapr sidecar loads the components automatically
6. Application starts and uses Dapr conversation API

## Verification

```bash
# Check ServiceAccount exists
kubectl get sa chatbot-sa -n default-insurance-chat

# Check Role and RoleBinding
kubectl get role dapr-component-manager -n default-insurance-chat
kubectl get rolebinding chatbot-dapr-manager -n default-insurance-chat
```

## Cleanup

```bash
kubectl delete -f k8s/chatbot-rbac.yaml
```
