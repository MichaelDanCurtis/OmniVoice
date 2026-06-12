using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace OmniVoice.Core;

public sealed class EngineStreamingClient : IAsyncDisposable
{
    private readonly Uri _baseUri;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private ClientWebSocket? _socket;
    private CancellationTokenSource? _receiveCts;
    private EngineStreamingDiagnostics _diagnostics = EngineStreamingDiagnostics.Idle;

    public event Action<TranscriptUpdate>? OnUpdate;
    public event Action<EngineStreamingDiagnostics>? OnDiagnostics;

    public EngineStreamingClient(string baseUrl = "ws://127.0.0.1:8765")
    {
        _baseUri = new Uri(baseUrl.TrimEnd('/') + "/");
    }

    public async Task ConnectAsync(AsrProviderKind provider, int sampleRate, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            await CloseInternalAsync();
            UpdateDiagnostics(d => d with
            {
                State = EngineStreamingConnectionState.Connecting,
                ProviderId = provider.WireValue(),
                SampleRate = sampleRate,
                ChunksSent = 0,
                BytesSent = 0,
                UpdatesReceived = 0,
                PartialsReceived = 0,
                FinalsReceived = 0,
                DroppedChunks = 0,
                DroppedBytes = 0,
                LastText = "",
                LastError = null,
            });

            var query = $"stream?provider={Uri.EscapeDataString(provider.WireValue())}&sample_rate={sampleRate}";
            _socket = new ClientWebSocket();
            await _socket.ConnectAsync(new Uri(_baseUri, query), ct);
            UpdateDiagnostics(d => d with { State = EngineStreamingConnectionState.Open });

            _receiveCts = new CancellationTokenSource();
            _ = Task.Run(() => ReceiveLoopAsync(_receiveCts.Token), CancellationToken.None);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task SendPcmFloat32Async(ReadOnlyMemory<byte> data, CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            if (_socket?.State != WebSocketState.Open)
            {
                UpdateDiagnostics(d => d with
                {
                    DroppedChunks = d.DroppedChunks + 1,
                    DroppedBytes = d.DroppedBytes + data.Length,
                });
                return;
            }

            await _socket.SendAsync(data, WebSocketMessageType.Binary, true, ct);
            UpdateDiagnostics(d => d with
            {
                ChunksSent = d.ChunksSent + 1,
                BytesSent = d.BytesSent + data.Length,
            });
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task FinishAsync(CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            if (_socket?.State != WebSocketState.Open)
            {
                UpdateDiagnostics(d => d with { State = EngineStreamingConnectionState.Closed });
                return;
            }

            UpdateDiagnostics(d => d with { State = EngineStreamingConnectionState.Closing });
            var bytes = Encoding.UTF8.GetBytes("__finish__");
            await _socket.SendAsync(bytes, WebSocketMessageType.Text, true, ct);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task CancelAsync()
    {
        await _gate.WaitAsync();
        try
        {
            await CloseInternalAsync();
            UpdateDiagnostics(d => d with { State = EngineStreamingConnectionState.Cancelled });
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task ReceiveLoopAsync(CancellationToken ct)
    {
        var buffer = new byte[8192];
        var builder = new StringBuilder();

        try
        {
            while (_socket?.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                builder.Clear();
                WebSocketReceiveResult result;
                do
                {
                    result = await _socket.ReceiveAsync(buffer, ct);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        UpdateDiagnostics(d => d with { State = EngineStreamingConnectionState.Closed });
                        return;
                    }

                    builder.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
                } while (!result.EndOfMessage);

                if (!TryDecode(builder.ToString(), out var update)) continue;

                UpdateDiagnostics(d => d with
                {
                    UpdatesReceived = d.UpdatesReceived + 1,
                    PartialsReceived = d.PartialsReceived + (update.IsFinal ? 0 : 1),
                    FinalsReceived = d.FinalsReceived + (update.IsFinal ? 1 : 0),
                    LastText = update.Text,
                });
                OnUpdate?.Invoke(update);

                if (update.IsFinal)
                {
                    UpdateDiagnostics(d => d with { State = EngineStreamingConnectionState.Closed });
                    await CloseInternalAsync();
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            UpdateDiagnostics(d => d with
            {
                State = EngineStreamingConnectionState.Failed,
                LastError = ex.Message,
            });
        }
    }

    private static bool TryDecode(string json, out TranscriptUpdate update)
    {
        update = new TranscriptUpdate("", false);
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (!root.TryGetProperty("type", out var typeProp) ||
                !root.TryGetProperty("text", out var textProp))
                return false;

            var type = typeProp.GetString() ?? "";
            var text = textProp.GetString() ?? "";
            if (type == "error") return false;

            update = new TranscriptUpdate(text, type == "final");
            return true;
        }
        catch
        {
            return false;
        }
    }

    private async Task CloseInternalAsync()
    {
        _receiveCts?.Cancel();
        if (_socket is { State: WebSocketState.Open or WebSocketState.CloseReceived })
        {
            try
            {
                await _socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "done", CancellationToken.None);
            }
            catch
            {
                // ignored
            }
        }

        _socket?.Dispose();
        _socket = null;
        _receiveCts?.Dispose();
        _receiveCts = null;
    }

    private void UpdateDiagnostics(Func<EngineStreamingDiagnostics, EngineStreamingDiagnostics> update)
    {
        _diagnostics = update(_diagnostics);
        OnDiagnostics?.Invoke(_diagnostics);
    }

    public async ValueTask DisposeAsync()
    {
        await _gate.WaitAsync();
        try
        {
            await CloseInternalAsync();
        }
        finally
        {
            _gate.Release();
            _gate.Dispose();
        }
    }
}