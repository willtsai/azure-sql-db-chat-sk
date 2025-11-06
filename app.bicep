extension radius

extension radiusResources

param environment string

param chatModelName string
param embeddingModelName string

resource insurancechat 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'insurance-chat'
  properties: {
    environment: environment
  }
}

resource chatbot 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'chatbot'
  properties: {
    application: insurancechat.id
    environment: environment
    container: {
      // image: 'ghcr.io/willtsai/azure-sql-db-chat-sk@sha256:041ac9c4adb91ba6f1df093bda7bc88ffa0c6646f8c6542af3daad38e59feade'
      image: 'ghcr.io/willtsai/azure-sql-db-chat-sk:daprized-5'
      env: {
        MSSQL_TABLE_NAME: {
          value: 'ChatMemories'
        }
      }
    }
    connections: {
      aichat: {
        source: chatModel.id
      }
      aiembedding: {
        source: embeddingModel.id
      }
      sqlserverdb: {
        source: sqlServerDb.id
      }
    }
    extensions: [
      {
        kind: 'daprSidecar'
        appId: 'chatbot'
      }
    ]
  }
}

resource chatModel 'Radius.Resources/aiModels@2025-11-01-preview' = {
  name: 'ai-chat-model'
  properties: {
    application: insurancechat.id
    environment: environment
    model: chatModelName
  }
}

resource embeddingModel 'Radius.Resources/aiModels@2025-11-01-preview' = {
  name: 'ai-embedding-model'
  properties: {
    application: insurancechat.id
    environment: environment
    model: embeddingModelName
  }
}

resource sqlServerDb 'Radius.Resources/sqlServerDatabases@2025-11-01-preview' = {
  name: 'sql-server-db'
  properties: {
    application: insurancechat.id
    environment: environment
    database: 'insurancechatdb'
    version: '2025'
  }
}
