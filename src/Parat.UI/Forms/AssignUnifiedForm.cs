using System.Data;
using System.Drawing;
using System.Windows.Forms;
using System.Xml;
using Parat.Core.Interfaces;

namespace Parat.UI.Forms;

/// <summary>
/// Combined dialog for assigning site/laterality, facility, and patient IDs.
/// Ported from ui/assign-unified-ui.ps1 and ui/assign-site-laterality-ui.ps1.
/// </summary>
public class AssignUnifiedForm : Form
{
    private readonly IUnifiedAssignmentService _unifiedService;
    private readonly ISiteLateralityService _siteLateralityService;
    private readonly IFacilityAssignmentService _facilityService;

    // ── Options dialog controls ──────────────────────────────────────────
    private CheckBox _chkSite = null!;
    private CheckBox _chkSiteOverride = null!;
    private CheckBox _chkLat = null!;
    private CheckBox _chkLatOverride = null!;
    private CheckBox _chkFacility = null!;
    private TextBox _txtFacilityNum = null!;
    private CheckBox _chkFacilityOverride = null!;
    private CheckBox _chkPid = null!;
    private TextBox _txtStartingNum = null!;
    private Label _lblStartingNumHint = null!;
    private RadioButton _rbPidMissing = null!;
    private RadioButton _rbPidOverwrite = null!;
    private RadioButton _rbPidReplaceZeros = null!;

    /// <summary>The assignment options collected when the user clicks Analyze.</summary>
    public Dictionary<string, object>? ResultOptions { get; private set; }

    public AssignUnifiedForm(
        IUnifiedAssignmentService unifiedService,
        ISiteLateralityService siteLateralityService,
        IFacilityAssignmentService facilityService,
        string filePath,
        int tumorCount,
        int patientCount,
        XmlNodeList tumors,
        XmlNamespaceManager nsMgr)
    {
        _unifiedService = unifiedService;
        _siteLateralityService = siteLateralityService;
        _facilityService = facilityService;

        InitializeControls(filePath, tumorCount, patientCount, tumors, nsMgr);
    }

    private void InitializeControls(
        string filePath, int tumorCount, int patientCount,
        XmlNodeList tumors, XmlNamespaceManager nsMgr)
    {
        // Detect facility from filename
        var fileName = Path.GetFileNameWithoutExtension(filePath);
        var detectedFacility = _facilityService.GetFacilityFromFilename(filePath) ?? "";

        // Scan existing values
        int tumorsWithSite = 0, tumorsWithLaterality = 0, tumorsWithFacility = 0;
        int patientsWithPid = 0, patientsWithoutPid = 0;
        long maxExistingPid = 0;
        var processedPatients = new HashSet<XmlNode>();

        foreach (XmlNode tumor in tumors)
        {
            var currentSite = GetItemValue(tumor, nsMgr, "primarySite");
            var currentLat = GetItemValue(tumor, nsMgr, "laterality");
            var currentFac = GetItemValue(tumor, nsMgr, "reportingFacility");

            if (!string.IsNullOrWhiteSpace(currentSite)) tumorsWithSite++;
            if (!string.IsNullOrWhiteSpace(currentLat)) tumorsWithLaterality++;
            if (!string.IsNullOrWhiteSpace(currentFac) && !System.Text.RegularExpressions.Regex.IsMatch(currentFac, @"^0+$"))
                tumorsWithFacility++;

            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
            if (patient != null && processedPatients.Add(patient))
            {
                var currentPid = GetItemValue(patient, nsMgr, "patientIdNumber");
                if (!string.IsNullOrWhiteSpace(currentPid))
                {
                    patientsWithPid++;
                    if (long.TryParse(currentPid, out var pidNum) && pidNum > maxExistingPid)
                        maxExistingPid = pidNum;
                }
                else
                {
                    patientsWithoutPid++;
                }
            }
        }

        var suggestedStartingNumber = maxExistingPid + 1;

        // ── Form properties ──────────────────────────────────────────────
        Text = "Unified Assignment";
        Width = 500;
        Height = 620;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        // ── Header ───────────────────────────────────────────────────────
        var lblHeader = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(470, 20),
            Text = $"File: {fileName}  |  Tumors: {tumorCount}  |  Patients: {patientCount}",
            Font = new Font("Segoe UI", 9f, FontStyle.Bold)
        };
        Controls.Add(lblHeader);

        // ── Primary Site & Laterality GroupBox ───────────────────────────
        var grpSiteLat = new GroupBox
        {
            Text = "Primary Site && Laterality",
            Location = new Point(10, 40),
            Size = new Size(465, 140)
        };

        _chkSite = new CheckBox
        {
            Text = "Assign Primary Site",
            Location = new Point(15, 25),
            AutoSize = true,
            Checked = true
        };
        grpSiteLat.Controls.Add(_chkSite);

        grpSiteLat.Controls.Add(new Label
        {
            Text = $"{tumorsWithSite} of {tumorCount} tumors have primary site",
            Location = new Point(200, 26),
            AutoSize = true,
            ForeColor = Color.Gray
        });

        _chkSiteOverride = new CheckBox
        {
            Text = "Override existing values",
            Location = new Point(35, 48),
            AutoSize = true,
            ForeColor = Color.Red
        };
        grpSiteLat.Controls.Add(_chkSiteOverride);

        _chkLat = new CheckBox
        {
            Text = "Assign Laterality",
            Location = new Point(15, 78),
            AutoSize = true,
            Checked = true
        };
        grpSiteLat.Controls.Add(_chkLat);

        grpSiteLat.Controls.Add(new Label
        {
            Text = $"{tumorsWithLaterality} of {tumorCount} tumors have laterality",
            Location = new Point(200, 79),
            AutoSize = true,
            ForeColor = Color.Gray
        });

        _chkLatOverride = new CheckBox
        {
            Text = "Override existing values",
            Location = new Point(35, 101),
            AutoSize = true,
            ForeColor = Color.Red
        };
        grpSiteLat.Controls.Add(_chkLatOverride);
        Controls.Add(grpSiteLat);

        // ── Facility GroupBox ────────────────────────────────────────────
        var grpFacility = new GroupBox
        {
            Text = "Facility",
            Location = new Point(10, 190),
            Size = new Size(465, 100)
        };

        _chkFacility = new CheckBox
        {
            Text = "Assign Facility",
            Location = new Point(15, 25),
            AutoSize = true,
            Checked = true
        };
        grpFacility.Controls.Add(_chkFacility);

        grpFacility.Controls.Add(new Label
        {
            Text = $"{tumorsWithFacility} of {tumorCount} tumors have facility",
            Location = new Point(200, 26),
            AutoSize = true,
            ForeColor = Color.Gray
        });

        grpFacility.Controls.Add(new Label
        {
            Text = "Number:",
            Location = new Point(35, 50),
            AutoSize = true
        });

        _txtFacilityNum = new TextBox
        {
            Location = new Point(95, 47),
            Width = 120,
            Text = detectedFacility
        };
        grpFacility.Controls.Add(_txtFacilityNum);

        grpFacility.Controls.Add(new Label
        {
            Text = !string.IsNullOrEmpty(detectedFacility)
                ? "(auto-detected)"
                : "(enter manually) (will be padded to 10 digits)",
            Location = new Point(220, 50),
            AutoSize = true,
            ForeColor = Color.Gray
        });

        _chkFacilityOverride = new CheckBox
        {
            Text = "Override existing values",
            Location = new Point(35, 73),
            AutoSize = true,
            ForeColor = Color.Red
        };
        grpFacility.Controls.Add(_chkFacilityOverride);
        Controls.Add(grpFacility);

        // ── Patient ID GroupBox ──────────────────────────────────────────
        var grpPid = new GroupBox
        {
            Text = "Patient ID",
            Location = new Point(10, 300),
            Size = new Size(465, 170)
        };

        _chkPid = new CheckBox
        {
            Text = "Assign Patient ID",
            Location = new Point(15, 25),
            AutoSize = true,
            Checked = false
        };
        grpPid.Controls.Add(_chkPid);

        var pidStatusText = $"{patientsWithPid} of {patientCount} patients have IDs";
        if (maxExistingPid > 0)
            pidStatusText += $" (highest: {maxExistingPid:D8})";

        grpPid.Controls.Add(new Label
        {
            Text = pidStatusText,
            Location = new Point(35, 48),
            Size = new Size(400, 18),
            ForeColor = Color.Gray
        });

        grpPid.Controls.Add(new Label
        {
            Text = "Start at:",
            Location = new Point(35, 72),
            AutoSize = true
        });

        _txtStartingNum = new TextBox
        {
            Location = new Point(90, 69),
            Width = 100,
            Text = suggestedStartingNumber.ToString("D8")
        };
        grpPid.Controls.Add(_txtStartingNum);

        _lblStartingNumHint = new Label
        {
            Text = "(next available)",
            Location = new Point(195, 72),
            AutoSize = true,
            ForeColor = Color.Gray
        };
        grpPid.Controls.Add(_lblStartingNumHint);

        _rbPidMissing = new RadioButton
        {
            Text = "Assign to patients without IDs only",
            Location = new Point(35, 95),
            AutoSize = true,
            Checked = true
        };
        grpPid.Controls.Add(_rbPidMissing);

        _rbPidOverwrite = new RadioButton
        {
            Text = "Overwrite all (renumber all patients)",
            Location = new Point(35, 117),
            AutoSize = true,
            ForeColor = Color.Red
        };
        grpPid.Controls.Add(_rbPidOverwrite);

        _rbPidReplaceZeros = new RadioButton
        {
            Text = "Replace zeros only (start at 90000001)",
            Location = new Point(35, 139),
            AutoSize = true,
            ForeColor = Color.Red
        };
        grpPid.Controls.Add(_rbPidReplaceZeros);
        Controls.Add(grpPid);

        // ── Wire enable/disable logic ────────────────────────────────────
        _chkSite.CheckedChanged += (_, _) => _chkSiteOverride.Enabled = _chkSite.Checked;
        _chkLat.CheckedChanged += (_, _) => _chkLatOverride.Enabled = _chkLat.Checked;

        _chkFacility.CheckedChanged += (_, _) =>
        {
            _txtFacilityNum.Enabled = _chkFacility.Checked;
            _chkFacilityOverride.Enabled = _chkFacility.Checked;
        };

        EventHandler updatePidEnabled = (_, _) =>
        {
            _rbPidMissing.Enabled = _chkPid.Checked;
            _rbPidOverwrite.Enabled = _chkPid.Checked;
            _rbPidReplaceZeros.Enabled = _chkPid.Checked;
            _txtStartingNum.Enabled = _chkPid.Checked && !_rbPidReplaceZeros.Checked;

            if (_rbPidReplaceZeros.Checked)
                _lblStartingNumHint.Text = "(fixed at 90000001)";
            else if (_rbPidOverwrite.Checked)
                _lblStartingNumHint.Text = "(renumbers all)";
            else
                _lblStartingNumHint.Text = "(next available)";
        };

        _chkPid.CheckedChanged += updatePidEnabled;
        _rbPidMissing.CheckedChanged += updatePidEnabled;
        _rbPidOverwrite.CheckedChanged += updatePidEnabled;
        _rbPidReplaceZeros.CheckedChanged += updatePidEnabled;

        // Initialize enabled states
        _chkSiteOverride.Enabled = _chkSite.Checked;
        _chkLatOverride.Enabled = _chkLat.Checked;
        _txtFacilityNum.Enabled = _chkFacility.Checked;
        _chkFacilityOverride.Enabled = _chkFacility.Checked;
        updatePidEnabled(this, EventArgs.Empty);

        // ── Buttons ──────────────────────────────────────────────────────
        var btnAnalyze = new Button
        {
            Text = "Analyze && Preview",
            Width = 130,
            Height = 30,
            Location = new Point(250, 540)
        };
        btnAnalyze.Click += OnAnalyzeClick;
        AcceptButton = btnAnalyze;
        Controls.Add(btnAnalyze);

        var btnCancel = new Button
        {
            Text = "Cancel",
            Width = 90,
            Height = 30,
            Location = new Point(385, 540),
            DialogResult = DialogResult.Cancel
        };
        CancelButton = btnCancel;
        Controls.Add(btnCancel);
    }

    private void OnAnalyzeClick(object? sender, EventArgs e)
    {
        // Validate facility number
        if (_chkFacility.Checked)
        {
            var facNum = _txtFacilityNum.Text.Trim();
            if (!System.Text.RegularExpressions.Regex.IsMatch(facNum, @"^\d+$"))
            {
                MessageBox.Show(
                    "Invalid facility number. Must be numeric.",
                    "Validation Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var facNumPadded = facNum.PadLeft(10, '0');
            if (facNumPadded.Length != 10)
            {
                MessageBox.Show(
                    $"Facility number must be 10 digits or less (will be left-padded with zeros).\nYou entered {facNum.Length} digits.",
                    "Validation Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
        }

        // Validate starting number
        if (_chkPid.Checked && _rbPidMissing.Checked)
        {
            var startNum = _txtStartingNum.Text.Trim();
            if (!System.Text.RegularExpressions.Regex.IsMatch(startNum, @"^\d+$"))
            {
                MessageBox.Show(
                    "Invalid starting number. Must be numeric.",
                    "Validation Error",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
        }

        // Determine PID mode
        var pidMode = "Default";
        if (_rbPidOverwrite.Checked) pidMode = "OverwriteAll";
        else if (_rbPidReplaceZeros.Checked) pidMode = "ReplaceZeros";

        ResultOptions = new Dictionary<string, object>
        {
            ["AssignSite"] = _chkSite.Checked,
            ["SiteOverride"] = _chkSiteOverride.Checked,
            ["AssignLaterality"] = _chkLat.Checked,
            ["LateralityOverride"] = _chkLatOverride.Checked,
            ["AssignFacility"] = _chkFacility.Checked,
            ["FacilityNumber"] = _txtFacilityNum.Text.Trim().PadLeft(10, '0'),
            ["FacilityOverride"] = _chkFacilityOverride.Checked,
            ["AssignPid"] = _chkPid.Checked,
            ["PidMode"] = pidMode,
            ["PidStartingNumber"] = int.Parse(_txtStartingNum.Text.Trim())
        };

        DialogResult = DialogResult.OK;
        Close();
    }

    private static string GetItemValue(XmlNode context, XmlNamespaceManager nsMgr, string naaccrId)
    {
        var node = context.SelectSingleNode($"./n:Item[@naaccrId='{naaccrId}']", nsMgr)
                   ?? context.SelectSingleNode($".//n:Item[@naaccrId='{naaccrId}']", nsMgr);
        return node?.InnerText?.Trim() ?? string.Empty;
    }
}

/// <summary>
/// Preview form showing proposed unified assignment changes with a grid and text preview.
/// Ported from Show-UnifiedPreviewReport in assign-unified-ui.ps1.
/// </summary>
public class AssignUnifiedPreviewForm : Form
{
    private readonly IUnifiedAssignmentService _unifiedService;
    private DataGridView _grid = null!;
    private RichTextBox _rtbPreview = null!;
    private CheckBox _chkShowChangesOnly = null!;
    private DataView _dataView = null!;

    public bool SaveXmlClicked { get; private set; }
    public bool SaveCsvClicked { get; private set; }
    public bool OpenAfterSave { get; private set; }

    public AssignUnifiedPreviewForm(
        IUnifiedAssignmentService unifiedService,
        List<Dictionary<string, object>> report,
        Dictionary<string, object> options,
        XmlNodeList tumors,
        XmlDocument xmlDoc,
        XmlNamespaceManager nsMgr)
    {
        _unifiedService = unifiedService;
        InitializeControls(report, options, tumors, xmlDoc, nsMgr);
    }

    private void InitializeControls(
        List<Dictionary<string, object>> report,
        Dictionary<string, object> options,
        XmlNodeList tumors,
        XmlDocument xmlDoc,
        XmlNamespaceManager nsMgr)
    {
        var assignSite = options.TryGetValue("AssignSite", out var asBool) && asBool is true;
        var assignLat = options.TryGetValue("AssignLaterality", out var alBool) && alBool is true;
        var assignFac = options.TryGetValue("AssignFacility", out var afBool) && afBool is true;
        var assignPid = options.TryGetValue("AssignPid", out var apBool) && apBool is true;

        // Count changes
        int siteCount = 0, latCount = 0, facCount = 0, pidCount = 0, totalChanges = 0;
        foreach (var item in report)
        {
            if (item.TryGetValue("ProposedSite", out var ps) && ps is string pss && !string.IsNullOrEmpty(pss)) siteCount++;
            if (item.TryGetValue("ProposedLaterality", out var pl) && pl is string pls && !string.IsNullOrEmpty(pls)) latCount++;
            if (item.TryGetValue("ProposedFacility", out var pf) && pf is string pfs && !string.IsNullOrEmpty(pfs)) facCount++;
            if (item.TryGetValue("ProposedPid", out var pp) && pp is string pps && !string.IsNullOrEmpty(pps)) pidCount++;
            if (item.TryGetValue("HasChanges", out var hc) && hc is true) totalChanges++;
        }

        // ── Form properties ──────────────────────────────────────────────
        Text = "Unified Assignment Preview";
        Width = 1600;
        Height = 800;
        StartPosition = FormStartPosition.CenterScreen;

        // ── Summary label ────────────────────────────────────────────────
        var summaryParts = new List<string> { $"To update: {totalChanges}" };
        if (assignSite) summaryParts.Add($"Sites: {siteCount}");
        if (assignLat) summaryParts.Add($"Laterality: {latCount}");
        if (assignFac) summaryParts.Add($"Facility: {facCount}");
        if (assignPid) summaryParts.Add($"Patient IDs: {pidCount}");

        var lblSummary = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(1560, 30),
            Text = string.Join(" | ", summaryParts),
            Font = new Font("Segoe UI", 10f, FontStyle.Bold)
        };
        Controls.Add(lblSummary);

        // ── Filter checkbox ──────────────────────────────────────────────
        _chkShowChangesOnly = new CheckBox
        {
            Text = "Show only records with changes",
            Checked = true,
            Location = new Point(10, 45),
            AutoSize = true
        };
        _chkShowChangesOnly.CheckedChanged += (_, _) => UpdateFilter();
        Controls.Add(_chkShowChangesOnly);

        // ── Split container ──────────────────────────────────────────────
        var splitContainer = new SplitContainer
        {
            Location = new Point(10, 75),
            Size = new Size(1560, 615),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            Orientation = Orientation.Horizontal,
            SplitterDistance = 300
        };

        // ── DataGridView ─────────────────────────────────────────────────
        _grid = new DataGridView
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            RowHeadersVisible = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.AllCells,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = false
        };

        // Build DataTable
        var fullTable = new DataTable();
        fullTable.Columns.Add("TumorIndex", typeof(int));
        fullTable.Columns.Add("PatientName", typeof(string));

        if (assignSite) { fullTable.Columns.Add("CurrentSite", typeof(string)); fullTable.Columns.Add("ProposedSite", typeof(string)); }
        if (assignLat) { fullTable.Columns.Add("CurrentLat", typeof(string)); fullTable.Columns.Add("ProposedLat", typeof(string)); }
        if (assignFac) { fullTable.Columns.Add("CurrentFac", typeof(string)); fullTable.Columns.Add("ProposedFac", typeof(string)); }
        if (assignPid) { fullTable.Columns.Add("CurrentPid", typeof(string)); fullTable.Columns.Add("ProposedPid", typeof(string)); }
        if (assignSite || assignLat) fullTable.Columns.Add("SourceText", typeof(string));
        fullTable.Columns.Add("HasChanges", typeof(bool));

        foreach (var item in report)
        {
            var row = fullTable.NewRow();
            row["TumorIndex"] = item.GetValueOrDefault("TumorIndex", 0);
            row["PatientName"] = item.GetValueOrDefault("PatientName", "") ?? "";

            if (assignSite) { row["CurrentSite"] = item.GetValueOrDefault("CurrentSite", "") ?? ""; row["ProposedSite"] = item.GetValueOrDefault("ProposedSite", "") ?? ""; }
            if (assignLat) { row["CurrentLat"] = item.GetValueOrDefault("CurrentLaterality", "") ?? ""; row["ProposedLat"] = item.GetValueOrDefault("ProposedLaterality", "") ?? ""; }
            if (assignFac) { row["CurrentFac"] = item.GetValueOrDefault("CurrentFacility", "") ?? ""; row["ProposedFac"] = item.GetValueOrDefault("ProposedFacility", "") ?? ""; }
            if (assignPid) { row["CurrentPid"] = item.GetValueOrDefault("CurrentPid", "") ?? ""; row["ProposedPid"] = item.GetValueOrDefault("ProposedPid", "") ?? ""; }
            if (assignSite || assignLat) row["SourceText"] = item.GetValueOrDefault("SourceText", "") ?? "";
            row["HasChanges"] = item.GetValueOrDefault("HasChanges", false);

            fullTable.Rows.Add(row);
        }

        _dataView = new DataView(fullTable);
        _grid.DataSource = _dataView;

        _grid.DataBindingComplete += (_, _) =>
        {
            if (_grid.Columns["HasChanges"] != null)
                _grid.Columns["HasChanges"].Visible = false;
        };

        UpdateFilter();

        // ── RichTextBox preview ──────────────────────────────────────────
        _rtbPreview = new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            Font = new Font("Consolas", 9f),
            WordWrap = true
        };

        _grid.SelectionChanged += (_, _) =>
        {
            if (_grid.SelectedRows.Count == 0) return;
            var selectedRow = _grid.SelectedRows[0];
            if (selectedRow.Cells["TumorIndex"].Value is not int tumorIndex) return;
            var idx = tumorIndex - 1;
            if (idx < 0 || idx >= tumors.Count) return;

            var tumor = tumors[idx]!;
            _rtbPreview.Clear();

            var textFieldIds = new[] { "textDxProcLabTests", "textDxProcPath", "textDxProcPe", "textHistologyTitle", "textPrimarySiteTitle" };
            foreach (var textId in textFieldIds)
            {
                var node = tumor.SelectSingleNode($"./n:Item[@naaccrId='{textId}']", nsMgr);
                if (node == null) continue;

                _rtbPreview.SelectionFont = new Font(_rtbPreview.Font, FontStyle.Bold);
                _rtbPreview.AppendText($"=== {textId} ===\r\n");
                _rtbPreview.SelectionFont = _rtbPreview.Font;

                var value = node.InnerText;
                _rtbPreview.AppendText(string.IsNullOrWhiteSpace(value) ? "(no text)\r\n" : $"{value}\r\n");
                _rtbPreview.AppendText("\r\n");
            }
        };

        splitContainer.Panel1.Controls.Add(_grid);
        splitContainer.Panel2.Controls.Add(_rtbPreview);
        Controls.Add(splitContainer);

        // ── Buttons ──────────────────────────────────────────────────────
        var btnSaveXml = new Button
        {
            Text = "Save Updated XML",
            Width = 150,
            Location = new Point(10, 710),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };
        btnSaveXml.Click += (_, _) =>
        {
            SaveXmlClicked = true;
            DialogResult = DialogResult.OK;
            Close();
        };
        Controls.Add(btnSaveXml);

        var btnSaveCsv = new Button
        {
            Text = "Save CSV Report",
            Width = 150,
            Location = new Point(170, 710),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };
        btnSaveCsv.Click += (_, _) =>
        {
            SaveCsvClicked = true;
            DialogResult = DialogResult.OK;
            Close();
        };
        Controls.Add(btnSaveCsv);

        var btnClose = new Button
        {
            Text = "Close",
            Width = 100,
            Location = new Point(330, 710),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left,
            DialogResult = DialogResult.Cancel
        };
        Controls.Add(btnClose);
    }

    private void UpdateFilter()
    {
        _dataView.RowFilter = _chkShowChangesOnly.Checked ? "HasChanges = True" : "";
    }
}
