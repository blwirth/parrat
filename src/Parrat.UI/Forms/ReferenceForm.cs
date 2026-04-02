using System.Data;
using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Interfaces;
using Parrat.Core.Services;
using Parrat.UI.Services;

namespace Parrat.UI.Forms;

/// <summary>
/// Read-only reference file viewer. Has NO export capability, NO "Selected"
/// checkbox column, and NO reference to AppState. All file data lives in
/// a private FileContext instance that is completely isolated from the
/// primary application state.
/// </summary>
public partial class ReferenceForm : Form
{
    private readonly FileContext _ctx = new();
    private readonly ReferenceNavigationService _navService;
    private readonly ReferenceFileLoader _fileLoader;
    private readonly IParratLogger _logger;

    private System.Windows.Forms.Timer? _searchTimer;
    private System.Windows.Forms.Timer? _autoSyncTimer;
    private string? _pendingLast, _pendingFirst, _pendingDob, _pendingPath;

    public ReferenceForm(
        IXmlFileService xmlFileService,
        IHl7FileService hl7FileService,
        IGridSettingsService gridSettingsService,
        IParratLogger logger)
    {
        _logger = logger;
        _navService = new ReferenceNavigationService(_ctx, logger);
        _fileLoader = new ReferenceFileLoader(xmlFileService, hl7FileService, gridSettingsService, logger);

        InitializeComponent();
        InitializeNavigation();
        WireEvents();
    }

    // ── Initialization ───────────────────────────────────────────────────

    private void InitializeNavigation()
    {
        _navService.GridNav = _gridNav;
        _navService.RtbPath = _rtbPath;
        _navService.RtbItems = _rtbItems;
        _navService.BtnPrev = _btnPrev;
        _navService.BtnNext = _btnNext;
        _navService.LblIndex = _lblIndex;
        _navService.TxtSearch = _txtSearch;
        _navService.PnlCopyBar = _pnlCopyBar;
        _navService.BtnCopyFields = _btnCopyFields;
    }

    private void WireEvents()
    {
        Shown += OnFormShown;

        _gridNav.SelectionChanged += (s, e) => _navService.HandleGridSelectionChanged();

        _btnPrev.Click += (s, e) => _navService.NavigatePrevious();
        _btnNext.Click += (s, e) => _navService.NavigateNext();

        _txtSearch.TextChanged += (s, e) => HandleSearchTextChanged();
        _btnClearSearch.Click += (s, e) => { _txtSearch.Text = ""; };

        foreach (var btn in _btnCopyFields)
            btn.Click += OnCopyFieldClick;

        KeyDown += OnFormKeyDown;
    }

    private void OnFormShown(object? sender, EventArgs e)
    {
        // Set default splitter positions (same ratios as MainForm)
        try
        {
            int outerDist = (int)(_splitOuter.Width * 0.20);
            if (outerDist > _splitOuter.Panel1MinSize)
                _splitOuter.SplitterDistance = outerDist;

            int innerDist = (int)(_splitInner.Width * 0.55);
            if (innerDist > _splitInner.Panel1MinSize)
                _splitInner.SplitterDistance = innerDist;
        }
        catch (Exception ex)
        {
            _logger.Log("WARN", $"Splitter layout error during initial form display: {ex.Message}", "REF_LAYOUT");
        }
    }

    // ── Public API ───────────────────────────────────────────────────────

    /// <summary>
    /// Loads the specified file into the reference panel.
    /// </summary>
    public bool OpenFile(string filePath)
    {
        _lblMatchStatus.Visible = false;
        _lblMatchStatus.Text = "";

        bool success = _fileLoader.LoadFile(filePath, _ctx, _gridNav);

        if (success)
        {
            var fileName = Path.GetFileName(filePath);
            Text = $"PARRAT Reference - {fileName}";
            _lblStatus.Text = $"Reference: {fileName} ({_ctx.RecordCount} {(_ctx.FileType == "hl7" ? "messages" : "tumors")})";
            _lblFileName.Text = $"File: {filePath}";

            _pnlSearch.Visible = true;
            _txtSearch.Text = "";
            _lblSearchCount.Text = "";

            _navService.ShowRecord(0);
        }

        return success;
    }

    /// <summary>
    /// Searches the reference file for records matching the given key fields.
    /// Called by MainForm's "Find in Reference" button.
    ///
    /// Matching strategy:
    /// - Exact match on DOB and pathReportNumber (when provided)
    /// - Case-insensitive match on names
    /// - Single match: navigates directly
    /// - Multiple matches: filters grid to candidates
    /// - Zero matches: shows status message, does not change grid
    /// </summary>
    public void FindByKeyFields(string? lastName, string? firstName, string? middleName, string? dob, string? pathReportNumber)
    {
        if (_ctx.NavTable == null || _ctx.RecordCount == 0)
        {
            ShowMatchStatus("No reference file loaded", isWarning: true);
            return;
        }

        var matchingIndices = new List<int>();
        var table = _ctx.NavTable;

        string lastLower = (lastName ?? "").Trim().ToLowerInvariant();
        string firstLower = (firstName ?? "").Trim().ToLowerInvariant();
        string dobTrimmed = (dob ?? "").Trim();
        string pathTrimmed = (pathReportNumber ?? "").Trim();

        foreach (DataRow row in table.Rows)
        {
            int index = Convert.ToInt32(row["Index"]);

            // Name matching (case-insensitive)
            string rowLast = (row.Table.Columns.Contains("nameLast") ? row["nameLast"]?.ToString() ?? "" : "").Trim().ToLowerInvariant();
            string rowFirst = (row.Table.Columns.Contains("nameFirst") ? row["nameFirst"]?.ToString() ?? "" : "").Trim().ToLowerInvariant();

            bool lastMatch = string.IsNullOrEmpty(lastLower) || rowLast == lastLower;
            bool firstMatch = string.IsNullOrEmpty(firstLower) || rowFirst == firstLower;

            // DOB matching (exact)
            bool dobMatch = true;
            if (!string.IsNullOrEmpty(dobTrimmed) && row.Table.Columns.Contains("dateOfBirth"))
            {
                string rowDob = (row["dateOfBirth"]?.ToString() ?? "").Trim();
                dobMatch = rowDob == dobTrimmed;
            }

            // Path report number matching (exact — checks pathReportNumber1 for XML, accessionNumber for HL7)
            bool pathMatch = true;
            if (!string.IsNullOrEmpty(pathTrimmed))
            {
                if (row.Table.Columns.Contains("pathReportNumber1"))
                {
                    string rowPath = (row["pathReportNumber1"]?.ToString() ?? "").Trim();
                    pathMatch = rowPath == pathTrimmed;
                }
                else if (row.Table.Columns.Contains("accessionNumber"))
                {
                    string rowAccession = (row["accessionNumber"]?.ToString() ?? "").Trim();
                    pathMatch = rowAccession == pathTrimmed;
                }
            }

            if (lastMatch && firstMatch && dobMatch && pathMatch)
                matchingIndices.Add(index);
        }

        if (matchingIndices.Count == 0)
        {
            // Try relaxed match: DOB + last name only
            matchingIndices = FindRelaxedMatches(table, lastLower, dobTrimmed);

            if (matchingIndices.Count == 0)
            {
                ShowMatchStatus("No match found in reference file", isWarning: true);
                // Clear any previous filter
                table.DefaultView.RowFilter = "";
                return;
            }

            ShowMatchStatus($"{matchingIndices.Count} possible match(es) found (relaxed: last name + DOB)", isWarning: false);
        }

        if (matchingIndices.Count == 1)
        {
            // Single match: clear filter and navigate directly
            table.DefaultView.RowFilter = "";
            ShowMatchStatus("Match found", isWarning: false);
            _navService.ShowRecord(matchingIndices[0] - 1); // Convert 1-based to 0-based
        }
        else
        {
            // Multiple matches: filter grid to candidates
            table.DefaultView.RowFilter = $"Index IN ({string.Join(",", matchingIndices)})";
            ShowMatchStatus($"{matchingIndices.Count} candidates found - select one to view", isWarning: false);

            // Navigate to first candidate
            _navService.ShowRecord(matchingIndices[0] - 1);
        }

        // Bring this window to the front
        if (WindowState == FormWindowState.Minimized)
            WindowState = FormWindowState.Normal;
        BringToFront();
    }

    /// <summary>
    /// Clears the match filter and status.
    /// </summary>
    public void ClearMatchFilter()
    {
        if (_ctx.NavTable != null)
            _ctx.NavTable.DefaultView.RowFilter = "";
        _lblMatchStatus.Visible = false;
        _lblMatchStatus.Text = "";
    }

    /// <summary>
    /// Called by MainForm when the primary record changes. If auto-sync is
    /// enabled, triggers a debounced FindByKeyFields after 250ms of inactivity.
    /// </summary>
    public void NotifyPrimaryRecordChanged(string? lastName, string? firstName, string? dob, string? pathReport)
    {
        if (!_chkAutoSync.Checked) return;

        _pendingLast = lastName;
        _pendingFirst = firstName;
        _pendingDob = dob;
        _pendingPath = pathReport;

        if (_autoSyncTimer == null)
        {
            _autoSyncTimer = new System.Windows.Forms.Timer { Interval = 250 };
            _autoSyncTimer.Tick += (s, e) =>
            {
                _autoSyncTimer.Stop();
                AutoSyncFind();
            };
        }

        _autoSyncTimer.Stop();
        _autoSyncTimer.Start();
    }

    private void AutoSyncFind()
    {
        if (_ctx.NavTable == null || _ctx.RecordCount == 0) return;

        // Use the same matching logic but silently skip on no-match
        var table = _ctx.NavTable;
        string lastLower = (_pendingLast ?? "").Trim().ToLowerInvariant();
        string firstLower = (_pendingFirst ?? "").Trim().ToLowerInvariant();
        string dobTrimmed = (_pendingDob ?? "").Trim();
        string pathTrimmed = (_pendingPath ?? "").Trim();

        var matchingIndices = new List<int>();

        foreach (DataRow row in table.Rows)
        {
            int index = Convert.ToInt32(row["Index"]);

            string rowLast = (row.Table.Columns.Contains("nameLast") ? row["nameLast"]?.ToString() ?? "" : "").Trim().ToLowerInvariant();
            string rowFirst = (row.Table.Columns.Contains("nameFirst") ? row["nameFirst"]?.ToString() ?? "" : "").Trim().ToLowerInvariant();

            bool lastMatch = string.IsNullOrEmpty(lastLower) || rowLast == lastLower;
            bool firstMatch = string.IsNullOrEmpty(firstLower) || rowFirst == firstLower;

            bool dobMatch = true;
            if (!string.IsNullOrEmpty(dobTrimmed) && row.Table.Columns.Contains("dateOfBirth"))
            {
                string rowDob = (row["dateOfBirth"]?.ToString() ?? "").Trim();
                dobMatch = rowDob == dobTrimmed;
            }

            bool pathMatch = true;
            if (!string.IsNullOrEmpty(pathTrimmed))
            {
                if (row.Table.Columns.Contains("pathReportNumber1"))
                {
                    string rowPath = (row["pathReportNumber1"]?.ToString() ?? "").Trim();
                    pathMatch = rowPath == pathTrimmed;
                }
                else if (row.Table.Columns.Contains("accessionNumber"))
                {
                    string rowAccession = (row["accessionNumber"]?.ToString() ?? "").Trim();
                    pathMatch = rowAccession == pathTrimmed;
                }
            }

            if (lastMatch && firstMatch && dobMatch && pathMatch)
                matchingIndices.Add(index);
        }

        if (matchingIndices.Count == 0)
        {
            // Try relaxed match
            matchingIndices = FindRelaxedMatches(table, lastLower, dobTrimmed);
        }

        if (matchingIndices.Count == 0)
        {
            ShowMatchStatus("Auto-sync: no match found", isWarning: true);
            return;
        }

        if (matchingIndices.Count == 1)
        {
            table.DefaultView.RowFilter = "";
            ShowMatchStatus("Auto-sync: match found", isWarning: false);
            _navService.ShowRecord(matchingIndices[0] - 1);
        }
        else
        {
            table.DefaultView.RowFilter = $"Index IN ({string.Join(",", matchingIndices)})";
            ShowMatchStatus($"Auto-sync: {matchingIndices.Count} candidates", isWarning: false);
            _navService.ShowRecord(matchingIndices[0] - 1);
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────

    private List<int> FindRelaxedMatches(DataTable table, string lastLower, string dobTrimmed)
    {
        var matches = new List<int>();

        if (string.IsNullOrEmpty(lastLower) && string.IsNullOrEmpty(dobTrimmed))
            return matches;

        foreach (DataRow row in table.Rows)
        {
            int index = Convert.ToInt32(row["Index"]);

            bool lastMatch = true;
            if (!string.IsNullOrEmpty(lastLower) && row.Table.Columns.Contains("nameLast"))
            {
                string rowLast = (row["nameLast"]?.ToString() ?? "").Trim().ToLowerInvariant();
                lastMatch = rowLast == lastLower;
            }

            bool dobMatch = true;
            if (!string.IsNullOrEmpty(dobTrimmed) && row.Table.Columns.Contains("dateOfBirth"))
            {
                string rowDob = (row["dateOfBirth"]?.ToString() ?? "").Trim();
                dobMatch = rowDob == dobTrimmed;
            }

            if (lastMatch && dobMatch)
                matches.Add(index);
        }

        return matches;
    }

    private void ShowMatchStatus(string message, bool isWarning)
    {
        _lblMatchStatus.Text = message;
        _lblMatchStatus.ForeColor = isWarning ? Color.DarkRed : Color.DarkSlateGray;
        _lblMatchStatus.Visible = true;
    }

    // ── Search ───────────────────────────────────────────────────────────

    private void HandleSearchTextChanged()
    {
        if (_searchTimer == null)
        {
            _searchTimer = new System.Windows.Forms.Timer { Interval = 200 };
            _searchTimer.Tick += (s, e) =>
            {
                try
                {
                    _searchTimer.Stop();

                    var searchText = _txtSearch.Text;
                    var navTable = _ctx.NavTable;
                    var searchIndex = _ctx.SearchIndex;

                    if (navTable == null) return;

                    var searchService = new SearchService(_logger);
                    searchService.ApplyFilter(searchText, navTable, searchIndex);

                    int totalCount = searchIndex.Length;

                    if (string.IsNullOrWhiteSpace(searchText))
                    {
                        _lblSearchCount.Text = "";
                    }
                    else
                    {
                        int matchCount = navTable.DefaultView.Count;
                        _lblSearchCount.Text = $"{matchCount} / {totalCount}";
                    }

                    searchService.HighlightMatches(_rtbPath, searchText);
                    searchService.HighlightMatches(_rtbItems, searchText);
                }
                catch (Exception ex)
                {
                    _logger.LogError("Reference search filter failed", "REF_SEARCH", ex);
                }
            };
        }

        _searchTimer.Stop();
        _searchTimer.Start();
    }

    // ── Keyboard shortcuts ───────────────────────────────────────────────

    private void OnFormKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Control && e.KeyCode == Keys.F && _pnlSearch.Visible)
        {
            _txtSearch.Focus();
            _txtSearch.SelectAll();
            e.Handled = true;
        }
        else if (e.KeyCode == Keys.Escape && _txtSearch.Focused)
        {
            _txtSearch.Text = "";
            e.Handled = true;
        }
    }

    // ── Copy button click ────────────────────────────────────────────────

    private void OnCopyFieldClick(object? sender, EventArgs e)
    {
        if (sender is not Button btn) return;
        var value = btn.Tag?.ToString();
        if (string.IsNullOrEmpty(value)) return;

        Clipboard.SetDataObject(value, true);

        // Flash green feedback
        var origBack = btn.BackColor;
        var origBorder = btn.FlatAppearance.BorderColor;
        btn.BackColor = Color.FromArgb(200, 235, 200);
        btn.FlatAppearance.BorderColor = Color.Green;

        var flashTimer = new System.Windows.Forms.Timer { Interval = 800 };
        flashTimer.Tick += (s2, e2) =>
        {
            flashTimer.Stop();
            btn.BackColor = origBack;
            btn.FlatAppearance.BorderColor = origBorder;
            flashTimer.Dispose();
        };
        flashTimer.Start();
    }
}
