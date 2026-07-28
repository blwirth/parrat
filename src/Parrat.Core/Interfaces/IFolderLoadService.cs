using Parrat.Core.Models;
using Parrat.Core.Services;

namespace Parrat.Core.Interfaces;

/// <summary>
/// Loads every report in a folder into memory as a single navigable set, so a
/// folder can be reviewed without first writing a concatenated file to disk.
/// </summary>
public interface IFolderLoadService
{
    /// <summary>
    /// Lists the loadable files directly inside a folder. Subfolders are not
    /// searched.
    /// </summary>
    FolderScanResult ScanFolder(string folderPath);

    /// <summary>
    /// Loads HL7 messages from the given files into one list, stamping each
    /// message with its source file and renumbering indexes across the set.
    /// </summary>
    FolderLoadResult<Hl7Message> LoadHl7Files(IEnumerable<string> filePaths);

    /// <summary>
    /// Loads ePath records from the given files into one list, stamping each
    /// record with its source file and renumbering indexes across the set.
    /// </summary>
    FolderLoadResult<EpathRecord> LoadEpathFiles(IEnumerable<string> filePaths);

    /// <summary>
    /// Merges NAACCR XML files into a single in-memory document, recording
    /// which file each tumor came from. Files whose headers are incompatible
    /// with the first loaded file are reported as failures rather than merged.
    /// </summary>
    XmlFolderLoadResult LoadXmlFiles(IEnumerable<string> filePaths);

    /// <summary>Total size in bytes of the given files, for load-size warnings.</summary>
    long TotalBytes(IEnumerable<string> filePaths);

    /// <summary>
    /// Counts the records the given files would contribute — tumors for NAACCR
    /// XML, messages for HL7, records for ePath — without parsing them into
    /// objects. Files that cannot be read contribute nothing; they are reported
    /// when the load itself is attempted.
    /// </summary>
    int CountRecords(DetectedFileFormat format, IEnumerable<string> filePaths);
}
