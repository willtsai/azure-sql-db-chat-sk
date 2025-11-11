using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.AzureOpenAI;
using Microsoft.SemanticKernel.Connectors.SqlServer;
using DotNetEnv;
using System.Text.Json;
using Spectre.Console;
using Azure.Identity;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.VectorData;
using System.Diagnostics;
using System.Threading;
using Microsoft.Data.SqlClient;

#pragma warning disable SKEXP0010

namespace azure_sql_sk;

public class Memory
{
    [VectorStoreKey]
    public int Id { get; set; }

    [VectorStoreData]
    public string? Content { get; set; }

    [VectorStoreVector(Dimensions: 1536, DistanceFunction = DistanceFunction.CosineDistance)]
    public ReadOnlyMemory<float>? Embedding { get; set; }
}

public class ChatBot
{
    private readonly string chatModelEndpoint;
    private readonly string chatModelApiKey;
    private readonly string embeddingModelEndpoint;
    private readonly string embeddingModelApiKey;
    private readonly string embeddingModelDeploymentName;
    private readonly string chatModelDeploymentName;
    private readonly string sqlConnectionString;
    private readonly string sqlTableName;

    public ChatBot(string envFile)
    {
        // Load .env file if it exists (for local development)
        // In containerized environments, variables are passed directly via environment
        if (File.Exists(envFile))
        {
            Env.Load(envFile);
        }

        // Read from environment variables (works for both .env and container env vars)
        chatModelEndpoint = Environment.GetEnvironmentVariable("CONNECTION_AICHAT_ENDPOINT") ?? string.Empty;
        chatModelApiKey = Environment.GetEnvironmentVariable("CONNECTION_AICHAT_APIKEY") ?? string.Empty;
        embeddingModelEndpoint = Environment.GetEnvironmentVariable("CONNECTION_AIEMBEDDING_ENDPOINT") ?? string.Empty;
        embeddingModelApiKey = Environment.GetEnvironmentVariable("CONNECTION_AIEMBEDDING_APIKEY") ?? string.Empty;
        embeddingModelDeploymentName = Environment.GetEnvironmentVariable("CONNECTION_AIEMBEDDING_DEPLOYMENT") ?? string.Empty;
        chatModelDeploymentName = Environment.GetEnvironmentVariable("CONNECTION_AICHAT_DEPLOYMENT") ?? string.Empty;
        sqlConnectionString = Environment.GetEnvironmentVariable("CONNECTION_SQLSERVERDB_CONNECTIONSTRING") ?? string.Empty;
        sqlTableName = Environment.GetEnvironmentVariable("MSSQL_TABLE_NAME") ?? "ChatMemories";
    }

    public async Task RunAsync(bool enableDebug = false)
    {
        AnsiConsole.Clear();
        AnsiConsole.Foreground = Color.Green;

        var table = new Table();
        table.Expand();
        table.AddColumn(new TableColumn("[bold]Insurance Agent Assistant[/] v2.3").Centered());
        AnsiConsole.Write(table);

        var openAIPromptExecutionSettings = new AzureOpenAIPromptExecutionSettings()
        {
            FunctionChoiceBehavior = FunctionChoiceBehavior.Auto()
        };

        var (logger, kernel, ai, knowledge) = await AnsiConsole.Status().StartAsync("Booting up agent...", async ctx =>
        {
            ctx.Spinner(Spinner.Known.Default);
            ctx.SpinnerStyle(Style.Parse("yellow"));

            AnsiConsole.WriteLine("Initializing kernel...");
            
            var sc = new ServiceCollection();
            sc.AddLogging(b => 
            {
                b.ClearProviders(); // Clear default providers
                b.SetMinimumLevel(enableDebug ? LogLevel.Debug : LogLevel.Information);
                b.AddProvider(new SpectreConsoleLoggerProvider());
            });
            sc.AddKernel();

            if (string.IsNullOrEmpty(chatModelApiKey))
            {
                var credentials = new DefaultAzureCredential();
                sc.AddAzureOpenAIChatCompletion(chatModelDeploymentName, chatModelEndpoint, credentials);
            }
            if (string.IsNullOrEmpty(embeddingModelApiKey))
            {
                var credentials = new DefaultAzureCredential();
                sc.AddAzureOpenAIEmbeddingGenerator(embeddingModelDeploymentName, embeddingModelEndpoint, credentials);
            }
            else
            {
                sc.AddAzureOpenAIChatCompletion(chatModelDeploymentName, chatModelEndpoint, chatModelApiKey);
                sc.AddAzureOpenAIEmbeddingGenerator(embeddingModelDeploymentName, embeddingModelEndpoint, embeddingModelApiKey);
            }

            var services = sc.BuildServiceProvider();

            var kernel = services.GetRequiredService<Kernel>();           
            var logger = services.GetRequiredService<ILogger<Program>>();            

            if (enableDebug)
            {
                logger.LogInformation($"Embedding AI Endpoint: {embeddingModelEndpoint}, Embedding: {embeddingModelDeploymentName}, Chat AI Endpoint: {chatModelEndpoint}, Chat: {chatModelDeploymentName}");
            }

            AnsiConsole.WriteLine("Initializing plugins...");             
            kernel.Plugins.AddFromObject(new SearchDatabasePlugin(kernel, logger, sqlConnectionString));
            foreach (var p in kernel.Plugins)
            {
                foreach (var f in p.GetFunctionsMetadata())
                {
                    AnsiConsole.WriteLine($"Plugin: {p.Name}, Function: {f.Name}");
                }
            }

            // await using var mcpClient = await McpClientFactory.CreateAsync(
            //     new SseClientTransport(new () {
            //         Name = "MyFirstMCP",
            //         Endpoint = "http://localhost:5248"
            //     })
            // );
            // var tools = await mcpClient.ListToolsAsync();
            // kernel.Plugins.AddFromFunctions("MyFirstMCP", tools.Select(x => x.AsKernelFunction()));

            var ai = kernel.GetRequiredService<IChatCompletionService>();       
            var eg = services.GetRequiredService<IEmbeddingGenerator<string, Embedding<float>>>();     

            AnsiConsole.WriteLine("Initializing vector store...");

            if (enableDebug)
            {
                var b = new SqlConnectionStringBuilder(sqlConnectionString);
                logger.LogInformation($"Server: {b.DataSource}, Database: {b.InitialCatalog}, Table: {sqlTableName}");
            }

            var vectorStore =  new SqlServerVectorStore(sqlConnectionString, new SqlServerVectorStoreOptions() { EmbeddingGenerator = eg });        
            var knowledgeCollection = vectorStore.GetCollection<int, Memory>(sqlTableName);                    
            await knowledgeCollection.EnsureCollectionExistsAsync();                       

            AnsiConsole.WriteLine("Adding sample knowledge...");
            string[] knowledge = [
                "Premium for car insurance have been increased by 15% starting from Septmber 2024",
                "Customers can reduce their premium by subscribing to the 'Safety Score' program which will monitor their driving habits and provide discounts based on their driving score.",
            ];
            var records = knowledge.Select(async (input, index) => new Memory { Id = index+1, Content = input, Embedding = await eg.GenerateVectorAsync(input) }).ToList();
            await knowledgeCollection.UpsertAsync(records.Select(t => t.Result)); 

            AnsiConsole.WriteLine("Done!");

            return (logger, kernel, ai, knowledgeCollection);
        });

        var isInteractiveConsole = AnsiConsole.Profile.Capabilities.Interactive && !Console.IsInputRedirected;

        if (!isInteractiveConsole)
        {
            AnsiConsole.MarkupLine("[yellow]Interactive console not available. Waiting indefinitely to avoid CrashLoopBackOff.[/]");
            logger?.LogInformation("Interactive console unavailable. Application entering passive wait mode.");
            await Task.Delay(Timeout.InfiniteTimeSpan);
            return;
        }

        AnsiConsole.WriteLine("Ready to chat! Hit 'ctrl-c' to quit.");
                
        var chat = new ChatHistory($"""
            You are an AI assistant that helps insurance agents to find information on customers data and status. 
            Use a professional tone when aswering and provide a summary of data instead of lists. 
            If users ask about topics you don't know, answer that you don't know. Today's date is {DateTime.Now:yyyy-MM-dd}. 
            Query the database at every user request, even if information is available in chat history, to make sure you always have the latest information.
        """);
        var builder = new StringBuilder();

        try
        {
            while (true)
            {
                AnsiConsole.WriteLine();
                var question = AnsiConsole.Prompt(new TextPrompt<string>($"🧑: "));

                if (string.IsNullOrWhiteSpace(question))
                    continue;

                switch (question)
                {
                    case "/c":
                        AnsiConsole.Clear();
                        continue;
                    case "/ch":
                        chat.RemoveRange(1, chat.Count - 1);
                        AnsiConsole.WriteLine("Chat history cleared.");
                        continue;

                    case "/h":
                        foreach (var message in chat)
                        {
                            AnsiConsole.WriteLine($"> ---------- {message.Role} ----------");
                            AnsiConsole.WriteLine($"> MESSAGE  > {message.Content}");
                            AnsiConsole.WriteLine($"> METADATA > {JsonSerializer.Serialize(message.Metadata)}");
                            AnsiConsole.WriteLine($"> ------------------------------------");
                        }
                        continue;
                }

                await AnsiConsole.Status().StartAsync("Thinking...", async ctx =>
                {
                    if (!enableDebug)
                    {
                        ctx.Spinner(Spinner.Known.Default);
                        ctx.SpinnerStyle(Style.Parse("yellow"));
                    }

                    logger.LogDebug("Searching information from the memory...");
                    builder.Clear();
                    await foreach (var result in knowledge.SearchAsync(question, 3))
                    {
                        if (result.Score < 0.7)
                        {
                            builder.AppendLine(result.Record.Content);
                        }
                    }
                    if (builder.Length > 0)
                    {
                        logger.LogDebug("Found information from the memory:" + Environment.NewLine + builder.ToString());

                        builder.Insert(0, "Here's some additional information you can use to answer the question: ");

                        chat.AddSystemMessage(builder.ToString());
                    }
                });

                AnsiConsole.WriteLine();
                AnsiConsole.WriteLine("🤖: Formulating answer...");
                builder.Clear();
                chat.AddUserMessage(question);
                var firstLine = true;
                try
                {
                    await foreach (var message in ai.GetStreamingChatMessageContentsAsync(chat, openAIPromptExecutionSettings, kernel))
                    {
                        if (!enableDebug)
                        {
                            if (firstLine && message.Content != null && message.Content.Length > 0)
                            {
                                AnsiConsole.Cursor.MoveUp();
                                AnsiConsole.WriteLine("                                  ");
                                AnsiConsole.Cursor.MoveUp();
                                AnsiConsole.Write($"🤖: ");
                                firstLine = false;
                            }
                        }
                        AnsiConsole.Write(message.Content ?? string.Empty);
                        builder.Append(message.Content);
                    }
                }
                catch (Exception ex) when (IsContentFilterException(ex))
                {
                    // Gracefully handle Azure OpenAI content filtering (HTTP 400 content_filter)
                    logger?.LogInformation("Content filter triggered; informing user.");
                    if (firstLine)
                    {
                        // Clean up spinner line if no content printed yet
                        AnsiConsole.Cursor.MoveUp();
                        AnsiConsole.WriteLine("                                  ");
                        AnsiConsole.Cursor.MoveUp();
                        AnsiConsole.Write("🤖: ");
                    }
                    var advisory = "Your prompt or the generated content was blocked by the service's safety/content filter. Please rephrase to avoid sensitive, violent, sexual, self-harm, hate, personal data, or jailbreaking attempts. Try focusing on factual, neutral wording.";
                    AnsiConsole.MarkupLine($"[red]{advisory}[/]");
                    builder.Clear();
                    builder.Append(advisory);
                }
                AnsiConsole.WriteLine();

                chat.AddAssistantMessage(builder.ToString());
            }
        }
        catch (InvalidOperationException ex) when (ex.Message.Contains("non-interactive", StringComparison.OrdinalIgnoreCase))
        {
            logger?.LogWarning(ex, "Interactive console not available; switching to passive wait mode.");
            AnsiConsole.MarkupLine("[yellow]Interactive console not available. Waiting indefinitely to avoid CrashLoopBackOff.[/]");
            await Task.Delay(Timeout.InfiniteTimeSpan);
        }
    }

    private static bool IsContentFilterException(Exception ex)
    {
        if (ex == null) return false;
        // Match known Azure OpenAI content filter patterns
        var msg = ex.Message ?? string.Empty;
        if (msg.Contains("content_filter", StringComparison.OrdinalIgnoreCase)) return true;
        // Some SDKs wrap status code info; attempt heuristic checks
        if (msg.Contains("HTTP 400", StringComparison.OrdinalIgnoreCase) && msg.Contains("filter", StringComparison.OrdinalIgnoreCase)) return true;
        // Inspect inner exceptions recursively (bounded depth)
        var inner = ex.InnerException;
        int depth = 0;
        while (inner != null && depth < 3)
        {
            var im = inner.Message ?? string.Empty;
            if (im.Contains("content_filter", StringComparison.OrdinalIgnoreCase)) return true;
            inner = inner.InnerException;
            depth++;
        }
        return false;
    }
}

