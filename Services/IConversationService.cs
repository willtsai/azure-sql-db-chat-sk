using Microsoft.SemanticKernel.ChatCompletion;

namespace azure_sql_sk.Services;

public interface IConversationService
{
    Task<string> GetChatCompletionAsync(ChatHistory messages, CancellationToken ct = default);
    IAsyncEnumerable<string> GetStreamingChatCompletionAsync(ChatHistory messages, CancellationToken ct = default);
    Task<ReadOnlyMemory<float>> GenerateEmbeddingAsync(string text, CancellationToken ct = default);
}
