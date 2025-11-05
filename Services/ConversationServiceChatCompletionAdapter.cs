using System.Runtime.CompilerServices;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;

namespace azure_sql_sk.Services;

public class ConversationServiceChatCompletionAdapter : IChatCompletionService
{
    private readonly IConversationService _conversationService;

    public ConversationServiceChatCompletionAdapter(IConversationService conversationService)
    {
        _conversationService = conversationService;
    }

    public IReadOnlyDictionary<string, object?> Attributes => new Dictionary<string, object?>();

    public async Task<IReadOnlyList<ChatMessageContent>> GetChatMessageContentsAsync(
        ChatHistory chatHistory,
        PromptExecutionSettings? executionSettings = null,
        Kernel? kernel = null,
        CancellationToken cancellationToken = default)
    {
        var content = await _conversationService.GetChatCompletionAsync(chatHistory, cancellationToken);
        return new List<ChatMessageContent>
        {
            new ChatMessageContent(AuthorRole.Assistant, content)
        };
    }

    public async IAsyncEnumerable<StreamingChatMessageContent> GetStreamingChatMessageContentsAsync(
        ChatHistory chatHistory,
        PromptExecutionSettings? executionSettings = null,
        Kernel? kernel = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (var content in _conversationService.GetStreamingChatCompletionAsync(chatHistory, cancellationToken))
        {
            yield return new StreamingChatMessageContent(AuthorRole.Assistant, content);
        }
    }
}
