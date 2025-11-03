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
        string sqlConnectionString = Environment.GetEnvironmentVariable("CONNECTION_SQLSERVERDB_CONNECTIONSTRING") ?? string.Empty;

        if (string.IsNullOrEmpty(sqlConnectionString)) {
            throw new ApplicationException("CONNECTION_SQLSERVERDB_CONNECTIONSTRING environment variable not set or empty.");
        }
        
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
            {"CONNECTION_AIEMBEDDING_APIKEY", embeddingModelApiKey},
            {"CONNECTION_AIEMBEDDING_DEPLOYMENT", embeddingModelDeploymentName}
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