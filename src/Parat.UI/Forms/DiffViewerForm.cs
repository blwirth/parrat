using System.Drawing;
using System.Windows.Forms;
using Parat.Core.Models;

namespace Parat.UI.Forms;

/// <summary>
/// Side-by-side diff viewer for two records (tumors or HL7 messages).
/// Uses a RichTextBox with color coding: green for added, red for deleted.
/// Ported from Show-NaaccrTumorDiff and Show-Hl7MessageDiff in lib/diff.ps1.
/// </summary>
public class DiffViewerForm : Form
{
    private readonly List<DiffLine> _diffLines;
    private readonly string _labelA;
    private readonly string _labelB;
    private readonly string _titlePrefix;

    private Label _lblSummary = null!;
    private RichTextBox _rtbDiff = null!;
    private Label _lblLegend = null!;
    private Button _btnClose = null!;

    public DiffViewerForm(
        List<DiffLine> diffLines,
        string labelA,
        string labelB,
        string titlePrefix = "Diff")
    {
        _diffLines = diffLines;
        _labelA = labelA;
        _labelB = labelB;
        _titlePrefix = titlePrefix;

        InitializeComponent();
        PopulateDiff();
    }

    private void InitializeComponent()
    {
        Text = $"{_titlePrefix}: Record A vs Record B";
        Width = 1400;
        Height = 900;
        StartPosition = FormStartPosition.CenterScreen;

        var addedCount = _diffLines.Count(d => d.Status == DiffStatus.Added);
        var deletedCount = _diffLines.Count(d => d.Status == DiffStatus.Deleted);
        var unchangedCount = _diffLines.Count(d => d.Status == DiffStatus.Unchanged);

        // ── Summary label ─────────────────────────────────────────────────
        _lblSummary = new Label();
        _lblSummary.Location = new Point(10, 10);
        _lblSummary.Size = new Size(1360, 50);
        _lblSummary.Font = new Font("Segoe UI", 9f);
        _lblSummary.Text = $"A: {_labelA}\nB: {_labelB}\nChanges: +{addedCount} added, -{deletedCount} removed, {unchangedCount} unchanged";

        // ── RichTextBox for diff display ──────────────────────────────────
        _rtbDiff = new RichTextBox();
        _rtbDiff.Location = new Point(10, 65);
        _rtbDiff.Size = new Size(1360, 750);
        _rtbDiff.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        _rtbDiff.Font = new Font("Consolas", 10f);
        _rtbDiff.ReadOnly = true;
        _rtbDiff.WordWrap = false;
        _rtbDiff.ScrollBars = RichTextBoxScrollBars.Both;

        // ── Legend label ──────────────────────────────────────────────────
        _lblLegend = new Label();
        _lblLegend.Location = new Point(10, 825);
        _lblLegend.Size = new Size(700, 20);
        _lblLegend.Text = "Legend:  + Added (in B only)  |  - Removed (in A only)  |  (no prefix) Unchanged  |  Line numbers: A  B";
        _lblLegend.ForeColor = Color.Gray;
        _lblLegend.Anchor = AnchorStyles.Bottom | AnchorStyles.Left;

        // ── Close button ──────────────────────────────────────────────────
        _btnClose = new Button();
        _btnClose.Text = "Close";
        _btnClose.Location = new Point(1280, 825);
        _btnClose.Size = new Size(90, 28);
        _btnClose.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
        _btnClose.Click += (s, e) => Close();

        Controls.AddRange(new Control[] { _lblSummary, _rtbDiff, _lblLegend, _btnClose });
    }

    private void PopulateDiff()
    {
        var lineNumA = 0;
        var lineNumB = 0;

        foreach (var line in _diffLines)
        {
            string prefix;
            Color color;
            Color bgColor;
            string lineNumText;

            switch (line.Status)
            {
                case DiffStatus.Unchanged:
                    lineNumA++;
                    lineNumB++;
                    prefix = "  ";
                    color = Color.Black;
                    bgColor = Color.White;
                    lineNumText = $"{lineNumA,4} {lineNumB,4}  ";
                    break;

                case DiffStatus.Added:
                    lineNumB++;
                    prefix = "+ ";
                    color = Color.DarkGreen;
                    bgColor = Color.FromArgb(220, 255, 220);
                    lineNumText = $"     {lineNumB,4}  ";
                    break;

                case DiffStatus.Deleted:
                    lineNumA++;
                    prefix = "- ";
                    color = Color.DarkRed;
                    bgColor = Color.FromArgb(255, 220, 220);
                    lineNumText = $"{lineNumA,4}      ";
                    break;

                default:
                    continue;
            }

            var content = line.Status == DiffStatus.Added ? line.ContentB : line.ContentA;
            var text = $"{lineNumText}{prefix}{content}\n";

            _rtbDiff.SelectionStart = _rtbDiff.TextLength;
            _rtbDiff.SelectionLength = 0;
            _rtbDiff.SelectionColor = color;
            _rtbDiff.SelectionBackColor = bgColor;
            _rtbDiff.AppendText(text);
        }

        _rtbDiff.SelectionStart = 0;
        _rtbDiff.ScrollToCaret();
    }
}
