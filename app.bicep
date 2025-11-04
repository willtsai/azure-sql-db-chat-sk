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
      image: 'ghcr.io/willtsai/azure-sql-db-chat-sk:azure'
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
