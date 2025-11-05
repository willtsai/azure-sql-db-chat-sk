using System.Runtime.CompilerServices;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel.ChatCompletion;

namespace azure_sql_sk.Services;

public class SemanticKernelConversationService : IConversationService
{
    private readonly IChatCompletionService _chatService;
    private readonly IEmbeddingGenerator<string, Embedding<float>> _embeddingGenerator;
    private readonly ILogger<SemanticKernelConversationService> _logger;

    public SemanticKernelConversationService(
        IChatCompletionService chatService,
        IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
        ILogger<SemanticKernelConversationService> logger)
    {
        _chatService = chatService;
        _embeddingGenerator = embeddingGenerator;
        _logger = logger;
    }

    public async Task<string> GetChatCompletionAsync(ChatHistory messages, CancellationToken ct = default)
    {
        _logger.LogDebug("Using Semantic Kernel for chat completion");
        var response = await _chatService.GetChatMessageContentAsync(messages, cancellationToken: ct);
        return response.Content ?? string.Empty;
    }

    public async IAsyncEnumerable<string> GetStreamingChatCompletionAsync(
        ChatHistory messages,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        _logger.LogDebug("Using Semantic Kernel for streaming chat completion");
        
        await foreach (var chunk in _chatService.GetStreamingChatMessageContentsAsync(messages, cancellationToken: ct))
        {
            if (!string.IsNullOrEmpty(chunk.Content))
            {
                yield return chunk.Content;
            }
        }
    }

    public async Task<ReadOnlyMemory<float>> GenerateEmbeddingAsync(string text, CancellationToken ct = default)
    {
        _logger.LogDebug("Using Semantic Kernel for embedding generation");
        var result = await _embeddingGenerator.GenerateAsync(new[] { text }, cancellationToken: ct);
        return result.First().Vector;
    }
}
