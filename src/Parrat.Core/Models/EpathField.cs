using System.Text.Json.Serialization;

namespace Parrat.Core.Models;

public class EpathField
{
    [JsonPropertyName("pos")]
    public int Position { get; set; }

    [JsonPropertyName("item")]
    public int ItemNumber { get; set; }

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("maxLen")]
    public int MaxLength { get; set; }

    [JsonPropertyName("hl7")]
    public string? Hl7Target { get; set; }
}
