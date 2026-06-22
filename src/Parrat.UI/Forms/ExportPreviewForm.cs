using System.Data;
using System.Drawing;
using System.Windows.Forms;
using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// CSV export configuration dialog.
/// Has a list of available fields (from NAACCR dictionary), selected fields list,
/// Add/Remove buttons, field ordering, config save/load, and a preview grid showing sample data.
/// Ported from ui/export-preview-ui.ps1 Show-ExportPreview.
/// </summary>
public class ExportPreviewForm : ParratFormBase
{
    private readonly INaaccrDictionary _dictionary;
    private readonly IConfigService _configService;
    private readonly IParratLogger? _logger;
    private readonly int[] _tumorIndices;
    private readonly XmlDocument _xmlDoc;
    private readonly XmlNamespaceManager _nsMgr;
    private readonly XmlNodeList? _tumors;

    private readonly List<string> _selectedFields = new();
    private readonly Dictionary<string, string> _customFieldParents = new();
    private bool _isPopulatingFields;

    // Controls
    private Panel _leftPanel = null!;
    private Panel _rightPanel = null!;
    private Panel _bottomPanel = null!;
    private TextBox _txtSearch = null!;
    private CheckedListBox _lstFields = null!;
    private Button _btnLoadConfig = null!;
    private Button _btnSaveConfig = null!;
    private Button _btnAddCustom = null!;
    private Button _btnMoveUp = null!;
    private Button _btnMoveDown = null!;
    private Button _btnRefresh = null!;
    private Button _btnSelectPresent = null!;
    private Button _btnSelectPresentAll = null!;
    private Button _btnClearSelection = null!;
    private Button _btnRemoveEmpty = null!;
    private ToolTip _toolTip = null!;
    private Label _lblSummary = null!;
    private Label _lblErrors = null!;
    private DataGridView _grid = null!;
    private Button _btnExport = null!;
    private Button _btnCancel = null!;

    /// <summary>Gets the final list of selected field XmlIds after the dialog closes.</summary>
    public List<string> SelectedFieldIds => new(_selectedFields);

    /// <summary>Gets the custom field parent element mappings after the dialog closes.</summary>
    public Dictionary<string, string> CustomFields => new(_customFieldParents);

    public ExportPreviewForm(
        INaaccrDictionary dictionary,
        IConfigService configService,
        int[] tumorIndices,
        XmlDocument xmlDoc,
        XmlNamespaceManager nsMgr,
        XmlNodeList? tumors,
        List<string>? initialFieldList = null,
        string title = "Export Preview",
        IParratLogger? logger = null)
    {
        _dictionary = dictionary;
        _configService = configService;
        _tumorIndices = tumorIndices;
        _xmlDoc = xmlDoc;
        _nsMgr = nsMgr;
        _tumors = tumors;
        _logger = logger;

        if (initialFieldList != null)
        {
            _selectedFields.AddRange(initialFieldList);
        }

        InitializeComponents();
        Text = title;

        Shown += (_, _) =>
        {
            PopulateFieldList();
            UpdatePreview();
        };

        FormClosing += (sender, e) =>
        {
            if (DialogResult == DialogResult.None)
                DialogResult = DialogResult.Cancel;
        };
    }

    private void InitializeComponents()
    {
        Width = 1400;
        Height = 700;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(1000, 500);

        // ===== LEFT PANEL: Field Selector =====
        _leftPanel = new Panel
        {
            Location = new Point(10, 10),
            Size = new Size(350, 590),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Bottom
        };

        var lblSearch = new Label
        {
            Text = "Search fields:",
            Location = new Point(0, 0),
            AutoSize = true
        };

        _txtSearch = new TextBox
        {
            Location = new Point(0, 20),
            Size = new Size(340, 23)
        };
        _txtSearch.TextChanged += (_, _) => PopulateFieldList(_txtSearch.Text);

        var pnlFieldButtons = new Panel
        {
            Location = new Point(0, 50),
            Size = new Size(340, 135)
        };

        _btnLoadConfig = new Button { Text = "Load Config", Location = new Point(0, 0), Width = 105 };
        _btnSaveConfig = new Button { Text = "Save Config", Location = new Point(115, 0), Width = 105 };
        _btnAddCustom = new Button { Text = "+ Custom", Location = new Point(230, 0), Width = 105 };
        _btnMoveUp = new Button { Text = "Move Up", Location = new Point(0, 35), Width = 105 };
        _btnMoveDown = new Button { Text = "Move Down", Location = new Point(115, 35), Width = 105 };
        _btnRefresh = new Button { Text = "Refresh", Location = new Point(230, 35), Width = 105 };
        _btnSelectPresent = new Button
        {
            Text = "Select Present Vars",
            Location = new Point(0, 70),
            Width = 165
        };
        _btnSelectPresentAll = new Button
        {
            Text = "Present (All Records)",
            Location = new Point(175, 70),
            Width = 165
        };

        var separator = new Label
        {
            AutoSize = false,
            BorderStyle = BorderStyle.Fixed3D,
            Location = new Point(0, 63),
            Size = new Size(340, 2)
        };

        _btnClearSelection = new Button
        {
            Text = "Clear Selection",
            Location = new Point(0, 105),
            Width = 165
        };
        _btnRemoveEmpty = new Button
        {
            Text = "Remove Empty Cols",
            Location = new Point(175, 105),
            Width = 165
        };

        _toolTip = new ToolTip();
        _toolTip.SetToolTip(_btnSelectPresent,
            "Select every variable present in the cases being exported.");
        _toolTip.SetToolTip(_btnSelectPresentAll,
            "Select every variable present anywhere in the loaded file, including non-selected cases " +
            "(adds blank columns for variables absent from the exported cases).");
        _toolTip.SetToolTip(_btnClearSelection,
            "Uncheck all selected fields and start over.");
        _toolTip.SetToolTip(_btnRemoveEmpty,
            "Remove selected variables that are blank for every exported case " +
            "(e.g. columns added by \"Present (All Records)\" that carry no data here).");

        pnlFieldButtons.Controls.AddRange(new Control[] { _btnLoadConfig, _btnSaveConfig, _btnAddCustom, _btnMoveUp, _btnMoveDown, _btnRefresh, separator, _btnSelectPresent, _btnSelectPresentAll, _btnClearSelection, _btnRemoveEmpty });

        var lblFields = new Label
        {
            Text = "Available Fields:",
            Location = new Point(0, 190),
            AutoSize = true
        };

        _lstFields = new CheckedListBox
        {
            Location = new Point(0, 210),
            Size = new Size(340, 375),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Bottom,
            CheckOnClick = true
        };

        _leftPanel.Controls.AddRange(new Control[] { lblSearch, _txtSearch, pnlFieldButtons, lblFields, _lstFields });

        // ===== RIGHT PANEL: Preview =====
        _rightPanel = new Panel
        {
            Location = new Point(370, 10),
            Size = new Size(1000, 590),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
        };

        _lblSummary = new Label
        {
            Location = new Point(0, 0),
            Size = new Size(1000, 25),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            Font = new Font("Segoe UI", 10, FontStyle.Bold)
        };

        _lblErrors = new Label
        {
            Location = new Point(0, 565),
            Size = new Size(1000, 20),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right,
            ForeColor = Color.Red
        };

        _grid = new DataGridView
        {
            Location = new Point(0, 30),
            Size = new Size(1000, 530),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            AutoSize = false,
            ScrollBars = ScrollBars.Both,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            RowHeadersVisible = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = false,
            ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.AutoSize
        };

        _rightPanel.Controls.AddRange(new Control[] { _lblSummary, _grid, _lblErrors });

        // ===== BOTTOM PANEL =====
        _bottomPanel = new Panel
        {
            Location = new Point(10, 610),
            Size = new Size(300, 40),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };

        _btnExport = new Button
        {
            Text = "Export",
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

        _bottomPanel.Controls.AddRange(new Control[] { _btnExport, _btnCancel });

        Controls.AddRange(new Control[] { _leftPanel, _rightPanel, _bottomPanel });
        CancelButton = _btnCancel;
        AcceptButton = _btnExport;

        // Wire events
        _lstFields.ItemCheck += LstFields_ItemCheck;
        _btnAddCustom.Click += BtnAddCustom_Click;
        _btnLoadConfig.Click += BtnLoadConfig_Click;
        _btnSaveConfig.Click += BtnSaveConfig_Click;
        _btnMoveUp.Click += BtnMoveUp_Click;
        _btnMoveDown.Click += BtnMoveDown_Click;
        _btnRefresh.Click += (_, _) => UpdatePreview();
        _btnSelectPresent.Click += (_, _) => SelectPresentVariables(allRecords: false);
        _btnSelectPresentAll.Click += (_, _) => SelectPresentVariables(allRecords: true);
        _btnClearSelection.Click += (_, _) => ClearSelection();
        _btnRemoveEmpty.Click += (_, _) => RemoveEmptyColumns();

        // The "all records" scope only differs from the export scope when fewer than all
        // tumors are being exported (Export Selected). For Export All it is a no-op.
        _btnSelectPresentAll.Enabled = _tumors != null && _tumorIndices.Length < _tumors.Count;
    }

    private string? ExtractXmlId(string displayText)
    {
        // Match "(xmlId)" at end of string
        var match = System.Text.RegularExpressions.Regex.Match(displayText, @"\(([^)]+)\)$");
        if (match.Success)
            return match.Groups[1].Value;

        // Match "CUSTOM - xmlId"
        match = System.Text.RegularExpressions.Regex.Match(displayText, @"^CUSTOM - (.+)$");
        if (match.Success)
            return match.Groups[1].Value;

        return null;
    }

    private void PopulateFieldList(string searchFilter = "")
    {
        _isPopulatingFields = true;
        try
        {
            _lstFields.BeginUpdate();
            _lstFields.Items.Clear();

            var allItems = new List<NaaccrItem>();
            foreach (var kvp in _dictionary.GetDictionary())
            {
                allItems.Add(kvp.Value);
            }

            // Filter if search text provided
            if (!string.IsNullOrWhiteSpace(searchFilter))
            {
                var lower = searchFilter.ToLower();
                allItems = allItems.Where(item =>
                    item.Name.ToLower().Contains(lower) ||
                    item.XmlId.ToLower().Contains(lower) ||
                    item.Number == searchFilter
                ).ToList();
            }

            var addedIds = new HashSet<string>();

            // Section header for selected
            if (_selectedFields.Count > 0 && string.IsNullOrWhiteSpace(searchFilter))
            {
                _lstFields.Items.Add("== SELECTED FIELDS ==");
            }

            foreach (var fieldId in _selectedFields)
            {
                var item = _dictionary.GetItemByXmlId(fieldId);
                string displayText;
                if (item != null)
                {
                    displayText = $"{item.Number} - {item.Name} ({item.XmlId})";
                }
                else
                {
                    displayText = $"CUSTOM - {fieldId}";
                }

                if (string.IsNullOrWhiteSpace(searchFilter) ||
                    displayText.ToLower().Contains(searchFilter.ToLower()))
                {
                    int index = _lstFields.Items.Add(displayText);
                    _lstFields.SetItemChecked(index, true);
                    addedIds.Add(fieldId);
                }
            }

            // Section header for available
            if (string.IsNullOrWhiteSpace(searchFilter) && allItems.Count > 0)
            {
                _lstFields.Items.Add("== AVAILABLE FIELDS ==");
            }

            foreach (var item in allItems)
            {
                if (!addedIds.Contains(item.XmlId))
                {
                    var displayText = $"{item.Number} - {item.Name} ({item.XmlId})";
                    _lstFields.Items.Add(displayText);
                }
            }

            _lstFields.EndUpdate();
        }
        finally
        {
            _isPopulatingFields = false;
        }
    }

    private void UpdatePreview()
    {
        var errors = new List<string>();
        var rows = new List<Dictionary<string, string>>();
        var currentFields = _selectedFields.ToList();

        if (currentFields.Count == 0)
        {
            _lblSummary.Text = "No fields selected";
            _grid.DataSource = null;
            return;
        }

        try
        {
            foreach (var tumorIndex in _tumorIndices)
            {
                if (_tumors == null || tumorIndex < 0 || tumorIndex >= _tumors.Count)
                {
                    errors.Add($"Invalid tumor index: {tumorIndex}");
                    continue;
                }

                var tumor = _tumors[tumorIndex];
                var patient = tumor?.SelectSingleNode("ancestor::n:Patient[1]", _nsMgr);

                if (patient == null)
                {
                    errors.Add($"Tumor at index {tumorIndex} has no parent Patient node");
                    continue;
                }

                var row = new Dictionary<string, string>();

                foreach (var fieldId in currentFields)
                {
                    row[fieldId] = ResolveFieldValue(fieldId, tumor!, patient);
                }

                rows.Add(row);
            }
        }
        catch (Exception ex)
        {
            _logger?.LogError("Error building export preview", "EXPORT", ex);
            errors.Add($"Error building preview: {ex.Message}");
        }

        // Update summary
        _lblSummary.Text = $"Preview: {rows.Count} row(s) with {currentFields.Count} column(s)";
        if (errors.Count > 0)
        {
            _lblSummary.Text += $" | Errors: {errors.Count}";
            var shownErrors = errors.Take(3);
            _lblErrors.Text = "Errors: " + string.Join("; ", shownErrors);
        }
        else
        {
            _lblErrors.Text = "";
        }

        // Build DataTable
        var table = new DataTable();
        foreach (var fieldId in currentFields)
        {
            table.Columns.Add(fieldId, typeof(string));
        }

        foreach (var row in rows)
        {
            var dataRow = table.NewRow();
            foreach (var fieldId in currentFields)
            {
                dataRow[fieldId] = row.GetValueOrDefault(fieldId, "");
            }
            table.Rows.Add(dataRow);
        }

        _grid.DataSource = table;

        // Auto-fit columns with min/max constraints
        _grid.AutoResizeColumns(DataGridViewAutoSizeColumnsMode.AllCells);
        foreach (DataGridViewColumn col in _grid.Columns)
        {
            var currentWidth = col.Width;
            col.AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
            col.MinimumWidth = 50;
            col.Width = Math.Max(Math.Min(currentWidth, 300), 50);
        }
    }

    /// <summary>
    /// Resolves a field's value for one tumor via the shared <see cref="TumorFieldReader"/>,
    /// so the preview always matches what the CSV export writes.
    /// </summary>
    private string ResolveFieldValue(string fieldId, XmlNode tumor, XmlNode? patient)
    {
        var parentElement = _dictionary.GetParentElement(fieldId, _customFieldParents);
        return TumorFieldReader.ReadValue(tumor, patient, fieldId, parentElement, _nsMgr);
    }

    private void ClearSelection()
    {
        if (_selectedFields.Count == 0)
        {
            _lblSummary.Text = "No fields selected";
            return;
        }

        _selectedFields.Clear();
        _customFieldParents.Clear();
        PopulateFieldList(_txtSearch.Text);
        UpdatePreview();
        _lblSummary.Text = "Cleared all selected fields";
    }

    /// <summary>
    /// Removes selected variables that are blank for every exported case. Variables present
    /// only in non-selected cases (added via "Present (All Records)") are pruned here, since
    /// they carry no data in the cases actually being exported.
    /// </summary>
    private void RemoveEmptyColumns()
    {
        if (_tumors == null || _selectedFields.Count == 0)
            return;

        var removed = TumorFieldReader.FindEmptyFields(
            _tumors, _tumorIndices, _selectedFields,
            id => _dictionary.GetParentElement(id, _customFieldParents), _nsMgr);

        if (removed.Count == 0)
        {
            _lblSummary.Text = "No empty columns to remove";
            return;
        }

        foreach (var id in removed)
        {
            _selectedFields.Remove(id);
            _customFieldParents.Remove(id);
        }

        PopulateFieldList(_txtSearch.Text);
        UpdatePreview();
        _lblSummary.Text = $"Removed {removed.Count} empty column(s) ({_selectedFields.Count} selected)";
    }

    private void LstFields_ItemCheck(object? sender, ItemCheckEventArgs e)
    {
        if (_isPopulatingFields) return;

        var itemText = _lstFields.Items[e.Index]?.ToString() ?? "";

        // Ignore section headers
        if (itemText.StartsWith("=="))
        {
            e.NewValue = e.CurrentValue;
            return;
        }

        var xmlId = ExtractXmlId(itemText);
        if (xmlId == null) return;

        if (e.NewValue == CheckState.Checked)
        {
            if (!_selectedFields.Contains(xmlId))
                _selectedFields.Add(xmlId);
        }
        else
        {
            _selectedFields.Remove(xmlId);
        }

        // Defer preview update to after the check state changes
        BeginInvoke(new Action(UpdatePreview));
    }

    private void SelectPresentVariables(bool allRecords)
    {
        if (_tumors == null || _tumors.Count == 0)
            return;

        // Scope: just the cases being exported, or every loaded record (incl. non-selected).
        var scanIndices = allRecords
            ? Enumerable.Range(0, _tumors.Count).ToArray()
            : _tumorIndices;

        var present = VariableScanHelper.ScanPresentVariables(_tumors, scanIndices, _nsMgr);

        // Union: keep existing selections; append only the variables not already chosen.
        var newIds = present.Keys.Where(id => !_selectedFields.Contains(id)).ToList();

        // Register unknown ids (absent from the dictionary) as custom fields with the level
        // they were found at, so they export with values rather than blanks.
        foreach (var id in newIds)
        {
            if (_dictionary.GetItemByXmlId(id) == null && !_customFieldParents.ContainsKey(id))
                _customFieldParents[id] = present[id];
        }

        // Canonical NAACCR order, then union onto the existing selection (order preserved).
        var orderedNew = VariableScanHelper.OrderByNaaccr(newIds, _dictionary);
        var merged = VariableScanHelper.MergePreservingOrder(_selectedFields, orderedNew);
        _selectedFields.Clear();
        _selectedFields.AddRange(merged);

        PopulateFieldList(_txtSearch.Text);
        UpdatePreview();

        var scopeLabel = allRecords ? "all loaded records" : "exported cases";
        _lblSummary.Text = newIds.Count == 0
            ? $"All {present.Count} present variable(s) from {scopeLabel} were already selected"
            : $"Added {newIds.Count} present variable(s) from {scopeLabel} ({_selectedFields.Count} selected)";
    }

    private void BtnAddCustom_Click(object? sender, EventArgs e)
    {
        using var customForm = new ParratFormBase
        {
            Text = "Add Custom Field",
            Width = 400,
            Height = 200,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false
        };

        var lblXmlId = new Label { Text = "XML NAACCR ID:", Location = new Point(10, 20), AutoSize = true };
        var txtXmlId = new TextBox { Location = new Point(130, 17), Width = 240 };
        var lblParent = new Label { Text = "Parent Element:", Location = new Point(10, 55), AutoSize = true };
        var cmbParent = new ComboBox
        {
            Location = new Point(130, 52),
            Width = 240,
            DropDownStyle = ComboBoxStyle.DropDownList
        };
        cmbParent.Items.AddRange(new object[] { "Tumor", "Patient", "NaaccrData" });
        cmbParent.SelectedIndex = 0;

        var btnAddOk = new Button { Text = "Add", Location = new Point(130, 100), DialogResult = DialogResult.OK };
        var btnAddCancel = new Button { Text = "Cancel", Location = new Point(220, 100), DialogResult = DialogResult.Cancel };

        customForm.Controls.AddRange(new Control[] { lblXmlId, txtXmlId, lblParent, cmbParent, btnAddOk, btnAddCancel });
        customForm.AcceptButton = btnAddOk;
        customForm.CancelButton = btnAddCancel;

        if (customForm.ShowDialog(this) == DialogResult.OK)
        {
            var newXmlId = txtXmlId.Text.Trim();
            if (!string.IsNullOrWhiteSpace(newXmlId))
            {
                if (!_selectedFields.Contains(newXmlId))
                {
                    _selectedFields.Add(newXmlId);
                    _customFieldParents[newXmlId] = cmbParent.SelectedItem?.ToString() ?? "Tumor";
                    PopulateFieldList(_txtSearch.Text);
                    UpdatePreview();
                }
                else
                {
                    MessageBox.Show($"Field '{newXmlId}' is already selected.", "Duplicate Field",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }
    }

    private void BtnLoadConfig_Click(object? sender, EventArgs e)
    {
        using var ofd = new OpenFileDialog
        {
            Filter = "JSON Files (*.json)|*.json|All files (*.*)|*.*",
            Title = "Load Export Configuration",
            InitialDirectory = _configService.GetExportConfigPath()
        };

        if (ofd.ShowDialog(this) == DialogResult.OK)
        {
            try
            {
                var config = _configService.GetExportConfig(ofd.FileName);
                _selectedFields.Clear();
                _customFieldParents.Clear();

                foreach (var field in config.Fields)
                {
                    _selectedFields.Add(field.XmlId);
                    if (field.IsCustom && !string.IsNullOrEmpty(field.ParentElement))
                    {
                        _customFieldParents[field.XmlId] = field.ParentElement;
                    }
                }

                PopulateFieldList(_txtSearch.Text);
                UpdatePreview();

                MessageBox.Show(
                    $"Loaded configuration: {config.Name}\nFields: {_selectedFields.Count}",
                    "Configuration Loaded",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                _logger?.LogError("Failed to load export configuration", "EXPORT", ex);
                MessageBox.Show(ex.Message, "Load Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    private void BtnSaveConfig_Click(object? sender, EventArgs e)
    {
        using var saveForm = new ParratFormBase
        {
            Text = "Save Export Configuration",
            Width = 400,
            Height = 150,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false
        };

        var lblName = new Label { Text = "Configuration Name:", Location = new Point(10, 20), AutoSize = true };
        var txtName = new TextBox { Location = new Point(140, 17), Width = 230 };
        var btnSaveOk = new Button { Text = "Save", Location = new Point(140, 60), DialogResult = DialogResult.OK };
        var btnSaveCancel = new Button { Text = "Cancel", Location = new Point(230, 60), DialogResult = DialogResult.Cancel };

        saveForm.Controls.AddRange(new Control[] { lblName, txtName, btnSaveOk, btnSaveCancel });
        saveForm.AcceptButton = btnSaveOk;
        saveForm.CancelButton = btnSaveCancel;

        if (saveForm.ShowDialog(this) == DialogResult.OK)
        {
            var configName = txtName.Text.Trim();
            if (string.IsNullOrWhiteSpace(configName))
            {
                configName = $"Unnamed_{DateTime.Now:yyyyMMdd_HHmmss}";
            }

            var fieldsArray = _selectedFields.Select(fieldId => new ExportField
            {
                XmlId = fieldId,
                IsCustom = _customFieldParents.ContainsKey(fieldId),
                ParentElement = _dictionary.GetParentElement(fieldId, _customFieldParents)
            }).ToList();

            var config = _configService.NewExportConfig(configName, fieldsArray, 25);
            var result = _configService.SaveExportConfig(config);

            if (result.Success)
            {
                MessageBox.Show(
                    $"Configuration saved to:\n{result.Path}",
                    "Configuration Saved",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show(result.Message, "Save Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    private void BtnMoveUp_Click(object? sender, EventArgs e)
    {
        var selectedIndex = _lstFields.SelectedIndex;
        if (selectedIndex <= 0) return;

        var itemText = _lstFields.Items[selectedIndex]?.ToString() ?? "";
        if (itemText.StartsWith("==")) return;

        var xmlId = ExtractXmlId(itemText);
        if (xmlId == null) return;

        var currentIndex = _selectedFields.IndexOf(xmlId);
        if (currentIndex > 0)
        {
            _selectedFields.RemoveAt(currentIndex);
            _selectedFields.Insert(currentIndex - 1, xmlId);
            PopulateFieldList(_txtSearch.Text);
            UpdatePreview();
        }
    }

    private void BtnMoveDown_Click(object? sender, EventArgs e)
    {
        var selectedIndex = _lstFields.SelectedIndex;
        if (selectedIndex < 0) return;

        var itemText = _lstFields.Items[selectedIndex]?.ToString() ?? "";
        if (itemText.StartsWith("==")) return;

        var xmlId = ExtractXmlId(itemText);
        if (xmlId == null) return;

        var currentIndex = _selectedFields.IndexOf(xmlId);
        if (currentIndex >= 0 && currentIndex < _selectedFields.Count - 1)
        {
            _selectedFields.RemoveAt(currentIndex);
            _selectedFields.Insert(currentIndex + 1, xmlId);
            PopulateFieldList(_txtSearch.Text);
            UpdatePreview();
        }
    }
}
