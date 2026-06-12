using System.Text.Json;
using System.Text.Json.Serialization;

namespace OmniVoice.Core;

public static class JsonOptions
{
    public static JsonSerializerOptions Engine { get; } = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) },
    };
}