using Microsoft.Extensions.AI;

namespace azure_sql_sk.Services;

public class ConversationServiceEmbeddingGenerator : IEmbeddingGenerator<string, Embedding<float>>
{
    private readonly IConversationService _conversationService;

    public ConversationServiceEmbeddingGenerator(IConversationService conversationService)
    {
        _conversationService = conversationService;
    }

    public EmbeddingGeneratorMetadata Metadata => new("conversation-service-embeddings");

    public async Task<GeneratedEmbeddings<Embedding<float>>> GenerateAsync(
        IEnumerable<string> values,
        EmbeddingGenerationOptions? options = null,
        CancellationToken cancellationToken = default)
    {
        var embeddings = new List<Embedding<float>>();
        
        foreach (var value in values)
        {
            var vector = await _conversationService.GenerateEmbeddingAsync(value, cancellationToken);
            embeddings.Add(new Embedding<float>(vector));
        }

        return new GeneratedEmbeddings<Embedding<float>>(embeddings);
    }

    public object? GetService(Type serviceType, object? serviceKey = null) => null;

    public void Dispose() { }
}
