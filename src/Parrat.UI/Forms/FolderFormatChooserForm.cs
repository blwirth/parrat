using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;

namespace Parrat.UI.Forms;

/// <summary>
/// Asks which record format to load when a folder holds more than one.
/// Formats cannot be merged into a single view, so exactly one is loaded.
/// </summary>
public class FolderFormatChooserForm : ParratFormBase
{
    private readonly List<RadioButton> _options = new();

    /// <summary>The format the user chose. Only meaningful when DialogResult is OK.</summary>
    public DetectedFileFormat SelectedFormat { get; private set; }

    public FolderFormatChooserForm(FolderScanResult scan, IReadOnlyDictionary<DetectedFileFormat, int> recordCounts)
    {
        Text = "Choose Format to Load";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MinimizeBox = false;
        MaximizeBox = false;

        var prompt = new Label
        {
            Text = "This folder contains more than one record format.\n" +
                   "Choose which one to load:",
            Location = new Point(14, 14),
            Size = new Size(390, 36),
            AutoSize = false
        };
        Controls.Add(prompt);

        var y = 58;
        foreach (var format in scan.AvailableFormats)
        {
            var fileCount = scan.FilesOfFormat(format).Count;
            var files = PluralHelper.Count(fileCount, "file");

            var detail = recordCounts.TryGetValue(format, out var records)
                ? $"{files}, {PluralHelper.Count(records, FileFormatDetector.DescribeRecordUnit(format))}"
                : files;

            var radio = new RadioButton
            {
                Text = $"{FileFormatDetector.DescribeFormat(format)}  ({detail})",
                Location = new Point(24, y),
                Size = new Size(370, 24),
                Tag = format,
                Checked = _options.Count == 0
            };

            _options.Add(radio);
            Controls.Add(radio);
            y += 26;
        }

        SelectedFormat = scan.AvailableFormats[0];

        // Sized to its content: the dialog holds one row per format present, so
        // a fixed height either gapes or crowds depending on how many there are.
        const int width = 420;
        int buttonsTop = y + 22;
        ClientSize = new Size(width, buttonsTop + 28 + 14);

        var btnOk = new Button
        {
            Text = "Load",
            DialogResult = DialogResult.OK,
            Location = new Point(width - 188, buttonsTop),
            Size = new Size(85, 28)
        };
        btnOk.Click += (s, e) =>
        {
            var chosen = _options.FirstOrDefault(r => r.Checked);
            if (chosen?.Tag is DetectedFileFormat format)
                SelectedFormat = format;
        };
        Controls.Add(btnOk);

        var btnCancel = new Button
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Location = new Point(width - 97, buttonsTop),
            Size = new Size(85, 28)
        };
        Controls.Add(btnCancel);

        AcceptButton = btnOk;
        CancelButton = btnCancel;
    }
}
