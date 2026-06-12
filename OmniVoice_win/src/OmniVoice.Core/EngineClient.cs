using System.Net.Http.Json;
using System.Text.Json;

namespace OmniVoice.Core;

public sealed class EngineClient : IDisposable
{
    public sealed class EngineException(string message, int? statusCode = null) : Exception(message)
    {
        public int? StatusCode { get; } = statusCode;
    }

    private readonly HttpClient _http;
    private readonly Uri _baseUri;

    public EngineClient(string baseUrl = "http://127.0.0.1:8765", HttpClient? http = null)
    {
        _baseUri = new Uri(baseUrl.TrimEnd('/') + "/");
        _http = http ?? new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
    }

    public async Task<EngineHealth> HealthAsync(CancellationToken ct = default)
    {
        return await GetAsync<EngineHealth>("health", ct) ?? throw new EngineException("Empty health response");
    }

    public async Task<IReadOnlyList<EngineProviderInfo>> ProvidersAsync(CancellationToken ct = default) =>
        await GetAsync<List<EngineProviderInfo>>("providers", ct) ?? [];

    public async Task<IReadOnlyList<EngineModelStatus>> ModelsAsync(CancellationToken ct = default) =>
        await GetAsync<List<EngineModelStatus>>("models", ct) ?? [];

    public async Task<IReadOnlyList<EngineTranscriptRecord>> TranscriptsAsync(int limit = 100, CancellationToken ct = default) =>
        await GetAsync<List<EngineTranscriptRecord>>($"api/transcripts?limit={limit}", ct) ?? [];

    public async Task<CleanupResult> CleanupAsync(CleanupRequest request, CancellationToken ct = default) =>
        await PostAsync<CleanupResult>("cleanup", request, ct)
        ?? throw new EngineException("Empty cleanup response");

    public async Task<TranscribeResult> TranscribeAsync(byte[] audio, AsrProviderKind provider, CancellationToken ct = default)
    {
        using var content = new ByteArrayContent(audio);
        using var response = await _http.PostAsync(
            new Uri(_baseUri, $"transcribe?provider={Uri.EscapeDataString(provider.WireValue())}"),
            content,
            ct);
        return await ReadResponseAsync<TranscribeResult>(response, ct)
               ?? throw new EngineException("Empty transcribe response");
    }

    public async Task<AiHandoffResult> AiHandoffAsync(AiHandoffRequest request, CancellationToken ct = default) =>
        await PostAsync<AiHandoffResult>("api/ai/handoff", request, ct)
        ?? throw new EngineException("Empty AI handoff response");

    public async Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct = default) =>
        await PostAsync<TranslationResult>("api/translate", request, ct)
        ?? throw new EngineException("Empty translation response");

    public async Task<EngineModelUpdateInfo> CheckModelUpdateAsync(AsrProviderKind provider, CancellationToken ct = default) =>
        await GetAsync<EngineModelUpdateInfo>($"models/{provider.WireValue()}/update", ct)
        ?? throw new EngineException("Empty model update response");

    public async Task<EngineModelDownloadStatus> DownloadModelAsync(AsrProviderKind provider, CancellationToken ct = default) =>
        await PostAsync<EngineModelDownloadStatus>($"models/{provider.WireValue()}/download", new { }, ct)
        ?? throw new EngineException("Empty download response");

    public async Task<EngineModelDownloadStatus> ModelDownloadStatusAsync(AsrProviderKind provider, CancellationToken ct = default) =>
        await GetAsync<EngineModelDownloadStatus>($"models/{provider.WireValue()}/download", ct)
        ?? throw new EngineException("Empty download status response");

    private async Task<T?> GetAsync<T>(string relativePath, CancellationToken ct)
    {
        using var response = await _http.GetAsync(new Uri(_baseUri, relativePath), ct);
        return await ReadResponseAsync<T>(response, ct);
    }

    private async Task<T?> PostAsync<T>(string relativePath, object body, CancellationToken ct)
    {
        using var response = await _http.PostAsJsonAsync(new Uri(_baseUri, relativePath), body, JsonOptions.Engine, ct);
        return await ReadResponseAsync<T>(response, ct);
    }

    private static async Task<T?> ReadResponseAsync<T>(HttpResponseMessage response, CancellationToken ct)
    {
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
        {
            string? detail = null;
            try
            {
                using var doc = JsonDocument.Parse(body);
                if (doc.RootElement.TryGetProperty("detail", out var detailProp))
                    detail = detailProp.GetString();
            }
            catch
            {
                detail = body.Trim();
            }

            throw new EngineException(
                detail is { Length: > 0 } ? $"Engine returned {(int)response.StatusCode}: {detail}" : $"Engine returned {(int)response.StatusCode}",
                (int)response.StatusCode);
        }

        return string.IsNullOrWhiteSpace(body)
            ? default
            : JsonSerializer.Deserialize<T>(body, JsonOptions.Engine);
    }

    public void Dispose() => _http.Dispose();
}