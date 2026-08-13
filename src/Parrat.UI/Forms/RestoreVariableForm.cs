using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;
using Parrat.UI.Controls;

namespace Parrat.UI.Forms;

/// <summary>
/// Rescues field values that were blanket-overwritten — every record given the
/// same reportingFacility, say — by matching each loaded record back to the
/// untouched original file on a key and restoring the original values.
///
/// The loaded file is never modified: the plan is previewed record by record,
/// and applying it writes an entirely new repaired XML file.
/// </summary>
public class RestoreVariableForm : ParratFormBase
{
    private readonly INaaccrDictionary _dictionary;
    private readonly IXmlFileService _xmlFileService;
    private readonly XmlDocument _damagedDoc;
    private readonly XmlNodeList _damagedTumors;
    private readonly XmlNamespaceManager _damagedNsMgr;
    private readonly IReadOnlyCollection<string>? _presentFieldIds;
    private readonly string? _currentFilePath;
    private readonly IParratLogger _logger;

    private readonly TextBox _txtOriginal;
    private readonly Label _lblOriginalCount;
    private readonly TextBox _txtKeyField;
    private readonly ListBox _lstFields;
    private readonly CheckBox _chkCaseInsensitive;
    private readonly AnnouncingLabel _lblSummary;
    private readonly DataGridView _gridPlan;
    private readonly Button _btnSave;

    private string _keyFieldId = "";
    private XmlNodeList? _originalTumors;
    private XmlNamespaceManager? _originalNsMgr;

    public RestoreVariableForm(
        INaaccrDictionary dictionary,
        IXmlFileService xmlFileService,
        XmlDocument damagedDoc,
        XmlNodeList damagedTumors,
        XmlNamespaceManager damagedNsMgr,
        IReadOnlyCollection<string>? presentFieldIds,
        string? currentFilePath,
        IParratLogger logger)
    {
        _dictionary = dictionary;
        _xmlFileService = xmlFileService;
        _damagedDoc = damagedDoc;
        _damagedTumors = damagedTumors;
        _damagedNsMgr = damagedNsMgr;
        _presentFieldIds = presentFieldIds;
        _currentFilePath = currentFilePath;
        _logger = logger;

        Text = $"Restore Variable from File ({damagedTumors.Count:N0} tumors loaded)";
        Size = new Size(960, 680);
        MinimumSize = new Size(820, 540);
        FormBorderStyle = FormBorderStyle.Sizable;
        MaximizeBox = true;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        var lblHint = new Label
        {
            Text = "Matches each loaded record to the original file by the key field and restores the chosen "
                 + "variables' original values. The loaded file is not changed; saving writes a new repaired XML file.",
            Location = new Point(12, 10),
            Size = new Size(920, 32),
            ForeColor = Color.DimGray,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };

        // ── Original file row ────────────────────────────────────────────
        var lblOriginal = new Label { Text = "Original file:", Location = new Point(12, 52), AutoSize = true };

        _txtOriginal = new TextBox
        {
            Location = new Point(110, 48),
            Size = new Size(560, 24),
            ReadOnly = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            AccessibleName = "Original file"
        };

        var btnBrowse = new Button
        {
            Text = "&Browse...",
            Location = new Point(680, 47),
            Size = new Size(100, 26),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            AccessibleDescription = "Opens the untouched original XML file"
        };
        btnBrowse.Click += (_, _) => BrowseOriginal();

        _lblOriginalCount = new Label
        {
            Text = "",
            Location = new Point(790, 52),
            Size = new Size(150, 18),
            ForeColor = Color.DimGray,
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };

        // ── Key field row ────────────────────────────────────────────────
        var lblKey = new Label { Text = "Match key:", Location = new Point(12, 84), AutoSize = true };

        _txtKeyField = new TextBox
        {
            Location = new Point(110, 80),
            Size = new Size(560, 24),
            ReadOnly = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            AccessibleName = "Match key field",
            AccessibleDescription = "The field records are matched on between the two files"
        };

        var btnKeyField = new Button
        {
            Text = "&Key Field...",
            Location = new Point(680, 79),
            Size = new Size(100, 26),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            AccessibleDescription = "Opens the NAACCR field picker for the match key"
        };
        btnKeyField.Click += (_, _) => PickKeyField();

        _chkCaseInsensitive = new CheckBox
        {
            Text = "Ignore c&ase",
            Location = new Point(790, 82),
            AutoSize = true,
            Checked = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };

        // ── Restore fields row ───────────────────────────────────────────
        var lblFields = new Label { Text = "Restore:", Location = new Point(12, 116), AutoSize = true };

        _lstFields = new ListBox
        {
            Location = new Point(110, 112),
            Size = new Size(560, 62),
            IntegralHeight = false,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            AccessibleName = "Variables to restore"
        };

        var btnAddField = new Button
        {
            Text = "A&dd...",
            Location = new Point(680, 112),
            Size = new Size(100, 26),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            AccessibleDescription = "Adds a tumor-level variable to restore"
        };
        btnAddField.Click += (_, _) => AddRestoreField();

        var btnRemoveField = new Button
        {
            Text = "Re&move",
            Location = new Point(680, 144),
            Size = new Size(100, 26),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            AccessibleDescription = "Removes the highlighted variable from the restore list"
        };
        btnRemoveField.Click += (_, _) =>
        {
            if (_lstFields.SelectedIndex >= 0)
                _lstFields.Items.RemoveAt(_lstFields.SelectedIndex);
        };

        // ── Preview ──────────────────────────────────────────────────────
        var btnPreview = new Button
        {
            Text = "&Preview",
            Location = new Point(12, 186),
            Size = new Size(90, 26),
            AccessibleDescription = "Plans the restore and lists every record's fate without writing anything"
        };
        btnPreview.Click += (_, _) => RunPreview();

        // Announcing: the plan summary answers the question the user just
        // asked, so it has to reach a screen reader as well as the screen.
        _lblSummary = new AnnouncingLabel
        {
            Text = "",
            Location = new Point(110, 191),
            Size = new Size(830, 20),
            ForeColor = Color.DimGray,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            AccessibleDescription = "Summary of the planned restore"
        };

        _gridPlan = new DataGridView
        {
            Location = new Point(12, 218),
            Size = new Size(928, 372),
            Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            RowHeadersVisible = false,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            AccessibleName = "Restore plan"
        };
        _gridPlan.Columns.Add("Record", "Record");
        _gridPlan.Columns.Add("Key", "Key");
        _gridPlan.Columns.Add("Field", "Field");
        _gridPlan.Columns.Add("Current", "Current");
        _gridPlan.Columns.Add("Original", "Original");
        _gridPlan.Columns.Add("Status", "Status");
        _gridPlan.Columns["Record"]!.FillWeight = 40;
        _gridPlan.Columns["Status"]!.FillWeight = 70;

        // ── Bottom buttons ───────────────────────────────────────────────
        var btnClose = new Button
        {
            Text = "Close",
            Location = new Point(742, 602),
            Size = new Size(90, 28),
            DialogResult = DialogResult.Cancel,
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            AccessibleDescription = "Closes the dialog; the loaded file is unchanged either way"
        };

        _btnSave = new Button
        {
            Text = "&Save Repaired XML...",
            Location = new Point(12, 602),
            Size = new Size(170, 28),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
            AccessibleDescription = "Writes a new XML file with the planned values restored"
        };
        _btnSave.Click += (_, _) => SaveRepaired();

        Controls.AddRange(new Control[]
        {
            lblHint, lblOriginal, _txtOriginal, btnBrowse, _lblOriginalCount,
            lblKey, _txtKeyField, btnKeyField, _chkCaseInsensitive,
            lblFields, _lstFields, btnAddField, btnRemoveField,
            btnPreview, _lblSummary, _gridPlan, _btnSave, btnClose
        });

        CancelButton = btnClose;

        SetKeyField(DefaultKeyField());
        _lstFields.Items.Add("reportingFacility");
    }

    // ── Setup helpers ────────────────────────────────────────────────────

    private string DefaultKeyField()
    {
        string[] preferred = { "pathReportNumber1", "accessionNumberHosp", "patientIdNumber" };

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
        _txtKeyField.Text = string.IsNullOrEmpty(name) || name == fieldId ? fieldId : $"{name} ({fieldId})";
    }

    private void PickKeyField()
    {
        using var picker = new NaaccrFieldPickerDialog(_dictionary, _keyFieldId, _presentFieldIds, allowUnmap: false);
        if (picker.ShowDialog(this) == DialogResult.OK && !string.IsNullOrEmpty(picker.SelectedXmlId))
            SetKeyField(picker.SelectedXmlId);
    }

    private void AddRestoreField()
    {
        using var picker = new NaaccrFieldPickerDialog(_dictionary, null, _presentFieldIds, allowUnmap: false);
        if (picker.ShowDialog(this) != DialogResult.OK || string.IsNullOrEmpty(picker.SelectedXmlId))
            return;

        var fieldId = picker.SelectedXmlId;

        if (_lstFields.Items.Contains(fieldId))
            return;

        // Restored values are written per tumor; a patient-level variable would
        // bleed the last tumor's value across every tumor of the patient.
        var parent = _dictionary.GetParentElement(fieldId);
        if (parent != "Tumor")
        {
            MessageBox.Show(
                $"{fieldId} is a {parent}-level variable. Only tumor-level variables can be restored per record.",
                "Restore Variable", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        _lstFields.Items.Add(fieldId);
    }

    private void BrowseOriginal()
    {
        try
        {
            using var ofd = new OpenFileDialog
            {
                Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*",
                Title = "Open Original XML File"
            };
            if (ofd.ShowDialog(this) != DialogResult.OK) return;

            if (!string.IsNullOrEmpty(_currentFilePath)
                && string.Equals(Path.GetFullPath(ofd.FileName), Path.GetFullPath(_currentFilePath), StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show("That is the loaded file itself. Choose the untouched original file.",
                    "Restore Variable", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var (_, tumors, nsMgr) = _xmlFileService.LoadNaaccrXml(ofd.FileName);

            _originalTumors = tumors;
            _originalNsMgr = nsMgr;
            _txtOriginal.Text = ofd.FileName;
            _lblOriginalCount.Text = $"{tumors.Count:N0} tumors";
        }
        catch (Exception ex)
        {
            _logger.LogError("Original file load failed", "RESTORE_VAR", ex);
            MessageBox.Show($"Error loading original XML: {ex.Message}", "Restore Variable",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // ── Planning ─────────────────────────────────────────────────────────

    private FieldRestorePlan? BuildPlan()
    {
        if (_originalTumors == null || _originalNsMgr == null)
        {
            MessageBox.Show("Browse to the untouched original XML file first.",
                "Restore Variable", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return null;
        }

        if (_lstFields.Items.Count == 0)
        {
            MessageBox.Show("Add at least one variable to restore.",
                "Restore Variable", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return null;
        }

        var fields = _lstFields.Items.Cast<object>().Select(f => f.ToString() ?? "").ToList();

        return FieldRestoreHelper.BuildPlan(
            _damagedTumors, _damagedNsMgr,
            _originalTumors, _originalNsMgr,
            _keyFieldId, fields, _chkCaseInsensitive.Checked);
    }

    private FieldRestorePlan? RunPreview()
    {
        var plan = BuildPlan();
        if (plan == null) return null;

        _gridPlan.SuspendLayout();
        _gridPlan.Rows.Clear();

        foreach (var row in plan.Rows)
        {
            int gridRow = _gridPlan.Rows.Add(
                row.TumorIndex + 1, row.KeyValue, row.FieldId,
                row.CurrentValue, row.OriginalValue, DescribeStatus(row.Status));

            if (row.Status == RestoreStatus.Restore)
                _gridPlan.Rows[gridRow].DefaultCellStyle.BackColor = Color.FromArgb(225, 240, 225);
            else if (row.Status is RestoreStatus.Ambiguous or RestoreStatus.NoMatch or RestoreStatus.MissingKey)
                _gridPlan.Rows[gridRow].DefaultCellStyle.BackColor = Color.FromArgb(250, 230, 225);
        }

        _gridPlan.ResumeLayout();

        _lblSummary.ForeColor = plan.RestoreCount > 0 ? Color.DarkSlateGray : Color.DarkRed;
        _lblSummary.Text = Summarize(plan);

        return plan;
    }

    private static string Summarize(FieldRestorePlan plan)
    {
        var parts = new List<string> { $"{plan.RestoreCount:N0} to restore" };

        if (plan.AlreadyCorrectCount > 0) parts.Add($"{plan.AlreadyCorrectCount:N0} already correct");
        if (plan.NoMatchCount > 0) parts.Add($"{plan.NoMatchCount:N0} with no match in the original");
        if (plan.MissingKeyCount > 0) parts.Add($"{plan.MissingKeyCount:N0} missing the key");
        if (plan.AmbiguousCount > 0) parts.Add($"{plan.AmbiguousCount:N0} ambiguous (conflicting originals)");
        if (plan.OriginalEmptyCount > 0) parts.Add($"{plan.OriginalEmptyCount:N0} empty in the original");

        return string.Join("; ", parts) + ".";
    }

    private static string DescribeStatus(RestoreStatus status) => status switch
    {
        RestoreStatus.Restore => "Restore",
        RestoreStatus.AlreadyCorrect => "Already correct",
        RestoreStatus.NoMatch => "No match in original",
        RestoreStatus.MissingKey => "Missing key",
        RestoreStatus.Ambiguous => "Ambiguous",
        RestoreStatus.OriginalEmpty => "Empty in original",
        _ => status.ToString()
    };

    // ── Saving ───────────────────────────────────────────────────────────

    private void SaveRepaired()
    {
        // Re-plan at save time so the file written always reflects the current
        // inputs, whether or not Preview was pressed since they last changed.
        var plan = RunPreview();
        if (plan == null) return;

        if (plan.RestoreCount == 0)
        {
            MessageBox.Show("Nothing to restore: no record has a differing original value.",
                "Restore Variable", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            using var sfd = new SaveFileDialog
            {
                Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*",
                Title = "Save Repaired XML File"
            };
            if (!string.IsNullOrEmpty(_currentFilePath))
            {
                sfd.FileName = Path.GetFileNameWithoutExtension(_currentFilePath) + "_repaired.xml";
                sfd.InitialDirectory = Path.GetDirectoryName(_currentFilePath) ?? "";
            }

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            if (!string.IsNullOrEmpty(_currentFilePath)
                && string.Equals(Path.GetFullPath(sfd.FileName), Path.GetFullPath(_currentFilePath), StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show("Choose a new file name: the repair is written as a new file, never over the loaded one.",
                    "Restore Variable", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var repaired = FieldRestoreHelper.BuildRepairedDocument(_damagedDoc, _damagedNsMgr, plan);

            var settings = new XmlWriterSettings
            {
                Indent = true,
                IndentChars = "  ",
                NewLineChars = "\r\n",
                NewLineHandling = NewLineHandling.Replace
            };
            using (var writer = XmlWriter.Create(sfd.FileName, settings))
                repaired.Save(writer);

            _logger.Log("INFO",
                $"Restored {plan.RestoreCount} value(s) on {_keyFieldId} into {Path.GetFileName(sfd.FileName)}", "RESTORE_VAR");

            MessageBox.Show(
                $"Restored {plan.RestoreCount:N0} value(s) and wrote:\n{sfd.FileName}\n\n"
                + "The loaded file was not changed. Open the repaired file to continue working with it.",
                "Restore Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _logger.LogError("Restore save failed", "RESTORE_VAR", ex);
            MessageBox.Show($"Error saving repaired XML: {ex.Message}", "Restore Variable",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
