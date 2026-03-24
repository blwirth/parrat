namespace Parat.Core.Models;

public class ObxSkipConfig
{
    public int Version { get; set; } = 1;
    public List<string> SkipCodes { get; set; } = new();
    public Dictionary<string, string> SkipCodeDescriptions { get; set; } = new();
}
