using System.Data;
using System.Windows.Forms;
using Parrat.Core.Interfaces;
using Parrat.UI.Services;

namespace Parrat.UI.Forms;

/// <summary>
/// Main application form for PARRAT.
/// Hosts the DataGridView (record list), RichTextBox panels (text/items display),
/// MenuStrip, StatusBar, and navigation controls.
/// Ported from the form layout and event wiring in parrat.ps1.
/// </summary>
public partial class MainForm : ParratFormBase
{
    private readonly AppState _state;
    private readonly MenuBuilder _menuBuilder;
    private readonly NavigationService _navigationService;
    private readonly FileHandlers _fileHandlers;
    private readonly IParratLogger _logger;
    private MenuStrip _menuStrip = null!;

    // Reference panel
    private ReferenceForm? _referenceForm;

    public MainForm(
        AppState state,
        MenuBuilder menuBuilder,
        NavigationService navigationService,
        FileHandlers fileHandlers,
        IParratLogger logger,
        IDiffService diffService,
        IXmlFileService xmlFileService,
        IHl7FileService hl7FileService,
        IDeduplicationService deduplicationService,
        IUnifiedAssignmentService unifiedAssignmentService,
        ISiteLateralityService siteLateralityService,
        IFacilityAssignmentService facilityAssignmentService,
        IObxService obxService,
        IPidAssignmentService pidAssignmentService,
        IRemoveVariableService removeVariableService,
        IConvertTxtService convertTxtService,
        IExportService exportService,
        INoahService noahService,
        ISplitFileService splitFileService,
        IConcatenateService concatenateService,
        IConfigService configService,
        INaaccrDictionary naaccrDictionary,
        ICsvParserService csvParserService,
        ICsvImportService csvImportService,
        IXlsxParserService xlsxParserService,
        IEpathParserService epathParserService)
    {
        _state = state;
        _menuBuilder = menuBuilder;
        _navigationService = navigationService;
        _fileHandlers = fileHandlers;
        _logger = logger;

        // Set handler services
        _diffService = diffService;
        _xmlFileService = xmlFileService;
        _hl7FileService = hl7FileService;
        _deduplicationService = deduplicationService;
        _unifiedAssignmentService = unifiedAssignmentService;
        _siteLateralityService = siteLateralityService;
        _facilityAssignmentService = facilityAssignmentService;
        _obxService = obxService;
        _pidAssignmentService = pidAssignmentService;
        _removeVariableService = removeVariableService;
        _convertTxtService = convertTxtService;
        _exportService = exportService;
        _noahService = noahService;
        _splitFileService = splitFileService;
        _concatenateService = concatenateService;
        _configService = configService;
        _naaccrDictionary = naaccrDictionary;
        _csvParserService = csvParserService;
        _csvImportService = csvImportService;
        _xlsxParserService = xlsxParserService;
        _epathParserService = epathParserService;

        InitializeComponent();
        InitializeMenu();
        InitializeNavigation();
        WireEvents();
        WireMenuHandlers();

        // Set initial title
        UpdateTitle();
    }

    // ── Public accessors for services that need control references ────────

    /// <summary>Status label for record count / messages.</summary>
    public ToolStripStatusLabel StatusLabel => _lblStatus;

    /// <summary>Status label showing current file name.</summary>
    public ToolStripStatusLabel FileNameLabel => _lblFileName;

    /// <summary>The navigation grid (tumor/message list).</summary>
    public DataGridView GridNav => _gridNav;

    /// <summary>The path/text RichTextBox (middle panel).</summary>
    public RichTextBox RtbPath => _rtbPath;

    /// <summary>The items RichTextBox (right panel).</summary>
    public RichTextBox RtbItems => _rtbItems;

    /// <summary>The search text box.</summary>
    public TextBox TxtSearch => _txtSearch;

    /// <summary>The search count label.</summary>
    public Label LblSearchCount => _lblSearchCount;

    /// <summary>The search clear button.</summary>
    public Button BtnClearSearch => _btnClearSearch;

    /// <summary>The search panel.</summary>
    public Panel PnlSearch => _pnlSearch;

    /// <summary>The Previous button.</summary>
    public Button BtnPrev => _btnPrev;

    /// <summary>The Next button.</summary>
    public Button BtnNext => _btnNext;

    /// <summary>The index label (e.g., "Tumor 1 of 5 (0 selected)").</summary>
    public Label LblIndex => _lblIndex;

    /// <summary>The copy buttons bar panel above the items pane.</summary>
    public FlowLayoutPanel PnlCopyBar => _pnlCopyBar;

    /// <summary>The 4 copy field buttons: [0]=Last, [1]=First, [2]=DOB, [3]=Path#.</summary>
    public Button[] BtnCopyFields => _btnCopyFields;

    /// <summary>Provides access to the MenuBuilder for external wiring.</summary>
    public MenuBuilder MenuBuilder => _menuBuilder;

    /// <summary>Provides access to the NavigationService.</summary>
    public NavigationService NavigationService => _navigationService;

    // ── Initialization ───────────────────────────────────────────────────

    private void InitializeMenu()
    {
        _menuStrip = _menuBuilder.BuildMenuStrip();
        MainMenuStrip = _menuStrip;
        Controls.Add(_menuStrip);

        // Wire file/navigation menu handlers
        _menuBuilder.MnuOpen.Click += (s, e) => _fileHandlers.HandleOpen(this);

        _menuBuilder.MnuOpenRecent.DropDownOpening += (s, e) =>
            _fileHandlers.PopulateOpenRecentMenu(_menuBuilder.MnuOpenRecent, this);

        _menuBuilder.MnuOpenFolder.Click += (s, e) => _fileHandlers.HandleOpenContainingFolder();

        _menuBuilder.MnuRestart.Click += (s, e) => _fileHandlers.HandleRestart();

        _menuBuilder.MnuOpenReference.Click += (s, e) => HandleOpenReference();
    }

    private void InitializeNavigation()
    {
        // Wire control references into NavigationService
        _navigationService.GridNav = _gridNav;
        _navigationService.RtbPath = _rtbPath;
        _navigationService.RtbItems = _rtbItems;
        _navigationService.BtnPrev = _btnPrev;
        _navigationService.BtnNext = _btnNext;
        _navigationService.LblIndex = _lblIndex;
        _navigationService.TxtSearch = _txtSearch;
        _navigationService.PnlCopyBar = _pnlCopyBar;
        _navigationService.BtnCopyFields = _btnCopyFields;
    }

    // ── Event wiring ─────────────────────────────────────────────────────

    private void WireEvents()
    {
        // Form shown — set splitter distances after dimensions are available
        Shown += OnFormShown;

        // Grid selection -> show record
        _gridNav.SelectionChanged += OnGridSelectionChanged;

        // Space key toggles checkboxes on selected rows
        _gridNav.KeyDown += OnGridKeyDown;

        // Commit checkbox changes immediately when clicked
        _gridNav.CurrentCellDirtyStateChanged += OnCurrentCellDirtyStateChanged;

        // Update selected count when checkbox value changes
        _gridNav.CellValueChanged += OnCellValueChanged;

        // Navigation buttons
        _btnPrev.Click += (s, e) => _navigationService.NavigatePrevious();
        _btnNext.Click += (s, e) => _navigationService.NavigateNext();

        // Search text changed with debounce
        _txtSearch.TextChanged += (s, e) => _fileHandlers.HandleSearchTextChanged(this);
        _btnClearSearch.Click += (s, e) => _fileHandlers.HandleSearchClear(this);

        // Copy buttons
        foreach (var btn in _btnCopyFields)
            btn.Click += OnCopyFieldClick;

        // Find in Reference button
        _btnFindInRef.Click += OnFindInReferenceClick;

        // Save column widths on resize
        _gridNav.ColumnWidthChanged += OnGridColumnWidthChanged;

        // Keyboard shortcuts
        KeyDown += OnFormKeyDown;

        // Form closing
        FormClosing += OnFormClosing;
    }

    // ── Event handlers ───────────────────────────────────────────────────

    private void OnFormShown(object? sender, EventArgs e)
    {
        // Set min sizes and splitter distances after form has proper dimensions
        _splitOuter.Panel2MinSize = 400;
        _splitInner.Panel2MinSize = 200;

        // Restore saved panel layout or use defaults
        var layout = _fileHandlers.GridSettingsService.Load().Layout;
        _splitOuter.SplitterDistance = layout.OuterSplitRatio > 0
            ? (int)(_splitOuter.Width * layout.OuterSplitRatio)
            : (int)(_splitOuter.Width * 0.20);
        _splitInner.SplitterDistance = layout.InnerSplitRatio > 0
            ? (int)(_splitInner.Width * layout.InnerSplitRatio)
            : (int)(_splitInner.Width * 0.55);

        // Save on splitter move
        _splitOuter.SplitterMoved += OnSplitterMoved;
        _splitInner.SplitterMoved += OnSplitterMoved;
    }

    private void OnGridSelectionChanged(object? sender, EventArgs e)
    {
        _navigationService.HandleGridSelectionChanged();
        NotifyReferenceOfCurrentRecord();
    }

    private void NotifyReferenceOfCurrentRecord()
    {
        if (_referenceForm == null || _referenceForm.IsDisposed) return;

        string lastName = _btnCopyFields[0].Tag?.ToString() ?? "";
        string firstName = _btnCopyFields[1].Tag?.ToString() ?? "";
        string dob = _btnCopyFields[2].Tag?.ToString() ?? "";
        string pathReport = _btnCopyFields[3].Tag?.ToString() ?? "";

        _referenceForm.NotifyPrimaryRecordChanged(lastName, firstName, dob, pathReport);
    }

    private void OnGridKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode != Keys.Space) return;

        e.Handled = true;
        e.SuppressKeyPress = true;

        if (_gridNav.SelectedRows.Count == 0) return;

        var dataTable = _gridNav.DataSource as DataTable;
        if (dataTable == null) return;

        // Move current cell off the checkbox column
        if (_gridNav.CurrentCell != null
            && _gridNav.CurrentCell.ColumnIndex == 0
            && _gridNav.ColumnCount > 1)
        {
            _gridNav.CurrentCell = _gridNav.Rows[_gridNav.CurrentCell.RowIndex].Cells[1];
        }

        // Use first selected row to determine toggle direction
        int firstIdx = _gridNav.SelectedRows[0].Index;
        bool newVal = !(bool)dataTable.Rows[firstIdx]["Selected"];

        // Batch update
        _state.SpaceBatchToggling = true;
        _gridNav.SuspendLayout();
        foreach (DataGridViewRow gridRow in _gridNav.SelectedRows)
        {
            dataTable.Rows[gridRow.Index]["Selected"] = newVal;
        }
        _gridNav.ResumeLayout();
        _state.SpaceBatchToggling = false;

        // Update the selected count label
        _navigationService.UpdateSelectedCountLabel();
    }

    private void OnCurrentCellDirtyStateChanged(object? sender, EventArgs e)
    {
        if (_state.SpaceBatchToggling) return;
        if (_gridNav.IsCurrentCellDirty && _gridNav.CurrentCell.ColumnIndex == 0)
        {
            _gridNav.CommitEdit(DataGridViewDataErrorContexts.Commit);
        }
    }

    private void OnCellValueChanged(object? sender, DataGridViewCellEventArgs e)
    {
        if (e.ColumnIndex != 0) return;
        if (_state.IsLoadingData || _state.SpaceBatchToggling) return;

        _navigationService.UpdateSelectedCountLabel();
    }

    private void OnFormKeyDown(object? sender, KeyEventArgs e)
    {
        // Ctrl+O — Open file
        if (e.Control && !e.Shift && e.KeyCode == Keys.O)
        {
            _fileHandlers.HandleOpen(this);
            e.Handled = true;
            e.SuppressKeyPress = true;
        }
        // Ctrl+F — Focus search
        else if (e.Control && !e.Shift && e.KeyCode == Keys.F)
        {
            if (_pnlSearch.Visible)
            {
                _txtSearch.Focus();
                _txtSearch.SelectAll();
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }
        // Ctrl+R — Find in Reference
        else if (e.Control && !e.Shift && e.KeyCode == Keys.R)
        {
            if (_referenceForm != null && !_referenceForm.IsDisposed)
            {
                OnFindInReferenceClick(this, EventArgs.Empty);
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }
        // Ctrl+Shift+R — Restart
        else if (e.Control && e.Shift && e.KeyCode == Keys.R)
        {
            _fileHandlers.HandleRestart();
            e.Handled = true;
            e.SuppressKeyPress = true;
        }
        // Escape — Clear search
        else if (e.KeyCode == Keys.Escape)
        {
            if (_txtSearch.Focused)
            {
                _txtSearch.Text = "";
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }
    }

    private void OnSplitterMoved(object? sender, SplitterEventArgs e)
    {
        if (_splitOuter.Width == 0 || _splitInner.Width == 0) return;
        var settings = _fileHandlers.GridSettingsService.Load();
        settings.Layout.OuterSplitRatio = (double)_splitOuter.SplitterDistance / _splitOuter.Width;
        settings.Layout.InnerSplitRatio = (double)_splitInner.SplitterDistance / _splitInner.Width;
        _fileHandlers.GridSettingsService.Save(settings);
    }

    private void OnGridColumnWidthChanged(object? sender, DataGridViewColumnEventArgs e)
    {
        // Don't save during file load
        if (_state.IsLoadingData) return;
        if (e.Column.Name is "Selected" or "Index") return;
        _fileHandlers.SaveGridColumnWidths(_gridNav);
    }

    private void OnCopyFieldClick(object? sender, EventArgs e)
    {
        if (sender is not Button btn) return;
        var value = btn.Tag as string;
        if (string.IsNullOrEmpty(value)) return;

        try
        {
            Clipboard.SetDataObject(value, copy: true);

            // Success feedback: flash green background, revert after 800ms
            var originalBack = btn.BackColor;
            var originalBorder = btn.FlatAppearance.BorderColor;
            btn.BackColor = Color.FromArgb(200, 235, 200);
            btn.FlatAppearance.BorderColor = Color.Green;

            var timer = new System.Windows.Forms.Timer { Interval = 800 };
            timer.Tick += (_, _) =>
            {
                btn.BackColor = originalBack;
                btn.FlatAppearance.BorderColor = originalBorder;
                timer.Stop();
                timer.Dispose();
            };
            timer.Start();
        }
        catch (Exception ex)
        {
            _logger.LogError("Clipboard copy failed", "COPY", ex);
        }
    }

    // ── Reference panel ─────────────────────────────────────────────────

    private void HandleOpenReference()
    {
        using var ofd = new OpenFileDialog
        {
            Filter = "NAACCR/HL7 Files (*.xml;*.hl7)|*.xml;*.hl7|NAACCR XML (*.xml)|*.xml|HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
            Title = "Select reference file"
        };

        if (ofd.ShowDialog() != DialogResult.OK) return;

        // Close existing reference form if open
        if (_referenceForm != null && !_referenceForm.IsDisposed)
        {
            _referenceForm.Close();
            _referenceForm = null;
        }

        var refForm = new ReferenceForm(
            _xmlFileService,
            _hl7FileService,
            _fileHandlers.GridSettingsService,
            _logger);

        if (!refForm.OpenFile(ofd.FileName))
        {
            refForm.Dispose();
            return;
        }

        _referenceForm = refForm;
        _referenceForm.Owner = this;
        _referenceForm.FormClosed += (s, e) =>
        {
            _referenceForm = null;
            _btnFindInRef.Visible = false;
        };

        _referenceForm.Show();
        _btnFindInRef.Visible = true;
    }

    private void OnFindInReferenceClick(object? sender, EventArgs e)
    {
        if (_referenceForm == null || _referenceForm.IsDisposed) return;

        // Read key fields from the copy button Tags (already populated by NavigationService)
        string lastName = _btnCopyFields[0].Tag?.ToString() ?? "";
        string firstName = _btnCopyFields[1].Tag?.ToString() ?? "";
        string dob = _btnCopyFields[2].Tag?.ToString() ?? "";
        string pathReport = _btnCopyFields[3].Tag?.ToString() ?? "";

        _referenceForm.FindByKeyFields(lastName, firstName, null, dob, pathReport);
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        _logger.Close();
    }

    // ── Public helpers ───────────────────────────────────────────────────

    /// <summary>
    /// Updates the title bar with the app title and optional file name.
    /// </summary>
    public void UpdateTitle(string? version = null)
    {
        var appTitle = string.IsNullOrEmpty(version) ? "PARRAT" : $"PARRAT {version}";
        if (!string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            var fileName = Path.GetFileName(_state.CurrentFilePath);
            Text = $"{appTitle} - {fileName}";
        }
        else
        {
            Text = appTitle;
        }
    }

    /// <summary>
    /// Updates the status bar text.
    /// </summary>
    public void SetStatusText(string text)
    {
        _lblStatus.Text = text;
    }

    /// <summary>
    /// Updates the file name in the status bar.
    /// </summary>
    public void SetFileNameText(string text)
    {
        _lblFileName.Text = text;
    }

    /// <summary>
    /// Creates and binds the navigation DataTable with standard columns for XML records.
    /// </summary>
    public DataTable CreateXmlNavTable()
    {
        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("nameLast", typeof(string));
        table.Columns.Add("nameFirst", typeof(string));
        table.Columns.Add("dateOfBirth", typeof(string));
        table.Columns.Add("pathReportNumber1", typeof(string));
        table.Columns.Add("primarySite", typeof(string));
        table.Columns.Add("dateOfDiagnosis", typeof(string));

        _gridNav.DataSource = table;
        _state.NavTable = table;
        return table;
    }

    /// <summary>
    /// Creates and binds the navigation DataTable with standard columns for HL7 messages.
    /// </summary>
    public DataTable CreateHl7NavTable()
    {
        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("PatientLastName", typeof(string));
        table.Columns.Add("PatientFirstName", typeof(string));
        table.Columns.Add("DateOfBirth", typeof(string));
        table.Columns.Add("MessageType", typeof(string));
        table.Columns.Add("SendingFacility", typeof(string));
        table.Columns.Add("MessageDateTime", typeof(string));

        _gridNav.DataSource = table;
        _state.NavTable = table;
        return table;
    }
}
