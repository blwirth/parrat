using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Dialog for selecting two files to compare.
/// Has file browse buttons, file type detection (XML or HL7), comparison mode
/// selection, and a Compare button that opens DiffViewerForm.
/// Ported from Show-FileDiffSetupDialog and Show-FileDiff in ui/diff-files-ui.ps1.
/// </summary>
public class DiffFilesForm : ParratFormBase
{
    private readonly IDiffService _diffService;
    private readonly IXmlFileService _xmlFileService;
    private readonly IHl7FileService _hl7FileService;

    private string? _detectedFileType;

    private Label _lblFileA = null!;
    private TextBox _txtFileA = null!;
    private Button _btnBrowseA = null!;
    private Label _lblFileB = null!;
    private TextBox _txtFileB = null!;
    private Button _btnBrowseB = null!;
    private GroupBox _grpHl7Mode = null!;
    private RadioButton _rbHl7Index = null!;
    private RadioButton _rbHl7Key = null!;
    private GroupBox _grpXmlMode = null!;
    private RadioButton _rbXmlLine = null!;
    private RadioButton _rbXmlPatient = null!;
    private Button _btnCompare = null!;
    private Button _btnCancel = null!;

    public DiffFilesForm(
        IDiffService diffService,
        IXmlFileService xmlFileService,
        IHl7FileService hl7FileService)
    {
        _diffService = diffService;
        _xmlFileService = xmlFileService;
        _hl7FileService = hl7FileService;

        InitializeComponent();
    }

    /// <summary>File path A selected by user.</summary>
    public string FilePathA => _txtFileA.Text;

    /// <summary>File path B selected by user.</summary>
    public string FilePathB => _txtFileB.Text;

    /// <summary>Detected file type: "xml" or "hl7".</summary>
    public string? DetectedFileType => _detectedFileType;

    /// <summary>Comparison mode selected: "Index", "Key", "Line", or "Patient".</summary>
    public string ComparisonMode
    {
        get
        {
            if (_detectedFileType == "hl7")
                return _rbHl7Index.Checked ? "Index" : "Key";
            if (_detectedFileType == "xml")
                return _rbXmlLine.Checked ? "Line" : "Patient";
            return "Index";
        }
    }

    private void InitializeComponent()
    {
        Text = "Diff Files";
        Width = 600;
        Height = 320;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        // ── First file ────────────────────────────────────────────────────
        _lblFileA = new Label();
        _lblFileA.Location = new Point(15, 20);
        _lblFileA.Size = new Size(100, 20);
        _lblFileA.Text = "First File:";

        _txtFileA = new TextBox();
        _txtFileA.Location = new Point(15, 42);
        _txtFileA.Size = new Size(470, 23);
        _txtFileA.ReadOnly = true;

        _btnBrowseA = new Button();
        _btnBrowseA.Location = new Point(495, 41);
        _btnBrowseA.Size = new Size(80, 25);
        _btnBrowseA.Text = "Browse...";
        _btnBrowseA.Click += OnBrowseAClick;

        // ── Second file ───────────────────────────────────────────────────
        _lblFileB = new Label();
        _lblFileB.Location = new Point(15, 75);
        _lblFileB.Size = new Size(100, 20);
        _lblFileB.Text = "Second File:";

        _txtFileB = new TextBox();
        _txtFileB.Location = new Point(15, 97);
        _txtFileB.Size = new Size(470, 23);
        _txtFileB.ReadOnly = true;
        _txtFileB.Enabled = false;

        _btnBrowseB = new Button();
        _btnBrowseB.Location = new Point(495, 96);
        _btnBrowseB.Size = new Size(80, 25);
        _btnBrowseB.Text = "Browse...";
        _btnBrowseB.Enabled = false;
        _btnBrowseB.Click += OnBrowseBClick;

        // ── HL7 comparison mode group ─────────────────────────────────────
        _grpHl7Mode = new GroupBox();
        _grpHl7Mode.Location = new Point(15, 135);
        _grpHl7Mode.Size = new Size(560, 75);
        _grpHl7Mode.Text = "HL7 Comparison Method";
        _grpHl7Mode.Visible = false;

        _rbHl7Index = new RadioButton();
        _rbHl7Index.Location = new Point(15, 22);
        _rbHl7Index.Size = new Size(530, 20);
        _rbHl7Index.Text = "By Position - compare message 1 vs message 1, message 2 vs message 2, etc.";
        _rbHl7Index.Checked = true;

        _rbHl7Key = new RadioButton();
        _rbHl7Key.Location = new Point(15, 46);
        _rbHl7Key.Size = new Size(530, 20);
        _rbHl7Key.Text = "By Message Control ID - match messages by MSH-10 identifier";

        _grpHl7Mode.Controls.AddRange(new Control[] { _rbHl7Index, _rbHl7Key });

        // ── XML comparison mode group ─────────────────────────────────────
        _grpXmlMode = new GroupBox();
        _grpXmlMode.Location = new Point(15, 135);
        _grpXmlMode.Size = new Size(560, 75);
        _grpXmlMode.Text = "XML Comparison Method";
        _grpXmlMode.Visible = false;

        _rbXmlLine = new RadioButton();
        _rbXmlLine.Location = new Point(15, 22);
        _rbXmlLine.Size = new Size(530, 20);
        _rbXmlLine.Text = "Line-by-Line - traditional diff view (warning: large files are slower)";

        _rbXmlPatient = new RadioButton();
        _rbXmlPatient.Location = new Point(15, 46);
        _rbXmlPatient.Size = new Size(530, 20);
        _rbXmlPatient.Text = "By Patient - compare patient records by position";
        _rbXmlPatient.Checked = true;

        _grpXmlMode.Controls.AddRange(new Control[] { _rbXmlLine, _rbXmlPatient });

        // ── Action buttons ────────────────────────────────────────────────
        _btnCompare = new Button();
        _btnCompare.Location = new Point(400, 235);
        _btnCompare.Size = new Size(90, 28);
        _btnCompare.Text = "Compare";
        _btnCompare.Enabled = false;
        _btnCompare.DialogResult = DialogResult.OK;

        _btnCancel = new Button();
        _btnCancel.Location = new Point(500, 235);
        _btnCancel.Size = new Size(75, 28);
        _btnCancel.Text = "Cancel";
        _btnCancel.DialogResult = DialogResult.Cancel;

        AcceptButton = _btnCompare;
        CancelButton = _btnCancel;

        Controls.AddRange(new Control[]
        {
            _lblFileA, _txtFileA, _btnBrowseA,
            _lblFileB, _txtFileB, _btnBrowseB,
            _grpHl7Mode, _grpXmlMode,
            _btnCompare, _btnCancel
        });
    }

    private void OnBrowseAClick(object? sender, EventArgs e)
    {
        using var ofd = new OpenFileDialog();
        ofd.Filter = "Files (*.xml;*.hl7)|*.xml;*.hl7|XML Files (*.xml)|*.xml|HL7 Files (*.hl7)|*.hl7|All Files (*.*)|*.*";
        ofd.Title = "Select First File";
        ofd.InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);

        if (ofd.ShowDialog() != DialogResult.OK)
            return;

        _txtFileA.Text = ofd.FileName;
        var ext = Path.GetExtension(ofd.FileName).ToLowerInvariant();

        if (ext == ".hl7")
        {
            _detectedFileType = "hl7";
            _grpHl7Mode.Visible = true;
            _grpXmlMode.Visible = false;
        }
        else if (ext == ".xml")
        {
            _detectedFileType = "xml";
            _grpHl7Mode.Visible = false;
            _grpXmlMode.Visible = true;
        }
        else
        {
            _detectedFileType = null;
            _grpHl7Mode.Visible = false;
            _grpXmlMode.Visible = false;
        }

        _txtFileB.Enabled = true;
        _btnBrowseB.Enabled = true;
        _txtFileB.Text = "";
        _btnCompare.Enabled = false;
    }

    private void OnBrowseBClick(object? sender, EventArgs e)
    {
        using var ofd = new OpenFileDialog();
        ofd.Title = "Select Second File";

        if (_detectedFileType == "hl7")
            ofd.Filter = "HL7 Files (*.hl7)|*.hl7|All Files (*.*)|*.*";
        else if (_detectedFileType == "xml")
            ofd.Filter = "XML Files (*.xml)|*.xml|All Files (*.*)|*.*";
        else
            ofd.Filter = "Files (*.xml;*.hl7)|*.xml;*.hl7|All Files (*.*)|*.*";

        if (!string.IsNullOrEmpty(_txtFileA.Text))
            ofd.InitialDirectory = Path.GetDirectoryName(_txtFileA.Text) ?? "";

        if (ofd.ShowDialog() != DialogResult.OK)
            return;

        var ext = Path.GetExtension(ofd.FileName).ToLowerInvariant();
        var expectedExt = _detectedFileType switch
        {
            "hl7" => ".hl7",
            "xml" => ".xml",
            _ => (string?)null
        };

        if (expectedExt != null && ext != expectedExt)
        {
            MessageBox.Show(
                $"Second file must be the same type as the first file ({expectedExt}).",
                "File Type Mismatch",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        _txtFileB.Text = ofd.FileName;
        _btnCompare.Enabled = true;
    }
}
