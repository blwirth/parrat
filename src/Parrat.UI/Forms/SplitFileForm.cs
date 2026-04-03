using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Interfaces;

namespace Parrat.UI.Forms;

/// <summary>
/// Dialog for splitting a file into N parts by last name alphabetically.
/// Has a split count selector (2-5), distribution preview, output directory selector,
/// and a Split button.
/// Ported from ui/split-file-ui.ps1 Show-SplitOptionsDialog.
/// </summary>
public class SplitFileForm : ParratFormBase
{
    private readonly ISplitFileService _splitFileService;
    private readonly string _filePath;
    private readonly int _totalRecords;
    private readonly List<string> _lastNames;
    private readonly string _fileType;

    private int _selectedSplitCount = 2;

    // Controls
    private Label _lblPreview = null!;
    private TextBox _txtOutputDir = null!;
    private RadioButton _rdo2 = null!;
    private RadioButton _rdo3 = null!;
    private RadioButton _rdo4 = null!;
    private RadioButton _rdo5 = null!;

    /// <summary>The selected split count (2-5), valid after DialogResult.OK.</summary>
    public int SplitCount => _selectedSplitCount;

    /// <summary>The selected output directory, valid after DialogResult.OK.</summary>
    public string OutputDirectory => _txtOutputDir?.Text ?? "";

    public SplitFileForm(
        ISplitFileService splitFileService,
        string filePath,
        int totalRecords,
        List<string> lastNames,
        string fileType)
    {
        _splitFileService = splitFileService;
        _filePath = filePath;
        _totalRecords = totalRecords;
        _lastNames = lastNames;
        _fileType = fileType;

        InitializeComponents();
        UpdatePreview(_selectedSplitCount);
    }

    private void InitializeComponents()
    {
        var fileName = Path.GetFileName(_filePath);
        var recordLabel = _fileType == "xml" ? "tumors" : "messages";

        Text = "Split File by Last Name";
        Width = 550;
        Height = 380;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        // Source file label
        var lblSource = new Label
        {
            Location = new Point(15, 15),
            Size = new Size(500, 20),
            Text = $"Source: {fileName}",
            Font = new Font("Segoe UI", 9, FontStyle.Bold)
        };

        // Total records label
        var lblTotal = new Label
        {
            Location = new Point(15, 40),
            Size = new Size(500, 20),
            Text = $"Total {recordLabel}: {_totalRecords}"
        };

        // Split count group box
        var grpSplit = new GroupBox
        {
            Text = "Split into how many files?",
            Location = new Point(15, 70),
            Size = new Size(500, 60)
        };

        _rdo2 = new RadioButton { Text = "2 files", Location = new Point(20, 25), Width = 70, Checked = true, Tag = 2 };
        _rdo3 = new RadioButton { Text = "3 files", Location = new Point(110, 25), Width = 70, Tag = 3 };
        _rdo4 = new RadioButton { Text = "4 files", Location = new Point(200, 25), Width = 70, Tag = 4 };
        _rdo5 = new RadioButton { Text = "5 files", Location = new Point(290, 25), Width = 70, Tag = 5 };

        grpSplit.Controls.AddRange(new Control[] { _rdo2, _rdo3, _rdo4, _rdo5 });

        // Preview label
        _lblPreview = new Label
        {
            Location = new Point(15, 140),
            Size = new Size(500, 100),
            Font = new Font("Consolas", 9)
        };

        // Wire radio button events
        EventHandler radioHandler = (sender, _) =>
        {
            if (sender is RadioButton rb && rb.Checked && rb.Tag is int count)
            {
                _selectedSplitCount = count;
                UpdatePreview(count);
            }
        };

        _rdo2.CheckedChanged += radioHandler;
        _rdo3.CheckedChanged += radioHandler;
        _rdo4.CheckedChanged += radioHandler;
        _rdo5.CheckedChanged += radioHandler;

        // Output directory selection
        var lblOutputDir = new Label
        {
            Location = new Point(15, 250),
            Size = new Size(100, 20),
            Text = "Output folder:"
        };

        _txtOutputDir = new TextBox
        {
            Location = new Point(115, 247),
            Size = new Size(320, 25),
            Text = Path.GetDirectoryName(_filePath) ?? "",
            ReadOnly = true
        };

        var btnBrowse = new Button
        {
            Text = "Browse...",
            Location = new Point(440, 245),
            Width = 75
        };
        btnBrowse.Click += (_, _) =>
        {
            using var folderDialog = new FolderBrowserDialog
            {
                Description = "Select output folder for split files",
                SelectedPath = _txtOutputDir.Text
            };
            if (folderDialog.ShowDialog(this) == DialogResult.OK)
            {
                _txtOutputDir.Text = folderDialog.SelectedPath;
            }
        };

        // Action buttons
        var btnSplit = new Button
        {
            Text = "Split",
            Width = 100,
            Location = new Point(330, 295),
            DialogResult = DialogResult.OK
        };

        var btnCancel = new Button
        {
            Text = "Cancel",
            Width = 100,
            Location = new Point(440, 295),
            DialogResult = DialogResult.Cancel
        };

        Controls.AddRange(new Control[]
        {
            lblSource, lblTotal, grpSplit, _lblPreview,
            lblOutputDir, _txtOutputDir, btnBrowse,
            btnSplit, btnCancel
        });

        AcceptButton = btnSplit;
        CancelButton = btnCancel;
    }

    private void UpdatePreview(int splitCount)
    {
        var ranges = _splitFileService.GetAlphabetRanges(splitCount);
        var distribution = _splitFileService.GetSplitDistribution(_lastNames, splitCount);

        var distLabel = _fileType == "xml" ? "patients" : "messages";

        var lines = new List<string> { $"Estimated distribution (by {distLabel}):" };

        for (int i = 0; i < ranges.Count; i++)
        {
            var range = ranges[i];
            var count = distribution.TryGetValue(i.ToString(), out var c) ? c :
                        distribution.TryGetValue(range, out var c2) ? c2 : 0;
            var pct = _lastNames.Count > 0
                ? Math.Round((double)count / _lastNames.Count * 100, 1)
                : 0;
            lines.Add($"  {range}: ~{count} {distLabel} ({pct}%)");
        }

        // Note about malformed records
        int malformedCount = 0;
        foreach (var name in _lastNames)
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                malformedCount++;
            }
            else
            {
                var firstChar = char.ToUpperInvariant(name.Trim()[0]);
                if (firstChar < 'A' || firstChar > 'Z')
                    malformedCount++;
            }
        }

        if (malformedCount > 0)
        {
            lines.Add("");
            lines.Add($"Note: {malformedCount} {distLabel} with missing/invalid last names");
            if (ranges.Count > 0)
                lines.Add($"      will be placed in the last file ({ranges[^1]})");
        }

        _lblPreview.Text = string.Join("\r\n", lines);
    }
}
