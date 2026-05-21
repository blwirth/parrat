using System.Data;
using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Interfaces;

namespace Parrat.UI.Forms;

/// <summary>
/// Dialog for merging multiple HL7 files.
/// File list with Add/Remove/Reorder, message count preview, and Concatenate button.
/// Ported from ui/concatenate-hl7-ui.ps1.
/// </summary>
public class ConcatenateHl7Form : ParratFormBase
{
    private readonly IConcatenateService _concatenateService;
    private readonly IParratLogger _logger;

    private readonly List<Dictionary<string, object>> _fileInfos = new();

    // Controls
    private Label _lblSummary = null!;
    private DataGridView _gridFiles = null!;
    private DataTable _tableFiles = null!;
    private Button _btnAddFiles = null!;
    private Button _btnRemove = null!;
    private Button _btnMoveUp = null!;
    private Button _btnMoveDown = null!;
    private Button _btnConcatenate = null!;
    private Button _btnClose = null!;

    /// <summary>Path of the output file after successful concatenation, or null.</summary>
    public string? OutputFilePath { get; private set; }

    /// <summary>Whether the user requested to open the output file.</summary>
    public bool ShouldOpenOutput { get; private set; }

    public ConcatenateHl7Form(
        IConcatenateService concatenateService,
        string[] initialFiles,
        IParratLogger? logger = null)
    {
        _concatenateService = concatenateService;
        _logger = logger!;

        InitializeComponents();
        LoadInitialFiles(initialFiles);
    }

    private void InitializeComponents()
    {
        Text = "Concatenate HL7 Files - Preview";
        Width = 1600;
        Height = 800;
        StartPosition = FormStartPosition.CenterScreen;

        _lblSummary = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(1560, 40),
            Font = new Font("Segoe UI", 10, FontStyle.Bold)
        };

        _gridFiles = new DataGridView
        {
            Location = new Point(10, 60),
            Size = new Size(1560, 580),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            ReadOnly = true,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            RowHeadersVisible = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.AllCells,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = false
        };

        _tableFiles = new DataTable();
        _tableFiles.Columns.Add("FileName", typeof(string));
        _tableFiles.Columns.Add("MessageCount", typeof(int));
        _tableFiles.Columns.Add("FileSizeMB", typeof(string));
        _tableFiles.Columns.Add("FilePath", typeof(string));
        _gridFiles.DataSource = _tableFiles;

        // File management buttons
        var pnlFileButtons = new Panel
        {
            Location = new Point(10, 650),
            Size = new Size(600, 35),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };

        _btnAddFiles = new Button { Text = "Add More Files...", Width = 120, Location = new Point(0, 0) };
        _btnRemove = new Button { Text = "Remove Selected", Width = 120, Location = new Point(130, 0) };
        _btnMoveUp = new Button { Text = "Move Up", Width = 80, Location = new Point(260, 0) };
        _btnMoveDown = new Button { Text = "Move Down", Width = 80, Location = new Point(350, 0) };

        pnlFileButtons.Controls.AddRange(new Control[] { _btnAddFiles, _btnRemove, _btnMoveUp, _btnMoveDown });

        _btnConcatenate = new Button
        {
            Text = "Concatenate and Save",
            Width = 180,
            Location = new Point(10, 710),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };

        _btnClose = new Button
        {
            Text = "Close",
            Width = 100,
            Location = new Point(200, 710),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left
        };

        Controls.AddRange(new Control[] { _lblSummary, _gridFiles, pnlFileButtons, _btnConcatenate, _btnClose });

        _btnAddFiles.Click += BtnAddFiles_Click;
        _btnRemove.Click += BtnRemove_Click;
        _btnMoveUp.Click += BtnMoveUp_Click;
        _btnMoveDown.Click += BtnMoveDown_Click;
        _btnConcatenate.Click += BtnConcatenate_Click;
        _btnClose.Click += (_, _) => Close();
    }

    private void LoadInitialFiles(string[] files)
    {
        var errors = new List<string>();

        foreach (var file in files)
        {
            try
            {
                var info = _concatenateService.GetHl7FileInfo(file);
                _fileInfos.Add(info);
            }
            catch (Exception ex)
            {
                _logger.LogError($"Failed to load HL7 file info: {Path.GetFileName(file)}", "CONCAT", ex);
                errors.Add($"Error loading {file}: {ex.Message}");
            }
        }

        if (errors.Count > 0)
        {
            MessageBox.Show(
                "Errors loading files:\n\n" + string.Join("\n", errors),
                "File Load Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }

        if (_fileInfos.Count == 0)
        {
            MessageBox.Show("No valid HL7 files found.", "No Files",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        UpdateUI();
    }

    private void UpdateUI()
    {
        int totalMessages = 0;
        long totalSize = 0;

        foreach (var item in _fileInfos)
        {
            if (item.TryGetValue("MessageCount", out var mc) && mc is int count)
                totalMessages += count;
            if (item.TryGetValue("FileSize", out var fs) && fs is long size)
                totalSize += size;
        }

        var totalSizeMB = Math.Round(totalSize / (1024.0 * 1024.0), 2);
        _lblSummary.Text = $"Files: {_fileInfos.Count} | Total Messages: {totalMessages} | Total Size: {totalSizeMB} MB";

        _tableFiles.Clear();
        foreach (var item in _fileInfos)
        {
            var filePath = item.GetValueOrDefault("FilePath")?.ToString() ?? "";
            var fileName = Path.GetFileName(filePath);
            var msgCount = item.TryGetValue("MessageCount", out var mc2) && mc2 is int c ? c : 0;
            var fileSize = item.TryGetValue("FileSize", out var fs2) && fs2 is long s ? s : 0L;
            var fileSizeMB = Math.Round(fileSize / (1024.0 * 1024.0), 2);

            var row = _tableFiles.NewRow();
            row["FileName"] = fileName;
            row["MessageCount"] = msgCount;
            row["FileSizeMB"] = $"{fileSizeMB} MB";
            row["FilePath"] = filePath;
            _tableFiles.Rows.Add(row);
        }
    }

    private void BtnAddFiles_Click(object? sender, EventArgs e)
    {
        using var ofd = new OpenFileDialog
        {
            Filter = "HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
            Title = "Select additional HL7 files to add",
            Multiselect = true
        };

        if (ofd.ShowDialog(this) != DialogResult.OK) return;

        var addErrors = new List<string>();
        int addedCount = 0;

        foreach (var file in ofd.FileNames)
        {
            if (_fileInfos.Any(f => f.GetValueOrDefault("FilePath")?.ToString() == file))
            {
                addErrors.Add($"File already in list: {Path.GetFileName(file)}");
                continue;
            }

            try
            {
                var info = _concatenateService.GetHl7FileInfo(file);
                _fileInfos.Add(info);
                addedCount++;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Failed to add HL7 file: {Path.GetFileName(file)}", "CONCAT", ex);
                addErrors.Add($"Error loading {file}: {ex.Message}");
            }
        }

        if (addErrors.Count > 0)
        {
            MessageBox.Show(
                "Some files could not be added:\n\n" + string.Join("\n", addErrors),
                "Warning",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }

        if (addedCount > 0)
            UpdateUI();
    }

    private void BtnRemove_Click(object? sender, EventArgs e)
    {
        if (_gridFiles.SelectedRows.Count == 0)
        {
            MessageBox.Show("Please select a file to remove.", "No Selection",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var filePath = _gridFiles.SelectedRows[0].Cells["FilePath"].Value?.ToString();
        var itemToRemove = _fileInfos.FirstOrDefault(f => f.GetValueOrDefault("FilePath")?.ToString() == filePath);
        if (itemToRemove != null)
        {
            _fileInfos.Remove(itemToRemove);
            UpdateUI();
        }
    }

    private void BtnMoveUp_Click(object? sender, EventArgs e)
    {
        if (_gridFiles.SelectedRows.Count == 0) return;
        var idx = _gridFiles.SelectedRows[0].Index;
        if (idx <= 0) return;

        (_fileInfos[idx], _fileInfos[idx - 1]) = (_fileInfos[idx - 1], _fileInfos[idx]);
        UpdateUI();

        if (_gridFiles.Rows.Count > idx - 1)
        {
            _gridFiles.ClearSelection();
            _gridFiles.Rows[idx - 1].Selected = true;
        }
    }

    private void BtnMoveDown_Click(object? sender, EventArgs e)
    {
        if (_gridFiles.SelectedRows.Count == 0) return;
        var idx = _gridFiles.SelectedRows[0].Index;
        if (idx >= _fileInfos.Count - 1) return;

        (_fileInfos[idx], _fileInfos[idx + 1]) = (_fileInfos[idx + 1], _fileInfos[idx]);
        UpdateUI();

        if (_gridFiles.Rows.Count > idx + 1)
        {
            _gridFiles.ClearSelection();
            _gridFiles.Rows[idx + 1].Selected = true;
        }
    }

    private void BtnConcatenate_Click(object? sender, EventArgs e)
    {
        if (_fileInfos.Count == 0)
        {
            MessageBox.Show("No files to concatenate.", "No Files",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        using var folderDialog = new FolderBrowserDialog
        {
            Description = "Select output directory for concatenated HL7 file"
        };
        if (folderDialog.ShowDialog(this) != DialogResult.OK) return;

        var outputDir = folderDialog.SelectedPath;

        // Get output filename
        using var inputForm = new ParratFormBase
        {
            Text = "Enter Output Filename",
            Width = 400,
            Height = 150,
            StartPosition = FormStartPosition.CenterParent
        };

        var lblPrompt = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(370, 40),
            Text = "Enter the output filename (without .hl7 extension):"
        };
        var txtFilename = new TextBox { Location = new Point(10, 50), Width = 370, Text = "concatenated" };
        var btnOk = new Button { Text = "OK", Location = new Point(200, 80), DialogResult = DialogResult.OK };
        var btnCancel = new Button { Text = "Cancel", Location = new Point(280, 80), DialogResult = DialogResult.Cancel };

        inputForm.Controls.AddRange(new Control[] { lblPrompt, txtFilename, btnOk, btnCancel });
        inputForm.AcceptButton = btnOk;
        inputForm.CancelButton = btnCancel;

        if (inputForm.ShowDialog(this) != DialogResult.OK) return;

        var filename = txtFilename.Text.Trim();
        if (string.IsNullOrWhiteSpace(filename))
        {
            MessageBox.Show("Filename cannot be empty.", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        if (!filename.EndsWith(".hl7", StringComparison.OrdinalIgnoreCase))
            filename += ".hl7";

        var outputPath = Path.Combine(outputDir, filename);

        if (File.Exists(outputPath))
        {
            var overwrite = MessageBox.Show(
                $"File already exists:\n{outputPath}\n\nOverwrite?",
                "File Exists",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);
            if (overwrite != DialogResult.Yes) return;
        }

        try
        {
            int totalMessages = 0;
            foreach (var item in _fileInfos)
            {
                if (item.TryGetValue("MessageCount", out var mc) && mc is int count)
                    totalMessages += count;
            }

            _concatenateService.WriteConcatenatedHl7(_fileInfos, outputPath);

            var openResult = MessageBox.Show(
                $"Concatenated HL7 file saved to:\n{outputPath}\n\nTotal messages: {totalMessages}\n\nOpen newly created file?",
                "Success",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information);

            OutputFilePath = outputPath;
            ShouldOpenOutput = openResult == DialogResult.Yes;
            Close();
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to concatenate HL7 files", "CONCAT", ex);
            MessageBox.Show(
                $"Error concatenating HL7 files: {ex.Message}",
                "Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}
