using System.Data;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Xml;
using Parat.Core.Interfaces;
using Parat.Core.Models;
using Parat.Core.Services;
using Parat.UI.Forms;

namespace Parat.UI.Services;

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
    private readonly IParatLogger _logger;
    private readonly NavigationService _navigationService;
    private readonly MenuBuilder _menuBuilder;

    private System.Windows.Forms.Timer? _searchTimer;

    public FileHandlers(
        AppState state,
        IXmlFileService xmlFileService,
        IHl7FileService hl7FileService,
        IRecentFilesService recentFilesService,
        IParatLogger logger,
        NavigationService navigationService,
        MenuBuilder menuBuilder)
    {
        _state = state;
        _xmlFileService = xmlFileService;
        _hl7FileService = hl7FileService;
        _recentFilesService = recentFilesService;
        _logger = logger;
        _navigationService = navigationService;
        _menuBuilder = menuBuilder;
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
            Filter = "NAACCR/HL7 Files (*.xml;*.hl7)|*.xml;*.hl7|NAACCR XML (*.xml)|*.xml|HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
            Title = "Select NAACCR XML or HL7 file"
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
    /// </summary>
    public void OpenFile(string filePath, MainForm form)
    {
        var extension = Path.GetExtension(filePath).ToLowerInvariant();

        if (extension == ".hl7")
            ImportHl7File(filePath, form);
        else
            ImportXmlFile(filePath, form);
    }

    // ── Import XML ───────────────────────────────────────────────────────

    private void ImportXmlFile(string filePath, MainForm form)
    {
        try
        {
            var (doc, tumors, nsMgr) = _xmlFileService.LoadNaaccrXml(filePath);

            _state.XmlDoc = doc;
            _state.Tumors = tumors;
            _state.NsMgr = nsMgr;
            _state.CurrentFilePath = filePath;
            _state.FileType = "xml";
            _state.CurrentIndex = -1;

            // Clear HL7 data
            _state.Hl7Messages.Clear();

            _menuBuilder.UpdateMenuStatesForFileType("xml");

            if (tumors.Count == 0)
            {
                MessageBox.Show("No <Tumor> elements found in this file.", "No Tumors");
                form.SetStatusText("No tumors found");
                form.SetFileNameText($"File: {filePath}");
                form.RtbPath.Clear();
                form.RtbItems.Clear();
                form.GridNav.DataSource = null;
                form.BtnPrev.Enabled = false;
                form.BtnNext.Enabled = false;
                form.LblIndex.Text = "";
                form.PnlSearch.Visible = false;
                form.UpdateTitle();
                return;
            }

            var fileName = Path.GetFileName(filePath);
            form.SetStatusText($"Loaded: {fileName} (Tumors: {tumors.Count})");
            form.SetFileNameText($"File: {filePath}");

            _logger.Log("INFO", $"Loaded {fileName} with {tumors.Count} tumors", "OPEN_FILE");
            _recentFilesService.AddRecentFile(filePath, "xml");

            // Build navigation table
            var table = new DataTable();
            table.Columns.Add("Selected", typeof(bool));
            table.Columns.Add("Index", typeof(int));
            table.Columns.Add("nameLast", typeof(string));
            table.Columns.Add("nameFirst", typeof(string));
            table.Columns.Add("dateOfBirth", typeof(string));
            table.Columns.Add("pathReportNumber1", typeof(string));
            table.Columns.Add("primarySite", typeof(string));
            table.Columns.Add("dateOfDiagnosis", typeof(string));

            table.BeginLoadData();
            for (int i = 0; i < tumors.Count; i++)
            {
                var tumor = tumors[i]!;
                var patient = _xmlFileService.GetPatientForTumor(tumor);

                var row = table.NewRow();
                row["Selected"] = false;
                row["Index"] = i + 1;
                row["nameLast"] = patient != null ? _xmlFileService.GetItemValue(patient, "nameLast", nsMgr) : "";
                row["nameFirst"] = patient != null ? _xmlFileService.GetItemValue(patient, "nameFirst", nsMgr) : "";
                row["dateOfBirth"] = patient != null ? _xmlFileService.GetItemValue(patient, "dateOfBirth", nsMgr) : "";
                row["pathReportNumber1"] = _xmlFileService.GetItemValue(tumor, "pathReportNumber1", nsMgr);
                row["primarySite"] = _xmlFileService.GetItemValue(tumor, "primarySite", nsMgr);
                row["dateOfDiagnosis"] = _xmlFileService.GetItemValue(tumor, "dateOfDiagnosis", nsMgr);

                table.Rows.Add(row);
            }
            table.EndLoadData();

            _state.NavTable = table;

            // Temporarily disable event handling while loading data
            _state.IsLoadingData = true;
            form.GridNav.DataSource = table;

            ConfigureGridColumns(form.GridNav);

            _state.IsLoadingData = false;

            _navigationService.ShowTumor(0);

            // Build search index
            var searchService = new SearchService(tumors, nsMgr);
            _state.SearchIndex = searchService.BuildSearchIndex("xml");

            form.PnlSearch.Visible = true;
            form.TxtSearch.Text = "";
            form.LblSearchCount.Text = "";
            form.UpdateTitle();
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load XML file", "OPEN_FILE", ex);
            MessageBox.Show($"Error loading XML: {ex.Message}", "Error");
        }
    }

    // ── Import HL7 ───────────────────────────────────────────────────────

    private void ImportHl7File(string filePath, MainForm form)
    {
        try
        {
            var messages = _hl7FileService.LoadHl7File(filePath);

            if (messages.Count == 0)
            {
                MessageBox.Show("No HL7 messages found in this file.", "No Messages");
                form.SetStatusText("No messages found");
                form.SetFileNameText($"File: {filePath}");
                form.RtbPath.Clear();
                form.RtbItems.Clear();
                form.GridNav.DataSource = null;
                form.BtnPrev.Enabled = false;
                form.BtnNext.Enabled = false;
                form.LblIndex.Text = "";
                form.PnlSearch.Visible = false;
                form.UpdateTitle();
                return;
            }

            // Set state
            _state.Hl7Messages = messages;
            _state.CurrentFilePath = filePath;
            _state.FileType = "hl7";
            _state.CurrentIndex = -1;

            // Clear XML data
            _state.XmlDoc = null;
            _state.Tumors = null;
            _state.NsMgr = null;

            _menuBuilder.UpdateMenuStatesForFileType("hl7");

            var fileName = Path.GetFileName(filePath);
            form.SetStatusText($"Loaded: {fileName} (Messages: {messages.Count})");
            form.SetFileNameText($"File: {filePath}");

            _logger.Log("INFO", $"Loaded {fileName} with {messages.Count} messages", "OPEN_FILE");
            _recentFilesService.AddRecentFile(filePath, "hl7");

            // Build navigation table for HL7
            var table = new DataTable();
            table.Columns.Add("Selected", typeof(bool));
            table.Columns.Add("Index", typeof(int));
            table.Columns.Add("nameLast", typeof(string));
            table.Columns.Add("nameFirst", typeof(string));
            table.Columns.Add("dateOfBirth", typeof(string));
            table.Columns.Add("patientId", typeof(string));
            table.Columns.Add("messageType", typeof(string));
            table.Columns.Add("orderDateTime", typeof(string));

            table.BeginLoadData();
            foreach (var msg in messages)
            {
                var row = table.NewRow();
                row["Selected"] = false;
                row["Index"] = msg.Index + 1;
                row["nameLast"] = msg.PatientLastName;
                row["nameFirst"] = msg.PatientFirstName;
                row["dateOfBirth"] = msg.DateOfBirth;
                row["patientId"] = msg.PatientId;
                row["messageType"] = msg.MessageType;
                row["orderDateTime"] = msg.OrderDateTime;

                table.Rows.Add(row);
            }
            table.EndLoadData();

            _state.NavTable = table;

            // Temporarily disable event handling while loading data
            _state.IsLoadingData = true;
            form.GridNav.DataSource = table;

            ConfigureGridColumns(form.GridNav);

            _state.IsLoadingData = false;

            // Select first row and show first message
            if (form.GridNav.Rows.Count > 0)
            {
                form.GridNav.Rows[0].Selected = true;
                form.GridNav.CurrentCell = form.GridNav.Rows[0].Cells[0];
            }
            _navigationService.ShowHl7Message(0);

            // Build search index
            var searchService = new SearchService(null, null, messages);
            _state.SearchIndex = searchService.BuildSearchIndex("hl7");

            form.PnlSearch.Visible = true;
            form.TxtSearch.Text = "";
            form.LblSearchCount.Text = "";
            form.UpdateTitle();
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load HL7 file", "OPEN_FILE", ex);
            MessageBox.Show($"Error loading HL7: {ex.Message}", "Error");
        }
    }

    // ── Grid column configuration ────────────────────────────────────────

    private static void ConfigureGridColumns(DataGridView grid)
    {
        if (grid.Columns.Count == 0) return;

        foreach (DataGridViewColumn col in grid.Columns)
        {
            if (col.Name == "Selected")
            {
                col.ReadOnly = false;
                col.Width = 60;
                col.DisplayIndex = 0;
                col.SortMode = DataGridViewColumnSortMode.NotSortable;
            }
            else
            {
                col.ReadOnly = true;
                col.SortMode = DataGridViewColumnSortMode.Automatic;
            }
        }
    }

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
            var emptyItem = new ToolStripMenuItem("(No recent files)") { Enabled = false };
            mnuOpenRecent.DropDownItems.Add(emptyItem);
            return;
        }

        foreach (var entry in recentFiles)
        {
            var displayName = Path.GetFileName(entry.FilePath);
            var item = new ToolStripMenuItem(displayName)
            {
                ToolTipText = entry.FilePath
            };

            var capturedPath = entry.FilePath;
            item.Click += (s, e) =>
            {
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

        var clearItem = new ToolStripMenuItem("Clear Recent Files");
        clearItem.Click += (s, e) =>
        {
            _recentFilesService.ClearRecentFiles();
        };
        mnuOpenRecent.DropDownItems.Add(clearItem);
    }

    // ── Open Containing Folder ───────────────────────────────────────────

    /// <summary>
    /// Opens the file explorer to the directory of the currently loaded file.
    /// Ported from btnOpenContainingFolder.ps1.
    /// </summary>
    public void HandleOpenContainingFolder()
    {
        if (string.IsNullOrEmpty(_state.CurrentFilePath)) return;

        var dir = Path.GetDirectoryName(_state.CurrentFilePath);
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

                    // Use a SearchService instance for ApplyFilter
                    var searchService = new SearchService();
                    searchService.ApplyFilter(searchText, navTable, searchIndex);

                    int totalCount = searchIndex.Length;

                    if (string.IsNullOrWhiteSpace(searchText))
                    {
                        form.LblSearchCount.Text = "";
                    }
                    else
                    {
                        int matchCount = navTable.DefaultView.Count;
                        form.LblSearchCount.Text = $"{matchCount} / {totalCount}";
                    }

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
        // dotnet run builds to e.g. src/Parat.UI/bin/Debug/net8.0-windows/win-x64/Parat.UI.exe
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
