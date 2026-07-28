using System.Data;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Parrat.UI.Forms;

namespace Parrat.UI.Services;

/// <summary>
/// Handles file-related operations: Open, Open Recent, Open Containing Folder,
/// Search, and Restart. Ported from PS1 button-handler scripts.
/// </summary>
public class FileHandlers
{
    private readonly AppState _state;
    private readonly IXmlFileService _xmlFileService;
    private readonly IHl7FileService _hl7FileService;
    private readonly IRecentFilesService _recentFilesService;
    private readonly IParratLogger _logger;
    private readonly NavigationService _navigationService;
    private readonly MenuBuilder _menuBuilder;
    private readonly IGridSettingsService _gridSettingsService;
    private readonly IEpathParserService _epathParserService;
    private readonly IFolderLoadService _folderLoadService;
    private readonly IFilterService _filterService;
    private readonly INaaccrDictionary _naaccrDictionary;

    private System.Windows.Forms.Timer? _searchTimer;

    public FileHandlers(
        AppState state,
        IXmlFileService xmlFileService,
        IHl7FileService hl7FileService,
        IRecentFilesService recentFilesService,
        IParratLogger logger,
        NavigationService navigationService,
        MenuBuilder menuBuilder,
        IGridSettingsService gridSettingsService,
        IEpathParserService epathParserService,
        IFolderLoadService folderLoadService,
        IFilterService filterService,
        INaaccrDictionary naaccrDictionary)
    {
        _folderLoadService = folderLoadService;
        _filterService = filterService;
        _naaccrDictionary = naaccrDictionary;
        _state = state;
        _xmlFileService = xmlFileService;
        _hl7FileService = hl7FileService;
        _recentFilesService = recentFilesService;
        _logger = logger;
        _navigationService = navigationService;
        _menuBuilder = menuBuilder;
        _gridSettingsService = gridSettingsService;
        _epathParserService = epathParserService;
    }

    // ── Open File ────────────────────────────────────────────────────────

    /// <summary>
    /// Shows an OpenFileDialog and loads the selected XML or HL7 file.
    /// Ported from Get-BtnOpenHandler / Import-XmlFile / Import-Hl7File in btnOpen.ps1.
    /// </summary>
    public void HandleOpen(MainForm form)
    {
        using var ofd = new OpenFileDialog
        {
            Filter = "NAACCR/HL7/ePath Files (*.xml;*.hl7;*.txt;*.dat)|*.xml;*.hl7;*.txt;*.dat|NAACCR XML (*.xml)|*.xml|HL7 Files (*.hl7;*.txt)|*.hl7;*.txt|ePath Flat Files (*.dat)|*.dat|All files (*.*)|*.*",
            Title = "Select NAACCR XML, HL7, or ePath file"
        };

        var lastDir = _recentFilesService.GetLastOpenedDirectory();
        if (lastDir != null)
            ofd.InitialDirectory = lastDir;

        if (ofd.ShowDialog() == DialogResult.OK)
        {
            OpenFile(ofd.FileName, form);
        }
    }

    /// <summary>
    /// Opens a file by path (used by both Open and Open Recent).
    /// Routing is driven by file content, not extension: HL7 path reports
    /// frequently arrive as .txt, and .txt is also used for raw pathology
    /// narrative, so the extension alone cannot tell them apart.
    /// </summary>
    public void OpenFile(string filePath, MainForm form)
    {
        if (!File.Exists(filePath))
        {
            MessageBox.Show($"File not found: {filePath}", "File Not Found",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        switch (FileFormatDetector.DetectFile(filePath))
        {
            case DetectedFileFormat.Hl7:
                ImportHl7File(filePath, form);
                break;

            case DetectedFileFormat.NaaccrXml:
                ImportXmlFile(filePath, form);
                break;

            case DetectedFileFormat.EpathDat:
                ImportEpathFile(filePath, form);
                break;

            case DetectedFileFormat.PlainText:
                _logger.Log("INFO", $"Declined to open plain-text file {Path.GetFileName(filePath)}", "OPEN_FILE");
                MessageBox.Show(
                    "This file is readable text but does not contain HL7 messages, " +
                    "NAACCR XML, or ePath records.\n\n" +
                    "If it is a raw pathology report, use File → Convert .txt to .hl7 first.",
                    "Unsupported File", MessageBoxButtons.OK, MessageBoxIcon.Information);
                break;

            default:
                // Content was inconclusive — fall back to the extension so the
                // format-specific validator can report exactly what is wrong.
                OpenByExtension(filePath, form);
                break;
        }
    }

    /// <summary>Fallback routing when content detection is inconclusive.</summary>
    private void OpenByExtension(string filePath, MainForm form)
    {
        var extension = Path.GetExtension(filePath).ToLowerInvariant();

        if (extension is ".hl7" or ".txt")
            ImportHl7File(filePath, form);
        else if (extension == ".dat")
            ImportEpathFile(filePath, form);
        else
            ImportXmlFile(filePath, form);
    }

    // ── Open Folder ──────────────────────────────────────────────────────

    /// <summary>
    /// Loads every report in a chosen folder as one navigable set, without
    /// writing a concatenated file to disk. Only the selected folder is read;
    /// subfolders are deliberately not searched.
    /// </summary>
    public void HandleOpenFolder(MainForm form)
    {
        using var fbd = new FolderBrowserDialog
        {
            Description = "Select a folder of reports to load (subfolders are not searched)",
            UseDescriptionForTitle = true,
            ShowNewFolderButton = false
        };

        var lastDir = _recentFilesService.GetLastOpenedDirectory();
        if (lastDir != null)
            fbd.SelectedPath = lastDir;

        if (fbd.ShowDialog() != DialogResult.OK)
            return;

        OpenFolder(fbd.SelectedPath, form);
    }

    /// <summary>Loads a folder by path. Separated from the dialog for reuse and testing.</summary>
    /// <param name="preferredFormat">
    /// Format to preselect in the chooser, used when reopening from Open Recent.
    /// </param>
    public void OpenFolder(string folderPath, MainForm form, DetectedFileFormat? preferredFormat = null)
    {
        try
        {
            var scan = _folderLoadService.ScanFolder(folderPath);

            if (!scan.HasLoadableFiles)
            {
                MessageBox.Show(
                    $"No NAACCR XML, HL7, or ePath reports found directly in:\n\n{folderPath}\n\n" +
                    $"{PluralHelper.Count(scan.SkippedFiles.Count, "file")} in this folder are not a supported record format. " +
                    "Subfolders are not searched.",
                    "Nothing to Load", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var format = ChooseFormat(scan, form, preferredFormat);
            if (format == null)
                return;

            var paths = scan.FilesOfFormat(format.Value).Select(f => f.FilePath).ToList();

            if (!ConfirmLoadSize(paths, format.Value))
                return;

            var folderName = Path.GetFileName(folderPath.TrimEnd(Path.DirectorySeparatorChar,
                Path.AltDirectorySeparatorChar));
            if (string.IsNullOrEmpty(folderName))
                folderName = folderPath;

            // Set folder state before populating the view: the grid adds its
            // source file column based on it.
            _state.CurrentFilePath = null;
            _state.LoadedFolderPath = folderPath;
            _state.TumorSourceFiles = null;

            // A folder of thousands of records takes seconds to read; without
            // this the window simply looks frozen.
            var previousCursor = form.Cursor;
            form.Cursor = Cursors.WaitCursor;
            form.SetStatusText($"Loading {PluralHelper.Count(paths.Count, "file")} from {folderName}...");
            Application.DoEvents();

            try
            {
                switch (format.Value)
                {
                    case DetectedFileFormat.Hl7:
                    {
                        var result = _folderLoadService.LoadHl7Files(paths);
                        if (!EnsureRecordsLoaded(result.Records.Count, result.Failures, folderPath, form))
                            return;

                        _logger.Log("INFO",
                            $"Loaded folder {folderPath}: {result.Records.Count} messages from {PluralHelper.Count(result.FileCount, "file")}",
                            "OPEN_FOLDER");

                        _recentFilesService.AddRecentFolder(
                            folderPath, FileFormatDetector.DescribeShortType(format.Value));

                        ShowHl7Messages(result.Records, form,
                            $"Loaded folder: {folderName} ({result.FileCount} files, Messages: {result.Records.Count})",
                            $"Folder: {folderPath}");

                        ReportLoadIssues(result.Failures, scan, null);
                        break;
                    }

                    case DetectedFileFormat.NaaccrXml:
                    {
                        var result = _folderLoadService.LoadXmlFiles(paths);
                        if (!EnsureRecordsLoaded(result.TumorCount, result.Failures, folderPath, form))
                            return;

                        _logger.Log("INFO",
                            $"Loaded folder {folderPath}: {result.TumorCount} tumors from {PluralHelper.Count(result.FileCount, "file")}",
                            "OPEN_FOLDER");

                        _state.TumorSourceFiles = result.TumorSourceFiles;

                        _recentFilesService.AddRecentFolder(
                            folderPath, FileFormatDetector.DescribeShortType(format.Value));

                        ShowXmlTumors(result.Document!, result.Tumors!, result.NsMgr!, form,
                            $"Loaded folder: {folderName} ({result.FileCount} files, Tumors: {result.TumorCount})",
                            $"Folder: {folderPath}");

                        ReportLoadIssues(result.Failures, scan, result.Warnings);
                        break;
                    }

                    default:
                    {
                        var result = _folderLoadService.LoadEpathFiles(paths);
                        if (!EnsureRecordsLoaded(result.Records.Count, result.Failures, folderPath, form))
                            return;

                        _logger.Log("INFO",
                            $"Loaded folder {folderPath}: {result.Records.Count} ePath records from {PluralHelper.Count(result.FileCount, "file")}",
                            "OPEN_FOLDER");

                        _recentFilesService.AddRecentFolder(
                            folderPath, FileFormatDetector.DescribeShortType(format.Value));

                        ShowEpathRecords(result.Records, form,
                            $"Loaded folder: {folderName} ({result.FileCount} files, Records: {result.Records.Count})",
                            $"Folder: {folderPath}");

                        ReportLoadIssues(result.Failures, scan, null);
                        break;
                    }
                }
            }
            finally
            {
                form.Cursor = previousCursor;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError($"Failed to load folder {folderPath}", "OPEN_FOLDER", ex);
            MessageBox.Show($"Error loading folder: {ex.Message}", "Error");
        }
    }

    /// <summary>
    /// Bytes of source data above which a folder load is worth confirming.
    /// Parsed records occupy several times their file size in memory, so a
    /// folder this large is where a load starts to be felt.
    /// </summary>
    private const long LargeLoadBytes = 500L * 1024 * 1024;

    /// <summary>
    /// Warns before loading a very large folder, since everything is held in
    /// memory at once. Returns false if the user backs out.
    /// </summary>
    private bool ConfirmLoadSize(List<string> paths, DetectedFileFormat format)
    {
        var bytes = _folderLoadService.TotalBytes(paths);
        if (bytes < LargeLoadBytes)
            return true;

        var megabytes = bytes / (1024 * 1024);

        var answer = MessageBox.Show(
            $"This folder holds {PluralHelper.Count(paths.Count, $"{FileFormatDetector.DescribeFormat(format)} file")} " +
            $"totalling {megabytes:N0} MB.\n\n" +
            "Folder loads are held entirely in memory, and parsed records take several times " +
            "their file size. This may take a while and use several gigabytes.\n\n" +
            "Load anyway?",
            "Large Folder", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);

        if (answer != DialogResult.Yes)
            _logger.Log("INFO", $"User declined folder load of {megabytes} MB", "OPEN_FOLDER");

        return answer == DialogResult.Yes;
    }

    /// <summary>
    /// Picks which format to load. A folder holding more than one record format
    /// cannot be merged into a single view, so the user chooses.
    /// </summary>
    private DetectedFileFormat? ChooseFormat(
        FolderScanResult scan, MainForm form, DetectedFileFormat? preferredFormat)
    {
        var formats = scan.AvailableFormats;
        if (formats.Count == 1)
            return formats[0];

        // Counting streams each file, so it is far cheaper than loading — but
        // not free, and it only happens when there is actually a choice to make.
        var recordCounts = new Dictionary<DetectedFileFormat, int>();

        var previousCursor = form.Cursor;
        form.Cursor = Cursors.WaitCursor;
        form.SetStatusText("Counting records...");
        Application.DoEvents();

        try
        {
            foreach (var format in formats)
            {
                recordCounts[format] = _folderLoadService.CountRecords(
                    format, scan.FilesOfFormat(format).Select(f => f.FilePath));
            }
        }
        finally
        {
            form.Cursor = previousCursor;
        }

        using var chooser = new FolderFormatChooserForm(scan, recordCounts, preferredFormat);
        return chooser.ShowDialog() == DialogResult.OK ? chooser.SelectedFormat : null;
    }

    /// <summary>
    /// Reports the case where every candidate file failed and restores the
    /// non-folder state so the app is not left claiming a folder is open.
    /// </summary>
    private bool EnsureRecordsLoaded(
        int recordCount, List<FolderFileFailure> failures, string folderPath, MainForm form)
    {
        if (recordCount > 0)
            return true;

        _state.LoadedFolderPath = null;
        _state.TumorSourceFiles = null;

        var detail = failures.Count > 0
            ? "\n\n" + string.Join("\n", failures.Take(10).Select(f => $"  • {f.FileName}: {f.Reason}"))
            : "";

        MessageBox.Show(
            $"No records could be read from the reports in:\n\n{folderPath}{detail}",
            "Nothing Loaded", MessageBoxButtons.OK, MessageBoxIcon.Warning);

        ClearRecordView(form, "No records loaded", $"Folder: {folderPath}");
        return false;
    }

    /// <summary>
    /// Surfaces files that were left out of the load. Skipped and failed files
    /// are always reported — a report silently missing from a QA pass is worse
    /// than an extra dialog.
    /// </summary>
    private static void ReportLoadIssues(
        List<FolderFileFailure> failures, FolderScanResult scan, List<string>? warnings)
    {
        warnings ??= new List<string>();

        if (failures.Count == 0 && scan.SkippedFiles.Count == 0 && warnings.Count == 0)
            return;

        var lines = new List<string>();

        if (failures.Count > 0)
        {
            lines.Add($"{PluralHelper.Count(failures.Count, "file")} could not be read:");
            lines.AddRange(failures.Take(10).Select(f => $"  • {f.FileName}: {f.Reason}"));
            if (failures.Count > 10)
                lines.Add($"  ... and {failures.Count - 10} more.");
        }

        if (scan.SkippedFiles.Count > 0)
        {
            if (lines.Count > 0) lines.Add("");
            lines.Add($"{PluralHelper.Count(scan.SkippedFiles.Count, "file")} were not loaded:");
            lines.AddRange(scan.SkippedFiles.Take(10).Select(f =>
                $"  • {f.FileName} ({FileFormatDetector.DescribeFormat(f.Format)})"));
            if (scan.SkippedFiles.Count > 10)
                lines.Add($"  ... and {scan.SkippedFiles.Count - 10} more.");
        }

        if (warnings.Count > 0)
        {
            if (lines.Count > 0) lines.Add("");
            lines.Add("The merged files disagree on file-level values:");
            lines.AddRange(warnings.Take(10).Select(w => $"  • {w}"));
            if (warnings.Count > 10)
                lines.Add($"  ... and {warnings.Count - 10} more.");
        }

        MessageBox.Show(string.Join("\n", lines), "Files Not Loaded",
            MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    // ── Import XML ───────────────────────────────────────────────────────

    private void ImportXmlFile(string filePath, MainForm form)
    {
        try
        {
            var validation = FileFormatValidator.ValidateNaaccrXmlFile(filePath);
            if (!validation.IsValid)
            {
                MessageBox.Show($"This file does not appear to be a valid NAACCR XML file:\n\n{validation.Summary}",
                    "Invalid File Format", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (validation.Warnings.Count > 0)
                ShowValidationWarnings("NAACCR XML", validation);

            var (doc, tumors, nsMgr) = _xmlFileService.LoadNaaccrXml(filePath);

            if (tumors.Count == 0)
            {
                _state.XmlDoc = doc;
                _state.Tumors = tumors;
                _state.NsMgr = nsMgr;
                _state.CurrentFilePath = filePath;
                _state.LoadedFolderPath = null;
                _state.FileType = "xml";
                _state.CurrentIndex = -1;
                _state.Hl7Messages.Clear();
                _menuBuilder.UpdateMenuStatesForFileType("xml");

                MessageBox.Show("No <Tumor> elements found in this file.", "No Tumors");
                ClearRecordView(form, "No tumors found", $"File: {filePath}");
                return;
            }

            _state.CurrentFilePath = filePath;
            _state.LoadedFolderPath = null;

            var fileName = Path.GetFileName(filePath);
            _logger.Log("INFO", $"Loaded {fileName} with {tumors.Count} tumors", "OPEN_FILE");
            _recentFilesService.AddRecentFile(filePath, "xml");

            ShowXmlTumors(doc, tumors, nsMgr, form,
                $"Loaded: {fileName} (Tumors: {tumors.Count})",
                $"File: {filePath}");
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load XML file", "OPEN_FILE", ex);
            MessageBox.Show($"Error loading XML: {ex.Message}", "Error");
        }
    }

    /// <summary>
    /// Populates state, grid and search index from a NAACCR document.
    /// Shared by single-file and folder loads; for a folder load the caller has
    /// already set <see cref="AppState.TumorSourceFiles"/>.
    /// </summary>
    private void ShowXmlTumors(
        XmlDocument doc, XmlNodeList tumors, XmlNamespaceManager nsMgr,
        MainForm form, string statusText, string fileNameText)
    {
        _state.XmlDoc = doc;
        _state.Tumors = tumors;
        _state.NsMgr = nsMgr;
        _state.FileType = "xml";
        _state.CurrentIndex = -1;

        // Clear other data
        _state.Hl7Messages.Clear();
        _state.EpathRecords.Clear();

        _menuBuilder.UpdateMenuStatesForFileType("xml");

        form.SetStatusText(statusText);
        form.SetFileNameText(fileNameText);

        // Build navigation table using grid settings
        var gridSettings = _gridSettingsService.Load();
        var xmlCols = gridSettings.Xml.Columns;

        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        AddSourceFileColumn(table);
        foreach (var col in xmlCols)
            table.Columns.Add(col.Id, typeof(string));
        NavMatchHelper.AddMatchColumn(table);

        // One pass over each element's children per record, rather than an
        // XPath lookup per cell — the difference is roughly tenfold once a
        // file holds thousands of tumors.
        var itemReader = new NaaccrItemReader(xmlCols.Select(c => c.Id));
        var values = new Dictionary<string, string>(xmlCols.Count, StringComparer.Ordinal);
        var sourceFiles = _state.TumorSourceFiles;

        table.BeginLoadData();
        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;

            values.Clear();
            itemReader.ReadInto(tumor, values);
            if (values.Count < xmlCols.Count)
                itemReader.ReadInto(_xmlFileService.GetPatientForTumor(tumor), values);

            var row = table.NewRow();
            row["Selected"] = false;
            row["Index"] = i + 1;
            if (_state.IsFolderLoad)
            {
                row[SourceFileColumn] = sourceFiles != null && i < sourceFiles.Length
                    ? Path.GetFileName(sourceFiles[i])
                    : "";
            }
            foreach (var col in xmlCols)
                row[col.Id] = values.TryGetValue(col.Id, out var val) ? val : "";

            table.Rows.Add(row);
        }
        table.EndLoadData();

        _state.NavTable = table;

        // Temporarily disable event handling while loading data
        _state.IsLoadingData = true;
        form.GridNav.DataSource = null;
        form.GridNav.Columns.Clear();
        form.GridNav.DataSource = table;

        ConfigureGridColumns(form.GridNav, xmlCols);

        _state.IsLoadingData = false;

        _navigationService.ShowTumor(0);

        // Build search index, including the source file name for folder loads so
        // typing a file name filters the view down to that report's tumors.
        var searchService = new SearchService(_logger, tumors, nsMgr);
        var searchIndex = searchService.BuildSearchIndex("xml");

        if (_state.IsFolderLoad && sourceFiles != null)
        {
            for (int i = 0; i < searchIndex.Length && i < sourceFiles.Length; i++)
                searchIndex[i] = $"{searchIndex[i]} {Path.GetFileName(sourceFiles[i]).ToLower()}";
        }

        _state.SearchIndex = searchIndex;

        form.PnlSearch.Visible = true;
        form.TxtSearch.Text = "";
        form.LblSearchCount.Text = "";
        ResetRecordFilter(form);
        form.UpdateTitle();
    }

    // ── Import HL7 ───────────────────────────────────────────────────────

    private void ImportHl7File(string filePath, MainForm form)
    {
        try
        {
            var validation = FileFormatValidator.ValidateHl7File(filePath);
            if (!validation.IsValid)
            {
                MessageBox.Show($"This file does not appear to be a valid HL7 file:\n\n{validation.Summary}",
                    "Invalid File Format", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (validation.Warnings.Count > 0)
                ShowValidationWarnings("HL7", validation);

            var messages = _hl7FileService.LoadHl7File(filePath);

            if (messages.Count == 0)
            {
                MessageBox.Show("No HL7 messages found in this file.", "No Messages");
                ClearRecordView(form, "No messages found", $"File: {filePath}");
                return;
            }

            _state.CurrentFilePath = filePath;
            _state.LoadedFolderPath = null;

            var fileName = Path.GetFileName(filePath);
            _logger.Log("INFO", $"Loaded {fileName} with {messages.Count} messages", "OPEN_FILE");
            _recentFilesService.AddRecentFile(filePath, "hl7");

            ShowHl7Messages(messages, form,
                $"Loaded: {fileName} (Messages: {messages.Count})",
                $"File: {filePath}");
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load HL7 file", "OPEN_FILE", ex);
            MessageBox.Show($"Error loading HL7: {ex.Message}", "Error");
        }
    }

    /// <summary>
    /// Populates state, grid and search index from a set of HL7 messages.
    /// Shared by single-file and folder loads; the caller has already set the
    /// path state that determines which of the two this is.
    /// </summary>
    private void ShowHl7Messages(List<Hl7Message> messages, MainForm form, string statusText, string fileNameText)
    {
        _state.Hl7Messages = messages;
        _state.FileType = "hl7";
        _state.CurrentIndex = -1;

        // Clear XML data
        _state.XmlDoc = null;
        _state.Tumors = null;
        _state.NsMgr = null;
        _state.EpathRecords.Clear();

        _menuBuilder.UpdateMenuStatesForFileType("hl7");

        form.SetStatusText(statusText);
        form.SetFileNameText(fileNameText);

        // Build navigation table for HL7 (fixed columns, widths from settings)
        var gridSettings = _gridSettingsService.Load();

        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        AddSourceFileColumn(table);
        table.Columns.Add("nameLast", typeof(string));
        table.Columns.Add("nameFirst", typeof(string));
        table.Columns.Add("dateOfBirth", typeof(string));
        table.Columns.Add("accessionNumber", typeof(string));
        table.Columns.Add("patientId", typeof(string));
        table.Columns.Add("messageType", typeof(string));
        table.Columns.Add("orderDateTime", typeof(string));
        NavMatchHelper.AddMatchColumn(table);

        table.BeginLoadData();
        foreach (var msg in messages)
        {
            var row = table.NewRow();
            row["Selected"] = false;
            row["Index"] = msg.Index + 1;
            if (_state.IsFolderLoad)
                row[SourceFileColumn] = Path.GetFileName(msg.SourceFile);
            row["nameLast"] = msg.PatientLastName;
            row["nameFirst"] = msg.PatientFirstName;
            row["dateOfBirth"] = msg.DateOfBirth;
            row["accessionNumber"] = msg.AccessionNumber;
            row["patientId"] = msg.PatientId;
            row["messageType"] = msg.MessageType;
            row["orderDateTime"] = msg.OrderDateTime;

            table.Rows.Add(row);
        }
        table.EndLoadData();

        _state.NavTable = table;

        // Temporarily disable event handling while loading data
        _state.IsLoadingData = true;
        form.GridNav.DataSource = null;
        form.GridNav.Columns.Clear();
        form.GridNav.DataSource = table;

        ConfigureGridColumns(form.GridNav, gridSettings.Hl7.Columns);

        _state.IsLoadingData = false;

        // Select first row and show first message
        if (form.GridNav.Rows.Count > 0)
        {
            form.GridNav.Rows[0].Selected = true;
            form.GridNav.CurrentCell = form.GridNav.Rows[0].Cells[0];
        }
        _navigationService.ShowHl7Message(0);

        // Build search index
        var searchService = new SearchService(_logger, null, null, messages);
        _state.SearchIndex = searchService.BuildSearchIndex("hl7");

        form.PnlSearch.Visible = true;
        form.TxtSearch.Text = "";
        form.LblSearchCount.Text = "";
        ResetRecordFilter(form);
        form.UpdateTitle();
    }

    // ── Import ePath (.dat) ─────────────────────────────────────────────

    private void ImportEpathFile(string filePath, MainForm form)
    {
        try
        {
            var validation = FileFormatValidator.ValidateEpathDatFile(filePath);
            if (!validation.IsValid)
            {
                MessageBox.Show($"This file does not appear to be a valid ePath .dat file:\n\n{validation.Summary}",
                    "Invalid File Format", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (validation.Warnings.Count > 0)
                ShowValidationWarnings("ePath .dat", validation);

            var records = _epathParserService.ParseDatFile(filePath);

            if (records.Count == 0)
            {
                MessageBox.Show("No ePath records found in this file.", "No Records");
                ClearRecordView(form, "No records found", $"File: {filePath}");
                return;
            }

            _state.CurrentFilePath = filePath;
            _state.LoadedFolderPath = null;

            var fileName = Path.GetFileName(filePath);
            var version = records[0].FormatVersion;

            _logger.Log("INFO", $"Loaded {fileName} with {records.Count} ePath records ({version})", "OPEN_FILE");
            _recentFilesService.AddRecentFile(filePath, "epath");

            ShowEpathRecords(records, form,
                $"Loaded: {fileName} (ePath {version}, Records: {records.Count})",
                $"File: {filePath}");
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load ePath file", "OPEN_FILE", ex);
            MessageBox.Show($"Error loading ePath file: {ex.Message}", "Error");
        }
    }

    /// <summary>
    /// Populates state, grid and search index from a set of ePath records.
    /// Shared by single-file and folder loads.
    /// </summary>
    private void ShowEpathRecords(List<EpathRecord> records, MainForm form, string statusText, string fileNameText)
    {
        _state.EpathRecords = records;
        _state.FileType = "epath";
        _state.CurrentIndex = -1;

        // Clear other data
        _state.XmlDoc = null;
        _state.Tumors = null;
        _state.NsMgr = null;
        _state.Hl7Messages.Clear();

        _menuBuilder.UpdateMenuStatesForFileType("epath");

        form.SetStatusText(statusText);
        form.SetFileNameText(fileNameText);

        // Build navigation table
        var gridSettings = _gridSettingsService.Load();

        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        AddSourceFileColumn(table);
        table.Columns.Add("nameLast", typeof(string));
        table.Columns.Add("nameFirst", typeof(string));
        table.Columns.Add("dateOfBirth", typeof(string));
        table.Columns.Add("pathReportNumber", typeof(string));
        table.Columns.Add("patientId", typeof(string));
        table.Columns.Add("sendingFacility", typeof(string));
        table.Columns.Add("formatVersion", typeof(string));
        NavMatchHelper.AddMatchColumn(table);

        table.BeginLoadData();
        foreach (var rec in records)
        {
            var row = table.NewRow();
            row["Selected"] = false;
            row["Index"] = rec.Index + 1;
            if (_state.IsFolderLoad)
                row[SourceFileColumn] = Path.GetFileName(rec.SourceFile);
            row["nameLast"] = rec.PatientLastName;
            row["nameFirst"] = rec.PatientFirstName;
            row["dateOfBirth"] = rec.DateOfBirth;
            row["pathReportNumber"] = rec.PathReportNumber;
            row["patientId"] = rec.PatientId;
            row["sendingFacility"] = rec.SendingFacility;
            row["formatVersion"] = rec.FormatVersion;

            table.Rows.Add(row);
        }
        table.EndLoadData();

        _state.NavTable = table;

        _state.IsLoadingData = true;
        form.GridNav.DataSource = null;
        form.GridNav.Columns.Clear();
        form.GridNav.DataSource = table;

        ConfigureGridColumns(form.GridNav, gridSettings.Hl7.Columns);

        _state.IsLoadingData = false;

        if (form.GridNav.Rows.Count > 0)
        {
            form.GridNav.Rows[0].Selected = true;
            form.GridNav.CurrentCell = form.GridNav.Rows[0].Cells[0];
        }
        _navigationService.ShowEpathRecord(0);

        // Build search index from display fields, plus the source file name so a
        // folder load can be filtered down to one report.
        var searchEntries = records.Select(r =>
            string.Join(" ", r.DisplayFields.Select(f => f.Value)
                .Append(Path.GetFileName(r.SourceFile)))).ToArray();
        _state.SearchIndex = searchEntries;

        form.PnlSearch.Visible = true;
        form.TxtSearch.Text = "";
        form.LblSearchCount.Text = "";
        ResetRecordFilter(form);
        form.UpdateTitle();
    }

    // ── Shared view helpers ─────────────────────────────────────────────

    /// <summary>Grid column showing which file a record came from during a folder load.</summary>
    internal const string SourceFileColumn = "sourceFile";

    /// <summary>
    /// Adds the source file column, but only for folder loads — for a single
    /// file it would repeat the same value on every row.
    /// </summary>
    private void AddSourceFileColumn(DataTable table)
    {
        if (_state.IsFolderLoad)
            table.Columns.Add(SourceFileColumn, typeof(string));
    }

    /// <summary>Resets the record panels when a load produced nothing to show.</summary>
    private void ClearRecordView(MainForm form, string statusText, string fileNameText)
    {
        ResetRecordFilter(form);
        form.SetStatusText(statusText);
        form.SetFileNameText(fileNameText);
        form.RtbPath.Clear();
        form.RtbItems.Clear();
        form.GridNav.DataSource = null;
        form.BtnPrev.Enabled = false;
        form.BtnNext.Enabled = false;
        form.LblIndex.Text = "";
        form.PnlSearch.Visible = false;
        form.HideFilterBanner();
        form.UpdateTitle();
    }

    // ── Validation warnings ────────────────────────────────────────────

    private static void ShowValidationWarnings(string fileType, FileFormatValidator.ValidationResult validation)
    {
        var warningText = string.Join("\n", validation.Warnings.Select(w => $"  \u2022 {w}"));
        MessageBox.Show($"File loaded with warnings ({fileType}):\n\n{warningText}",
            "Validation Warnings", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    // ── Grid column configuration ────────────────────────────────────────

    internal static void ConfigureGridColumns(DataGridView grid, List<GridColumnDef> columnDefs)
    {
        if (grid.Columns.Count == 0) return;

        // Allow user resizing
        grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;

        // Build a lookup for saved widths
        var widthLookup = new Dictionary<string, int>();
        for (int i = 0; i < columnDefs.Count; i++)
            widthLookup[columnDefs[i].Id] = columnDefs[i].Width;

        foreach (DataGridViewColumn col in grid.Columns)
        {
            if (col.Name == "Selected")
            {
                col.ReadOnly = false;
                col.Width = 60;
                col.DisplayIndex = 0;
                col.Resizable = DataGridViewTriState.False;
                col.SortMode = DataGridViewColumnSortMode.NotSortable;
            }
            else if (col.Name == NavMatchHelper.MatchColumn)
            {
                // Bookkeeping for the search box and the record filter; the row
                // filter reads it, the user never should.
                col.Visible = false;
            }
            else if (col.Name == "Index")
            {
                col.ReadOnly = true;
                col.DisplayIndex = grid.Columns.Contains("Selected") ? 1 : 0;
                col.Width = 55;
                col.Resizable = DataGridViewTriState.False;
                col.SortMode = DataGridViewColumnSortMode.Automatic;
            }
            else
            {
                col.ReadOnly = true;
                col.SortMode = DataGridViewColumnSortMode.Automatic;
                col.Resizable = DataGridViewTriState.True;

                // Apply saved width, or auto-fit once then allow manual resize
                if (widthLookup.TryGetValue(col.Name, out var w) && w > 0)
                {
                    col.Width = w;
                }
                else
                {
                    // Auto-size to content, then switch back so user can drag
                    col.AutoSizeMode = DataGridViewAutoSizeColumnMode.AllCells;
                    int fitted = col.Width;
                    col.AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
                    col.Width = fitted;
                }
            }
        }
    }

    // ── Grid settings persistence ───────────────────────────────────────

    /// <summary>
    /// Saves the current grid column widths to settings.
    /// Called on column resize events.
    /// </summary>
    public void SaveGridColumnWidths(DataGridView grid)
    {
        var fileType = _state.FileType;
        if (string.IsNullOrEmpty(fileType)) return;

        var settings = _gridSettingsService.Load();
        var config = fileType == "xml" ? settings.Xml : settings.Hl7;

        foreach (var colDef in config.Columns)
        {
            if (grid.Columns.Contains(colDef.Id))
                colDef.Width = grid.Columns[colDef.Id]!.Width;
        }

        _gridSettingsService.Save(settings);
    }

    /// <summary>Provides access to the grid settings service for dialogs.</summary>
    public IGridSettingsService GridSettingsService => _gridSettingsService;

    // ── Open Recent ──────────────────────────────────────────────────────

    /// <summary>
    /// Populates the Open Recent submenu with entries from IRecentFilesService.
    /// Ported from btnOpenRecent.ps1.
    /// </summary>
    public void PopulateOpenRecentMenu(ToolStripMenuItem mnuOpenRecent, MainForm form)
    {
        mnuOpenRecent.DropDownItems.Clear();

        var recentFiles = _recentFilesService.GetRecentFiles();

        if (recentFiles.Count == 0)
        {
            var emptyItem = new ToolStripMenuItem("(No recent items)") { Enabled = false };
            mnuOpenRecent.DropDownItems.Add(emptyItem);
            return;
        }

        foreach (var entry in recentFiles)
        {
            // A folder path has no extension to hint at what it is, so say so.
            var displayName = DisplayNameFor(entry.FilePath);
            if (entry.IsFolder)
                displayName += "  (folder)";

            var item = new ToolStripMenuItem(displayName)
            {
                ToolTipText = entry.FilePath
            };

            var capturedPath = entry.FilePath;
            var capturedIsFolder = entry.IsFolder;
            var capturedFormat = FileFormatDetector.ParseShortType(entry.FileType);

            item.Click += (s, e) =>
            {
                if (capturedIsFolder)
                {
                    if (Directory.Exists(capturedPath))
                    {
                        // The format recorded last time preselects the chooser;
                        // the folder is rescanned, so its contents may have moved on.
                        OpenFolder(capturedPath, form,
                            capturedFormat == DetectedFileFormat.Unknown ? null : capturedFormat);
                    }
                    else
                    {
                        MessageBox.Show($"Folder not found: {capturedPath}", "Folder Not Found",
                            MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }

                    return;
                }

                if (File.Exists(capturedPath))
                {
                    OpenFile(capturedPath, form);
                }
                else
                {
                    MessageBox.Show($"File not found: {capturedPath}", "File Not Found",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            };

            mnuOpenRecent.DropDownItems.Add(item);
        }

        mnuOpenRecent.DropDownItems.Add(new ToolStripSeparator());

        var clearItem = new ToolStripMenuItem("Clear Recent Items");
        clearItem.Click += (s, e) =>
        {
            _recentFilesService.ClearRecentFiles();
        };
        mnuOpenRecent.DropDownItems.Add(clearItem);
    }

    /// <summary>
    /// The name to show for a recent entry. Falls back to the full path for a
    /// drive root, which has no name of its own.
    /// </summary>
    private static string DisplayNameFor(string path)
    {
        var name = Path.GetFileName(path);
        return string.IsNullOrEmpty(name) ? path : name;
    }

    // ── Open Containing Folder ───────────────────────────────────────────

    /// <summary>
    /// Opens the file explorer to the directory of the currently loaded file.
    /// Ported from btnOpenContainingFolder.ps1.
    /// </summary>
    public void HandleOpenContainingFolder()
    {
        // During a folder load there is no single current file, so open the
        // folder that was loaded.
        var dir = _state.IsFolderLoad
            ? _state.LoadedFolderPath
            : string.IsNullOrEmpty(_state.CurrentFilePath)
                ? null
                : Path.GetDirectoryName(_state.CurrentFilePath);

        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return;

        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                Process.Start("explorer.exe", dir);
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                Process.Start("open", dir);
            }
            else
            {
                Process.Start("xdg-open", dir);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to open containing folder", "OPEN_FOLDER", ex);
            MessageBox.Show($"Error opening folder: {ex.Message}", "Error");
        }
    }

    // ── Search ───────────────────────────────────────────────────────────

    /// <summary>
    /// Handles search text changes with a 200ms debounce timer.
    /// Ported from Get-SearchTextChangedHandler in btnSearch.ps1.
    /// </summary>
    public void HandleSearchTextChanged(MainForm form)
    {
        if (_searchTimer == null)
        {
            _searchTimer = new System.Windows.Forms.Timer { Interval = 200 };
            _searchTimer.Tick += (s, e) =>
            {
                try
                {
                    _searchTimer.Stop();

                    var searchText = form.TxtSearch.Text;
                    var navTable = _state.NavTable;
                    var searchIndex = _state.SearchIndex;

                    if (navTable == null) return;

                    var searchService = new SearchService(_logger);

                    // The record filter stays in force while the user types: the
                    // grid shows what satisfies both, not whichever was applied last.
                    ApplyNavFilters(form, searchService.GetMatchingIndices(searchText, searchIndex));

                    // Re-highlight current record panels
                    searchService.HighlightMatches(form.RtbPath, searchText);
                    searchService.HighlightMatches(form.RtbItems, searchText);
                }
                catch (Exception ex)
                {
                    _logger.LogError("Search filter failed", "SEARCH", ex);
                }
            };
        }

        // Reset timer on each keystroke
        _searchTimer.Stop();
        _searchTimer.Start();
    }

    /// <summary>
    /// Clears the search text and filter. Ported from Get-SearchClearHandler in btnSearch.ps1.
    /// </summary>
    public void HandleSearchClear(MainForm form)
    {
        form.TxtSearch.Text = "";
    }

    // ── Record filter ────────────────────────────────────────────────────

    /// <summary>
    /// Builds a field source for the loaded records, covering the fields the
    /// filter refers to. Returns null for a file type the filter does not
    /// support, or when nothing is loaded.
    /// </summary>
    public IFilterFieldSource? CreateFilterFieldSource(FilterDefinition? filter)
    {
        var fields = _filterService.GetReferencedFields(filter);

        return _state.FileType switch
        {
            "xml" => new XmlFilterFieldSource(_state.Tumors, fields, ResolveNaaccrLevel),
            "hl7" => new Hl7FilterFieldSource(_state.Hl7Messages),
            _ => null
        };
    }

    /// <summary>
    /// The element a NAACCR item lives under, so a filter on a patient- or
    /// file-level field resolves correctly from a tumor row.
    /// </summary>
    private string ResolveNaaccrLevel(string fieldId) => _naaccrDictionary.GetParentElement(fieldId);

    /// <summary>
    /// Runs a filter over the loaded records and narrows the grid to what
    /// survives it and the search box together. A null or empty filter clears
    /// the filter and leaves the search box alone.
    /// </summary>
    public void ApplyRecordFilter(MainForm form, FilterDefinition? filter)
    {
        try
        {
            if (filter == null || filter.IsEmpty)
            {
                _state.ActiveFilter = null;
                _state.FilterMatches = null;
            }
            else
            {
                var source = CreateFilterFieldSource(filter);
                if (source == null)
                {
                    _logger.Log("WARN", $"Record filter not supported for file type '{_state.FileType}'", "FILTER");
                    return;
                }

                _state.ActiveFilter = filter;
                _state.FilterMatches = _filterService.GetMatchingIndices(filter, source);
            }

            RefreshNavFilters(form);
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to apply record filter", "FILTER", ex);
            MessageBox.Show($"Error applying filter: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Drops the active filter, leaving the search box untouched.</summary>
    public void ClearRecordFilter(MainForm form) => ApplyRecordFilter(form, null);

    /// <summary>
    /// Drops the filter as part of a load. Filters name fields, and the fields
    /// of the file just closed may not exist in the one just opened — carrying
    /// one over would silently hide records for a reason the user cannot see.
    /// </summary>
    private void ResetRecordFilter(MainForm form)
    {
        _state.ActiveFilter = null;
        _state.FilterMatches = null;
        _menuBuilder.MnuClearFilter.Enabled = false;
        form.HideFilterBanner();
    }

    /// <summary>
    /// Re-narrows the grid using the current search text and the active filter.
    /// </summary>
    public void RefreshNavFilters(MainForm form)
    {
        var searchService = new SearchService(_logger);
        ApplyNavFilters(form, searchService.GetMatchingIndices(form.TxtSearch.Text, _state.SearchIndex));
    }

    /// <summary>
    /// The single place the nav grid is narrowed. Both constraints are applied
    /// together — a record has to satisfy the search box and the filter — and
    /// the labels that report what is showing are refreshed from the result.
    /// </summary>
    private void ApplyNavFilters(MainForm form, int[]? searchMatches)
    {
        var navTable = _state.NavTable;
        if (navTable == null) return;

        NavMatchHelper.Apply(navTable, searchMatches, _state.FilterMatches);

        int visible = navTable.DefaultView.Count;
        int total = _state.RecordCount;

        form.LblSearchCount.Text = searchMatches == null ? "" : $"{visible} / {total}";
        _menuBuilder.MnuClearFilter.Enabled = _state.HasActiveFilter;
        form.UpdateFilterBanner(visible, total);
        _navigationService.UpdateIndexLabel();
    }

    // ── Restart Application ──────────────────────────────────────────────

    /// <summary>
    /// Restarts the application. Launches a new process and exits.
    /// When running via dotnet run, re-invokes dotnet run so source changes are recompiled.
    /// When running as a published exe, re-launches the executable directly.
    /// </summary>
    public void HandleRestart()
    {
        try
        {
            _logger.Log("INFO", "Application restart requested", "RESTART");

            var exePath = Environment.ProcessPath ?? Application.ExecutablePath;
            var projectDir = FindProjectDir(exePath);

            if (projectDir != null)
            {
                // Running via dotnet run — re-invoke so changes are recompiled
                var startInfo = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "dotnet",
                    Arguments = $"run --project \"{projectDir}\"",
                    UseShellExecute = false
                };
                System.Diagnostics.Process.Start(startInfo);
            }
            else
            {
                // Published exe — restart directly
                System.Diagnostics.Process.Start(exePath);
            }

            Application.Exit();
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to restart application", "RESTART", ex);
            MessageBox.Show($"Error restarting: {ex.Message}", "Error");
        }
    }

    /// <summary>
    /// Detects if we're running from a bin/Debug or bin/Release build output directory.
    /// If so, walks up to find the project directory containing the .csproj.
    /// Returns null for published/standalone executables not under a bin/ output path.
    /// </summary>
    private static string? FindProjectDir(string exePath)
    {
        // dotnet run builds to e.g. src/Parrat.UI/bin/Debug/net8.0-windows/win-x64/Parrat.UI.exe
        // Only match if the path contains a bin/Debug or bin/Release segment
        var normalized = exePath.Replace('\\', '/');
        if (!normalized.Contains("/bin/Debug/") && !normalized.Contains("/bin/Release/"))
            return null;

        var dir = Path.GetDirectoryName(exePath);
        while (dir != null)
        {
            if (Path.GetFileName(dir) == "bin")
            {
                // The parent of bin/ is the project directory
                var projectDir = Path.GetDirectoryName(dir);
                if (projectDir != null && Directory.GetFiles(projectDir, "*.csproj").Length > 0)
                    return projectDir;
                return null;
            }
            dir = Path.GetDirectoryName(dir);
        }
        return null;
    }
}
