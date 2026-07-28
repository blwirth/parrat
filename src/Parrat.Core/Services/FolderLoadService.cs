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
    private readonly IParratLogger _logger;

    /// <summary>Formats that can be merged into a single in-memory set.</summary>
    private static readonly DetectedFileFormat[] LoadableFormats =
    {
        DetectedFileFormat.Hl7,
        DetectedFileFormat.EpathDat
    };

    public FolderLoadService(
        IHl7FileService hl7FileService,
        IEpathParserService epathParserService)
        : this(hl7FileService, epathParserService, NullParratLogger.Instance)
    {
    }

    public FolderLoadService(
        IHl7FileService hl7FileService,
        IEpathParserService epathParserService,
        IParratLogger logger)
    {
        _hl7FileService = hl7FileService;
        _epathParserService = epathParserService;
        _logger = logger;
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
