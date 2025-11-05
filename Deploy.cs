using System;
using System.Collections.Generic;
using System.Text;
using DbUp;
using DbUp.ScriptProviders;
using Microsoft.Data.SqlClient;
using DotNetEnv;

namespace azure_sql_sk;

class DatabaseUtils
{
    static public void Deploy(string envFile)
    {
        // Load .env file if it exists (for local development)
        // In containerized environments, variables are passed directly via environment
        if (File.Exists(envFile))
        {
            Env.Load(envFile);
        }

        string embeddingModelEndpoint = Environment.GetEnvironmentVariable("CONNECTION_AIEMBEDDING_ENDPOINT") ?? string.Empty;
        string embeddingModelApiKey = Environment.GetEnvironmentVariable("CONNECTION_AIEMBEDDING_APIKEY") ?? string.Empty;
        string embeddingModelDeploymentName = Environment.GetEnvironmentVariable("CONNECTION_AIEMBEDDING_DEPLOYMENT") ?? string.Empty;
        string embeddingModelName = Environment.GetEnvironmentVariable("CONNECTION_AIEMBEDDING_MODEL") ?? embeddingModelDeploymentName;
        string sqlConnectionString = Environment.GetEnvironmentVariable("CONNECTION_SQLSERVERDB_CONNECTIONSTRING") ?? string.Empty;

        if (string.IsNullOrEmpty(sqlConnectionString)) {
            throw new ApplicationException("CONNECTION_SQLSERVERDB_CONNECTIONSTRING environment variable not set or empty.");
        }
        
        // Detect if endpoint is Azure OpenAI or OpenAI-compatible
        bool isAzureOpenAI = !string.IsNullOrEmpty(embeddingModelEndpoint) && 
                             (embeddingModelEndpoint.Contains("azure") || embeddingModelEndpoint.Contains("openai.azure.com"));
        
        // Build appropriate embedding URL based on provider
        string embeddingUrl;
        if (isAzureOpenAI)
        {
            // Azure OpenAI format: https://xxx.openai.azure.com/openai/deployments/{deployment}/embeddings?api-version={version}
            embeddingUrl = $"{embeddingModelEndpoint.TrimEnd('/')}/openai/deployments/{embeddingModelDeploymentName}/embeddings?api-version=2024-02-15-preview";
        }
        else
        {
            // OpenAI-compatible format: http://xxx/v1/embeddings
            embeddingUrl = $"{embeddingModelEndpoint.TrimEnd('/')}/embeddings";
        }
        
        Console.WriteLine($"Detected provider: {(isAzureOpenAI ? "Azure OpenAI" : "OpenAI-compatible")}");
        Console.WriteLine($"Embedding URL: {embeddingUrl}");
        
        var csb = new SqlConnectionStringBuilder(sqlConnectionString);
        Console.WriteLine($"Deploying database: {csb.InitialCatalog}@{csb.DataSource} ");

        Console.WriteLine("Testing connection...");
        var conn = new SqlConnection(csb.ToString());
        conn.Open();
        conn.Close();

        FileSystemScriptOptions options = new() {
            IncludeSubDirectories = false,
            Extensions = ["*.sql"],
            Filter = (file) => !file.EndsWith(".local.sql"),
            Encoding = Encoding.UTF8
        };

        Dictionary<string, string> variables = new() {
            {"CONNECTION_AIEMBEDDING_ENDPOINT", embeddingModelEndpoint},
            {"CONNECTION_AIEMBEDDING_APIKEY", embeddingModelApiKey ?? string.Empty},
            {"CONNECTION_AIEMBEDDING_DEPLOYMENT", embeddingModelDeploymentName},
            {"CONNECTION_AIEMBEDDING_MODEL", embeddingModelName},
            {"CONNECTION_AIEMBEDDING_URL", embeddingUrl},
            {"IS_AZURE_OPENAI", isAzureOpenAI ? "1" : "0"}
        };

        Console.WriteLine("Starting deployment...");
        var dbup = DeployChanges.To
            .SqlDatabase(csb.ConnectionString)
            .WithVariables(variables)
            .WithScriptsFromFileSystem("sql", options)
            .JournalToSqlTable("dbo", "$__dbup_journal")                                               
            .LogToConsole()
            .Build();
        
        var result = dbup.PerformUpgrade();

        if (!result.Successful)
        {
            throw result.Error;            
        }
    }
}