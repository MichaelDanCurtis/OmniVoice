namespace OmniVoice.Core;

public static class WaveEncoder
{
    public static byte[] EncodePcm16(IReadOnlyList<short> samples, int sampleRate)
    {
        var dataSize = samples.Count * 2;
        using var stream = new MemoryStream(44 + dataSize);
        using var writer = new BinaryWriter(stream);

        writer.Write(new[] { (byte)'R', (byte)'I', (byte)'F', (byte)'F' });
        writer.Write(36 + dataSize);
        writer.Write(new[] { (byte)'W', (byte)'A', (byte)'V', (byte)'E' });
        writer.Write(new[] { (byte)'f', (byte)'m', (byte)'t', (byte)' ' });
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(sampleRate);
        writer.Write(sampleRate * 2);
        writer.Write((short)2);
        writer.Write((short)16);
        writer.Write(new[] { (byte)'d', (byte)'a', (byte)'t', (byte)'a' });
        writer.Write(dataSize);

        foreach (var sample in samples)
            writer.Write(sample);

        return stream.ToArray();
    }

    public static short FloatToInt16(float value)
    {
        var clipped = Math.Clamp(value, -1f, 1f);
        return clipped == -1f ? short.MinValue : (short)(clipped * short.MaxValue);
    }
}