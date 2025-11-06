using Microsoft.Extensions.DependencyInjection;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.Connectors.AzureOpenAI;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.Extensions.AI;
using Azure.Identity;
using Azure.AI.OpenAI;
using OpenAI;

#pragma warning disable SKEXP0010

namespace azure_sql_sk;

public static class AIProviderFactory
{
    public static void ConfigureAIServices(
        IServiceCollection services,
        string chatEndpoint,
        string chatApiKey,
        string chatDeployment,
        string embeddingEndpoint,
        string embeddingApiKey,
        string embeddingDeployment)
    {
        bool isAzureOpenAI = chatEndpoint.Contains(".openai.azure.com", StringComparison.OrdinalIgnoreCase);
        
        if (isAzureOpenAI)
        {
            ConfigureAzureOpenAI(services, chatEndpoint, chatApiKey, chatDeployment, 
                                embeddingEndpoint, embeddingApiKey, embeddingDeployment);
        }
        else
        {
            ConfigureOpenAICompatible(services, chatEndpoint, chatApiKey, chatDeployment,
                                     embeddingEndpoint, embeddingApiKey, embeddingDeployment);
        }
    }

    private static void ConfigureAzureOpenAI(
        IServiceCollection services,
        string chatEndpoint,
        string chatApiKey,
        string chatDeployment,
        string embeddingEndpoint,
        string embeddingApiKey,
        string embeddingDeployment)
    {
        if (string.IsNullOrEmpty(chatApiKey))
        {
            var credentials = new DefaultAzureCredential();
            services.AddAzureOpenAIChatCompletion(chatDeployment, chatEndpoint, credentials);
        }
        else
        {
            services.AddAzureOpenAIChatCompletion(chatDeployment, chatEndpoint, chatApiKey);
        }

        if (string.IsNullOrEmpty(embeddingApiKey))
        {
            var credentials = new DefaultAzureCredential();
            services.AddAzureOpenAIEmbeddingGenerator(embeddingDeployment, embeddingEndpoint, credentials);
        }
        else
        {
            services.AddAzureOpenAIEmbeddingGenerator(embeddingDeployment, embeddingEndpoint, embeddingApiKey);
        }
    }

    private static void ConfigureOpenAICompatible(
        IServiceCollection services,
        string chatEndpoint,
        string chatApiKey,
        string chatDeployment,
        string embeddingEndpoint,
        string embeddingApiKey,
        string embeddingDeployment)
    {
        if (string.IsNullOrEmpty(chatApiKey))
        {
            services.AddOpenAIChatCompletion(chatDeployment, endpoint: new Uri(chatEndpoint));
            services.AddOpenAIEmbeddingGenerator(embeddingDeployment, embeddingEndpoint);
        }
        else
        {
            services.AddOpenAIChatCompletion(chatDeployment, apiKey: chatApiKey, endpoint: new Uri(chatEndpoint));
            services.AddOpenAIEmbeddingGenerator(embeddingDeployment, embeddingApiKey, embeddingEndpoint);
        }
    }
}
