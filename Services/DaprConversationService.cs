using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Dapr.Client;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel.ChatCompletion;

namespace azure_sql_sk.Services;

public class DaprConversationService : IConversationService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<DaprConversationService> _logger;
    private readonly string _daprHttpEndpoint;
    private const string ChatComponentName = "conversation-chat";
    private const string EmbeddingComponentName = "conversation-embedding";

    public DaprConversationService(
        IHttpClientFactory httpClientFactory,
        ILogger<DaprConversationService> logger,
        string daprHttpEndpoint = "http://localhost:3500")
    {
        _httpClient = httpClientFactory.CreateClient();
        _logger = logger;
        _daprHttpEndpoint = daprHttpEndpoint;
    }

    public async Task<string> GetChatCompletionAsync(ChatHistory messages, CancellationToken ct = default)
    {
        _logger.LogDebug($"Calling Dapr conversation API with component '{ChatComponentName}'");

        // Dapr conversation API expects ConversationRequest format
        var request = new
        {
            conversationContext = "",
            inputs = messages.Select(m => new
            {
                message = m.Content ?? string.Empty,
                role = m.Role.ToString().ToLowerInvariant()
            }).ToArray()
        };

        var httpRequest = new HttpRequestMessage(HttpMethod.Post,
            $"{_daprHttpEndpoint}/v1.0-alpha1/conversation/{ChatComponentName}/converse")
        {
            Content = JsonContent.Create(request)
        };

        httpRequest.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");

        var response = await _httpClient.SendAsync(httpRequest, ct);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync(ct);
            _logger.LogError($"Dapr conversation API error: {response.StatusCode} - {error}");
            response.EnsureSuccessStatusCode();
        }

        var result = await response.Content.ReadFromJsonAsync<DaprConversationResponse>(ct);
        return result?.Outputs?[0]?.Result ?? string.Empty;
    }

    public async IAsyncEnumerable<string> GetStreamingChatCompletionAsync(
        ChatHistory messages,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        _logger.LogDebug($"Calling Dapr conversation API with component '{ChatComponentName}' (streaming)");

        var request = new
        {
            conversationContext = "",
            inputs = messages.Select(m => new
            {
                message = m.Content ?? string.Empty,
                role = m.Role.ToString().ToLowerInvariant()
            }).ToArray(),
            parameters = new 
            { 
                stream = true 
            }
        };

        var httpRequest = new HttpRequestMessage(HttpMethod.Post,
            $"{_daprHttpEndpoint}/v1.0-alpha1/conversation/{ChatComponentName}/converse")
        {
            Content = JsonContent.Create(request)
        };

        httpRequest.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");

        var response = await _httpClient.SendAsync(httpRequest, HttpCompletionOption.ResponseHeadersRead, ct);

        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);

        while (!reader.EndOfStream && !ct.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(ct);
            if (string.IsNullOrWhiteSpace(line)) continue;

            if (line.StartsWith("data: "))
            {
                var data = line.Substring(6).Trim();
                if (data == "[DONE]") break;

                DaprConversationStreamChunk? chunk = null;
                try
                {
                    chunk = JsonSerializer.Deserialize<DaprConversationStreamChunk>(data);
                }
                catch (JsonException ex)
                {
                    _logger.LogWarning(ex, $"Failed to parse SSE chunk: {data}");
                    continue;
                }

                var content = chunk?.Result;
                if (!string.IsNullOrEmpty(content))
                {
                    yield return content;
                }
            }
        }
    }

    public async Task<ReadOnlyMemory<float>> GenerateEmbeddingAsync(string text, CancellationToken ct = default)
    {
        _logger.LogDebug($"Calling Dapr conversation API with component '{EmbeddingComponentName}' for embedding");

        // Dapr conversation API expects a ConversationRequest with specific structure
        var request = new
        {
            conversationContext = "",
            inputs = new[] 
            { 
                new { 
                    message = text,
                    role = "user"
                }
            }
        };

        var httpRequest = new HttpRequestMessage(HttpMethod.Post, 
            $"{_daprHttpEndpoint}/v1.0-alpha1/conversation/{EmbeddingComponentName}/converse")
        {
            Content = JsonContent.Create(request)
        };
        
        // Ensure JSON content type
        httpRequest.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");

        var response = await _httpClient.SendAsync(httpRequest, ct);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync(ct);
            _logger.LogError($"Dapr conversation API error: {response.StatusCode} - {error}");
            response.EnsureSuccessStatusCode();
        }

        var result = await response.Content.ReadFromJsonAsync<DaprConversationEmbeddingResponse>(ct);
        var embedding = result?.Outputs?[0]?.Embedding ?? Array.Empty<float>();
        return new ReadOnlyMemory<float>(embedding);
    }

    // Dapr Conversation API response models
    private class DaprConversationResponse
    {
        [JsonPropertyName("outputs")]
        public List<DaprConversationOutput>? Outputs { get; set; }
    }

    private class DaprConversationOutput
    {
        [JsonPropertyName("result")]
        public string? Result { get; set; }
    }

    private class DaprConversationStreamChunk
    {
        [JsonPropertyName("result")]
        public string? Result { get; set; }
    }

    private class DaprConversationEmbeddingResponse
    {
        [JsonPropertyName("outputs")]
        public List<DaprConversationEmbeddingOutput>? Outputs { get; set; }
    }

    private class DaprConversationEmbeddingOutput
    {
        [JsonPropertyName("embedding")]
        public float[]? Embedding { get; set; }
    }

    // Legacy OpenAI format models (kept for reference, not used with Dapr conversation API)
    private class OpenAIRequest
    {
        [JsonPropertyName("messages")]
        public List<OpenAIMessage> Messages { get; set; } = new();

        [JsonPropertyName("stream")]
        public bool Stream { get; set; }
    }

    private class OpenAIMessage
    {
        [JsonPropertyName("role")]
        public string Role { get; set; } = string.Empty;

        [JsonPropertyName("content")]
        public string Content { get; set; } = string.Empty;
    }

    private class OpenAIResponse
    {
        [JsonPropertyName("choices")]
        public List<OpenAIChoice>? Choices { get; set; }
    }

    private class OpenAIChoice
    {
        [JsonPropertyName("message")]
        public OpenAIMessage? Message { get; set; }
    }

    private class OpenAIStreamChunk
    {
        [JsonPropertyName("choices")]
        public List<OpenAIStreamChoice>? Choices { get; set; }
    }

    private class OpenAIStreamChoice
    {
        [JsonPropertyName("delta")]
        public OpenAIDelta? Delta { get; set; }
    }

    private class OpenAIDelta
    {
        [JsonPropertyName("content")]
        public string? Content { get; set; }
    }

    private class OpenAIEmbeddingRequest
    {
        [JsonPropertyName("input")]
        public string Input { get; set; } = string.Empty;
    }

    private class OpenAIEmbeddingResponse
    {
        [JsonPropertyName("data")]
        public List<OpenAIEmbeddingData>? Data { get; set; }
    }

    private class OpenAIEmbeddingData
    {
        [JsonPropertyName("embedding")]
        public float[]? Embedding { get; set; }
    }
}
