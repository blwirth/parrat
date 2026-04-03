using System.Data;
using System.Xml;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Shows a preview of duplicate groups found during deduplication.
/// Displays a DataGridView with duplicate groups and Apply/Cancel buttons.
/// Ported from Show-DeduplicationPreview in ui/deduplicate-ui.ps1.
/// </summary>
public class DeduplicationPreviewForm : ParratFormBase
{
    private readonly DeduplicationResult _result;
    private readonly int _originalCount;
    private readonly string _dedupType;

    private Label _lblSummary = null!;
    private DataGridView _grid = null!;
    private Button _btnProceed = null!;
    private Button _btnCancel = null!;

    public DeduplicationPreviewForm(
        DeduplicationResult result,
        int originalCount,
        string dedupType)
    {
        _result = result;
        _originalCount = originalCount;
        _dedupType = dedupType;

        InitializeComponent();
        PopulateGrid();
    }

    private void InitializeComponent()
    {
        Text = $"Deduplication Preview - {_dedupType}";
        Width = 1400;
        Height = 700;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        var dedupedCount = _result.IndicesToKeep.Count;
        var removedCount = _originalCount - dedupedCount;
        var duplicateCount = _result.Report.Count;

        // ── Summary label ─────────────────────────────────────────────────
        _lblSummary = new Label();
        _lblSummary.Location = new Point(10, 10);
        _lblSummary.Size = new Size(1360, 40);
        _lblSummary.Text = $"Original tumors: {_originalCount} | Will keep: {dedupedCount} | Will remove: {removedCount} duplicates | Duplicate groups: {duplicateCount}";
        _lblSummary.Font = new Font("Segoe UI", 10f, FontStyle.Bold);

        // ── DataGridView ──────────────────────────────────────────────────
        _grid = new DataGridView();
        _grid.Location = new Point(10, 60);
        _grid.Size = new Size(1360, 500);
        _grid.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        _grid.ReadOnly = true;
        _grid.AllowUserToAddRows = false;
        _grid.AllowUserToDeleteRows = false;
        _grid.RowHeadersVisible = false;
        _grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.AllCells;
        _grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;

        // ── Buttons ───────────────────────────────────────────────────────
        _btnProceed = new Button();
        _btnProceed.Text = "Proceed with Deduplication";
        _btnProceed.Width = 200;
        _btnProceed.Height = 30;
        _btnProceed.Location = new Point(10, 580);
        _btnProceed.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
        _btnProceed.Click += (s, e) =>
        {
            DialogResult = DialogResult.OK;
            Close();
        };

        _btnCancel = new Button();
        _btnCancel.Text = "Cancel";
        _btnCancel.Width = 100;
        _btnCancel.Height = 30;
        _btnCancel.Location = new Point(220, 580);
        _btnCancel.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
        _btnCancel.Click += (s, e) =>
        {
            DialogResult = DialogResult.Cancel;
            Close();
        };

        CancelButton = _btnCancel;

        FormClosing += (s, e) =>
        {
            if (DialogResult == DialogResult.None)
                DialogResult = DialogResult.Cancel;
        };

        Controls.AddRange(new Control[] { _lblSummary, _grid, _btnProceed, _btnCancel });
    }

    private void PopulateGrid()
    {
        var table = new DataTable();
        table.Columns.Add("PatientKey", typeof(string));
        table.Columns.Add("AllIndices", typeof(string));
        table.Columns.Add("KeptIndex", typeof(int));
        table.Columns.Add("RemovedIndices", typeof(string));
        table.Columns.Add("Reason", typeof(string));
        table.Columns.Add("DateReceived", typeof(string));
        table.Columns.Add("Physician3", typeof(string));

        foreach (var item in _result.Report)
        {
            var row = table.NewRow();
            row["PatientKey"] = item.PatientKey;
            row["AllIndices"] = item.AllIndices;
            row["KeptIndex"] = item.KeptIndex;
            row["RemovedIndices"] = item.RemovedIndices;
            row["Reason"] = item.Reason;
            row["DateReceived"] = item.DateReceived;
            row["Physician3"] = item.Physician3;
            table.Rows.Add(row);
        }

        _grid.DataSource = table;
    }

    /// <summary>
    /// Returns the file suffix based on dedup type.
    /// </summary>
    public string GetFileSuffix() => _dedupType switch
    {
        "TrueMatches" => "-ddtr",
        "PrimaryKey" => "-ddpk",
        "PathReport" => "-ddpr",
        _ => "-dedup"
    };
}
