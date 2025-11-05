@description('The context provided by Radius for linking resources')
param context object

extension kubernetes with {
  kubeConfig: ''
  namespace: context.runtime.kubernetes.namespace
} as kubernetes

var model = context.resource.properties.?model ?? 'tinyllama'
var uniqueName = 'llama-${uniqueString(context.resource.id)}'

// Model registry mapping HuggingFace URLs
var modelRegistry = {
  // Chat models
  tinyllama: {
    url: 'https://huggingface.co/ggml-org/models/resolve/main/tinyllama-1.1b/ggml-model-f16.gguf'
    filename: 'tinyllama.gguf'
    type: 'chat'
    contextSize: '512'
    threads: '4'
    memoryRequest: '4Gi'
    memoryLimit: '8Gi'
  }
  'llama3.2': {
    url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf'
    filename: 'llama3.2-3b.gguf'
    type: 'chat'
    contextSize: '2048'
    threads: '8'
    memoryRequest: '6Gi'
    memoryLimit: '12Gi'
  }
  'phi-3-mini': {
    url: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf'
    filename: 'phi3-mini.gguf'
    type: 'chat'
    contextSize: '4096'
    threads: '8'
    memoryRequest: '6Gi'
    memoryLimit: '12Gi'
  }
  // Embedding models
  'nomic-embed-text': {
    url: 'https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q8_0.gguf'
    filename: 'nomic-embed.gguf'
    type: 'embedding'
    contextSize: '2048'
    threads: '4'
    memoryRequest: '4Gi'
    memoryLimit: '8Gi'
  }
  'bge-small': {
    url: 'https://huggingface.co/BAAI/bge-small-en-v1.5-gguf/resolve/main/bge-small-en-v1.5-q8_0.gguf'
    filename: 'bge-small.gguf'
    type: 'embedding'
    contextSize: '512'
    threads: '4'
    memoryRequest: '2Gi'
    memoryLimit: '4Gi'
  }
}

var modelConfig = modelRegistry[model]

resource llamaDeployment 'apps/Deployment@v1' = {
  metadata: {
    name: uniqueName
    namespace: context.runtime.kubernetes.namespace
    labels: {
      'app.kubernetes.io/name': uniqueName
      'app.kubernetes.io/part-of': context.application.name
      'radapp.io/application': context.application.name
      'radapp.io/resource': context.resource.name
      'radapp.io/resource-type': 'Radius.Resources-aiModels'
    }
  }
  spec: {
    replicas: 1
    selector: {
      matchLabels: { app: uniqueName }
    }
    template: {
      metadata: {
        labels: {
          app: uniqueName
          'app.kubernetes.io/name': uniqueName
        }
      }
      spec: {
        initContainers: [
          {
            name: 'download-model'
            image: 'curlimages/curl:latest'
            command: ['sh', '-c']
            args: [
              'curl -L --fail --show-error --progress-bar ${modelConfig.url} -o /models/${modelConfig.filename} && ls -lh /models/'
            ]
            volumeMounts: [
              { name: 'model-volume', mountPath: '/models' }
            ]
          }
        ]
        containers: [
          {
            name: 'llama-cpp-server'
            image: 'ghcr.io/ggerganov/llama.cpp:server'
            ports: [{ containerPort: 8080 }]
            command: ['/app/llama-server']
            args: modelConfig.type == 'embedding' ? [
              '--model', '/models/${modelConfig.filename}'
              '--host', '0.0.0.0'
              '--port', '8080'
              '--embedding'
              '--ctx-size', modelConfig.contextSize
              '--threads', modelConfig.threads
            ] : [
              '--model', '/models/${modelConfig.filename}'
              '--host', '0.0.0.0'
              '--port', '8080'
              '--ctx-size', modelConfig.contextSize
              '--n-predict', '512'
              '--threads', modelConfig.threads
            ]
            volumeMounts: [
              { name: 'model-volume', mountPath: '/models' }
            ]
            resources: {
              requests: {
                memory: modelConfig.memoryRequest
                cpu: '2000m'
              }
              limits: {
                memory: modelConfig.memoryLimit
                cpu: '4000m'
              }
            }
            livenessProbe: {
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 120
              periodSeconds: 30
            }
            readinessProbe: {
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 60
              periodSeconds: 10
            }
          }
        ]
        volumes: [
          {
            name: 'model-volume'
            emptyDir: { sizeLimit: '10Gi' }
          }
        ]
      }
    }
  }
}

resource llamaService 'core/Service@v1' = {
  metadata: {
    name: uniqueName
    namespace: context.runtime.kubernetes.namespace
    labels: {
      'app.kubernetes.io/name': uniqueName
      'radapp.io/application': context.application.name
      'radapp.io/resource': context.resource.name
    }
  }
  spec: {
    type: 'ClusterIP'
    selector: { app: uniqueName }
    ports: [
      { port: 80, targetPort: 8080, protocol: 'TCP' }
    ]
  }
}

output result object = {
  values: {
    endpoint: 'http://${llamaService.metadata.name}.${llamaService.metadata.namespace}.svc.cluster.local:80/v1'
    model: model
    deployment: model
    apiVersion: 'v1'
    location: 'local'
    modelType: modelConfig.type
  }
  secrets: {
    apiKey: ''
  }
}
