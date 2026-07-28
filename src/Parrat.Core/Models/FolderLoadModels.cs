using Parrat.Core.Services;

namespace Parrat.Core.Models;

/// <summary>A file found in a scanned folder, with the format detected from its content.</summary>
public record FolderFileEntry(string FilePath, DetectedFileFormat Format)
{
    public string FileName => Path.GetFileName(FilePath);
}

/// <summary>A file that could not be loaded, with the reason it was left out.</summary>
public record FolderFileFailure(string FilePath, string Reason)
{
    public string FileName => Path.GetFileName(FilePath);
}

/// <summary>
/// The result of scanning a folder for loadable files. Files PARRAT cannot open
/// are reported in <see cref="SkippedFiles"/> rather than dropped silently, so a
/// misnamed or malformed report never disappears from a QA pass unnoticed.
/// </summary>
public class FolderScanResult
{
    public string FolderPath { get; init; } = string.Empty;

    /// <summary>Loadable files, grouped by detected format and sorted by file name.</summary>
    public Dictionary<DetectedFileFormat, List<FolderFileEntry>> FilesByFormat { get; init; } = new();

    /// <summary>Files in the folder that are not a supported record format.</summary>
    public List<FolderFileEntry> SkippedFiles { get; init; } = new();

    /// <summary>Formats present in the folder, in a stable display order.</summary>
    public IReadOnlyList<DetectedFileFormat> AvailableFormats =>
        FilesByFormat.Where(kvp => kvp.Value.Count > 0)
            .Select(kvp => kvp.Key)
            .OrderBy(f => (int)f)
            .ToList();

    public bool HasLoadableFiles => AvailableFormats.Count > 0;

    public List<FolderFileEntry> FilesOfFormat(DetectedFileFormat format) =>
        FilesByFormat.TryGetValue(format, out var files) ? files : new List<FolderFileEntry>();
}

/// <summary>
/// The merged result of loading several NAACCR XML files. Unlike HL7 and ePath,
/// which merge as flat record lists, XML files merge into one document so the
/// rest of the application sees exactly what it sees for a single file.
/// </summary>
public class XmlFolderLoadResult
{
    public System.Xml.XmlDocument? Document { get; init; }
    public System.Xml.XmlNodeList? Tumors { get; init; }
    public System.Xml.XmlNamespaceManager? NsMgr { get; init; }

    /// <summary>Source file for each tumor, parallel to <see cref="Tumors"/>.</summary>
    public string[] TumorSourceFiles { get; init; } = Array.Empty<string>();

    public List<string> LoadedFiles { get; init; } = new();
    public List<FolderFileFailure> Failures { get; init; } = new();

    /// <summary>
    /// Differences between files that do not prevent the merge but could
    /// mislead — chiefly file-level items that disagree between documents.
    /// </summary>
    public List<string> Warnings { get; init; } = new();

    public int TumorCount => Tumors?.Count ?? 0;
    public int FileCount => LoadedFiles.Count;
}

/// <summary>
/// Records loaded from a set of files, together with any files that failed.
/// Records carry the file they came from so a search hit can be traced back to
/// its original report.
/// </summary>
public class FolderLoadResult<T>
{
    public List<T> Records { get; init; } = new();

    /// <summary>Files that were read successfully and contributed records.</summary>
    public List<string> LoadedFiles { get; init; } = new();

    public List<FolderFileFailure> Failures { get; init; } = new();

    public int FileCount => LoadedFiles.Count;
}
