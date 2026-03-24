namespace Parat.Core.Models;

public class RecentFileEntry
{
    public string FilePath { get; set; } = string.Empty;
    public string FileType { get; set; } = string.Empty; // "xml" or "hl7"
    public DateTime OpenedAt { get; set; }
}
