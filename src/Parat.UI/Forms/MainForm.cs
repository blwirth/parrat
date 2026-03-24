using System.Data;
using System.Windows.Forms;
using Parat.Core.Interfaces;
using Parat.UI.Services;

namespace Parat.UI.Forms;

/// <summary>
/// Main application form for PARAT.
/// Hosts the DataGridView (record list), RichTextBox panels (text/items display),
/// MenuStrip, StatusBar, and navigation controls.
/// Ported from the form layout and event wiring in parat.ps1.
/// </summary>
public partial class MainForm : Form
{
    private readonly AppState _state;
    private readonly MenuBuilder _menuBuilder;
    private readonly NavigationService _navigationService;
    private readonly FileHandlers _fileHandlers;
    private readonly IParatLogger _logger;
    private MenuStrip _menuStrip = null!;

    public MainForm(
        AppState state,
        MenuBuilder menuBuilder,
        NavigationService navigationService,
        FileHandlers fileHandlers,
        IParatLogger logger)
    {
        _state = state;
        _menuBuilder = menuBuilder;
        _navigationService = navigationService;
        _fileHandlers = fileHandlers;
        _logger = logger;

        InitializeComponent();
        InitializeMenu();
        InitializeNavigation();
        WireEvents();

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
        _splitOuter.SplitterDistance = (int)(_splitOuter.Width * 0.20);
        _splitInner.SplitterDistance = (int)(_splitInner.Width * 0.55);
    }

    private void OnGridSelectionChanged(object? sender, EventArgs e)
    {
        _navigationService.HandleGridSelectionChanged();
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
        var appTitle = string.IsNullOrEmpty(version) ? "PARAT" : $"PARAT {version}";
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
