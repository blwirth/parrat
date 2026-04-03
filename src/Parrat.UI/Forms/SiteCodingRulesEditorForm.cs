using System.Data;
using System.Drawing;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Editor for site coding rules with pattern grid, expression builder, test panel,
/// and priority ordering. Ported from ui/site-coding-rules-editor-ui.ps1.
/// </summary>
public class SiteCodingRulesEditorForm : ParratFormBase
{
    private readonly ISiteLateralityService _siteLateralityService;
    private readonly IParratLogger _logger;
    private string _filePath;
    private bool _isDirty;
    private List<SiteCodingRule> _currentPatterns;

    private DataGridView _grid = null!;
    private DataTable _gridTable = null!;
    private Label _lblFile = null!;
    private Label _lblCount = null!;

    public SiteCodingRulesEditorForm(
        ISiteLateralityService siteLateralityService,
        string filePath,
        IParratLogger logger)
    {
        _siteLateralityService = siteLateralityService;
        _filePath = filePath;
        _logger = logger;
        _currentPatterns = new List<SiteCodingRule>();

        InitializeControls();
    }

    private void InitializeControls()
    {
        // Load patterns
        try
        {
            _currentPatterns = _siteLateralityService.ReadSiteCodingRules(_filePath);
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load site coding rules file", "CODING_TABLE", ex);
            MessageBox.Show($"Failed to load file: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        // ── Form properties ──────────────────────────────────────────────
        Text = "Edit Site Coding Rules";
        Width = 900;
        Height = 600;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(700, 400);

        // ── File info label ──────────────────────────────────────────────
        _lblFile = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(860, 20),
            Text = $"File: {_filePath}",
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        Controls.Add(_lblFile);

        // ── Toolbar panel ────────────────────────────────────────────────
        var toolPanel = new Panel
        {
            Location = new Point(10, 35),
            Size = new Size(860, 35),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };

        var btnAdd = new Button { Text = "Add", Location = new Point(0, 5), Width = 70 };
        btnAdd.Click += OnAddPattern;

        var btnDelete = new Button { Text = "Delete", Location = new Point(80, 5), Width = 70 };
        btnDelete.Click += OnDeletePattern;

        var btnMoveUp = new Button { Text = "Move Up", Location = new Point(160, 5), Width = 75 };
        btnMoveUp.Click += OnMoveUp;

        var btnMoveDown = new Button { Text = "Move Down", Location = new Point(245, 5), Width = 85 };
        btnMoveDown.Click += OnMoveDown;

        _lblCount = new Label
        {
            Location = new Point(350, 10),
            AutoSize = true,
            Text = $"Rows: {_currentPatterns.Count}"
        };

        toolPanel.Controls.AddRange(new Control[] { btnAdd, btnDelete, btnMoveUp, btnMoveDown, _lblCount });
        Controls.Add(toolPanel);

        // ── DataGridView ─────────────────────────────────────────────────
        _grid = new DataGridView
        {
            Location = new Point(10, 75),
            Size = new Size(860, 430),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            ReadOnly = true,
            MultiSelect = false,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            RowHeadersVisible = false
        };

        // Create DataTable
        _gridTable = new DataTable();
        _gridTable.Columns.Add("Priority", typeof(string));
        _gridTable.Columns.Add("Code", typeof(string));
        _gridTable.Columns.Add("Expression", typeof(string));
        _gridTable.Columns.Add("Lat=9", typeof(string));
        _gridTable.Columns.Add("Enabled", typeof(string));

        LoadGridData();
        _grid.DataSource = _gridTable;

        // Configure columns
        if (_grid.Columns["Priority"] != null) _grid.Columns["Priority"].Width = 40;
        if (_grid.Columns["Code"] != null) _grid.Columns["Code"].Width = 60;
        if (_grid.Columns["Expression"] != null) _grid.Columns["Expression"].AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
        if (_grid.Columns["Lat=9"] != null) _grid.Columns["Lat=9"].Width = 45;
        if (_grid.Columns["Enabled"] != null) _grid.Columns["Enabled"].Width = 50;

        // Double-click to edit
        _grid.CellDoubleClick += OnGridCellDoubleClick;

        Controls.Add(_grid);

        // ── Button panel ─────────────────────────────────────────────────
        var buttonPanel = new Panel
        {
            Location = new Point(10, 515),
            Size = new Size(860, 40),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
        };

        var btnSave = new Button { Text = "Save", Location = new Point(0, 5), Width = 80 };
        btnSave.Click += OnSave;

        var btnSaveAs = new Button { Text = "Save As...", Location = new Point(90, 5), Width = 80 };
        btnSaveAs.Click += OnSaveAs;

        var btnCancel = new Button { Text = "Cancel", Location = new Point(180, 5), Width = 80 };
        btnCancel.Click += OnCancelClick;

        buttonPanel.Controls.AddRange(new Control[] { btnSave, btnSaveAs, btnCancel });
        Controls.Add(buttonPanel);

        // ── Form closing ─────────────────────────────────────────────────
        FormClosing += OnFormClosing;
    }

    private void LoadGridData()
    {
        _gridTable.Rows.Clear();
        int validCount = 0;
        foreach (var pattern in _currentPatterns)
        {
            if (string.IsNullOrWhiteSpace(pattern.Code)) continue;

            var preview = GetExpressionPreview(pattern.Expression, pattern.Logic);
            var enabledText = pattern.Enabled ? "true" : "";
            var forceLat = !string.IsNullOrEmpty(pattern.ForceLaterality) ? "true" : "";

            var row = _gridTable.NewRow();
            row["Priority"] = pattern.Priority.ToString();
            row["Code"] = pattern.Code;
            row["Expression"] = preview;
            row["Lat=9"] = forceLat;
            row["Enabled"] = enabledText;
            _gridTable.Rows.Add(row);
            validCount++;
        }
        _lblCount.Text = $"Rows: {validCount}";
    }

    private static string GetExpressionPreview(List<ExpressionItem> expression, string logic)
    {
        if (expression.Count == 0) return "(no terms)";

        var parts = new List<string>();
        foreach (var item in expression)
        {
            switch (item.Type)
            {
                case "term":
                    parts.Add(item.Value ?? "");
                    break;
                case "group":
                    var groupTerms = item.Terms != null ? string.Join(", ", item.Terms) : "";
                    parts.Add($"[{item.Logic}: {groupTerms}]");
                    break;
                case "topo-template":
                    parts.Add($"{{topo}}: {item.Template}");
                    break;
            }
        }

        var separator = logic == "AND" ? " AND " : " OR ";
        return string.Join(separator, parts);
    }

    // ── Event handlers ───────────────────────────────────────────────────

    private void OnAddPattern(object? sender, EventArgs e)
    {
        using var dialog = new PatternEditDialog(_siteLateralityService, "Add Pattern");
        if (dialog.ShowDialog(this) != DialogResult.OK || dialog.ResultPattern == null) return;

        _currentPatterns.Add(dialog.ResultPattern);
        _isDirty = true;
        LoadGridData();
        if (_grid.Rows.Count > 0)
            _grid.Rows[_grid.Rows.Count - 1].Selected = true;
    }

    private void OnDeletePattern(object? sender, EventArgs e)
    {
        if (_grid.SelectedRows.Count == 0)
        {
            MessageBox.Show("Please select a row to delete.", "No Selection",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var result = MessageBox.Show("Delete selected pattern?", "Confirm Delete",
            MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (result != DialogResult.Yes) return;

        var idx = _grid.SelectedRows[0].Index;
        if (idx >= 0 && idx < _currentPatterns.Count)
        {
            _currentPatterns.RemoveAt(idx);
            _isDirty = true;
            LoadGridData();
        }
    }

    private void OnMoveUp(object? sender, EventArgs e)
    {
        if (_grid.SelectedRows.Count == 0) return;
        var idx = _grid.SelectedRows[0].Index;
        if (idx <= 0) return;

        (_currentPatterns[idx], _currentPatterns[idx - 1]) = (_currentPatterns[idx - 1], _currentPatterns[idx]);
        _isDirty = true;
        LoadGridData();
        _grid.Rows[idx - 1].Selected = true;
    }

    private void OnMoveDown(object? sender, EventArgs e)
    {
        if (_grid.SelectedRows.Count == 0) return;
        var idx = _grid.SelectedRows[0].Index;
        if (idx >= _currentPatterns.Count - 1) return;

        (_currentPatterns[idx], _currentPatterns[idx + 1]) = (_currentPatterns[idx + 1], _currentPatterns[idx]);
        _isDirty = true;
        LoadGridData();
        _grid.Rows[idx + 1].Selected = true;
    }

    private void OnGridCellDoubleClick(object? sender, DataGridViewCellEventArgs e)
    {
        if (e.RowIndex < 0 || e.RowIndex >= _currentPatterns.Count) return;

        using var dialog = new PatternEditDialog(_siteLateralityService, "Edit Pattern", _currentPatterns[e.RowIndex]);
        if (dialog.ShowDialog(this) != DialogResult.OK || dialog.ResultPattern == null) return;

        _currentPatterns[e.RowIndex] = dialog.ResultPattern;
        _isDirty = true;
        LoadGridData();
        _grid.Rows[e.RowIndex].Selected = true;
    }

    private void OnSave(object? sender, EventArgs e)
    {
        try
        {
            SaveToFile(_filePath);
            _isDirty = false;
            _logger.Log("INFO", $"Site coding rules saved to {Path.GetFileName(_filePath)}", "CODING_TABLE");
            MessageBox.Show($"File saved successfully.\n\n{_filePath}", "Saved",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to save site coding rules", "CODING_TABLE", ex);
            MessageBox.Show($"Failed to save file: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnSaveAs(object? sender, EventArgs e)
    {
        using var saveDialog = new SaveFileDialog
        {
            Title = "Save Site Coding Rules As",
            InitialDirectory = Path.GetDirectoryName(_filePath) ?? "",
            Filter = "JSONL Files (*.jsonl)|*.jsonl|All Files (*.*)|*.*",
            DefaultExt = "jsonl",
            FileName = Path.GetFileName(_filePath)
        };

        if (saveDialog.ShowDialog() != DialogResult.OK) return;

        try
        {
            SaveToFile(saveDialog.FileName);
            _isDirty = false;
            _filePath = saveDialog.FileName;
            _lblFile.Text = $"File: {_filePath}";
            _logger.Log("INFO", $"Site coding rules saved as {Path.GetFileName(saveDialog.FileName)}", "CODING_TABLE");
            MessageBox.Show($"File saved successfully.\n\n{saveDialog.FileName}", "Saved",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to save site coding rules (Save As)", "CODING_TABLE", ex);
            MessageBox.Show($"Failed to save file: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void SaveToFile(string path)
    {
        var lines = _currentPatterns.Select(p => JsonSerializer.Serialize(new
        {
            code = p.Code,
            priority = p.Priority,
            logic = p.Logic,
            expression = p.Expression.Select(ei => ei.Type switch
            {
                "term" => (object)new { type = ei.Type, value = ei.Value },
                "group" => new { type = ei.Type, logic = ei.Logic, terms = ei.Terms },
                "topo-template" => new { type = ei.Type, template = ei.Template },
                _ => new { type = ei.Type, value = ei.Value }
            }),
            enabled = p.Enabled,
            forceLaterality = p.ForceLaterality
        }));
        File.WriteAllLines(path, lines);
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

/// <summary>
/// Sub-dialog for adding or editing a single site coding rule pattern.
/// Ported from Show-PatternEditDialog in ui/site-coding-rules-editor-ui.ps1.
/// </summary>
public class PatternEditDialog : ParratFormBase
{
    private readonly ISiteLateralityService _siteLateralityService;
    private List<ExpressionItem> _expressionItems;

    private TextBox _txtCode = null!;
    private NumericUpDown _numPriority = null!;
    private CheckBox _chkEnabled = null!;
    private CheckBox _chkForceLat = null!;
    private RadioButton _rdoOr = null!;
    private RadioButton _rdoAnd = null!;
    private ListBox _lstTerms = null!;
    private TextBox _txtTestPhrases = null!;
    private RichTextBox _rtbTestResults = null!;

    public SiteCodingRule? ResultPattern { get; private set; }

    public PatternEditDialog(
        ISiteLateralityService siteLateralityService,
        string title,
        SiteCodingRule? pattern = null)
    {
        _siteLateralityService = siteLateralityService;
        _expressionItems = new List<ExpressionItem>();

        if (pattern?.Expression != null)
        {
            foreach (var item in pattern.Expression)
            {
                _expressionItems.Add(new ExpressionItem
                {
                    Type = item.Type,
                    Value = item.Value,
                    Terms = item.Terms != null ? new List<string>(item.Terms) : null,
                    Logic = item.Logic,
                    Template = item.Template
                });
            }
        }

        InitializeControls(title, pattern);
    }

    private void InitializeControls(string title, SiteCodingRule? pattern)
    {
        // ── Form properties ──────────────────────────────────────────────
        Text = title;
        Width = 600;
        Height = 700;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        // ── Site Code ────────────────────────────────────────────────────
        Controls.Add(new Label { Text = "Site Code:", Location = new Point(15, 20), AutoSize = true });

        _txtCode = new TextBox
        {
            Location = new Point(100, 17),
            Width = 80,
            Text = pattern?.Code ?? ""
        };
        Controls.Add(_txtCode);

        // ── Priority ─────────────────────────────────────────────────────
        Controls.Add(new Label { Text = "Priority:", Location = new Point(200, 20), AutoSize = true });

        _numPriority = new NumericUpDown
        {
            Location = new Point(260, 17),
            Width = 60,
            Minimum = 1,
            Maximum = 999,
            Value = pattern?.Priority > 0 ? pattern.Priority : 1
        };
        Controls.Add(_numPriority);

        // ── Enabled checkbox ─────────────────────────────────────────────
        _chkEnabled = new CheckBox
        {
            Text = "Enabled",
            Location = new Point(340, 18),
            Checked = pattern?.Enabled ?? true,
            AutoSize = true
        };
        Controls.Add(_chkEnabled);

        // ── Force Laterality checkbox ────────────────────────────────────
        _chkForceLat = new CheckBox
        {
            Text = "Force Laterality = 9 (Unknown)",
            Location = new Point(15, 50),
            Checked = !string.IsNullOrEmpty(pattern?.ForceLaterality),
            AutoSize = true
        };
        Controls.Add(_chkForceLat);

        // ── Logic group ──────────────────────────────────────────────────
        var grpLogic = new GroupBox
        {
            Text = "Top-Level Logic",
            Location = new Point(15, 75),
            Size = new Size(555, 50)
        };

        _rdoOr = new RadioButton
        {
            Text = "Any term matches (OR)",
            Location = new Point(15, 20),
            AutoSize = true,
            Checked = pattern == null || pattern.Logic != "AND"
        };

        _rdoAnd = new RadioButton
        {
            Text = "All terms match (AND)",
            Location = new Point(200, 20),
            AutoSize = true,
            Checked = pattern?.Logic == "AND"
        };

        grpLogic.Controls.AddRange(new Control[] { _rdoOr, _rdoAnd });
        Controls.Add(grpLogic);

        // ── Terms label ──────────────────────────────────────────────────
        Controls.Add(new Label { Text = "Expression Terms:", Location = new Point(15, 135), AutoSize = true });

        // ── Terms listbox ────────────────────────────────────────────────
        _lstTerms = new ListBox
        {
            Location = new Point(15, 155),
            Size = new Size(450, 200),
            SelectionMode = SelectionMode.One
        };
        RefreshTermsList();
        Controls.Add(_lstTerms);

        // ── Term buttons ─────────────────────────────────────────────────
        var pnlTermButtons = new Panel
        {
            Location = new Point(475, 155),
            Size = new Size(95, 220)
        };

        var btnAddTerm = new Button { Text = "Add Term", Location = new Point(0, 0), Width = 90 };
        btnAddTerm.Click += OnAddTerm;

        var btnAddAndGroup = new Button { Text = "Add AND", Location = new Point(0, 35), Width = 90 };
        btnAddAndGroup.Click += (_, _) => OnAddGroup("AND");

        var btnAddOrGroup = new Button { Text = "Add OR", Location = new Point(0, 70), Width = 90 };
        btnAddOrGroup.Click += (_, _) => OnAddGroup("OR");

        var btnAddTopoTemplate = new Button { Text = "Add {topo}", Location = new Point(0, 105), Width = 90 };
        btnAddTopoTemplate.Click += OnAddTopoTemplate;

        var btnEditTerm = new Button { Text = "Edit", Location = new Point(0, 150), Width = 90 };
        btnEditTerm.Click += OnEditTerm;

        var btnRemoveTerm = new Button { Text = "Remove", Location = new Point(0, 185), Width = 90 };
        btnRemoveTerm.Click += OnRemoveTerm;

        pnlTermButtons.Controls.AddRange(new Control[] { btnAddTerm, btnAddAndGroup, btnAddOrGroup, btnAddTopoTemplate, btnEditTerm, btnRemoveTerm });
        Controls.Add(pnlTermButtons);

        // ── Test section ─────────────────────────────────────────────────
        Controls.Add(new Label { Text = "Test Phrases (one per line):", Location = new Point(15, 370), AutoSize = true });

        _txtTestPhrases = new TextBox
        {
            Location = new Point(15, 390),
            Size = new Size(450, 70),
            Multiline = true,
            ScrollBars = ScrollBars.Vertical
        };
        Controls.Add(_txtTestPhrases);

        var btnTest = new Button { Text = "Test", Location = new Point(475, 390), Width = 90 };
        btnTest.Click += OnTest;
        Controls.Add(btnTest);

        Controls.Add(new Label { Text = "Results:", Location = new Point(15, 465), AutoSize = true });

        _rtbTestResults = new RichTextBox
        {
            Location = new Point(15, 485),
            Size = new Size(555, 120),
            ReadOnly = true,
            BackColor = Color.White,
            Font = new Font("Consolas", 9f)
        };
        Controls.Add(_rtbTestResults);

        // ── OK / Cancel ──────────────────────────────────────────────────
        var btnOk = new Button
        {
            Text = "OK",
            Location = new Point(400, 620),
            Width = 80
        };
        btnOk.Click += OnOkClick;
        AcceptButton = btnOk;
        Controls.Add(btnOk);

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(490, 620),
            Width = 80,
            DialogResult = DialogResult.Cancel
        };
        CancelButton = btnCancel;
        Controls.Add(btnCancel);
    }

    private void RefreshTermsList()
    {
        _lstTerms.Items.Clear();
        foreach (var item in _expressionItems)
        {
            switch (item.Type)
            {
                case "term":
                    _lstTerms.Items.Add(item.Value ?? "");
                    break;
                case "group":
                    var groupDisplay = $"[{item.Logic}: {string.Join(", ", item.Terms ?? new List<string>())}]";
                    _lstTerms.Items.Add(groupDisplay);
                    break;
                case "topo-template":
                    _lstTerms.Items.Add($"{{topo}}: {item.Template}");
                    break;
            }
        }
    }

    // ── Term editing handlers ────────────────────────────────────────────

    private void OnAddTerm(object? sender, EventArgs e)
    {
        var value = ShowTextInputDialog("Add Term", "Enter search phrase:");
        if (value == null) return;

        var term = value.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(term))
        {
            _expressionItems.Add(new ExpressionItem { Type = "term", Value = term });
            RefreshTermsList();
        }
    }

    private void OnAddGroup(string logic)
    {
        var value = ShowTextInputDialog($"Add {logic} Group",
            $"Enter terms (comma-separated):\n{(logic == "AND" ? "All terms must match for group to match." : "Any term matching will satisfy the group.")}");
        if (value == null) return;

        var terms = value.Split(',')
            .Select(t => t.Trim().ToLowerInvariant())
            .Where(t => !string.IsNullOrEmpty(t))
            .ToList();

        if (terms.Count < 2)
        {
            MessageBox.Show($"{logic} group requires at least 2 terms.", "Invalid Input",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        _expressionItems.Add(new ExpressionItem { Type = "group", Logic = logic, Terms = terms });
        RefreshTermsList();
    }

    private void OnAddTopoTemplate(object? sender, EventArgs e)
    {
        var value = ShowTextInputDialog("Add Topo-Template",
            "Enter template with {topo} placeholder:\nExample: consistent with {topo} origin", "{topo}");
        if (value == null) return;

        var template = value.Trim().ToLowerInvariant();
        if (!string.IsNullOrEmpty(template) && template.Contains("{topo}"))
        {
            _expressionItems.Add(new ExpressionItem { Type = "topo-template", Template = template });
            RefreshTermsList();
        }
        else
        {
            MessageBox.Show("Template must contain {topo} placeholder.", "Invalid Input",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void OnEditTerm(object? sender, EventArgs e)
    {
        var idx = _lstTerms.SelectedIndex;
        if (idx < 0)
        {
            MessageBox.Show("Please select an item to edit.", "No Selection",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var item = _expressionItems[idx];

        switch (item.Type)
        {
            case "term":
            {
                var value = ShowTextInputDialog("Edit Term", "Enter search phrase:", item.Value ?? "");
                if (value == null) return;
                var term = value.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(term))
                {
                    _expressionItems[idx] = new ExpressionItem { Type = "term", Value = term };
                    RefreshTermsList();
                }
                break;
            }
            case "group":
            {
                var value = ShowTextInputDialog($"Edit {item.Logic} Group",
                    "Enter terms (comma-separated):",
                    string.Join(", ", item.Terms ?? new List<string>()));
                if (value == null) return;
                var terms = value.Split(',')
                    .Select(t => t.Trim().ToLowerInvariant())
                    .Where(t => !string.IsNullOrEmpty(t))
                    .ToList();
                if (terms.Count >= 2)
                {
                    _expressionItems[idx] = new ExpressionItem { Type = "group", Logic = item.Logic, Terms = terms };
                    RefreshTermsList();
                }
                break;
            }
            case "topo-template":
            {
                var value = ShowTextInputDialog("Edit Topo-Template",
                    "Enter template with {topo} placeholder:\nExample: consistent with {topo} origin",
                    item.Template ?? "{topo}");
                if (value == null) return;
                var template = value.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(template) && template.Contains("{topo}"))
                {
                    _expressionItems[idx] = new ExpressionItem { Type = "topo-template", Template = template };
                    RefreshTermsList();
                }
                else
                {
                    MessageBox.Show("Template must contain {topo} placeholder.", "Invalid Input",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
                break;
            }
        }
    }

    private void OnRemoveTerm(object? sender, EventArgs e)
    {
        var idx = _lstTerms.SelectedIndex;
        if (idx < 0)
        {
            MessageBox.Show("Please select an item to remove.", "No Selection",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var result = MessageBox.Show("Remove this item?", "Confirm Remove",
            MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (result == DialogResult.Yes)
        {
            _expressionItems.RemoveAt(idx);
            RefreshTermsList();
        }
    }

    // ── Test handler ─────────────────────────────────────────────────────

    private void OnTest(object? sender, EventArgs e)
    {
        _rtbTestResults.Clear();
        var lines = _txtTestPhrases.Text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);

        var tempLogic = _rdoAnd.Checked ? "AND" : "OR";
        var tempPattern = new SiteCodingRule
        {
            Code = _txtCode.Text.Trim(),
            Logic = tempLogic,
            Expression = _expressionItems
        };

        var isFirstLine = true;
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (string.IsNullOrWhiteSpace(trimmed)) continue;

            if (!isFirstLine) _rtbTestResults.AppendText("\n");
            isFirstLine = false;

            var low = trimmed.ToLowerInvariant();
            var testResult = _siteLateralityService.TestSiteCodingRule(tempPattern, low);

            if (testResult.Matched)
            {
                // Render with green highlights on matched spans
                var lineStart = _rtbTestResults.TextLength;
                _rtbTestResults.AppendText(trimmed);

                // Try to highlight matched terms
                foreach (var ei in _expressionItems)
                {
                    if (ei.Type == "term" && ei.Value != null)
                    {
                        HighlightTerm(lineStart, low, ei.Value);
                    }
                    else if (ei.Type == "group" && ei.Terms != null)
                    {
                        foreach (var term in ei.Terms)
                            HighlightTerm(lineStart, low, term);
                    }
                }

                // Append site code and laterality
                var siteCode = testResult.TopoCode ?? tempPattern.Code;
                var lat = _siteLateralityService.GetLaterality(low);
                var latLabel = lat switch
                {
                    "1" => "1 (Right)",
                    "2" => "2 (Left)",
                    "9" => "9 (Unknown)",
                    _ => "N/A"
                };
                if (_chkForceLat.Checked) latLabel = "9 (Forced)";

                _rtbTestResults.Select(_rtbTestResults.TextLength, 0);
                _rtbTestResults.SelectionBackColor = Color.White;
                var tagText = $"  [ pSite: {siteCode} | Lat: {latLabel} ]";
                var tagStart = _rtbTestResults.TextLength;
                _rtbTestResults.AppendText(tagText);
                _rtbTestResults.Select(tagStart, tagText.Length);
                _rtbTestResults.SelectionColor = Color.FromArgb(0, 120, 0);
            }
            else
            {
                var startPos = _rtbTestResults.TextLength;
                _rtbTestResults.AppendText($"{trimmed}  - NO MATCH");
                _rtbTestResults.Select(startPos, _rtbTestResults.TextLength - startPos);
                _rtbTestResults.SelectionColor = Color.Gray;
            }
        }

        _rtbTestResults.Select(0, 0);
        _rtbTestResults.ScrollToCaret();
    }

    private void HighlightTerm(int lineStart, string low, string term)
    {
        try
        {
            var escaped = Regex.Escape(term);
            var rx = $@"(?<![a-zA-Z]){escaped}(?![a-zA-Z])";
            var m = Regex.Match(low, rx);
            if (m.Success)
            {
                _rtbTestResults.Select(lineStart + m.Index, m.Length);
                _rtbTestResults.SelectionBackColor = Color.FromArgb(180, 255, 180);
            }
        }
        catch
        {
            // Regex highlighting is best-effort for UI display
        }
    }

    // ── OK handler ───────────────────────────────────────────────────────

    private void OnOkClick(object? sender, EventArgs e)
    {
        var code = _txtCode.Text.Trim().ToUpperInvariant();
        if (Regex.IsMatch(code, @"^\d{1,3}$"))
            code = "C" + code.PadLeft(3, '0');
        else if (Regex.IsMatch(code, @"^C\d{1,2}$"))
            code = "C" + code[1..].PadLeft(3, '0');

        ResultPattern = new SiteCodingRule
        {
            Code = code,
            Priority = (int)_numPriority.Value,
            Expression = _expressionItems,
            Logic = _rdoAnd.Checked ? "AND" : "OR",
            Enabled = _chkEnabled.Checked,
            ForceLaterality = _chkForceLat.Checked ? "9" : null
        };

        DialogResult = DialogResult.OK;
        Close();
    }

    // ── Helper: simple text input dialog ─────────────────────────────────

    private static string? ShowTextInputDialog(string title, string prompt, string defaultValue = "")
    {
        using var inputForm = new Form
        {
            Text = title,
            Width = 420,
            Height = prompt.Contains('\n') ? 160 : 130,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false
        };

        var lblInput = new Label
        {
            Text = prompt,
            Location = new Point(15, 15),
            Size = prompt.Contains('\n') ? new Size(380, 35) : new Size(380, 20),
            AutoSize = !prompt.Contains('\n')
        };

        var yOffset = prompt.Contains('\n') ? 55 : 40;
        var txtInput = new TextBox
        {
            Location = new Point(15, yOffset),
            Width = 370,
            Text = defaultValue
        };

        var btnOk = new Button
        {
            Text = "OK",
            Location = new Point(220, yOffset + 30),
            Width = 75,
            DialogResult = DialogResult.OK
        };

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(305, yOffset + 30),
            Width = 75,
            DialogResult = DialogResult.Cancel
        };

        inputForm.Controls.AddRange(new Control[] { lblInput, txtInput, btnOk, btnCancel });
        inputForm.AcceptButton = btnOk;
        inputForm.CancelButton = btnCancel;

        return inputForm.ShowDialog() == DialogResult.OK ? txtInput.Text : null;
    }
}
