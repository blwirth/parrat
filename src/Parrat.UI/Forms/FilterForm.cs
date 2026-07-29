using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Builds a record filter: a list of field/operator/value conditions chained
/// left to right with AND or OR.
///
/// The vocabulary is deliberately SQL's — LIKE with % and _, BETWEEN, IN —
/// because that is the language registrars already think in when they describe
/// what they are looking for. Nothing here touches a database; every condition
/// is evaluated in memory by <see cref="FilterEvaluator"/>.
/// </summary>
public class FilterForm : ParratFormBase
{
    private readonly INaaccrDictionary _dictionary;
    private readonly IFilterService _filterService;
    private readonly Func<FilterDefinition, IFilterFieldSource?> _sourceFactory;
    private readonly string _fileType;
    private readonly int _recordCount;
    private readonly IReadOnlyCollection<string>? _presentFieldIds;

    private readonly FlowLayoutPanel _pnlRows;
    private readonly Label _lblMatches;
    private readonly List<ConditionRow> _rows = new();

    /// <summary>
    /// The filter to apply. Empty when the user chose to clear the filter;
    /// meaningful only when the dialog returned <see cref="DialogResult.OK"/>.
    /// </summary>
    public FilterDefinition Result { get; private set; } = new();

    /// <param name="existingFilter">The filter in force, reopened for editing.</param>
    /// <param name="presentFieldIds">NAACCR ids found in the loaded file, for the field picker.</param>
    /// <param name="sourceFactory">Builds a field source for previewing a candidate filter.</param>
    public FilterForm(
        INaaccrDictionary dictionary,
        IFilterService filterService,
        string fileType,
        int recordCount,
        FilterDefinition? existingFilter,
        IReadOnlyCollection<string>? presentFieldIds,
        Func<FilterDefinition, IFilterFieldSource?> sourceFactory)
    {
        _dictionary = dictionary;
        _filterService = filterService;
        _fileType = fileType;
        _recordCount = recordCount;
        _presentFieldIds = presentFieldIds;
        _sourceFactory = sourceFactory;

        string typeName = fileType == "hl7" ? "HL7" : "NAACCR XML";

        Text = $"Filter Records: {typeName} ({recordCount:N0} records)";
        Size = new Size(880, 520);
        MinimumSize = new Size(720, 380);
        FormBorderStyle = FormBorderStyle.Sizable;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        var lblHint = new Label
        {
            Text = "Conditions are combined top to bottom: \"A AND B OR C\" means \"(A AND B) OR C\". "
                 + "Values are compared as text, dates included.",
            Location = new Point(12, 10),
            Size = new Size(840, 32),
            ForeColor = Color.DimGray
        };

        // Rows stack themselves at whatever height they actually are. Placing
        // them by hand meant spacing them by a constant, which stops matching
        // the rows the moment DPI scaling changes their height.
        _pnlRows = new FlowLayoutPanel
        {
            Location = new Point(12, 46),
            Size = new Size(840, 300),
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = true,
            BorderStyle = BorderStyle.FixedSingle,
            // Extra height goes to the conditions, which is the part of this
            // dialog that can grow, rather than to dead space above the buttons.
            Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
        };

        var btnAdd = new Button
        {
            Text = "+ Add condition",
            Location = new Point(12, 356),
            Size = new Size(130, 26),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };
        btnAdd.Click += (_, _) => AddRow(new FilterCondition());

        var btnPreview = new Button
        {
            Text = "Preview",
            Location = new Point(150, 356),
            Size = new Size(90, 26),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };
        btnPreview.Click += (_, _) => RunPreview();

        _lblMatches = new Label
        {
            Text = "",
            Location = new Point(250, 361),
            Size = new Size(300, 20),
            ForeColor = Color.DimGray,
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };

        var btnClear = new Button
        {
            Text = "Clear filter",
            Location = new Point(560, 392),
            Size = new Size(90, 28),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        btnClear.Click += (_, _) => ClearFilter();

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(658, 392),
            Size = new Size(90, 28),
            DialogResult = DialogResult.Cancel,
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };

        var btnApply = new Button
        {
            Text = "Apply",
            Location = new Point(756, 392),
            Size = new Size(96, 28),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        btnApply.Click += (_, _) => ApplyFilter();

        Controls.AddRange(new Control[]
        {
            lblHint, _pnlRows, btnAdd, btnPreview, _lblMatches, btnClear, btnCancel, btnApply
        });

        AcceptButton = btnApply;
        CancelButton = btnCancel;

        LoadConditions(existingFilter);
    }

    // ── Condition rows ───────────────────────────────────────────────────

    private void LoadConditions(FilterDefinition? existing)
    {
        if (existing != null && !existing.IsEmpty && existing.FileType == _fileType)
        {
            foreach (var condition in existing.Conditions)
                AddRow(condition.Clone());
        }
        else
        {
            AddRow(new FilterCondition());
        }
    }

    private void AddRow(FilterCondition condition)
    {
        var row = new ConditionRow(this, condition, _rows.Count == 0);
        row.RemoveRequested += () => RemoveRow(row);

        // Rows built after the form loaded missed its one-shot DPI pass, and
        // would otherwise be a fraction of the height of the row above them.
        ScaleNewControl(row.Container);

        _rows.Add(row);
        _pnlRows.Controls.Add(row.Container);
        RefreshRowConjunctions();
    }

    private void RemoveRow(ConditionRow row)
    {
        // The dialog always shows at least one row: an empty list would leave
        // the user with nothing to type into and no obvious way back.
        if (_rows.Count == 1)
        {
            row.Reset();
            return;
        }

        _rows.Remove(row);
        _pnlRows.Controls.Remove(row.Container);
        row.Container.Dispose();
        RefreshRowConjunctions();
    }

    /// <summary>Only the first row has nothing above it to join to.</summary>
    private void RefreshRowConjunctions()
    {
        for (int i = 0; i < _rows.Count; i++)
            _rows[i].SetIsFirst(i == 0);
    }

    // ── Actions ──────────────────────────────────────────────────────────

    /// <summary>
    /// Collects the rows into a filter, reporting the first problem found
    /// rather than silently dropping a half-finished condition.
    /// </summary>
    private bool TryBuildFilter(out FilterDefinition filter)
    {
        filter = new FilterDefinition { FileType = _fileType };

        for (int i = 0; i < _rows.Count; i++)
        {
            var condition = _rows[i].ToCondition();

            if (string.IsNullOrWhiteSpace(condition.FieldId))
            {
                // A single untouched row means "no filter", not an error.
                if (_rows.Count == 1 && string.IsNullOrWhiteSpace(condition.Value))
                    return true;

                return Invalid($"Condition {i + 1} has no field selected.");
            }

            bool needsValue = condition.Operator is not (FilterOperator.IsEmpty or FilterOperator.IsNotEmpty);

            if (needsValue && string.IsNullOrWhiteSpace(condition.Value))
                return Invalid($"Condition {i + 1} needs a value.");

            if (condition.Operator == FilterOperator.Between)
            {
                if (string.IsNullOrWhiteSpace(condition.Value2))
                    return Invalid($"Condition {i + 1} needs both ends of the range.");

                if (string.Compare(condition.Value.Trim(), condition.Value2.Trim(),
                        StringComparison.OrdinalIgnoreCase) > 0)
                {
                    return Invalid($"Condition {i + 1}: the range start is after its end.");
                }
            }

            filter.Conditions.Add(condition);
        }

        return true;
    }

    private bool Invalid(string message)
    {
        MessageBox.Show(message, "Filter", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        return false;
    }

    /// <summary>
    /// Runs the filter as it currently stands and reports the count, so the
    /// user can tell a filter that matches nothing from one they mistyped
    /// before committing to it.
    /// </summary>
    private void RunPreview()
    {
        if (!TryBuildFilter(out var filter))
            return;

        if (filter.IsEmpty)
        {
            _lblMatches.Text = $"No conditions: all {_recordCount:N0} records.";
            return;
        }

        try
        {
            Cursor = Cursors.WaitCursor;

            var source = _sourceFactory(filter);
            if (source == null)
            {
                _lblMatches.Text = "Preview unavailable for this file type.";
                return;
            }

            int matches = _filterService.GetMatchingIndices(filter, source).Length;
            _lblMatches.Text = $"Matches: {matches:N0} of {_recordCount:N0}";
        }
        finally
        {
            Cursor = Cursors.Default;
        }
    }

    private void ApplyFilter()
    {
        if (!TryBuildFilter(out var filter))
            return;

        Result = filter;
        DialogResult = DialogResult.OK;
        Close();
    }

    private void ClearFilter()
    {
        Result = new FilterDefinition { FileType = _fileType };
        DialogResult = DialogResult.OK;
        Close();
    }

    // ── Field selection, shared by the rows ──────────────────────────────

    /// <summary>
    /// Prompts for a field, using the NAACCR picker for XML and the fixed
    /// catalogue of parsed properties for HL7. Returns null when cancelled.
    /// </summary>
    internal string? PromptForField(string? currentFieldId)
    {
        if (_fileType == "hl7")
            return PromptForHl7Field(currentFieldId);

        using var picker = new NaaccrFieldPickerDialog(
            _dictionary, currentFieldId, _presentFieldIds, allowUnmap: false);

        return picker.ShowDialog(this) == DialogResult.OK ? picker.SelectedXmlId : null;
    }

    private string? PromptForHl7Field(string? currentFieldId)
    {
        using var dialog = new Hl7FieldPickerDialog(currentFieldId);
        return dialog.ShowDialog(this) == DialogResult.OK ? dialog.SelectedFieldId : null;
    }

    /// <summary>The label shown on a row's field button.</summary>
    internal string FieldLabel(string fieldId)
    {
        if (string.IsNullOrEmpty(fieldId))
            return "Choose field...";

        if (_fileType == "hl7")
            return Hl7FilterFields.GetDisplayName(fieldId);

        var item = _dictionary.GetItemByXmlId(fieldId);
        return item == null ? fieldId : $"{item.Name} ({fieldId})";
    }

    /// <summary>
    /// True when a field holds a NAACCR date, which is what makes the Year part
    /// the useful default rather than an exact 8-digit match.
    /// </summary>
    internal bool IsDateField(string fieldId)
    {
        if (string.IsNullOrEmpty(fieldId))
            return false;

        if (_fileType == "hl7")
            return fieldId.Contains("Date", StringComparison.OrdinalIgnoreCase);

        return string.Equals(_dictionary.GetItemByXmlId(fieldId)?.DataType, "date", StringComparison.OrdinalIgnoreCase);
    }

    // ── One condition row ────────────────────────────────────────────────

    /// <summary>
    /// A single line of the filter: [AND/OR] [field] [part] [operator] [value] [x].
    /// The value boxes appear and disappear with the operator, so a row never
    /// shows an input the chosen operator ignores.
    /// </summary>
    private sealed class ConditionRow
    {
        internal const int RowHeight = 30;

        private readonly FilterForm _owner;
        private readonly ComboBox _cboConjunction;
        private readonly Button _btnField;
        private readonly ComboBox _cboPart;
        private readonly ComboBox _cboOperator;
        private readonly TextBox _txtValue;
        private readonly Label _lblAnd;
        private readonly TextBox _txtValue2;

        private string _fieldId = "";

        public Panel Container { get; }

        public event Action? RemoveRequested;

        public ConditionRow(FilterForm owner, FilterCondition condition, bool isFirst)
        {
            _owner = owner;
            _fieldId = condition.FieldId;

            Container = new Panel
            {
                Size = new Size(800, RowHeight),
                Margin = new Padding(4, 3, 4, 3)
            };

            _cboConjunction = new ComboBox
            {
                Location = new Point(0, 3),
                Size = new Size(58, 24),
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            _cboConjunction.Items.AddRange(new object[] { "AND", "OR" });
            _cboConjunction.SelectedIndex = condition.Conjunction == FilterConjunction.Or ? 1 : 0;

            _btnField = new Button
            {
                Location = new Point(64, 3),
                Size = new Size(230, 24),
                TextAlign = ContentAlignment.MiddleLeft,
                Text = owner.FieldLabel(condition.FieldId)
            };
            _btnField.Click += (_, _) => ChooseField();

            _cboPart = new ComboBox
            {
                Location = new Point(300, 3),
                Size = new Size(110, 24),
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            _cboPart.Items.AddRange(new object[]
            {
                new PartChoice(FieldPart.Whole, "whole value"),
                new PartChoice(FieldPart.Year, "year (1-4)"),
                new PartChoice(FieldPart.YearMonth, "year+month (1-6)"),
                new PartChoice(FieldPart.Date, "date (1-8)")
            });
            SelectPart(condition.Part);

            _cboOperator = new ComboBox
            {
                Location = new Point(416, 3),
                Size = new Size(130, 24),
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            _cboOperator.Items.AddRange(OperatorChoices);
            SelectOperator(condition.Operator);
            _cboOperator.SelectedIndexChanged += (_, _) => UpdateValueVisibility();

            _txtValue = new TextBox
            {
                Location = new Point(552, 3),
                Size = new Size(110, 24),
                Text = condition.Value
            };

            _lblAnd = new Label
            {
                Location = new Point(666, 7),
                Size = new Size(28, 18),
                Text = "and",
                TextAlign = ContentAlignment.MiddleCenter
            };

            _txtValue2 = new TextBox
            {
                Location = new Point(696, 3),
                Size = new Size(80, 24),
                Text = condition.Value2
            };

            var btnRemove = new Button
            {
                Location = new Point(782, 3),
                Size = new Size(24, 24),
                Text = "✕",
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 8f)
            };
            btnRemove.FlatAppearance.BorderSize = 0;
            btnRemove.Click += (_, _) => RemoveRequested?.Invoke();

            Container.Controls.AddRange(new Control[]
            {
                _cboConjunction, _btnField, _cboPart, _cboOperator, _txtValue, _lblAnd, _txtValue2, btnRemove
            });

            SetIsFirst(isFirst);
            UpdateValueVisibility();
        }

        /// <summary>The first row joins to nothing, so it hides its conjunction.</summary>
        public void SetIsFirst(bool isFirst) => _cboConjunction.Visible = !isFirst;

        public void Reset()
        {
            _fieldId = "";
            _btnField.Text = _owner.FieldLabel("");
            _txtValue.Text = "";
            _txtValue2.Text = "";
            SelectPart(FieldPart.Whole);
            SelectOperator(FilterOperator.Equals);
            UpdateValueVisibility();
        }

        public FilterCondition ToCondition() => new()
        {
            Conjunction = _cboConjunction.SelectedIndex == 1 ? FilterConjunction.Or : FilterConjunction.And,
            FieldId = _fieldId,
            Part = ((PartChoice)_cboPart.SelectedItem!).Part,
            Operator = ((OperatorChoice)_cboOperator.SelectedItem!).Operator,
            Value = _txtValue.Text,
            Value2 = _txtValue2.Text
        };

        private void ChooseField()
        {
            var picked = _owner.PromptForField(_fieldId);
            if (picked == null) return;

            bool wasUnset = string.IsNullOrEmpty(_fieldId);
            _fieldId = picked;
            _btnField.Text = _owner.FieldLabel(picked);

            // A date field almost always wants a year comparison, which is the
            // whole reason the part selector exists. Only suggested on a fresh
            // row so an explicit choice is never overwritten.
            if (wasUnset && _owner.IsDateField(picked))
                SelectPart(FieldPart.Year);
        }

        private void UpdateValueVisibility()
        {
            var op = ((OperatorChoice)_cboOperator.SelectedItem!).Operator;
            bool between = op == FilterOperator.Between;
            bool needsValue = op is not (FilterOperator.IsEmpty or FilterOperator.IsNotEmpty);

            _txtValue.Visible = needsValue;
            _lblAnd.Visible = between;
            _txtValue2.Visible = between;
        }

        private void SelectPart(FieldPart part)
        {
            for (int i = 0; i < _cboPart.Items.Count; i++)
            {
                if (((PartChoice)_cboPart.Items[i]!).Part == part)
                {
                    _cboPart.SelectedIndex = i;
                    return;
                }
            }
        }

        private void SelectOperator(FilterOperator op)
        {
            for (int i = 0; i < _cboOperator.Items.Count; i++)
            {
                if (((OperatorChoice)_cboOperator.Items[i]!).Operator == op)
                {
                    _cboOperator.SelectedIndex = i;
                    return;
                }
            }

            _cboOperator.SelectedIndex = 0;
        }

        private static readonly object[] OperatorChoices =
        {
            new OperatorChoice(FilterOperator.Equals, "="),
            new OperatorChoice(FilterOperator.NotEquals, "<>"),
            new OperatorChoice(FilterOperator.Contains, "contains"),
            new OperatorChoice(FilterOperator.NotContains, "does not contain"),
            new OperatorChoice(FilterOperator.StartsWith, "starts with"),
            new OperatorChoice(FilterOperator.EndsWith, "ends with"),
            new OperatorChoice(FilterOperator.Like, "LIKE (% _)"),
            new OperatorChoice(FilterOperator.NotLike, "NOT LIKE"),
            new OperatorChoice(FilterOperator.In, "IN (a,b,c)"),
            new OperatorChoice(FilterOperator.Between, "BETWEEN"),
            new OperatorChoice(FilterOperator.GreaterThan, ">"),
            new OperatorChoice(FilterOperator.GreaterOrEqual, ">="),
            new OperatorChoice(FilterOperator.LessThan, "<"),
            new OperatorChoice(FilterOperator.LessOrEqual, "<="),
            new OperatorChoice(FilterOperator.IsEmpty, "is empty"),
            new OperatorChoice(FilterOperator.IsNotEmpty, "is not empty")
        };

        private sealed record OperatorChoice(FilterOperator Operator, string Label)
        {
            public override string ToString() => Label;
        }

        private sealed record PartChoice(FieldPart Part, string Label)
        {
            public override string ToString() => Label;
        }
    }
}

/// <summary>
/// Picks one of the HL7 fields the parser extracts. A plain list rather than a
/// searchable dialog: there are fourteen of them, all on one screen.
/// </summary>
internal class Hl7FieldPickerDialog : ParratFormBase
{
    private readonly ListBox _lstFields;

    public string? SelectedFieldId { get; private set; }

    public Hl7FieldPickerDialog(string? currentFieldId)
    {
        SelectedFieldId = currentFieldId;

        Text = "Select HL7 Field";
        Size = new Size(380, 400);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        _lstFields = new ListBox
        {
            Location = new Point(10, 10),
            Size = new Size(345, 300)
        };
        _lstFields.DoubleClick += (_, _) => AcceptSelection();

        foreach (var field in Hl7FilterFields.All)
        {
            int index = _lstFields.Items.Add(field.DisplayName);
            if (string.Equals(field.Id, currentFieldId, StringComparison.OrdinalIgnoreCase))
                _lstFields.SelectedIndex = index;
        }

        var btnOk = new Button
        {
            Text = "OK",
            Location = new Point(180, 322),
            Width = 80
        };
        btnOk.Click += (_, _) => AcceptSelection();

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(275, 322),
            Width = 80,
            DialogResult = DialogResult.Cancel
        };

        Controls.AddRange(new Control[] { _lstFields, btnOk, btnCancel });
        AcceptButton = btnOk;
        CancelButton = btnCancel;
    }

    private void AcceptSelection()
    {
        if (_lstFields.SelectedIndex < 0) return;

        SelectedFieldId = Hl7FilterFields.All[_lstFields.SelectedIndex].Id;
        DialogResult = DialogResult.OK;
        Close();
    }
}
