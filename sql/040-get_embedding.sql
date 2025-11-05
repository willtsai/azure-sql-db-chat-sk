create or alter procedure [dbo].[get_embedding]
@inputText nvarchar(max),
@embedding vector(1536) output
as
begin try
    declare @retval int;
    declare @response nvarchar(max);
    
    -- Build payload based on provider type
    -- Azure OpenAI uses 'input', OpenAI-compatible may use 'input' or 'inputs'
    declare @payload nvarchar(max) = json_object('input': @inputText);
    
    -- For OpenAI-compatible endpoints (llama.cpp, Ollama), add model parameter
    $(if IS_AZURE_OPENAI = 0)
    set @payload = json_modify(@payload, '$.model', '$CONNECTION_AIEMBEDDING_MODEL$');
    $(endif)
    
    -- Call appropriate endpoint with or without credential
    $(if IS_AZURE_OPENAI = 1 or CONNECTION_AIEMBEDDING_APIKEY != '')
    -- Azure OpenAI or authenticated OpenAI-compatible
    exec @retval = sp_invoke_external_rest_endpoint
        @url = '$CONNECTION_AIEMBEDDING_URL$',
        @method = 'POST',
        @credential = [$CONNECTION_AIEMBEDDING_ENDPOINT$],
        @payload = @payload,
        @response = @response output;
    $(else)
    -- Unauthenticated OpenAI-compatible (local llama.cpp)
    exec @retval = sp_invoke_external_rest_endpoint
        @url = '$CONNECTION_AIEMBEDDING_URL$',
        @method = 'POST',
        @payload = @payload,
        @response = @response output;
    $(endif)
end try
begin catch
    select 
        'SQL' as error_source, 
        error_number() as error_code,
        error_message() as error_message
    return;
end catch

if (@retval != 0) begin
    select 
        'API' as error_source, 
        json_value(@response, '$.result.error.code') as error_code,
        json_value(@response, '$.result.error.message') as error_message,
        @response as error_response
    return;
end;

-- Extract embedding from response
-- Both Azure OpenAI and OpenAI-compatible use same response format: data[0].embedding
declare @re nvarchar(max) = json_query(@response, '$.result.data[0].embedding')
set @embedding = cast(@re as vector(1536));

return @retval
go