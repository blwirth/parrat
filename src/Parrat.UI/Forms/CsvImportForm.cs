using System.Data;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// CSV-to-NAACCR XML import dialog with column mapping, auto-match,
/// field picker, and live preview/validation.
/// </summary>
public class CsvImportForm : ParratFormBase
{
    private readonly INaaccrDictionary _dictionary;
    private readonly ICsvImportService _importService;
    private readonly CsvParseResult _csvData;
    private readonly List<CsvImportMapping> _mappings;
    private readonly int _initialVersion;

    // Controls — top zone
    private Label _lblFileInfo = null!;
    private ComboBox _cboVersion = null!;
    private Button _btnAutoMatch = null!;
    private Button _btnClearAll = null!;

    // Controls — mapping grid (left)
    private DataGridView _gridMappings = null!;

    // Controls — preview/validation (right)
    private Label _lblPreviewSummary = null!;
    private Label _lblWarnings = null!;
    private DataGridView _gridPreview = null!;

    // Controls — bottom
    private Button _btnImport = null!;
    private Button _btnCancel = null!;

    /// <summary>Gets the final column mappings after the dialog closes.</summary>
    public List<CsvImportMapping> ResultMappings => _mappings.ToList();

    /// <summary>Gets the selected record type.</summary>
    public string RecordType => "A";

    /// <summary>Gets the selected NAACCR version.</summary>
    public int NaaccrVersion => int.TryParse(_cboVersion.SelectedItem?.ToString()?.Replace("v", ""), out var v) ? v : 25;

    public CsvImportForm(
        INaaccrDictionary dictionary,
        ICsvImportService importService,
        CsvParseResult csvData,
        List<CsvImportMapping> initialMappings,
        int initialVersion = 25)
    {
        _dictionary = dictionary;
        _importService = importService;
        _initialVersion = initialVersion;
        _csvData = csvData;
        _mappings = initialMappings.Select(m => new CsvImportMapping
        {
            CsvColumnIndex = m.CsvColumnIndex,
            CsvHeader = m.CsvHeader,
            MappedNaaccrId = m.MappedNaaccrId,
            IsAutoMatched = m.IsAutoMatched
        }).ToList();

        InitializeComponents();

        Shown += (_, _) =>
        {
            PopulateMappingGrid();
            UpdatePreviewAndValidation();
        };
    }

    private void InitializeComponents()
    {
        Text = "Import CSV — Map Columns to NAACCR Fields";
        Width = 1100;
        Height = 700;
        MinimumSize = new Size(900, 550);
        StartPosition = FormStartPosition.CenterScreen;

        // ===== TOP ZONE: File info & controls =====
        var topPanel = new Panel
        {
            Location = new Point(10, 10),
            Size = new Size(1060, 55),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };

        _lblFileInfo = new Label
        {
            Location = new Point(0, 0),
            Size = new Size(600, 20),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            Text = $"{_csvData.ColumnCount} columns, {_csvData.RowCount} data rows"
        };

        var lblVersion = new Label
        {
            Text = "NAACCR Version:",
            Location = new Point(0, 28),
            AutoSize = true
        };

        _cboVersion = new ComboBox
        {
            Location = new Point(105, 25),
            Width = 55,
            DropDownStyle = ComboBoxStyle.DropDownList
        };
        _cboVersion.Items.AddRange(new object[] { "v25", "v26" });
        _cboVersion.SelectedItem = $"v{_initialVersion}";
        _cboVersion.SelectedIndexChanged += (_, _) => OnVersionChanged();

        _btnAutoMatch = new Button
        {
            Text = "Auto-Match",
            Location = new Point(175, 24),
            Width = 90
        };
        _btnAutoMatch.Click += (_, _) => RunAutoMatch();

        _btnClearAll = new Button
        {
            Text = "Clear All",
            Location = new Point(275, 24),
            Width = 80
        };
        _btnClearAll.Click += (_, _) => ClearAllMappings();

        topPanel.Controls.AddRange(new Control[] { _lblFileInfo, lblVersion, _cboVersion, _btnAutoMatch, _btnClearAll });

        // ===== MIDDLE ZONE: Split between mapping grid and preview =====
        var splitContainer = new SplitContainer
        {
            Location = new Point(10, 70),
            Size = new Size(1060, 535),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            Orientation = Orientation.Vertical,
            SplitterDistance = 620,
            Panel1MinSize = 400,
            Panel2MinSize = 250
        };

        // ── Left: Mapping Grid ──
        var lblMappings = new Label
        {
            Text = "Column Mappings (click NAACCR Field to change):",
            Location = new Point(0, 0),
            AutoSize = true,
            Font = new Font("Segoe UI", 9, FontStyle.Bold)
        };

        _gridMappings = new DataGridView
        {
            Location = new Point(0, 22),
            Size = new Size(600, 500),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            RowHeadersVisible = false,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None,
            ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.AutoSize
        };
        _gridMappings.CellDoubleClick += GridMappings_CellDoubleClick;
        _gridMappings.KeyDown += GridMappings_KeyDown;

        splitContainer.Panel1.Controls.AddRange(new Control[] { lblMappings, _gridMappings });
        splitContainer.Panel1.Padding = new Padding(0, 0, 5, 0);

        // Resize mapping grid when panel resizes
        splitContainer.Panel1.Resize += (_, _) =>
        {
            _gridMappings.Size = new Size(
                splitContainer.Panel1.ClientSize.Width - 5,
                splitContainer.Panel1.ClientSize.Height - 25);
        };

        // ── Right: Preview & Validation ──
        _lblPreviewSummary = new Label
        {
            Location = new Point(0, 0),
            AutoSize = false,
            Size = new Size(400, 20),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            Font = new Font("Segoe UI", 9, FontStyle.Bold)
        };

        _lblWarnings = new Label
        {
            Location = new Point(0, 22),
            AutoSize = true,
            MaximumSize = new Size(400, 60),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            ForeColor = Color.FromArgb(180, 0, 0)
        };

        _gridPreview = new DataGridView
        {
            Location = new Point(0, 45),
            Size = new Size(400, 480),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            RowHeadersVisible = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None,
            ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.AutoSize
        };

        splitContainer.Panel2.Controls.AddRange(new Control[] { _lblPreviewSummary, _lblWarnings, _gridPreview });

        // Resize preview grid when panel resizes
        splitContainer.Panel2.Resize += (_, _) =>
        {
            var w = splitContainer.Panel2.ClientSize.Width;
            _lblPreviewSummary.Width = w;
            _lblWarnings.Width = w;
            _gridPreview.Size = new Size(w, splitContainer.Panel2.ClientSize.Height - 48);
        };

        // ===== BOTTOM ZONE =====
        var bottomPanel = new Panel
        {
            Location = new Point(10, 612),
            Size = new Size(300, 40),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };

        _btnImport = new Button
        {
            Text = "Import",
            Width = 100,
            Location = new Point(0, 5),
            DialogResult = DialogResult.OK
        };

        _btnCancel = new Button
        {
            Text = "Cancel",
            Width = 100,
            Location = new Point(110, 5),
            DialogResult = DialogResult.Cancel
        };

        bottomPanel.Controls.AddRange(new Control[] { _btnImport, _btnCancel });

        Controls.AddRange(new Control[] { topPanel, splitContainer, bottomPanel });
        AcceptButton = _btnImport;
        CancelButton = _btnCancel;
    }

    // ── Mapping Grid ─────────────────────────────────────────────────────

    private void PopulateMappingGrid()
    {
        var table = new DataTable();
        table.Columns.Add("CSV Column", typeof(string));
        table.Columns.Add("Sample Data", typeof(string));
        table.Columns.Add("NAACCR Field", typeof(string));
        table.Columns.Add("Status", typeof(string));
        table.Columns.Add("Parent", typeof(string));

        foreach (var m in _mappings)
        {
            var samples = GetSampleData(m.CsvColumnIndex, 3);
            var naaccrDisplay = m.IsSkipped ? "(unmapped — click to map)" : _dictionary.GetDisplayName(m.MappedNaaccrId!);
            var status = m.IsSkipped ? "" : (m.IsAutoMatched ? "Auto" : "Manual");
            var parent = m.IsSkipped ? "" : _dictionary.GetParentElement(m.MappedNaaccrId!);

            table.Rows.Add(m.CsvHeader, samples, naaccrDisplay, status, parent);
        }

        _gridMappings.DataSource = table;

        // Column widths
        if (_gridMappings.Columns.Count >= 5)
        {
            _gridMappings.Columns[0].Width = 120;  // CSV Column
            _gridMappings.Columns[1].Width = 180;  // Sample Data
            _gridMappings.Columns[2].Width = 200;  // NAACCR Field
            _gridMappings.Columns[3].Width = 55;   // Status
            _gridMappings.Columns[4].Width = 70;    // Parent
        }

        // Color rows
        ApplyRowColors();
    }

    private void ApplyRowColors()
    {
        for (int i = 0; i < _gridMappings.Rows.Count && i < _mappings.Count; i++)
        {
            var row = _gridMappings.Rows[i];
            if (_mappings[i].IsSkipped)
            {
                row.DefaultCellStyle.BackColor = Color.FromArgb(255, 255, 230); // Light yellow
            }
            else if (_mappings[i].IsAutoMatched)
            {
                row.DefaultCellStyle.BackColor = Color.FromArgb(230, 255, 230); // Light green
            }
            else
            {
                row.DefaultCellStyle.BackColor = Color.FromArgb(230, 240, 255); // Light blue
            }
        }
    }

    private string GetSampleData(int columnIndex, int maxRows)
    {
        var samples = _csvData.Rows
            .Take(maxRows)
            .Select(r => columnIndex < r.Length ? r[columnIndex] : "")
            .Where(v => !string.IsNullOrEmpty(v));
        return string.Join(" | ", samples);
    }

    // ── Field Picker ─────────────────────────────────────────────────────

    private void GridMappings_CellDoubleClick(object? sender, DataGridViewCellEventArgs e)
    {
        if (e.RowIndex < 0 || e.RowIndex >= _mappings.Count) return;
        OpenFieldPicker(e.RowIndex);
    }

    private void GridMappings_KeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space)
        {
            if (_gridMappings.CurrentRow != null)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                OpenFieldPicker(_gridMappings.CurrentRow.Index);
            }
        }
        else if (e.KeyCode == Keys.Delete || e.KeyCode == Keys.Back)
        {
            if (_gridMappings.CurrentRow != null)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
                var idx = _gridMappings.CurrentRow.Index;
                if (idx >= 0 && idx < _mappings.Count)
                {
                    _mappings[idx].MappedNaaccrId = null;
                    _mappings[idx].IsAutoMatched = false;
                    PopulateMappingGrid();
                    UpdatePreviewAndValidation();
                }
            }
        }
    }

    private void OpenFieldPicker(int mappingIndex)
    {
        var mapping = _mappings[mappingIndex];

        using var picker = new NaaccrFieldPickerDialog(_dictionary, mapping.MappedNaaccrId);
        if (picker.ShowDialog(this) != DialogResult.OK) return;

        var selectedId = picker.SelectedXmlId;
        if (selectedId == null)
        {
            // User chose "unmapped"
            mapping.MappedNaaccrId = null;
            mapping.IsAutoMatched = false;
        }
        else
        {
            mapping.MappedNaaccrId = selectedId;
            mapping.IsAutoMatched = false; // Manual selection
        }

        PopulateMappingGrid();
        UpdatePreviewAndValidation();
    }

    // ── Version / Auto-Match / Clear ────────────────────────────────────

    private void OnVersionChanged()
    {
        // Re-initialize dictionary for the selected version
        _dictionary.Initialize(NaaccrVersion);

        // Clear all mappings and re-run auto-match with the new version's dictionary
        foreach (var m in _mappings)
        {
            m.MappedNaaccrId = null;
            m.IsAutoMatched = false;
        }

        RunAutoMatch();
    }

    private void RunAutoMatch()
    {
        var usedIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Keep existing manual mappings
        foreach (var m in _mappings)
        {
            if (!m.IsSkipped)
            {
                usedIds.Add(m.MappedNaaccrId!);
            }
        }

        // Re-auto-match unmapped columns
        var headers = _mappings.Select(m => m.CsvHeader).ToArray();
        var freshMatch = _importService.AutoMatch(headers, NaaccrVersion);

        foreach (var m in _mappings)
        {
            if (m.IsSkipped)
            {
                var fresh = freshMatch.FirstOrDefault(f => f.CsvColumnIndex == m.CsvColumnIndex);
                if (fresh != null && !fresh.IsSkipped && !usedIds.Contains(fresh.MappedNaaccrId!))
                {
                    m.MappedNaaccrId = fresh.MappedNaaccrId;
                    m.IsAutoMatched = true;
                    usedIds.Add(fresh.MappedNaaccrId!);
                }
            }
        }

        PopulateMappingGrid();
        UpdatePreviewAndValidation();
    }

    private void ClearAllMappings()
    {
        foreach (var m in _mappings)
        {
            m.MappedNaaccrId = null;
            m.IsAutoMatched = false;
        }

        PopulateMappingGrid();
        UpdatePreviewAndValidation();
    }

    // ── Preview & Validation ─────────────────────────────────────────────

    private void UpdatePreviewAndValidation()
    {
        var warnings = new List<string>();
        var activeMappings = _mappings.Where(m => !m.IsSkipped).ToList();
        var unmappedCount = _mappings.Count(m => m.IsSkipped);

        // Check for patient ID
        bool hasPatientId = activeMappings.Any(m => m.MappedNaaccrId == "patientIdNumber");
        if (!hasPatientId)
            warnings.Add("No patient ID mapped — each row will be a separate patient.");

        // Check for duplicate mappings
        var dupes = activeMappings
            .GroupBy(m => m.MappedNaaccrId, StringComparer.OrdinalIgnoreCase)
            .Where(g => g.Count() > 1);
        foreach (var dupe in dupes)
        {
            var cols = string.Join(", ", dupe.Select(m => m.CsvHeader));
            warnings.Add($"Duplicate: '{dupe.Key}' mapped from columns: {cols}");
        }

        if (unmappedCount > 0)
            warnings.Add($"{unmappedCount} column(s) unmapped (will be skipped).");

        // Compute patient/tumor counts
        int patientCount, tumorCount;
        if (hasPatientId)
        {
            var pidMapping = activeMappings.First(m => m.MappedNaaccrId == "patientIdNumber");
            var groups = _csvData.Rows
                .GroupBy(r => pidMapping.CsvColumnIndex < r.Length ? r[pidMapping.CsvColumnIndex] : "")
                .Count();
            patientCount = groups;
            tumorCount = _csvData.RowCount;
        }
        else
        {
            patientCount = _csvData.RowCount;
            tumorCount = _csvData.RowCount;
        }

        _lblPreviewSummary.Text = $"Preview: {patientCount} patient(s), {tumorCount} tumor(s)";
        _lblWarnings.Text = string.Join("\n", warnings);

        // Build preview table (first 20 rows, mapped columns only)
        var previewTable = new DataTable();
        foreach (var m in activeMappings)
        {
            previewTable.Columns.Add(m.MappedNaaccrId, typeof(string));
        }

        var previewRows = _csvData.Rows.Take(20);
        foreach (var row in previewRows)
        {
            var dataRow = previewTable.NewRow();
            foreach (var m in activeMappings)
            {
                dataRow[m.MappedNaaccrId!] = m.CsvColumnIndex < row.Length ? row[m.CsvColumnIndex] : "";
            }
            previewTable.Rows.Add(dataRow);
        }

        _gridPreview.DataSource = previewTable;

        // Auto-fit with constraints
        _gridPreview.AutoResizeColumns(DataGridViewAutoSizeColumnsMode.AllCells);
        foreach (DataGridViewColumn col in _gridPreview.Columns)
        {
            var w = col.Width;
            col.AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
            col.MinimumWidth = 50;
            col.Width = Math.Max(Math.Min(w, 200), 50);
        }
    }
}

// ── Field Picker Dialog ──────────────────────────────────────────────────

/// <summary>
/// Popup dialog for searching and selecting a NAACCR field.
/// Shows a searchable list of all NAACCR dictionary items.
/// </summary>
internal class NaaccrFieldPickerDialog : ParratFormBase
{
    private readonly INaaccrDictionary _dictionary;
    private readonly TextBox _txtSearch;
    private readonly ListBox _lstFields;
    private readonly Button _btnOk;
    private readonly Button _btnCancel;
    private readonly Button _btnClear;

    /// <summary>Gets the selected NAACCR xmlId, or null if "unmapped" was chosen.</summary>
    public string? SelectedXmlId { get; private set; }

    public NaaccrFieldPickerDialog(INaaccrDictionary dictionary, string? currentXmlId)
    {
        _dictionary = dictionary;
        SelectedXmlId = currentXmlId;

        Text = "Select NAACCR Field";
        Width = 500;
        Height = 500;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        var lblSearch = new Label
        {
            Text = "Search (name, xmlId, or item number):",
            Location = new Point(10, 10),
            AutoSize = true
        };

        _txtSearch = new TextBox
        {
            Location = new Point(10, 30),
            Size = new Size(460, 23)
        };
        _txtSearch.TextChanged += (_, _) => PopulateList(_txtSearch.Text);

        _lstFields = new ListBox
        {
            Location = new Point(10, 60),
            Size = new Size(460, 340)
        };
        _lstFields.DoubleClick += (_, _) => AcceptSelection();

        _btnOk = new Button
        {
            Text = "OK",
            Location = new Point(200, 420),
            Width = 80,
            DialogResult = DialogResult.OK
        };
        _btnOk.Click += (_, _) => AcceptSelection();

        _btnClear = new Button
        {
            Text = "Unmap",
            Location = new Point(290, 420),
            Width = 80
        };
        _btnClear.Click += (_, _) =>
        {
            SelectedXmlId = null;
            DialogResult = DialogResult.OK;
            Close();
        };

        _btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(380, 420),
            Width = 80,
            DialogResult = DialogResult.Cancel
        };

        Controls.AddRange(new Control[] { lblSearch, _txtSearch, _lstFields, _btnOk, _btnClear, _btnCancel });
        AcceptButton = _btnOk;
        CancelButton = _btnCancel;

        Shown += (_, _) =>
        {
            PopulateList("");
            _txtSearch.Focus();
        };
    }

    private void PopulateList(string filter)
    {
        _lstFields.BeginUpdate();
        _lstFields.Items.Clear();

        var items = string.IsNullOrWhiteSpace(filter)
            ? _dictionary.GetDictionary().Values.OrderBy(i => i.NumberInt).ToList()
            : _dictionary.Search(filter);

        foreach (var item in items)
        {
            _lstFields.Items.Add($"{item.Number} - {item.Name} ({item.XmlId})");
        }

        // Pre-select current if visible
        if (SelectedXmlId != null)
        {
            for (int i = 0; i < _lstFields.Items.Count; i++)
            {
                if (_lstFields.Items[i]?.ToString()?.Contains($"({SelectedXmlId})") == true)
                {
                    _lstFields.SelectedIndex = i;
                    break;
                }
            }
        }

        _lstFields.EndUpdate();
    }

    private void AcceptSelection()
    {
        if (_lstFields.SelectedItem == null) return;

        var text = _lstFields.SelectedItem.ToString() ?? "";
        var match = System.Text.RegularExpressions.Regex.Match(text, @"\(([^)]+)\)$");
        if (match.Success)
        {
            SelectedXmlId = match.Groups[1].Value;
            DialogResult = DialogResult.OK;
            Close();
        }
    }
}
