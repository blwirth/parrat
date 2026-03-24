using System.Data;
using System.Drawing;
using System.Windows.Forms;
using Parat.Core.Interfaces;
using Parat.Core.Models;

namespace Parat.UI.Forms;

/// <summary>
/// Editor for topography and laterality lookup tables.
/// Ported from Show-CodingTableEditor in ui/coding-table-editor-ui.ps1.
/// </summary>
public class CodingTableEditorForm : Form
{
    private readonly ISiteLateralityService _siteLateralityService;
    private readonly string _tableType; // "laterality" or "topography"
    private string _filePath;
    private bool _isDirty;

    private DataGridView _grid = null!;
    private DataTable _table = null!;
    private Label _lblFile = null!;
    private Label _lblCount = null!;

    public CodingTableEditorForm(
        ISiteLateralityService siteLateralityService,
        string filePath,
        string tableType,
        string title)
    {
        _siteLateralityService = siteLateralityService;
        _filePath = filePath;
        _tableType = tableType;
        InitializeControls(title);
    }

    private void InitializeControls(string title)
    {
        // Load data
        List<TopographyEntry>? topoData = null;
        Dictionary<string, bool>? latData = null;

        try
        {
            if (_tableType == "topography")
                topoData = _siteLateralityService.ReadTopographyJson(_filePath);
            else
                latData = _siteLateralityService.ReadLateralityJson(_filePath);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to load file: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        // ── Form properties ──────────────────────────────────────────────
        Text = $"Edit Coding Table: {title}";
        Width = 700;
        Height = 600;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(500, 400);

        // ── File info label ──────────────────────────────────────────────
        _lblFile = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(660, 20),
            Text = $"File: {_filePath}",
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        Controls.Add(_lblFile);

        // ── Toolbar panel ────────────────────────────────────────────────
        var toolPanel = new Panel
        {
            Location = new Point(10, 35),
            Size = new Size(660, 35),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };

        var btnAddRow = new Button
        {
            Text = "Add Row",
            Location = new Point(0, 5),
            Width = 80
        };
        btnAddRow.Click += OnAddRow;

        var btnDeleteRow = new Button
        {
            Text = "Delete Selected",
            Location = new Point(90, 5),
            Width = 100
        };
        btnDeleteRow.Click += OnDeleteRow;

        int dataCount = _tableType == "topography" ? (topoData?.Count ?? 0) : (latData?.Count ?? 0);
        _lblCount = new Label
        {
            Location = new Point(200, 10),
            AutoSize = true,
            Text = $"Rows: {dataCount}"
        };

        toolPanel.Controls.AddRange(new Control[] { btnAddRow, btnDeleteRow, _lblCount });
        Controls.Add(toolPanel);

        // ── DataGridView ─────────────────────────────────────────────────
        _grid = new DataGridView
        {
            Location = new Point(10, 75),
            Size = new Size(660, 430),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            AllowUserToAddRows = true,
            AllowUserToDeleteRows = true,
            ReadOnly = false,
            MultiSelect = true,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            RowHeadersVisible = true
        };

        // Create DataTable
        _table = new DataTable();
        _table.Columns.Add("Code", typeof(string));
        if (_tableType == "topography")
            _table.Columns.Add("SearchPhrase", typeof(string));

        // Load data into table
        if (_tableType == "topography" && topoData != null)
        {
            foreach (var item in topoData)
            {
                var row = _table.NewRow();
                row["Code"] = item.Code;
                row["SearchPhrase"] = item.SearchPhrase;
                _table.Rows.Add(row);
            }
        }
        else if (latData != null)
        {
            foreach (var kvp in latData)
            {
                var row = _table.NewRow();
                row["Code"] = kvp.Key;
                _table.Rows.Add(row);
            }
        }

        _grid.DataSource = _table;

        // Configure columns
        if (_grid.Columns["Code"] != null)
        {
            _grid.Columns["Code"].Width = 100;
            _grid.Columns["Code"].MinimumWidth = 80;
        }
        if (_tableType == "topography" && _grid.Columns["SearchPhrase"] != null)
        {
            _grid.Columns["SearchPhrase"].AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
        }

        // Track changes
        _table.RowChanged += (_, _) => { _isDirty = true; UpdateRowCount(); };
        _table.RowDeleted += (_, _) => { _isDirty = true; UpdateRowCount(); };
        _table.TableNewRow += (_, _) => { _isDirty = true; };

        Controls.Add(_grid);

        // ── Button panel ─────────────────────────────────────────────────
        var buttonPanel = new Panel
        {
            Location = new Point(10, 515),
            Size = new Size(660, 40),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
        };

        var btnSave = new Button
        {
            Text = "Save",
            Location = new Point(0, 5),
            Width = 80
        };
        btnSave.Click += OnSave;

        var btnSaveAs = new Button
        {
            Text = "Save As...",
            Location = new Point(90, 5),
            Width = 80
        };
        btnSaveAs.Click += OnSaveAs;

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(180, 5),
            Width = 80
        };
        btnCancel.Click += OnCancelClick;

        buttonPanel.Controls.AddRange(new Control[] { btnSave, btnSaveAs, btnCancel });
        Controls.Add(buttonPanel);

        // ── Form closing ─────────────────────────────────────────────────
        FormClosing += OnFormClosing;
    }

    private void UpdateRowCount()
    {
        int rowCount = 0;
        foreach (DataRow row in _table.Rows)
        {
            if (row.RowState != DataRowState.Deleted
                && !string.IsNullOrWhiteSpace(row["Code"]?.ToString()))
            {
                rowCount++;
            }
        }
        _lblCount.Text = $"Rows: {rowCount}";
    }

    private List<TopographyEntry> GetTableDataAsTopography()
    {
        var items = new List<TopographyEntry>();
        foreach (DataRow row in _table.Rows)
        {
            if (row.RowState == DataRowState.Deleted) continue;
            var code = row["Code"]?.ToString();
            if (string.IsNullOrWhiteSpace(code)) continue;

            items.Add(new TopographyEntry
            {
                Code = FormatSiteCode(code),
                SearchPhrase = row["SearchPhrase"]?.ToString() ?? ""
            });
        }
        return items;
    }

    private List<string> GetTableDataAsCodes()
    {
        var items = new List<string>();
        foreach (DataRow row in _table.Rows)
        {
            if (row.RowState == DataRowState.Deleted) continue;
            var code = row["Code"]?.ToString();
            if (string.IsNullOrWhiteSpace(code)) continue;
            items.Add(FormatSiteCode(code));
        }
        return items;
    }

    private static string FormatSiteCode(string code)
    {
        code = code.Trim().ToUpperInvariant();
        if (System.Text.RegularExpressions.Regex.IsMatch(code, @"^\d{1,3}$"))
            return "C" + code.PadLeft(3, '0');
        if (System.Text.RegularExpressions.Regex.IsMatch(code, @"^C\d{1,2}$"))
            return "C" + code[1..].PadLeft(3, '0');
        return code;
    }

    private void OnAddRow(object? sender, EventArgs e)
    {
        var newRow = _table.NewRow();
        newRow["Code"] = "";
        if (_tableType == "topography")
            newRow["SearchPhrase"] = "";
        _table.Rows.Add(newRow);

        _grid.ClearSelection();
        var lastRowIndex = _grid.Rows.Count - 2; // -2 because of the "new row" placeholder
        if (lastRowIndex >= 0)
        {
            _grid.Rows[lastRowIndex].Selected = true;
            _grid.CurrentCell = _grid.Rows[lastRowIndex].Cells[0];
            _grid.BeginEdit(true);
        }

        _isDirty = true;
        UpdateRowCount();
    }

    private void OnDeleteRow(object? sender, EventArgs e)
    {
        if (_grid.SelectedRows.Count == 0)
        {
            MessageBox.Show("Please select one or more rows to delete.",
                "No Selection", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var result = MessageBox.Show(
            $"Delete {_grid.SelectedRows.Count} selected row(s)?",
            "Confirm Delete", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (result != DialogResult.Yes) return;

        var indicesToDelete = new List<int>();
        foreach (DataGridViewRow row in _grid.SelectedRows)
        {
            if (!row.IsNewRow)
                indicesToDelete.Add(row.Index);
        }

        indicesToDelete.Sort();
        indicesToDelete.Reverse();

        foreach (var idx in indicesToDelete)
        {
            if (idx >= 0 && idx < _table.Rows.Count)
                _table.Rows[idx].Delete();
        }

        _isDirty = true;
        UpdateRowCount();
    }

    private void OnSave(object? sender, EventArgs e)
    {
        try
        {
            _grid.EndEdit();
            SaveToFile(_filePath);
            _isDirty = false;

            MessageBox.Show($"File saved successfully.\n\n{_filePath}",
                "Saved", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to save file: {ex.Message}",
                "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnSaveAs(object? sender, EventArgs e)
    {
        try
        {
            _grid.EndEdit();

            using var saveDialog = new SaveFileDialog
            {
                Title = "Save Coding Table As",
                InitialDirectory = Path.GetDirectoryName(_filePath) ?? ""
            };

            if (_tableType == "laterality")
            {
                saveDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*";
                saveDialog.DefaultExt = "json";
            }
            else
            {
                saveDialog.Filter = "JSONL Files (*.jsonl)|*.jsonl|All Files (*.*)|*.*";
                saveDialog.DefaultExt = "jsonl";
            }
            saveDialog.FileName = Path.GetFileName(_filePath);

            if (saveDialog.ShowDialog() != DialogResult.OK) return;

            SaveToFile(saveDialog.FileName);
            _isDirty = false;
            _filePath = saveDialog.FileName;
            _lblFile.Text = $"File: {_filePath}";

            MessageBox.Show($"File saved successfully.\n\n{saveDialog.FileName}",
                "Saved", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to save file: {ex.Message}",
                "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void SaveToFile(string path)
    {
        if (_tableType == "topography")
        {
            var items = GetTableDataAsTopography();
            if (items.Count == 0)
            {
                var result = MessageBox.Show("The table is empty. Save anyway?",
                    "Empty Table", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (result != DialogResult.Yes) return;
            }
            // Write as JSONL: one JSON object per line
            var lines = items.Select(item =>
                System.Text.Json.JsonSerializer.Serialize(new { code = item.Code, searchPhrase = item.SearchPhrase }));
            File.WriteAllLines(path, lines);
        }
        else
        {
            var codes = GetTableDataAsCodes();
            if (codes.Count == 0)
            {
                var result = MessageBox.Show("The table is empty. Save anyway?",
                    "Empty Table", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (result != DialogResult.Yes) return;
            }
            var json = System.Text.Json.JsonSerializer.Serialize(codes,
                new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(path, json);
        }
    }

    private void OnCancelClick(object? sender, EventArgs e)
    {
        if (_isDirty)
        {
            var result = MessageBox.Show("You have unsaved changes. Discard them?",
                "Unsaved Changes", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (result != DialogResult.Yes) return;
            _isDirty = false;
        }
        Close();
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (_isDirty)
        {
            var result = MessageBox.Show("You have unsaved changes. Discard them?",
                "Unsaved Changes", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (result != DialogResult.Yes)
                e.Cancel = true;
        }
    }
}
