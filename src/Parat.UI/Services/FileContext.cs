using System.Data;
using System.Xml;
using Parat.Core.Models;

namespace Parat.UI.Services;

/// <summary>
/// Isolated per-file state container for the reference panel.
/// Holds all data needed to display a file read-only, with NO export
/// capability, NO "Selected" column concept, and NO reference to AppState.
/// </summary>
public class FileContext
{
    // File data
    public XmlDocument? XmlDoc { get; set; }
    public XmlNodeList? Tumors { get; set; }
    public XmlNamespaceManager? NsMgr { get; set; }
    public List<Hl7Message> Hl7Messages { get; set; } = new();
    public string? CurrentFilePath { get; set; }
    public string? FileType { get; set; }

    // Navigation state
    public int CurrentIndex { get; set; } = -1;
    public DataTable? NavTable { get; set; }
    public string[] SearchIndex { get; set; } = Array.Empty<string>();

    // UI flags (local to this context)
    public bool IsLoadingData { get; set; }
    public bool IsShowingRecord { get; set; }

    public int RecordCount => FileType switch
    {
        "xml" => Tumors?.Count ?? 0,
        "hl7" => Hl7Messages.Count,
        _ => 0
    };

    public void Reset()
    {
        XmlDoc = null;
        Tumors = null;
        NsMgr = null;
        Hl7Messages.Clear();
        CurrentFilePath = null;
        FileType = null;
        CurrentIndex = -1;
        NavTable = null;
        SearchIndex = Array.Empty<string>();
        IsLoadingData = false;
        IsShowingRecord = false;
    }
}
