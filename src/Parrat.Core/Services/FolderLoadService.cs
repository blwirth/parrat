using System.Text;
using System.Xml;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

/// <summary>
/// Loads every report in a folder into memory as one navigable set.
///
/// This exists for QA against the original source files. Concatenating a folder
/// to disk just to read it produces a duplicate copy of data that is never
/// touched otherwise, which then has to be remembered and deleted; loading in
/// memory leaves the source folder untouched.
///
/// Only the selected folder is read — subfolders are deliberately not searched.
/// </summary>
public class FolderLoadService : IFolderLoadService
{
    private readonly IHl7FileService _hl7FileService;
    private readonly IEpathParserService _epathParserService;
    private readonly IXmlFileService _xmlFileService;
    private readonly IParratLogger _logger;

    /// <summary>Formats that can be merged into a single in-memory set.</summary>
    private static readonly DetectedFileFormat[] LoadableFormats =
    {
        DetectedFileFormat.Hl7,
        DetectedFileFormat.NaaccrXml,
        DetectedFileFormat.EpathDat
    };

    public FolderLoadService(
        IHl7FileService hl7FileService,
        IEpathParserService epathParserService,
        IXmlFileService xmlFileService)
        : this(hl7FileService, epathParserService, xmlFileService, NullParratLogger.Instance)
    {
    }

    public FolderLoadService(
        IHl7FileService hl7FileService,
        IEpathParserService epathParserService,
        IXmlFileService xmlFileService,
        IParratLogger logger)
    {
        _hl7FileService = hl7FileService;
        _epathParserService = epathParserService;
        _xmlFileService = xmlFileService;
        _logger = logger;
    }

    public long TotalBytes(IEnumerable<string> filePaths)
    {
        long total = 0;

        foreach (var path in filePaths)
        {
            try
            {
                var info = new FileInfo(path);
                if (info.Exists) total += info.Length;
            }
            catch (IOException)
            {
                // A file we cannot stat is one we will fail to load anyway.
            }
        }

        return total;
    }

    public int CountRecords(DetectedFileFormat format, IEnumerable<string> filePaths)
    {
        int total = 0;

        foreach (var path in filePaths)
        {
            try
            {
                total += format switch
                {
                    DetectedFileFormat.NaaccrXml => CountXmlTumors(path),
                    DetectedFileFormat.Hl7 => CountHl7Messages(path),
                    DetectedFileFormat.EpathDat => CountEpathRecords(path),
                    _ => 0
                };
            }
            catch (Exception ex)
            {
                // Counting is for display only. A file that cannot be read is
                // reported properly when the load runs.
                _logger.Log("WARN", $"Could not count records in {path}: {ex.Message}", "FOLDER_COUNT");
            }
        }

        return total;
    }

    /// <summary>
    /// Counts Tumor elements by streaming the document. One patient may carry
    /// several tumors, so patients are not a stand-in for the record count.
    /// </summary>
    private static int CountXmlTumors(string path)
    {
        var settings = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            IgnoreComments = true,
            IgnoreProcessingInstructions = true,
            IgnoreWhitespace = true
        };

        using var reader = XmlReader.Create(path, settings);

        int count = 0;
        while (reader.Read())
        {
            if (reader.NodeType == XmlNodeType.Element &&
                string.Equals(reader.LocalName, "Tumor", StringComparison.Ordinal))
            {
                count++;
            }
        }

        return count;
    }

    /// <summary>Counts message headers, ignoring the batch envelope.</summary>
    private static int CountHl7Messages(string path)
    {
        int count = 0;

        foreach (var line in ReadLines(path, Encoding.ASCII))
        {
            // Trimmed, matching how the parser decides a line starts a message.
            if (line.AsSpan().Trim().StartsWith("MSH|".AsSpan(), StringComparison.Ordinal))
                count++;
        }

        return count;
    }

    /// <summary>Counts ePath records, which are one per non-empty line.</summary>
    private static int CountEpathRecords(string path)
    {
        int count = 0;

        foreach (var line in ReadLines(path, Encoding.UTF8))
        {
            if (line.AsSpan().Trim().Length > 0)
                count++;
        }

        return count;
    }

    private static IEnumerable<string> ReadLines(string path, Encoding encoding)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 64 * 1024);
        using var reader = new StreamReader(stream, encoding, false, 64 * 1024);

        string? line;
        while ((line = reader.ReadLine()) != null)
            yield return line;
    }

    public FolderScanResult ScanFolder(string folderPath)
    {
        if (string.IsNullOrWhiteSpace(folderPath) || !Directory.Exists(folderPath))
            throw new DirectoryNotFoundException($"Folder not found: {folderPath}");

        var filesByFormat = new Dictionary<DetectedFileFormat, List<FolderFileEntry>>();
        var skipped = new List<FolderFileEntry>();

        // TopDirectoryOnly: a folder of reports should not pull in whatever
        // happens to sit in its subfolders.
        var paths = Directory
            .EnumerateFiles(folderPath, "*", SearchOption.TopDirectoryOnly)
            .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase);

        foreach (var path in paths)
        {
            var format = FileFormatDetector.DetectFile(path);
            var entry = new FolderFileEntry(path, format);

            if (LoadableFormats.Contains(format))
            {
                if (!filesByFormat.TryGetValue(format, out var list))
                    filesByFormat[format] = list = new List<FolderFileEntry>();
                list.Add(entry);
            }
            else
            {
                skipped.Add(entry);
            }
        }

        _logger.Log("INFO",
            $"Scanned {folderPath}: " +
            $"{filesByFormat.Sum(kvp => kvp.Value.Count)} loadable, {skipped.Count} skipped",
            "FOLDER_SCAN");

        return new FolderScanResult
        {
            FolderPath = folderPath,
            FilesByFormat = filesByFormat,
            SkippedFiles = skipped
        };
    }

    public FolderLoadResult<Hl7Message> LoadHl7Files(IEnumerable<string> filePaths)
    {
        return LoadFiles(
            filePaths,
            _hl7FileService.LoadHl7File,
            (message, sourceFile, index) =>
            {
                message.SourceFile = sourceFile;
                message.Index = index;
            });
    }

    public FolderLoadResult<EpathRecord> LoadEpathFiles(IEnumerable<string> filePaths)
    {
        return LoadFiles(
            filePaths,
            _epathParserService.ParseDatFile,
            (record, sourceFile, index) =>
            {
                record.SourceFile = sourceFile;
                record.Index = index;
            });
    }

    // ── NAACCR XML ───────────────────────────────────────────────────────

    public XmlFolderLoadResult LoadXmlFiles(IEnumerable<string> filePaths)
    {
        XmlDocument? merged = null;
        XmlElement? mergedRoot = null;
        XmlNamespaceManager? nsMgr = null;
        string? baseFile = null;
        Dictionary<string, string>? baseFileItems = null;

        // Which file each merged Patient element came from. Keyed by node
        // identity, so tumor attribution stays correct no matter how the
        // documents are structured.
        var patientSource = new Dictionary<XmlNode, string>(ReferenceEqualityComparer.Instance);

        var loaded = new List<string>();
        var failures = new List<FolderFileFailure>();
        var warnings = new List<string>();

        foreach (var path in filePaths)
        {
            try
            {
                if (merged == null)
                {
                    // The first usable file becomes the document everything else
                    // merges into, so its header governs the merged result.
                    var (doc, tumors, docNsMgr) = _xmlFileService.LoadNaaccrXml(path);

                    var root = doc.DocumentElement;
                    if (root == null)
                    {
                        failures.Add(new FolderFileFailure(path, "File has no root element."));
                        continue;
                    }

                    if (tumors.Count == 0)
                    {
                        failures.Add(new FolderFileFailure(path, "No tumors found."));
                        continue;
                    }

                    merged = doc;
                    mergedRoot = root;
                    nsMgr = docNsMgr;
                    baseFile = path;
                    baseFileItems = ReadFileLevelItems(root);

                    foreach (var patient in DirectChildElements(root, "Patient"))
                        patientSource[patient] = path;

                    loaded.Add(path);
                    continue;
                }

                var outcome = MergeFileInto(merged, mergedRoot!, baseFile!, baseFileItems!, path, patientSource);

                if (outcome.Failure != null)
                    failures.Add(outcome.Failure);
                else
                    loaded.Add(path);

                warnings.AddRange(outcome.Warnings);
            }
            catch (Exception ex)
            {
                _logger.LogError($"Failed to load {path} during XML folder load", "FOLDER_LOAD_XML", ex);
                failures.Add(new FolderFileFailure(path, ex.Message));
            }
        }

        if (merged == null || nsMgr == null)
            return new XmlFolderLoadResult { Failures = failures, Warnings = warnings };

        var mergedTumors = merged.SelectNodes("//n:Tumor", nsMgr)!;

        _logger.Log("INFO",
            $"Merged {loaded.Count} XML file(s) into {mergedTumors.Count} tumors",
            "FOLDER_LOAD_XML");

        return new XmlFolderLoadResult
        {
            Document = merged,
            Tumors = mergedTumors,
            NsMgr = nsMgr,
            TumorSourceFiles = MapTumorsToFiles(mergedTumors, patientSource),
            LoadedFiles = loaded,
            Failures = failures,
            Warnings = warnings
        };
    }

    /// <summary>Outcome of merging one file: either a failure, or warnings to report.</summary>
    private readonly record struct MergeOutcome(FolderFileFailure? Failure, List<string> Warnings);

    /// <summary>
    /// Streams one file's Patient elements straight into the merged document.
    ///
    /// Reading nodes through the target document builds them as its own nodes,
    /// so no second DOM is constructed and nothing is cloned — which for a
    /// folder of large files is the difference between holding one document and
    /// holding two plus a copy of everything imported so far.
    /// </summary>
    private static MergeOutcome MergeFileInto(
        XmlDocument merged,
        XmlElement mergedRoot,
        string baseFile,
        Dictionary<string, string> baseFileItems,
        string path,
        Dictionary<XmlNode, string> patientSource)
    {
        var warnings = new List<string>();

        var settings = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            IgnoreComments = true,
            IgnoreProcessingInstructions = true,
            // XmlDocument.Load drops insignificant whitespace by default, so the
            // base file carries none. Dropping it here too keeps every merged
            // file consistent — and on pretty-printed exports the whitespace
            // nodes alone are a substantial share of the document.
            IgnoreWhitespace = true
        };

        using var reader = XmlReader.Create(path, settings);

        if (!reader.Read() || reader.MoveToContent() != XmlNodeType.Element ||
            !string.Equals(reader.LocalName, "NaaccrData", StringComparison.Ordinal))
        {
            return new MergeOutcome(
                new FolderFileFailure(path, "Root element is not NaaccrData."), warnings);
        }

        var mismatch = DescribeHeaderMismatch(
            mergedRoot, reader.NamespaceURI,
            reader.GetAttribute("baseDictionaryUri") ?? "",
            reader.GetAttribute("recordType") ?? "",
            baseFile);

        if (mismatch != null)
            return new MergeOutcome(new FolderFileFailure(path, mismatch), warnings);

        if (reader.IsEmptyElement)
            return new MergeOutcome(new FolderFileFailure(path, "No tumors found."), warnings);

        // Patients are appended as they are read; if the file turns out to hold
        // no tumors they are removed again, so a tumourless file leaves nothing
        // behind in the merged document.
        var appended = new List<XmlNode>();
        int tumorCount = 0;

        reader.Read();

        while (!reader.EOF && reader.NodeType != XmlNodeType.EndElement)
        {
            if (reader.NodeType != XmlNodeType.Element)
            {
                reader.Read();
                continue;
            }

            if (string.Equals(reader.LocalName, "Patient", StringComparison.Ordinal))
            {
                // ReadNode consumes the element and advances the reader.
                var node = merged.ReadNode(reader);
                if (node != null)
                {
                    mergedRoot.AppendChild(node);
                    patientSource[node] = path;
                    appended.Add(node);
                    tumorCount += CountDescendantTumors(node);
                }
                continue;
            }

            if (string.Equals(reader.LocalName, "Item", StringComparison.Ordinal))
            {
                // File-level item: the base file's value governs the merged
                // document, so a disagreement is worth reporting.
                var id = reader.GetAttribute("naaccrId");
                var value = reader.IsEmptyElement ? "" : reader.ReadElementContentAsString();
                if (reader.NodeType == XmlNodeType.Element && reader.IsEmptyElement)
                    reader.Read();

                if (!string.IsNullOrEmpty(id) &&
                    baseFileItems.TryGetValue(id, out var baseValue) && baseValue != value)
                {
                    warnings.Add(
                        $"{Path.GetFileName(path)}: file-level item '{id}' is '{value}', " +
                        $"but '{Path.GetFileName(baseFile)}' has '{baseValue}'. The merged view uses '{baseValue}'.");
                }

                continue;
            }

            reader.Skip();
        }

        if (tumorCount == 0)
        {
            foreach (var node in appended)
            {
                mergedRoot.RemoveChild(node);
                patientSource.Remove(node);
            }

            return new MergeOutcome(new FolderFileFailure(path, "No tumors found."), warnings);
        }

        return new MergeOutcome(null, warnings);
    }

    /// <summary>Counts Tumor elements anywhere beneath a Patient element.</summary>
    private static int CountDescendantTumors(XmlNode patient)
    {
        int count = 0;

        for (var child = patient.FirstChild; child != null; child = child.NextSibling)
        {
            if (child.NodeType != XmlNodeType.Element) continue;

            if (string.Equals(child.LocalName, "Tumor", StringComparison.Ordinal))
                count++;
            else
                count += CountDescendantTumors(child);
        }

        return count;
    }

    /// <summary>Resolves each tumor to the file its Patient came from.</summary>
    private static string[] MapTumorsToFiles(XmlNodeList tumors, Dictionary<XmlNode, string> patientSource)
    {
        var sources = new string[tumors.Count];

        for (int i = 0; i < tumors.Count; i++)
        {
            var node = tumors[i]?.ParentNode;
            while (node != null && node.LocalName != "Patient")
                node = node.ParentNode;

            sources[i] = node != null && patientSource.TryGetValue(node, out var file)
                ? file
                : string.Empty;
        }

        return sources;
    }

    /// <summary>
    /// Returns why two NaaccrData roots cannot be merged, or null when they can.
    /// A registry's files must agree on dictionary and record type for their
    /// records to mean the same thing side by side.
    /// </summary>
    private static string? DescribeHeaderMismatch(
        XmlElement baseRoot, string namespaceUri, string dictionaryUri, string recordType, string baseFile)
    {
        var baseName = Path.GetFileName(baseFile);

        if (baseRoot.NamespaceURI != namespaceUri)
            return $"Namespace '{namespaceUri}' does not match '{baseRoot.NamespaceURI}' in {baseName}.";

        var expectedDictionary = baseRoot.GetAttribute("baseDictionaryUri");
        if (expectedDictionary != dictionaryUri)
            return $"baseDictionaryUri '{dictionaryUri}' does not match '{expectedDictionary}' in {baseName}.";

        var expectedRecordType = baseRoot.GetAttribute("recordType");
        if (expectedRecordType != recordType)
            return $"recordType '{recordType}' does not match '{expectedRecordType}' in {baseName}.";

        return null;
    }

    /// <summary>Reads the Items that sit directly on NaaccrData (file-level fields).</summary>
    private static Dictionary<string, string> ReadFileLevelItems(XmlElement root)
    {
        var items = new Dictionary<string, string>(StringComparer.Ordinal);

        foreach (var item in DirectChildElements(root, "Item"))
        {
            var id = ((XmlElement)item).GetAttribute("naaccrId");
            if (id.Length > 0 && !items.ContainsKey(id))
                items[id] = item.InnerText;
        }

        return items;
    }

    /// <summary>Enumerates direct child elements with the given local name.</summary>
    private static List<XmlNode> DirectChildElements(XmlNode parent, string localName)
    {
        var found = new List<XmlNode>();

        for (var child = parent.FirstChild; child != null; child = child.NextSibling)
        {
            if (child.NodeType == XmlNodeType.Element &&
                string.Equals(child.LocalName, localName, StringComparison.Ordinal))
            {
                found.Add(child);
            }
        }

        return found;
    }

    /// <summary>
    /// Loads each file in turn and merges the results. A file that fails to
    /// parse is recorded as a failure and the remaining files are still loaded,
    /// so one bad report cannot cost the whole folder.
    /// </summary>
    private FolderLoadResult<T> LoadFiles<T>(
        IEnumerable<string> filePaths,
        Func<string, List<T>> loadFile,
        Action<T, string, int> stamp)
    {
        var records = new List<T>();
        var loadedFiles = new List<string>();
        var failures = new List<FolderFileFailure>();

        foreach (var path in filePaths)
        {
            try
            {
                var loaded = loadFile(path);

                if (loaded.Count == 0)
                {
                    failures.Add(new FolderFileFailure(path, "No records found."));
                    continue;
                }

                foreach (var record in loaded)
                {
                    stamp(record, path, records.Count);
                    records.Add(record);
                }

                loadedFiles.Add(path);
            }
            catch (Exception ex)
            {
                _logger.LogError($"Failed to load {path} during folder load", "FOLDER_LOAD", ex);
                failures.Add(new FolderFileFailure(path, ex.Message));
            }
        }

        return new FolderLoadResult<T>
        {
            Records = records,
            LoadedFiles = loadedFiles,
            Failures = failures
        };
    }
}
