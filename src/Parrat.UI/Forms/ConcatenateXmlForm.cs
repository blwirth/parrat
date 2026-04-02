using System.Data;
using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Interfaces;

namespace Parrat.UI.Forms;

/// <summary>
/// Dialog for merging multiple NAACCR XML files.
/// Has a file list with Add/Remove/Reorder, header validation status,
/// duplicate patient ID warning, preview of tumor counts, and a Concatenate button.
/// Ported from ui/concatenate-xml-ui.ps1.
/// </summary>
public class ConcatenateXmlForm : Form
{
    private readonly IConcatenateService _concatenateService;
    private readonly IParratLogger _logger;

    private readonly List<Dictionary<string, object>> _fileInfos = new();
    private Dictionary<string, object>? _referenceInfo;

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

    public ConcatenateXmlForm(
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
        Text = "Concatenate XML Files - Preview";
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
        _tableFiles.Columns.Add("TumorCount", typeof(int));
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

        // Action buttons
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

        // Wire events
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

        // Load all files and get header info
        var headerInfos = new List<Dictionary<string, object>>();
        foreach (var file in files)
        {
            try
            {
                var info = _concatenateService.GetXmlHeaderInfo(file);
                headerInfos.Add(info);
            }
            catch (Exception ex)
            {
                _logger.LogError($"Failed to load XML header info: {Path.GetFileName(file)}", "CONCAT", ex);
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

        if (headerInfos.Count > 0)
        {
            _referenceInfo = headerInfos[0];
            _fileInfos.AddRange(headerInfos);
        }

        UpdateUI();
    }

    private void UpdateUI()
    {
        int totalTumors = 0;
        foreach (var item in _fileInfos)
        {
            if (item.TryGetValue("TumorCount", out var tc) && tc is int count)
                totalTumors += count;
        }

        var xmlVersion = _referenceInfo?.GetValueOrDefault("XmlVersion", "")?.ToString() ?? "";
        var recordType = _referenceInfo?.GetValueOrDefault("RecordType", "")?.ToString() ?? "";

        _lblSummary.Text = $"Files: {_fileInfos.Count} | Total Tumors: {totalTumors} | XML Version: {xmlVersion} | Record Type: {recordType}";

        _tableFiles.Clear();
        foreach (var item in _fileInfos)
        {
            var filePath = item.GetValueOrDefault("FilePath", "")?.ToString() ?? "";
            var fileName = Path.GetFileName(filePath);
            var tumorCount = item.TryGetValue("TumorCount", out var tc2) && tc2 is int c ? c : 0;

            var row = _tableFiles.NewRow();
            row["FileName"] = fileName;
            row["TumorCount"] = tumorCount;
            row["FilePath"] = filePath;
            _tableFiles.Rows.Add(row);
        }
    }

    private void BtnAddFiles_Click(object? sender, EventArgs e)
    {
        using var ofd = new OpenFileDialog
        {
            Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*",
            Title = "Select additional XML files to add",
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
                var info = _concatenateService.GetXmlHeaderInfo(file);

                if (_referenceInfo != null)
                {
                    var (valid, error) = _concatenateService.TestXmlHeaderAgainstReference(info, _referenceInfo);
                    if (!valid)
                    {
                        addErrors.Add($"File '{Path.GetFileName(file)}' headers don't match:\n{error}");
                        continue;
                    }
                }

                _fileInfos.Add(info);
                addedCount++;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Failed to add XML file: {Path.GetFileName(file)}", "CONCAT", ex);
                addErrors.Add($"Error loading {file}: {ex.Message}");
            }
        }

        if (addErrors.Count > 0)
        {
            MessageBox.Show(
                "Some files could not be added:\n\n" + string.Join("\n\n", addErrors),
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
            Description = "Select output directory for concatenated XML"
        };
        if (folderDialog.ShowDialog(this) != DialogResult.OK) return;

        var outputDir = folderDialog.SelectedPath;

        // Get output filename
        using var inputForm = new Form
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
            Text = "Enter the output filename (without .xml extension):"
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

        if (!filename.EndsWith(".xml", StringComparison.OrdinalIgnoreCase))
            filename += ".xml";

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
            // Check for duplicate patient IDs
            var duplicates = _concatenateService.GetDuplicatePatientIds(_fileInfos);
            bool reassignIds = false;

            if (duplicates.Count > 0)
            {
                var dupResult = ShowDuplicatePatientIdWarning(duplicates);
                if (dupResult == "Cancel") return;
                if (dupResult == "Reassign") reassignIds = true;
            }

            // Calculate totals for success message
            int totalTumors = 0;
            foreach (var item in _fileInfos)
            {
                if (item.TryGetValue("TumorCount", out var tc) && tc is int count)
                    totalTumors += count;
            }

            _concatenateService.WriteConcatenatedXml(_fileInfos, _referenceInfo!, outputPath, reassignPatientIds: reassignIds);

            var openResult = MessageBox.Show(
                $"Concatenated XML saved to:\n{outputPath}\n\nTotal tumors: {totalTumors}\n\nOpen newly created file?",
                "Success",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information);

            OutputFilePath = outputPath;
            ShouldOpenOutput = openResult == DialogResult.Yes;
            Close();
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to concatenate XML files", "CONCAT", ex);
            MessageBox.Show(
                $"Error concatenating XMLs: {ex.Message}",
                "Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private string ShowDuplicatePatientIdWarning(List<string> duplicates)
    {
        using var warningForm = new Form
        {
            Text = "Duplicate Patient IDs Detected",
            Width = 500,
            Height = 350,
            StartPosition = FormStartPosition.CenterScreen,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false
        };

        var lblWarning = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(470, 40),
            Text = "Warning: The following patient IDs appear in multiple files. This may cause issues in downstream systems.",
            ForeColor = Color.DarkRed
        };

        var txtDuplicates = new TextBox
        {
            Location = new Point(10, 55),
            Size = new Size(465, 150),
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            ReadOnly = true,
            Font = new Font("Consolas", 9)
        };

        var duplicateText = string.Join("\r\n", duplicates.OrderBy(d => d).Select(d => $"Duplicate: {d}"));
        txtDuplicates.Text = duplicateText;

        string dialogResult = "Cancel";

        var btnReassign = new Button
        {
            Text = "Reassign All Patient IDs (Start at 1)",
            Width = 220,
            Height = 30,
            Location = new Point(10, 220)
        };
        btnReassign.Click += (_, _) => { dialogResult = "Reassign"; warningForm.Close(); };

        var btnKeep = new Button
        {
            Text = "Concatenate Anyway (Keep IDs)",
            Width = 220,
            Height = 30,
            Location = new Point(10, 260),
            ForeColor = Color.DarkRed
        };
        btnKeep.Click += (_, _) => { dialogResult = "Keep"; warningForm.Close(); };

        var btnCancel = new Button
        {
            Text = "Cancel",
            Width = 100,
            Height = 30,
            Location = new Point(375, 260)
        };
        btnCancel.Click += (_, _) => { dialogResult = "Cancel"; warningForm.Close(); };

        warningForm.Controls.AddRange(new Control[] { lblWarning, txtDuplicates, btnReassign, btnKeep, btnCancel });
        warningForm.CancelButton = btnCancel;
        warningForm.ShowDialog(this);

        return dialogResult;
    }
}
