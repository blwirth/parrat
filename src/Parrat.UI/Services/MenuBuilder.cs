using System.Windows.Forms;
using Parrat.UI.Controls;

namespace Parrat.UI.Services;

/// <summary>
/// Constructs the full menu structure for MainForm.
/// Ported from the menu creation code in parrat.ps1.
/// Click handlers are wired by MainForm.Handlers.cs via WireMenuHandlers().
/// </summary>
public class MenuBuilder
{
    private readonly AppState _state;

    public MenuBuilder(AppState state)
    {
        _state = state;
    }

    // ── Public menu item references (for enable/disable logic) ───────────

    // File menu
    public ToolStripMenuItem MnuOpen { get; private set; } = null!;
    public ToolStripMenuItem MnuOpenRecent { get; private set; } = null!;
    public ToolStripMenuItem MnuOpenFolder { get; private set; } = null!;
    public ToolStripMenuItem MnuDiffFiles { get; private set; } = null!;
    public ToolStripMenuItem MnuConcatenate { get; private set; } = null!;
    public ToolStripMenuItem MnuSplit { get; private set; } = null!;
    public ToolStripMenuItem MnuConvertTxt { get; private set; } = null!;
    public ToolStripMenuItem MnuImportCsv { get; private set; } = null!;
    public ToolStripMenuItem MnuRestart { get; private set; } = null!;

    // Concatenate submenu
    public ToolStripMenuItem MenuItemConcatenateHl7 { get; private set; } = null!;
    public ToolStripMenuItem MenuItemConcatenateXml { get; private set; } = null!;
    public ToolStripMenuItem MenuItemConcatenateTxt { get; private set; } = null!;

    // View menu
    public ToolStripMenuItem MnuRawRecord { get; private set; } = null!;
    public ToolStripMenuItem MnuDiffRecords { get; private set; } = null!;

    // Edit menu
    public ToolStripMenuItem MnuAssign { get; private set; } = null!;
    public ToolStripMenuItem MnuModifyHl7 { get; private set; } = null!;
    public ToolStripMenuItem MnuModifyXml { get; private set; } = null!;
    public ToolStripMenuItem MnuDeduplicate { get; private set; } = null!;
    public ToolStripMenuItem MenuItemTrueMatches { get; private set; } = null!;
    public ToolStripMenuItem MenuItemPathReport { get; private set; } = null!;
    public ToolStripMenuItem MenuItemPrimaryKey { get; private set; } = null!;
    public ToolStripMenuItem MenuItemFixObx31 { get; private set; } = null!;
    public ToolStripMenuItem MenuItemRemoveEmptyObx5 { get; private set; } = null!;
    public ToolStripMenuItem MenuItemRemoveVariable { get; private set; } = null!;

    // Reference
    public ToolStripMenuItem MnuOpenReference { get; private set; } = null!;

    // Export menu
    public ToolStripMenuItem MnuExport { get; private set; } = null!;
    public ToolStripMenuItem MnuExportSelectedXml { get; private set; } = null!;
    public ToolStripMenuItem MnuExportSelectedHl7 { get; private set; } = null!;
    public ToolStripSeparator MnuExportSeparator { get; private set; } = null!;
    public ToolStripMenuItem MnuExportAllCsv { get; private set; } = null!;
    public ToolStripMenuItem MnuExportSelectedCsv { get; private set; } = null!;

    // Tools menu
    public ToolStripMenuItem MnuTestSiteLatCurrent { get; private set; } = null!;
    public ToolStripMenuItem MnuTestSiteLatCustom { get; private set; } = null!;
    public ToolStripMenuItem MnuFilterCurrentHl7 { get; private set; } = null!;
    public ToolStripMenuItem MnuFilterCustomPayload { get; private set; } = null!;

    // Settings menu
    public ToolStripMenuItem MnuManageCodingTables { get; private set; } = null!;
    public ToolStripMenuItem MnuNoahConfig { get; private set; } = null!;
    public ToolStripMenuItem MnuObxSkipCodes { get; private set; } = null!;
    public ToolStripMenuItem MnuGridColumns { get; private set; } = null!;

    // Help menu
    public ToolStripMenuItem MnuUserManual { get; private set; } = null!;
    public ToolStripMenuItem MnuOpenLogs { get; private set; } = null!;

    // ── Build menu strip ─────────────────────────────────────────────────

    /// <summary>
    /// Creates and returns a fully-populated MenuStrip with all menus
    /// and the ShortcutGrayRenderer applied.
    /// </summary>
    public MenuStrip BuildMenuStrip()
    {
        var menuStrip = new MenuStrip { Dock = DockStyle.Top };
        menuStrip.Renderer = new ShortcutGrayRenderer();

        menuStrip.Items.AddRange(new ToolStripItem[]
        {
            BuildFileMenu(),
            BuildViewMenu(),
            BuildEditMenu(),
            BuildExportMenu(),
            BuildToolsMenu(),
            BuildSettingsMenu(),
            BuildHelpMenu()
        });

        return menuStrip;
    }

    // ── File menu ────────────────────────────────────────────────────────

    private ToolStripMenuItem BuildFileMenu()
    {
        var mnuFile = new ToolStripMenuItem("File");

        MnuOpen = new ToolStripMenuItem("Open")
        {
            ShortcutKeys = Keys.Control | Keys.O
        };
        // Click handler wired by MainForm via FileHandlers
        mnuFile.DropDownItems.Add(MnuOpen);

        MnuOpenRecent = new ToolStripMenuItem("Open Recent");
        // DropDownOpening handler wired by MainForm via FileHandlers
        mnuFile.DropDownItems.Add(MnuOpenRecent);

        MnuOpenFolder = new ToolStripMenuItem("Open Containing Folder") { Enabled = false };
        // Click handler wired by MainForm via FileHandlers
        mnuFile.DropDownItems.Add(MnuOpenFolder);

        mnuFile.DropDownItems.Add(new ToolStripSeparator());

        MnuOpenReference = new ToolStripMenuItem("Open Reference File...") { Enabled = false };
        // Click handler wired by MainForm
        mnuFile.DropDownItems.Add(MnuOpenReference);

        mnuFile.DropDownItems.Add(new ToolStripSeparator());

        MnuDiffFiles = new ToolStripMenuItem("Diff Files...");
        // Click handler wired by MainForm.Handlers.cs
        mnuFile.DropDownItems.Add(MnuDiffFiles);

        mnuFile.DropDownItems.Add(new ToolStripSeparator());

        // Concatenate submenu
        MnuConcatenate = new ToolStripMenuItem("Concatenate...");

        MenuItemConcatenateHl7 = new ToolStripMenuItem("Concatenate HL7");
        // Click handler wired by MainForm.Handlers.cs
        MnuConcatenate.DropDownItems.Add(MenuItemConcatenateHl7);

        MenuItemConcatenateXml = new ToolStripMenuItem("Concatenate XML");
        // Click handler wired by MainForm.Handlers.cs
        MnuConcatenate.DropDownItems.Add(MenuItemConcatenateXml);

        MenuItemConcatenateTxt = new ToolStripMenuItem("Concatenate TXT");
        // Click handler wired by MainForm.Handlers.cs
        MnuConcatenate.DropDownItems.Add(MenuItemConcatenateTxt);

        mnuFile.DropDownItems.Add(MnuConcatenate);

        MnuSplit = new ToolStripMenuItem("Split...");
        // Click handler wired by MainForm.Handlers.cs
        mnuFile.DropDownItems.Add(MnuSplit);

        mnuFile.DropDownItems.Add(new ToolStripSeparator());

        MnuConvertTxt = new ToolStripMenuItem("Convert .txt");
        // Click handler wired by MainForm.Handlers.cs
        mnuFile.DropDownItems.Add(MnuConvertTxt);

        MnuImportCsv = new ToolStripMenuItem("Import CSV...");
        // Click handler wired by MainForm.Handlers.cs
        mnuFile.DropDownItems.Add(MnuImportCsv);

        mnuFile.DropDownItems.Add(new ToolStripSeparator());

        MnuRestart = new ToolStripMenuItem("Restart Application")
        {
            ShortcutKeys = Keys.Control | Keys.Shift | Keys.R
        };
        // Click handler wired by MainForm via FileHandlers
        mnuFile.DropDownItems.Add(MnuRestart);

        return mnuFile;
    }

    // ── View menu ────────────────────────────────────────────────────────

    private ToolStripMenuItem BuildViewMenu()
    {
        var mnuView = new ToolStripMenuItem("View");

        MnuRawRecord = new ToolStripMenuItem("Raw Record") { Enabled = false };
        // Click handler wired by MainForm.Handlers.cs
        mnuView.DropDownItems.Add(MnuRawRecord);

        MnuDiffRecords = new ToolStripMenuItem("Diff Records") { Enabled = false };
        // Click handler wired by MainForm.Handlers.cs
        mnuView.DropDownItems.Add(MnuDiffRecords);

        return mnuView;
    }

    // ── Edit menu ────────────────────────────────────────────────────────

    private ToolStripMenuItem BuildEditMenu()
    {
        var mnuEdit = new ToolStripMenuItem("Edit");

        MnuAssign = new ToolStripMenuItem("Assign...") { Enabled = false };
        // Click handler wired by MainForm.Handlers.cs
        mnuEdit.DropDownItems.Add(MnuAssign);

        mnuEdit.DropDownItems.Add(new ToolStripSeparator());

        // Modify HL7 submenu
        MnuModifyHl7 = new ToolStripMenuItem("Modify HL7") { Enabled = false };

        MenuItemFixObx31 = new ToolStripMenuItem("Fix OBX 3.1");
        // Click handler wired by MainForm.Handlers.cs
        MnuModifyHl7.DropDownItems.Add(MenuItemFixObx31);

        MenuItemRemoveEmptyObx5 = new ToolStripMenuItem("Remove Empty OBX 5");
        // Click handler wired by MainForm.Handlers.cs
        MnuModifyHl7.DropDownItems.Add(MenuItemRemoveEmptyObx5);

        mnuEdit.DropDownItems.Add(MnuModifyHl7);

        // Modify XML submenu
        MnuModifyXml = new ToolStripMenuItem("Modify XML") { Enabled = false };

        MenuItemRemoveVariable = new ToolStripMenuItem("Remove Variable...");
        // Click handler wired by MainForm.Handlers.cs
        MnuModifyXml.DropDownItems.Add(MenuItemRemoveVariable);

        mnuEdit.DropDownItems.Add(MnuModifyXml);

        mnuEdit.DropDownItems.Add(new ToolStripSeparator());

        // Deduplicate submenu
        MnuDeduplicate = new ToolStripMenuItem("Deduplicate...") { Enabled = false };

        MenuItemTrueMatches = new ToolStripMenuItem("Dedup true matches");
        // Click handler wired by MainForm.Handlers.cs
        MnuDeduplicate.DropDownItems.Add(MenuItemTrueMatches);

        MenuItemPathReport = new ToolStripMenuItem("Dedup by pathReportNumber1");
        // Click handler wired by MainForm.Handlers.cs
        MnuDeduplicate.DropDownItems.Add(MenuItemPathReport);

        MenuItemPrimaryKey = new ToolStripMenuItem("Dedup by primary key");
        // Click handler wired by MainForm.Handlers.cs
        MnuDeduplicate.DropDownItems.Add(MenuItemPrimaryKey);

        mnuEdit.DropDownItems.Add(MnuDeduplicate);

        return mnuEdit;
    }

    // ── Export menu ──────────────────────────────────────────────────────

    private ToolStripMenuItem BuildExportMenu()
    {
        MnuExport = new ToolStripMenuItem("Export") { Enabled = false };

        // Pre-build all items — matches PowerShell pattern where all items
        // are always present and enabled/disabled based on file type
        MnuExportSelectedXml = new ToolStripMenuItem("Export Selected as XML");
        MnuExport.DropDownItems.Add(MnuExportSelectedXml);

        MnuExportSelectedHl7 = new ToolStripMenuItem("Export Selected as HL7");
        MnuExport.DropDownItems.Add(MnuExportSelectedHl7);

        MnuExportSeparator = new ToolStripSeparator();
        MnuExport.DropDownItems.Add(MnuExportSeparator);

        MnuExportAllCsv = new ToolStripMenuItem("Export All as CSV");
        MnuExport.DropDownItems.Add(MnuExportAllCsv);

        MnuExportSelectedCsv = new ToolStripMenuItem("Export Selected as CSV");
        MnuExport.DropDownItems.Add(MnuExportSelectedCsv);

        // DropDownOpening + Click handlers wired by MainForm.Handlers.cs
        return MnuExport;
    }

    // ── Tools menu ───────────────────────────────────────────────────────

    private ToolStripMenuItem BuildToolsMenu()
    {
        var mnuTools = new ToolStripMenuItem("Tools");

        MnuTestSiteLatCurrent = new ToolStripMenuItem("Test current record (Site/Lat)") { Enabled = false };
        // Click handler wired by MainForm.Handlers.cs
        mnuTools.DropDownItems.Add(MnuTestSiteLatCurrent);

        MnuTestSiteLatCustom = new ToolStripMenuItem("Test custom text (Site/Lat)");
        // Click handler wired by MainForm.Handlers.cs
        mnuTools.DropDownItems.Add(MnuTestSiteLatCustom);

        mnuTools.DropDownItems.Add(new ToolStripSeparator());

        MnuFilterCurrentHl7 = new ToolStripMenuItem("Test current HL7 (NOAH)") { Enabled = false };
        // Click handler wired by MainForm.Handlers.cs
        mnuTools.DropDownItems.Add(MnuFilterCurrentHl7);

        MnuFilterCustomPayload = new ToolStripMenuItem("Test custom payload (NOAH)");
        // Click handler wired by MainForm.Handlers.cs
        mnuTools.DropDownItems.Add(MnuFilterCustomPayload);

        // Dynamic enable/disable on dropdown opening
        mnuTools.DropDownOpening += (s, e) =>
        {
            var fileType = _state.FileType;
            MnuFilterCurrentHl7.Enabled = fileType == "hl7";
            MnuTestSiteLatCurrent.Enabled = fileType == "xml" || fileType == "hl7";
        };

        return mnuTools;
    }

    // ── Settings menu ────────────────────────────────────────────────────

    private ToolStripMenuItem BuildSettingsMenu()
    {
        var mnuSettings = new ToolStripMenuItem("Settings");

        MnuManageCodingTables = new ToolStripMenuItem("Manage Coding Tables");
        // DropDownOpening handler wired by MainForm.Handlers.cs
        mnuSettings.DropDownItems.Add(MnuManageCodingTables);

        MnuNoahConfig = new ToolStripMenuItem("NOAH Configuration");
        // Click handler wired by MainForm.Handlers.cs
        mnuSettings.DropDownItems.Add(MnuNoahConfig);

        MnuObxSkipCodes = new ToolStripMenuItem("OBX Skip Codes...");
        // Click handler wired by MainForm.Handlers.cs
        mnuSettings.DropDownItems.Add(MnuObxSkipCodes);

        mnuSettings.DropDownItems.Add(new ToolStripSeparator());

        MnuGridColumns = new ToolStripMenuItem("Grid Columns...");
        // Click handler wired by MainForm.Handlers.cs
        mnuSettings.DropDownItems.Add(MnuGridColumns);

        return mnuSettings;
    }

    // ── Help menu ────────────────────────────────────────────────────────

    private ToolStripMenuItem BuildHelpMenu()
    {
        var mnuHelp = new ToolStripMenuItem("Help");

        MnuUserManual = new ToolStripMenuItem("User Manual");
        // Click handler wired by MainForm.Handlers.cs
        mnuHelp.DropDownItems.Add(MnuUserManual);

        mnuHelp.DropDownItems.Add(new ToolStripSeparator());

        MnuOpenLogs = new ToolStripMenuItem("Open Logs Folder");
        // Click handler wired by MainForm.Handlers.cs
        mnuHelp.DropDownItems.Add(MnuOpenLogs);

        mnuHelp.DropDownItems.Add(new ToolStripSeparator());

        var versionPath = Path.Combine(Parrat.Core.Helpers.PathHelper.RepoRoot, "VERSION");
        var versionText = File.Exists(versionPath)
            ? File.ReadAllText(versionPath).Trim()
            : "dev";
        var mnuVersion = new ToolStripMenuItem($"PARRAT {versionText}") { Enabled = false };
        mnuHelp.DropDownItems.Add(mnuVersion);

        return mnuHelp;
    }

    // ── Enable/disable logic ─────────────────────────────────────────────

    /// <summary>
    /// Updates enabled states of menu items based on the loaded file type.
    /// </summary>
    public void UpdateMenuStatesForFileType(string? fileType)
    {
        bool hasFile = !string.IsNullOrEmpty(fileType);

        MnuRawRecord.Enabled = hasFile;
        MnuDiffRecords.Enabled = hasFile;
        MnuDeduplicate.Enabled = hasFile;
        MnuExport.Enabled = hasFile;
        MnuOpenFolder.Enabled = hasFile;
        MnuOpenReference.Enabled = hasFile;

        bool isXml = fileType == "xml";
        MnuAssign.Enabled = isXml;
        MnuModifyXml.Enabled = isXml;

        bool isHl7 = fileType == "hl7";
        MnuModifyHl7.Enabled = isHl7;
    }
}
