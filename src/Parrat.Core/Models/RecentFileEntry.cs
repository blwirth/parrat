namespace Parrat.Core.Models;

public class RecentFileEntry
{
    public string FilePath { get; set; } = string.Empty;

    /// <summary>"xml", "hl7", or "epath". For a folder, the format it was loaded as.</summary>
    public string FileType { get; set; } = string.Empty;

    /// <summary>
    /// True when the entry is a folder loaded as one set rather than a single
    /// file. Absent from entries written before folder loading existed, which
    /// deserialize as false — correct for them.
    /// </summary>
    public bool IsFolder { get; set; }

    public DateTime OpenedAt { get; set; }
}
