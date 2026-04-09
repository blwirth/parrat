using System.Data;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Preview dialog shown before ePath .dat to .hl7 conversion.
/// Displays a record grid and HL7 preview for the selected record.
/// </summary>
public class EpathPreviewForm : ParratFormBase
{
    private readonly List<EpathRecord> _records;
    private readonly IEpathParserService _epathParserService;

    private DataGridView _gridRecords = null!;
    private RichTextBox _rtbPreview = null!;
    private Label _lblSummary = null!;
    private Button _btnConvert = null!;
    private Button _btnCancel = null!;

    public EpathPreviewForm(List<EpathRecord> records, IEpathParserService epathParserService)
    {
        _records = records;
        _epathParserService = epathParserService;
        InitializeComponents();

        Shown += (_, _) =>
        {
            PopulateGrid();
            if (_gridRecords.Rows.Count > 0)
                ShowPreviewForRow(0);
        };
    }

    private void InitializeComponents()
    {
        Text = "Convert .dat to .hl7 — Preview";
        Width = 1000;
        Height = 650;
        MinimumSize = new Size(800, 500);
        StartPosition = FormStartPosition.CenterScreen;

        // Summary label
        _lblSummary = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(960, 20),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
            Font = new Font("Segoe UI", 9, FontStyle.Bold)
        };

        var version = _records.Count > 0 ? _records[0].FormatVersion : "unknown";
        var hl7Ver = version == "NOAH v2" ? "2.5.1" : "2.3.1";
        _lblSummary.Text = $"{_records.Count} record(s), ePath {version} → HL7 v{hl7Ver}";

        // Split container: top grid, bottom HL7 preview
        var splitContainer = new SplitContainer
        {
            Location = new Point(10, 35),
            Size = new Size(960, 525),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            Orientation = Orientation.Horizontal,
            SplitterDistance = 220,
            Panel1MinSize = 100,
            Panel2MinSize = 150
        };

        // ── Top: Record grid ──
        var lblGrid = new Label
        {
            Text = "Records (select a row to preview HL7 output):",
            Location = new Point(0, 0),
            AutoSize = true
        };

        _gridRecords = new DataGridView
        {
            Location = new Point(0, 20),
            Size = new Size(940, 190),
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
        _gridRecords.SelectionChanged += (_, _) =>
        {
            if (_gridRecords.CurrentRow != null)
                ShowPreviewForRow(_gridRecords.CurrentRow.Index);
        };

        splitContainer.Panel1.Controls.AddRange(new Control[] { lblGrid, _gridRecords });
        splitContainer.Panel1.Resize += (_, _) =>
        {
            _gridRecords.Size = new Size(
                splitContainer.Panel1.ClientSize.Width,
                splitContainer.Panel1.ClientSize.Height - 22);
        };

        // ── Bottom: HL7 preview ──
        var lblPreview = new Label
        {
            Text = "HL7 Output Preview:",
            Location = new Point(0, 0),
            AutoSize = true
        };

        _rtbPreview = new RichTextBox
        {
            Location = new Point(0, 20),
            Size = new Size(940, 270),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            ReadOnly = true,
            WordWrap = false,
            Font = new Font("Consolas", 9)
        };

        splitContainer.Panel2.Controls.AddRange(new Control[] { lblPreview, _rtbPreview });
        splitContainer.Panel2.Resize += (_, _) =>
        {
            _rtbPreview.Size = new Size(
                splitContainer.Panel2.ClientSize.Width,
                splitContainer.Panel2.ClientSize.Height - 22);
        };

        // ── Bottom buttons ──
        var bottomPanel = new Panel
        {
            Location = new Point(10, 567),
            Size = new Size(300, 40),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };

        _btnConvert = new Button
        {
            Text = "Convert",
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

        bottomPanel.Controls.AddRange(new Control[] { _btnConvert, _btnCancel });

        Controls.AddRange(new Control[] { _lblSummary, splitContainer, bottomPanel });
        AcceptButton = _btnConvert;
        CancelButton = _btnCancel;
    }

    private void PopulateGrid()
    {
        var table = new DataTable();
        table.Columns.Add("#", typeof(int));
        table.Columns.Add("Name Last", typeof(string));
        table.Columns.Add("Name First", typeof(string));
        table.Columns.Add("DOB", typeof(string));
        table.Columns.Add("Sex", typeof(string));
        table.Columns.Add("MRN", typeof(string));
        table.Columns.Add("Path Report #", typeof(string));
        table.Columns.Add("Facility", typeof(string));

        foreach (var rec in _records)
        {
            table.Rows.Add(
                rec.Index + 1,
                rec.PatientLastName,
                rec.PatientFirstName,
                rec.DateOfBirth,
                rec.Sex,
                rec.PatientId,
                rec.PathReportNumber,
                rec.SendingFacility);
        }

        _gridRecords.DataSource = table;

        // Column widths
        if (_gridRecords.Columns.Count >= 8)
        {
            _gridRecords.Columns[0].Width = 40;
            _gridRecords.Columns[1].Width = 120;
            _gridRecords.Columns[2].Width = 100;
            _gridRecords.Columns[3].Width = 90;
            _gridRecords.Columns[4].Width = 40;
            _gridRecords.Columns[5].Width = 100;
            _gridRecords.Columns[6].Width = 120;
            _gridRecords.Columns[7].Width = 150;
        }
    }

    private void ShowPreviewForRow(int rowIndex)
    {
        if (rowIndex < 0 || rowIndex >= _records.Count) return;

        var record = _records[rowIndex];
        var hl7Version = record.FormatVersion == "NOAH v2" ? "2.5.1" : "2.3.1";
        var hl7Text = _epathParserService.BuildHl7FromMap(record.Fields, hl7Version);

        _rtbPreview.Text = hl7Text;

        // Color-code segments
        ColorizeHl7Preview();
    }

    private void ColorizeHl7Preview()
    {
        var segmentColors = new Dictionary<string, Color>
        {
            ["MSH"] = Color.FromArgb(0, 100, 0),
            ["PID"] = Color.FromArgb(0, 0, 160),
            ["PV1"] = Color.FromArgb(80, 0, 80),
            ["ORC"] = Color.FromArgb(120, 80, 0),
            ["OBR"] = Color.FromArgb(160, 80, 0),
            ["OBX"] = Color.FromArgb(100, 0, 0),
        };

        var text = _rtbPreview.Text;
        var lines = text.Split('\n');
        int pos = 0;

        foreach (var line in lines)
        {
            var trimmed = line.TrimEnd('\r');
            if (trimmed.Length >= 3)
            {
                var seg = trimmed[..3];
                if (segmentColors.TryGetValue(seg, out var color))
                {
                    _rtbPreview.Select(pos, Math.Min(3, trimmed.Length));
                    _rtbPreview.SelectionColor = color;
                    _rtbPreview.SelectionFont = new Font(_rtbPreview.Font, FontStyle.Bold);
                }
            }
            pos += line.Length + 1; // +1 for \n
        }

        _rtbPreview.Select(0, 0);
    }
}
