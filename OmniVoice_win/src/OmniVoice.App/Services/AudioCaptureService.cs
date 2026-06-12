using NAudio.Wave;
using OmniVoice.Core;

namespace OmniVoice.App.Services;

public sealed class AudioCaptureService : IDisposable
{
    private WaveInEvent? _waveIn;
    private readonly List<short> _samples = [];
    private readonly object _lock = new();

    public event Action<float>? OnLevel;
    public event Action<byte[]>? OnPcmChunk;

    public int SampleRate { get; private set; } = 16000;

    public static IReadOnlyList<MicrophoneDevice> ListDevices()
    {
        var devices = new List<MicrophoneDevice> { new("default", "System Default") };
        for (var i = 0; i < WaveInEvent.DeviceCount; i++)
        {
            var caps = WaveInEvent.GetCapabilities(i);
            devices.Add(new(i.ToString(), caps.ProductName));
        }

        return devices;
    }

    public void Start(string? deviceId)
    {
        Stop();
        var deviceNumber = 0;
        if (int.TryParse(deviceId, out var parsed))
            deviceNumber = parsed;

        _waveIn = new WaveInEvent
        {
            DeviceNumber = deviceNumber,
            WaveFormat = new WaveFormat(16000, 1),
            BufferMilliseconds = 50,
        };
        SampleRate = _waveIn.WaveFormat.SampleRate;

        _waveIn.DataAvailable += (_, e) =>
        {
            var floats = new float[e.BytesRecorded / 2];
            var sum = 0f;
            for (var i = 0; i < floats.Length; i++)
            {
                var sample = BitConverter.ToInt16(e.Buffer, i * 2);
                floats[i] = sample / 32768f;
                sum += Math.Abs(floats[i]);
            }

            var chunk = new byte[floats.Length * 4];
            Buffer.BlockCopy(floats, 0, chunk, 0, chunk.Length);

            lock (_lock)
            {
                for (var i = 0; i < floats.Length; i++)
                    _samples.Add(WaveEncoder.FloatToInt16(floats[i]));
            }

            OnLevel?.Invoke(floats.Length == 0 ? 0 : sum / floats.Length);
            OnPcmChunk?.Invoke(chunk);
        };

        _waveIn.StartRecording();
    }

    public byte[] StopWavData()
    {
        _waveIn?.StopRecording();
        _waveIn?.Dispose();
        _waveIn = null;

        short[] captured;
        lock (_lock)
        {
            captured = _samples.ToArray();
            _samples.Clear();
        }

        return WaveEncoder.EncodePcm16(captured, SampleRate);
    }

    public void Stop() => StopWavData();

    public void Dispose() => Stop();
}