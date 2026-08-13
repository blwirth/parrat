using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;
using Parrat.UI.Controls;

namespace Parrat.UI.Forms;

/// <summary>
/// Checks the Selected box on every tumor identified by a list of key values,
/// so a reviewed worklist — "these 120 cases are reportable" — becomes an
/// export selection in one step instead of 120 clicks.
///
/// The values can be pasted straight in (one per line, or comma-separated) or
/// pulled out of a CSV or Excel column, optionally keeping only the rows whose
/// status column holds a chosen value: "export the cases marked A, not B or C".
/// </summary>
public class SelectFromListForm : ParratFormBase
{
    private readonly INaaccrDictionary _dictionary;
    private readonly ICsvParserService _csvParser;
    private readonly IXlsxParserService _xlsxParser;
    private readonly XmlNodeList _tumors;
    private readonly XmlNamespaceManager _nsMgr;
    private readonly IReadOnlyCollection<string>? _presentFieldIds;
    private readonly IParratLogger _logger;

    private readonly TextBox _txtField;
    private readonly TextBox _txtValues;
    private readonly Label _lblCsvFile;
    private readonly ComboBox _cboKeyColumn;
    private readonly ComboBox _cboFilterColumn;
    private readonly CheckedListBox _lstFilterValues;
    private readonly Button _btnInsert;
    private readonly CheckBox _chkCaseInsensitive;
    private readonly RadioButton _rdoReplace;
    private readonly RadioButton _rdoAdd;
    private readonly AnnouncingLabel _lblPreview;
    private readonly TextBox _txtUnmatched;

    private string _keyFieldId = "";
    private CsvParseResult? _csv;

    /// <summary>0-based tumor indices to check; meaningful only on OK.</summary>
    public int[] MatchedIndices { get; private set; } = Array.Empty<int>();

    /// <summary>True to keep existing checkmarks, false to replace them.</summary>
    public bool AddToSelection => _rdoAdd.Checked;

    /// <summary>The field the list was matched on, for the status line.</summary>
    public string KeyFieldId => _keyFieldId;

    public SelectFromListForm(
        INaaccrDictionary dictionary,
        ICsvParserService csvParser,
        IXlsxParserService xlsxParser,
        XmlNodeList tumors,
        XmlNamespaceManager nsMgr,
        IReadOnlyCollection<string>? presentFieldIds,
        IParratLogger logger)
    {
        _dictionary = dictionary;
        _csvParser = csvParser;
        _xlsxParser = xlsxParser;
        _tumors = tumors;
        _nsMgr = nsMgr;
        _presentFieldIds = presentFieldIds;
        _logger = logger;

        Text = $"Select Records from List ({tumors.Count:N0} tumors loaded)";
        ClientSize = new Size(712, 656);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        var lblHint = new Label
        {
            Text = "Checks the Selected box on every record whose key field matches a listed value. "
                 + "A patient-level key (an MRN, say) selects all of that patient's tumors; review before exporting.",
            Location = new Point(12, 10),
            Size = new Size(688, 32),
            ForeColor = Color.DimGray
        };

        var lblField = new Label { Text = "Key field:", Location = new Point(12, 50), AutoSize = true };

        _txtField = new TextBox
        {
            Location = new Point(100, 46),
            Size = new Size(480, 24),
            ReadOnly = true,
            AccessibleName = "Key field",
            AccessibleDescription = "The NAACCR field the listed values identify records by"
        };

        var btnField = new Button
        {
            Text = "&Field...",
            Location = new Point(590, 45),
            Size = new Size(110, 26),
            AccessibleDescription = "Opens the NAACCR field picker"
        };
        btnField.Click += (_, _) => PickField();

        var lblValues = new Label
        {
            Text = "Key values (one per line, or comma-separated):",
            Location = new Point(12, 80),
            AutoSize = true
        };

        _txtValues = new TextBox
        {
            Location = new Point(12, 100),
            Size = new Size(688, 108),
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            AcceptsReturn = true,
            AccessibleName = "Key values"
        };

        var grpCsv = new GroupBox
        {
            Text = "Load values from a CSV or Excel list",
            Location = new Point(12, 216),
            Size = new Size(688, 210)
        };

        var btnBrowseCsv = new Button
        {
            Text = "&Browse CSV/Excel...",
            Location = new Point(10, 22),
            Size = new Size(130, 26),
            AccessibleDescription = "Opens a CSV or Excel file whose columns supply the key values"
        };
        btnBrowseCsv.Click += (_, _) => BrowseCsv();

        _lblCsvFile = new Label
        {
            Text = "No file loaded",
            Location = new Point(150, 27),
            Size = new Size(528, 18),
            ForeColor = Color.DimGray,
            AutoEllipsis = true
        };

        var lblKeyCol = new Label { Text = "Key values come from:", Location = new Point(10, 60), AutoSize = true };

        _cboKeyColumn = new ComboBox
        {
            Location = new Point(170, 56),
            Size = new Size(220, 24),
            DropDownStyle = ComboBoxStyle.DropDownList,
            Enabled = false,
            AccessibleName = "Key column"
        };

        var lblFilterCol = new Label { Text = "Use only rows where:", Location = new Point(10, 92), AutoSize = true };

        _cboFilterColumn = new ComboBox
        {
            Location = new Point(170, 88),
            Size = new Size(220, 24),
            DropDownStyle = ComboBoxStyle.DropDownList,
            Enabled = false,
            AccessibleName = "Filter column"
        };
        _cboFilterColumn.SelectedIndexChanged += (_, _) => RefreshFilterValues();

        var lblIsOneOf = new Label
        {
            Text = "is one of the checked values:",
            Location = new Point(400, 92),
            AutoSize = true
        };

        _lstFilterValues = new CheckedListBox
        {
            Location = new Point(400, 112),
            Size = new Size(278, 58),
            CheckOnClick = true,
            Enabled = false,
            IntegralHeight = false,
            AccessibleName = "Filter values to include"
        };

        _btnInsert = new Button
        {
            Text = "&Insert values above",
            Location = new Point(170, 174),
            Size = new Size(220, 26),
            Enabled = false,
            AccessibleDescription = "Replaces the key values box with the values read from the CSV"
        };
        _btnInsert.Click += (_, _) => InsertCsvValues();

        grpCsv.Controls.AddRange(new Control[]
        {
            btnBrowseCsv, _lblCsvFile, lblKeyCol, _cboKeyColumn,
            lblFilterCol, _cboFilterColumn, lblIsOneOf, _lstFilterValues, _btnInsert
        });

        _chkCaseInsensitive = new CheckBox
        {
            Text = "Ignore &case",
            Location = new Point(12, 434),
            AutoSize = true,
            Checked = true
        };

        _rdoReplace = new RadioButton
        {
            Text = "&Replace current selection",
            Location = new Point(160, 434),
            AutoSize = true,
            Checked = true
        };

        _rdoAdd = new RadioButton
        {
            Text = "&Add to current selection",
            Location = new Point(390, 434),
            AutoSize = true
        };

        var btnPreview = new Button
        {
            Text = "&Preview",
            Location = new Point(12, 464),
            Size = new Size(90, 26),
            AccessibleDescription = "Counts the matching records without selecting them"
        };
        btnPreview.Click += (_, _) => RunMatch();

        // Announcing: the match count answers the question the user just asked,
        // so it has to reach a screen reader as well as the screen.
        _lblPreview = new AnnouncingLabel
        {
            Text = "",
            Location = new Point(110, 469),
            Size = new Size(590, 20),
            ForeColor = Color.DimGray,
            AccessibleDescription = "Result of the last preview"
        };

        var lblUnmatched = new Label { Text = "Values with no match:", Location = new Point(12, 496), AutoSize = true };

        _txtUnmatched = new TextBox
        {
            Location = new Point(12, 516),
            Size = new Size(688, 90),
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            AccessibleName = "Values with no match"
        };

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(506, 616),
            Size = new Size(90, 28),
            DialogResult = DialogResult.Cancel,
            AccessibleDescription = "Closes the dialog without changing the selection"
        };

        var btnOk = new Button
        {
            Text = "&Select",
            Location = new Point(604, 616),
            Size = new Size(96, 28),
            AccessibleDescription = "Checks the Selected box on every matching record"
        };
        btnOk.Click += (_, _) => AcceptSelection();

        Controls.AddRange(new Control[]
        {
            lblHint, lblField, _txtField, btnField, lblValues, _txtValues, grpCsv,
            _chkCaseInsensitive, _rdoReplace, _rdoAdd,
            btnPreview, _lblPreview, lblUnmatched, _txtUnmatched, btnCancel, btnOk
        });

        AcceptButton = btnOk;
        CancelButton = btnCancel;

        SetKeyField(DefaultKeyField());
    }

    // ── Key field ────────────────────────────────────────────────────────

    /// <summary>
    /// The field a registrar most likely keys a worklist by, preferring ids the
    /// loaded file actually contains.
    /// </summary>
    private string DefaultKeyField()
    {
        string[] preferred = { "patientIdNumber", "pathReportNumber1", "medicalRecordNumber", "accessionNumberHosp" };

        if (_presentFieldIds != null)
        {
            foreach (var id in preferred)
            {
                if (_presentFieldIds.Contains(id))
                    return id;
            }
        }

        return preferred[0];
    }

    private void SetKeyField(string fieldId)
    {
        _keyFieldId = fieldId;
        var name = _dictionary.GetDisplayName(fieldId);
        _txtField.Text = string.IsNullOrEmpty(name) || name == fieldId ? fieldId : $"{name} ({fieldId})";
    }

    private void PickField()
    {
        using var picker = new NaaccrFieldPickerDialog(_dictionary, _keyFieldId, _presentFieldIds, allowUnmap: false);
        if (picker.ShowDialog(this) == DialogResult.OK && !string.IsNullOrEmpty(picker.SelectedXmlId))
            SetKeyField(picker.SelectedXmlId);
    }

    // ── CSV list ─────────────────────────────────────────────────────────

    private void BrowseCsv()
    {
        try
        {
            using var ofd = new OpenFileDialog
            {
                Filter = "List files (*.csv;*.xlsx)|*.csv;*.xlsx|CSV files (*.csv)|*.csv|Excel files (*.xlsx)|*.xlsx|All files (*.*)|*.*",
                Title = "Open CSV or Excel List"
            };
            if (ofd.ShowDialog(this) != DialogResult.OK) return;

            bool isXlsx = Path.GetExtension(ofd.FileName).Equals(".xlsx", StringComparison.OrdinalIgnoreCase);
            var csv = isXlsx ? _xlsxParser.Parse(ofd.FileName) : _csvParser.Parse(ofd.FileName);
            if (csv.ColumnCount == 0 || csv.RowCount == 0)
            {
                MessageBox.Show("The file has no data rows.", "Select from List",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            _csv = csv;
            _lblCsvFile.Text = $"{Path.GetFileName(ofd.FileName)} ({csv.RowCount:N0} rows)";

            _cboKeyColumn.Items.Clear();
            _cboKeyColumn.Items.AddRange(csv.Headers.Cast<object>().ToArray());
            _cboKeyColumn.SelectedIndex = 0;
            _cboKeyColumn.Enabled = true;

            _cboFilterColumn.Items.Clear();
            _cboFilterColumn.Items.Add("(every row)");
            _cboFilterColumn.Items.AddRange(csv.Headers.Cast<object>().ToArray());
            _cboFilterColumn.SelectedIndex = 0;
            _cboFilterColumn.Enabled = true;

            _btnInsert.Enabled = true;
        }
        catch (Exception ex)
        {
            _logger.LogError("List file load failed", "SELECT_LIST", ex);
            MessageBox.Show($"Error reading list file: {ex.Message}", "Select from List",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void RefreshFilterValues()
    {
        _lstFilterValues.Items.Clear();

        int filterIndex = _cboFilterColumn.SelectedIndex - 1;
        if (_csv == null || filterIndex < 0)
        {
            _lstFilterValues.Enabled = false;
            return;
        }

        foreach (var value in ListSelectionHelper.DistinctColumnValues(_csv, filterIndex))
            _lstFilterValues.Items.Add(value, false);

        _lstFilterValues.Enabled = true;
    }

    private void InsertCsvValues()
    {
        if (_csv == null) return;

        int keyIndex = _cboKeyColumn.SelectedIndex;
        int filterIndex = _cboFilterColumn.SelectedIndex - 1;

        var included = _lstFilterValues.CheckedItems.Cast<object>()
            .Select(v => v.ToString() ?? "").ToList();

        if (filterIndex >= 0 && included.Count == 0)
        {
            MessageBox.Show("Check at least one value to include, or set the filter column back to \"(every row)\".",
                "Select from List", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var values = ListSelectionHelper.ExtractKeyValues(_csv, keyIndex, filterIndex, included);
        if (values.Count == 0)
        {
            MessageBox.Show("No key values found in the chosen column for the included rows.",
                "Select from List", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        _txtValues.Text = string.Join(Environment.NewLine, values);
        _lblPreview.Text = $"Inserted {values.Count:N0} value(s) from the list file — Preview counts the matches.";
    }

    // ── Matching ─────────────────────────────────────────────────────────

    private ListMatchResult? RunMatch()
    {
        if (string.IsNullOrEmpty(_keyFieldId))
        {
            MessageBox.Show("Choose the key field the values identify records by.",
                "Select from List", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return null;
        }

        var values = ListSelectionHelper.ParseValues(_txtValues.Text);
        if (values.Count == 0)
        {
            MessageBox.Show("Enter or load at least one key value.",
                "Select from List", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return null;
        }

        var result = ListSelectionHelper.MatchTumors(
            _tumors, _nsMgr, _keyFieldId, values, _chkCaseInsensitive.Checked);

        int matchedValues = result.ValueCount - result.UnmatchedValues.Count;
        var text = $"{matchedValues:N0} of {result.ValueCount:N0} values matched {result.MatchedIndices.Length:N0} tumor(s)";
        if (result.MultiMatchValues.Count > 0)
            text += $"; {result.MultiMatchValues.Count:N0} value(s) matched more than one tumor";

        _lblPreview.ForeColor = result.UnmatchedValues.Count > 0 ? Color.DarkRed : Color.DarkSlateGray;
        _lblPreview.Text = text;
        _txtUnmatched.Text = string.Join(Environment.NewLine, result.UnmatchedValues);

        return result;
    }

    private void AcceptSelection()
    {
        var result = RunMatch();
        if (result == null) return;

        if (result.MatchedIndices.Length == 0)
        {
            MessageBox.Show("No records match the listed values, so there is nothing to select.\n\n"
                + "Check that the key field is the one the list was built from.",
                "Select from List", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (result.UnmatchedValues.Count > 0)
        {
            var proceed = MessageBox.Show(
                $"{result.UnmatchedValues.Count:N0} of {result.ValueCount:N0} values matched no record "
                + "(listed in \"Values with no match\").\n\nSelect the "
                + $"{result.MatchedIndices.Length:N0} matching record(s) anyway?",
                "Some Values Not Found", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
            if (proceed != DialogResult.OK) return;
        }

        MatchedIndices = result.MatchedIndices;
        DialogResult = DialogResult.OK;
    }
}
