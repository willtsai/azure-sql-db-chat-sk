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
        _logger.LogDebug($"Calling Dapr component '{ChatComponentName}' for chat completion");

        var request = new OpenAIRequest
        {
            Messages = messages.Select(m => new OpenAIMessage
            {
                Role = m.Role.ToString().ToLowerInvariant(),
                Content = m.Content ?? string.Empty
            }).ToList(),
            Stream = false
        };

        var response = await _httpClient.PostAsJsonAsync(
            $"{_daprHttpEndpoint}/v1.0/invoke/{ChatComponentName}/method/v1/chat/completions",
            request,
            ct);

        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<OpenAIResponse>(ct);
        return result?.Choices?[0]?.Message?.Content ?? string.Empty;
    }

    public async IAsyncEnumerable<string> GetStreamingChatCompletionAsync(
        ChatHistory messages,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        _logger.LogDebug($"Calling Dapr component '{ChatComponentName}' for streaming chat completion");

        var request = new OpenAIRequest
        {
            Messages = messages.Select(m => new OpenAIMessage
            {
                Role = m.Role.ToString().ToLowerInvariant(),
                Content = m.Content ?? string.Empty
            }).ToList(),
            Stream = true
        };

        var response = await _httpClient.PostAsJsonAsync(
            $"{_daprHttpEndpoint}/v1.0/invoke/{ChatComponentName}/method/v1/chat/completions",
            request,
            ct);

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

                OpenAIStreamChunk? chunk = null;
                try
                {
                    chunk = JsonSerializer.Deserialize<OpenAIStreamChunk>(data);
                }
                catch (JsonException ex)
                {
                    _logger.LogWarning(ex, $"Failed to parse SSE chunk: {data}");
                    continue;
                }

                var content = chunk?.Choices?[0]?.Delta?.Content;
                if (!string.IsNullOrEmpty(content))
                {
                    yield return content;
                }
            }
        }
    }

    public async Task<ReadOnlyMemory<float>> GenerateEmbeddingAsync(string text, CancellationToken ct = default)
    {
        _logger.LogDebug($"Calling Dapr component '{EmbeddingComponentName}' for embedding generation");

        var request = new OpenAIEmbeddingRequest
        {
            Input = text
        };

        var response = await _httpClient.PostAsJsonAsync(
            $"{_daprHttpEndpoint}/v1.0/invoke/{EmbeddingComponentName}/method/v1/embeddings",
            request,
            ct);

        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<OpenAIEmbeddingResponse>(ct);
        var embedding = result?.Data?[0]?.Embedding ?? Array.Empty<float>();
        return new ReadOnlyMemory<float>(embedding);
    }

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
