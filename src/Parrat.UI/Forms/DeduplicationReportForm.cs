using System.Data;
using System.Xml;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Shows results after deduplication. Displays a report of what was removed
/// and why (tiebreaker reasons). Has Save XML, Save CSV, and Close buttons.
/// Ported from Show-DeduplicationReport in ui/deduplicate-ui.ps1.
/// </summary>
public class DeduplicationReportForm : Form
{
    private readonly IDeduplicationService _deduplicationService;
    private readonly List<DuplicateReport> _report;
    private readonly HashSet<int> _indicesToKeep;
    private readonly int _originalCount;
    private readonly string _originalFilePath;
    private readonly XmlDocument _xmlDoc;
    private readonly XmlNodeList _tumors;
    private readonly string _fileSuffix;

    private Label _lblSummary = null!;
    private DataGridView _grid = null!;
    private Button _btnSaveXml = null!;
    private Button _btnSaveCsv = null!;
    private Button _btnClose = null!;

    public DeduplicationReportForm(
        IDeduplicationService deduplicationService,
        List<DuplicateReport> report,
        HashSet<int> indicesToKeep,
        int originalCount,
        string originalFilePath,
        XmlDocument xmlDoc,
        XmlNodeList tumors,
        string fileSuffix = "-dedup")
    {
        _deduplicationService = deduplicationService;
        _report = report;
        _indicesToKeep = indicesToKeep;
        _originalCount = originalCount;
        _originalFilePath = originalFilePath;
        _xmlDoc = xmlDoc;
        _tumors = tumors;
        _fileSuffix = fileSuffix;

        InitializeComponent();
        PopulateGrid();
    }

    private void InitializeComponent()
    {
        var dedupedCount = _indicesToKeep.Count;
        var removedCount = _originalCount - dedupedCount;

        Text = "Deduplication Report";
        Width = 1400;
        Height = 700;
        StartPosition = FormStartPosition.CenterScreen;

        // ── Summary label ─────────────────────────────────────────────────
        _lblSummary = new Label();
        _lblSummary.Location = new Point(10, 10);
        _lblSummary.Size = new Size(1360, 40);
        _lblSummary.Text = $"Original tumors: {_originalCount} | Kept: {dedupedCount} | Removed: {removedCount} duplicates";
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
        _btnSaveXml = new Button();
        _btnSaveXml.Text = "Save Deduped XML";
        _btnSaveXml.Width = 150;
        _btnSaveXml.Height = 30;
        _btnSaveXml.Location = new Point(10, 580);
        _btnSaveXml.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
        _btnSaveXml.Click += OnSaveXmlClick;

        _btnSaveCsv = new Button();
        _btnSaveCsv.Text = "Save CSV Report";
        _btnSaveCsv.Width = 150;
        _btnSaveCsv.Height = 30;
        _btnSaveCsv.Location = new Point(170, 580);
        _btnSaveCsv.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
        _btnSaveCsv.Click += OnSaveCsvClick;

        _btnClose = new Button();
        _btnClose.Text = "Close";
        _btnClose.Width = 100;
        _btnClose.Height = 30;
        _btnClose.Location = new Point(330, 580);
        _btnClose.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;
        _btnClose.Click += (s, e) => Close();

        Controls.AddRange(new Control[] { _lblSummary, _grid, _btnSaveXml, _btnSaveCsv, _btnClose });
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

        foreach (var item in _report)
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

    private void OnSaveXmlClick(object? sender, EventArgs e)
    {
        try
        {
            var originalFileName = Path.GetFileNameWithoutExtension(_originalFilePath);
            var directory = Path.GetDirectoryName(_originalFilePath) ?? ".";
            var outputPath = Path.Combine(directory, $"{originalFileName}{_fileSuffix}.xml");

            _deduplicationService.WriteDedupedXml(_xmlDoc, _tumors, _indicesToKeep, outputPath);

            MessageBox.Show(
                $"Deduplicated XML saved to:\n{outputPath}",
                "Success",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Error saving XML: {ex.Message}",
                "Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private void OnSaveCsvClick(object? sender, EventArgs e)
    {
        try
        {
            var originalFileName = Path.GetFileNameWithoutExtension(_originalFilePath);
            var directory = Path.GetDirectoryName(_originalFilePath) ?? ".";
            var csvPath = Path.Combine(directory, $"{originalFileName}{_fileSuffix}-report.csv");

            using var writer = new StreamWriter(csvPath);

            // Write header
            writer.WriteLine("PatientKey,AllIndices,KeptIndex,RemovedIndices,Reason,DateReceived,Physician3");

            // Write rows
            foreach (var item in _report)
            {
                writer.WriteLine(string.Join(",",
                    CsvEscape(item.PatientKey),
                    CsvEscape(item.AllIndices),
                    item.KeptIndex,
                    CsvEscape(item.RemovedIndices),
                    CsvEscape(item.Reason),
                    CsvEscape(item.DateReceived),
                    CsvEscape(item.Physician3)));
            }

            MessageBox.Show(
                $"CSV report saved to:\n{csvPath}",
                "Success",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Error saving CSV: {ex.Message}",
                "Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static string CsvEscape(string value)
    {
        if (string.IsNullOrEmpty(value))
            return "\"\"";

        if (value.Contains(',') || value.Contains('"') || value.Contains('\n'))
            return $"\"{value.Replace("\"", "\"\"")}\"";

        return $"\"{value}\"";
    }
}
