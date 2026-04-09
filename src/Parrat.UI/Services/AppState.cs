using System.Data;
using System.Xml;
using Parrat.Core.Models;

namespace Parrat.UI.Services;

public class AppState
{
    // File state
    public XmlDocument? XmlDoc { get; set; }
    public XmlNodeList? Tumors { get; set; }
    public XmlNamespaceManager? NsMgr { get; set; }
    public List<Hl7Message> Hl7Messages { get; set; } = new();
    public string? CurrentFilePath { get; set; }
    public string? FileType { get; set; } // "xml" or "hl7"
    public string? SourceFormat { get; set; } // "xml", "hl7", or "epath" — tracks original file format

    // Navigation state
    public int CurrentIndex { get; set; } = -1;
    public DataTable? NavTable { get; set; }
    public string[] SearchIndex { get; set; } = Array.Empty<string>();

    // UI flags
    public bool IsLoadingData { get; set; }
    public bool IsShowingTumor { get; set; }
    public bool SpaceBatchToggling { get; set; }

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
        SourceFormat = null;
        CurrentIndex = -1;
        NavTable = null;
        SearchIndex = Array.Empty<string>();
        IsLoadingData = false;
        IsShowingTumor = false;
        SpaceBatchToggling = false;
    }
}
