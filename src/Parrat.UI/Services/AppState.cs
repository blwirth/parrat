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
    public List<EpathRecord> EpathRecords { get; set; } = new();
    public string? CurrentFilePath { get; set; }
    public string? FileType { get; set; } // "xml", "hl7", or "epath"

    /// <summary>
    /// Folder whose reports are currently loaded as one set, or null when a
    /// single file is open. CurrentFilePath is null during a folder load, since
    /// the records come from many files and no single file can be written back.
    /// </summary>
    public string? LoadedFolderPath { get; set; }

    /// <summary>True when records were loaded from a folder rather than one file.</summary>
    public bool IsFolderLoad => !string.IsNullOrEmpty(LoadedFolderPath);

    /// <summary>
    /// Source file for each tumor during an XML folder load, parallel to
    /// <see cref="Tumors"/>. HL7 and ePath records carry their source on the
    /// record itself; XML nodes have nowhere to put it without altering the
    /// document, so it is tracked alongside.
    /// </summary>
    public string[]? TumorSourceFiles { get; set; }

    // Navigation state
    public int CurrentIndex { get; set; } = -1;
    public DataTable? NavTable { get; set; }
    public string[] SearchIndex { get; set; } = Array.Empty<string>();

    /// <summary>
    /// The record filter in force, or null when none is applied. Cleared on
    /// every load: its field ids belong to the file it was built against.
    /// </summary>
    public FilterDefinition? ActiveFilter { get; set; }

    /// <summary>
    /// 0-based indices of the records the active filter matched, or null when
    /// no filter is applied. Cached so retyping in the search box re-intersects
    /// rather than re-scanning every record.
    /// </summary>
    public int[]? FilterMatches { get; set; }

    /// <summary>
    /// How many records existed when <see cref="FilterMatches"/> was captured.
    ///
    /// The matches are positions, not identities. Should the loaded records
    /// ever change underneath them, those positions would quietly point at
    /// different records than the ones the filter actually matched. Today every
    /// operation that alters the record set saves and reopens the file, which
    /// clears the filter, so this cannot happen — recording the count makes
    /// that a checked assumption rather than a lucky one.
    /// </summary>
    public int FilterMatchesRecordCount { get; set; }

    /// <summary>True when a filter is narrowing the record list.</summary>
    public bool HasActiveFilter => ActiveFilter is { IsEmpty: false };

    /// <summary>
    /// True when the filter was applied against a record set that no longer
    /// matches the one loaded, which makes its cached matches meaningless.
    /// </summary>
    public bool IsFilterStale =>
        HasActiveFilter && FilterMatchesRecordCount != RecordCount;

    /// <summary>How many records survive the filter; the full count when none is applied.</summary>
    public int FilteredRecordCount => FilterMatches?.Length ?? RecordCount;

    // UI flags
    public bool IsLoadingData { get; set; }
    public bool IsShowingTumor { get; set; }
    public bool SpaceBatchToggling { get; set; }

    public int RecordCount => FileType switch
    {
        "xml" => Tumors?.Count ?? 0,
        "hl7" => Hl7Messages.Count,
        "epath" => EpathRecords.Count,
        _ => 0
    };

    public void Reset()
    {
        XmlDoc = null;
        Tumors = null;
        NsMgr = null;
        Hl7Messages.Clear();
        EpathRecords.Clear();
        CurrentFilePath = null;
        LoadedFolderPath = null;
        TumorSourceFiles = null;
        FileType = null;
        CurrentIndex = -1;
        NavTable = null;
        SearchIndex = Array.Empty<string>();
        ActiveFilter = null;
        FilterMatches = null;
        FilterMatchesRecordCount = 0;
        IsLoadingData = false;
        IsShowingTumor = false;
        SpaceBatchToggling = false;
    }
}
