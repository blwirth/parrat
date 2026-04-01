using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Dialog for NOAH reportability settings, model selection, and custom payload entry.
/// Combines Show-NoahSettingsDialog, Show-NoahModelSelectionDialog, and
/// Show-CustomPayloadDialog from ui/noah-reportability-ui.ps1.
/// </summary>
public class NoahReportabilityForm : Form
{
    private readonly INoahService _noahService;

    // ── Settings controls ────────────────────────────────────────────────
    private Label _lblExePath = null!;
    private TextBox _txtExePath = null!;
    private Button _btnBrowse = null!;
    private Label _lblOutput = null!;
    private ComboBox _cmbOutput = null!;
    private GroupBox _grpModels = null!;
    private Label _lblLastUpdated = null!;
    private ListBox _lstModels = null!;
    private Button _btnRefresh = null!;
    private Label _lblRefreshStatus = null!;
    private Button _btnSave = null!;
    private Button _btnCancel = null!;

    /// <summary>Mode the dialog was opened in.</summary>
    public enum DialogMode { Settings, ModelSelection, CustomPayload }

    private readonly DialogMode _mode;
    private readonly NoahConfig _config;

    // ── Model-selection controls ─────────────────────────────────────────
    private Label? _lblModel;
    private ComboBox? _cmbModel;
    private Label? _lblModelStatus;
    private Button? _btnRunFilter;
    private Button? _btnModelCancel;
    private List<NoahModel>? _availableModels;

    // ── Custom-payload controls ──────────────────────────────────────────
    private Label? _lblPayloadPrompt;
    private TextBox? _txtCustomText;
    private Button? _btnTestNoah;
    private Button? _btnPayloadCancel;

    // ── Results ──────────────────────────────────────────────────────────

    /// <summary>Selected model info (ModelSelection mode).</summary>
    public NoahModel? SelectedModel { get; private set; }

    /// <summary>Output format chosen (ModelSelection mode).</summary>
    public string OutputFormat => _config.Output;

    /// <summary>Custom payload text (CustomPayload mode).</summary>
    public string? CustomPayloadText { get; private set; }

    /// <summary>Whether settings were saved (Settings mode).</summary>
    public bool SettingsSaved { get; private set; }

    public NoahReportabilityForm(INoahService noahService, NoahConfig config, DialogMode mode)
    {
        _noahService = noahService;
        _config = config;
        _mode = mode;

        switch (mode)
        {
            case DialogMode.Settings:
                InitializeSettingsLayout();
                break;
            case DialogMode.ModelSelection:
                InitializeModelSelectionLayout();
                break;
            case DialogMode.CustomPayload:
                InitializeCustomPayloadLayout();
                break;
        }

        StartPosition = FormStartPosition.CenterScreen;
    }

    // =====================================================================
    //  SETTINGS MODE
    // =====================================================================

    private void InitializeSettingsLayout()
    {
        Text = "NOAH Settings";
        Width = 600;
        Height = 450;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        // ── EXE Path Section ─────────────────────────────────────────
        _lblExePath = new Label
        {
            Location = new Point(10, 15),
            Size = new Size(560, 20),
            Text = "NOAH Executable Path:"
        };

        _txtExePath = new TextBox
        {
            Location = new Point(10, 40),
            Size = new Size(470, 25),
            Text = _config.ExePath,
            ReadOnly = true
        };

        _btnBrowse = new Button
        {
            Text = "Browse...",
            Width = 90,
            Location = new Point(490, 38)
        };
        _btnBrowse.Click += OnBrowseClick;

        // ── Output Format Section ────────────────────────────────────
        _lblOutput = new Label
        {
            Location = new Point(10, 75),
            Size = new Size(120, 20),
            Text = "Output Format:"
        };

        _cmbOutput = new ComboBox
        {
            Location = new Point(130, 72),
            Size = new Size(100, 25),
            DropDownStyle = ComboBoxStyle.DropDownList
        };
        _cmbOutput.Items.AddRange(new object[] { "hl7", "xml" });
        _cmbOutput.SelectedIndex = _config.Output == "xml" ? 1 : 0;

        // ── Models Section ───────────────────────────────────────────
        _grpModels = new GroupBox
        {
            Text = "Cached Models",
            Location = new Point(10, 110),
            Size = new Size(565, 220)
        };

        _lblLastUpdated = new Label
        {
            Location = new Point(10, 25),
            Size = new Size(400, 20)
        };

        var cachedModels = _noahService.GetCachedModels();
        if (cachedModels.LastUpdated != null)
        {
            if (DateTime.TryParse(cachedModels.LastUpdated, out var lastUpdated))
                _lblLastUpdated.Text = $"Last updated: {lastUpdated:yyyy-MM-dd HH:mm:ss}";
            else
                _lblLastUpdated.Text = $"Last updated: {cachedModels.LastUpdated}";
        }
        else
        {
            _lblLastUpdated.Text = "Last updated: Never (no cached models)";
        }

        _lstModels = new ListBox
        {
            Location = new Point(10, 50),
            Size = new Size(540, 120),
            Font = new Font("Consolas", 9f)
        };

        if (cachedModels.Models.Count > 0)
        {
            foreach (var model in cachedModels.Models)
                _lstModels.Items.Add($"{model.Name} - {model.Id}");
        }
        else
        {
            _lstModels.Items.Add("(No models cached - click Refresh to fetch from API)");
        }

        _btnRefresh = new Button
        {
            Text = "Refresh Models from API",
            Width = 180,
            Location = new Point(10, 180)
        };
        _btnRefresh.Click += OnRefreshModelsClick;

        _lblRefreshStatus = new Label
        {
            Location = new Point(200, 183),
            Size = new Size(350, 20),
            ForeColor = Color.Blue
        };

        _grpModels.Controls.AddRange(new Control[]
            { _lblLastUpdated, _lstModels, _btnRefresh, _lblRefreshStatus });

        // ── Buttons ──────────────────────────────────────────────────
        _btnSave = new Button
        {
            Text = "Save",
            Width = 100,
            Location = new Point(380, 370),
            DialogResult = DialogResult.OK
        };

        _btnCancel = new Button
        {
            Text = "Cancel",
            Width = 100,
            Location = new Point(490, 370),
            DialogResult = DialogResult.Cancel
        };

        Controls.AddRange(new Control[]
        {
            _lblExePath, _txtExePath, _btnBrowse,
            _lblOutput, _cmbOutput,
            _grpModels,
            _btnSave, _btnCancel
        });

        AcceptButton = _btnSave;
        CancelButton = _btnCancel;

        // Wire save
        _btnSave.Click += (_, _) =>
        {
            _config.ExePath = _txtExePath.Text;
            _config.Output = _cmbOutput.SelectedItem?.ToString() ?? "hl7";
            _noahService.SaveConfig(_config);
            SettingsSaved = true;
        };
    }

    private void OnBrowseClick(object? sender, EventArgs e)
    {
        using var ofd = new OpenFileDialog
        {
            Filter = "NOAH Client (NOAHClientCentralRegistry.exe)|NOAHClientCentralRegistry.exe|Executable (*.exe)|*.exe|All files (*.*)|*.*",
            Title = "Select NOAHClientCentralRegistry.exe"
        };

        if (ofd.ShowDialog() == DialogResult.OK)
            _txtExePath.Text = ofd.FileName;
    }

    private void OnRefreshModelsClick(object? sender, EventArgs e)
    {
        var exePath = _txtExePath.Text;
        if (string.IsNullOrWhiteSpace(exePath) || !File.Exists(exePath))
        {
            MessageBox.Show(
                "Please configure the NOAH executable path first.",
                "NOAH Settings",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        _btnRefresh.Enabled = false;
        _lblRefreshStatus.Text = "Starting NOAH server...";
        _lblRefreshStatus.ForeColor = Color.Blue;
        Refresh();

        Process? serverProcess = null;
        try
        {
            var tempConfig = new NoahConfig
            {
                ExePath = exePath,
                ApiServerUrl = _config.ApiServerUrl
            };

            serverProcess = _noahService.StartServer(tempConfig);
            _lblRefreshStatus.Text = "Fetching models from API...";
            Refresh();

            var models = _noahService.GetModels(tempConfig, ref serverProcess);

            if (models.Count == 0)
            {
                _lblRefreshStatus.Text = "No models returned from API";
                _lblRefreshStatus.ForeColor = Color.Orange;
                return;
            }

            _noahService.SaveCachedModels(models);

            _lstModels.Items.Clear();
            foreach (var model in models)
                _lstModels.Items.Add($"{model.Name} - {model.Id}");

            _lblLastUpdated.Text = $"Last updated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}";
            _lblRefreshStatus.Text = $"Successfully loaded {models.Count} model(s)";
            _lblRefreshStatus.ForeColor = Color.Green;
        }
        catch (Exception ex)
        {
            _lblRefreshStatus.Text = $"Error: {ex.Message}";
            _lblRefreshStatus.ForeColor = Color.Red;
        }
        finally
        {
            if (serverProcess != null)
                _noahService.StopServer(serverProcess);
            _btnRefresh.Enabled = true;
        }
    }

    // =====================================================================
    //  MODEL SELECTION MODE
    // =====================================================================

    private void InitializeModelSelectionLayout()
    {
        Text = "NOAH Model Selection";
        Width = 500;
        Height = 180;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        var cachedModels = _noahService.GetCachedModels();
        _availableModels = cachedModels.Models;

        _lblModel = new Label
        {
            Location = new Point(10, 15),
            Size = new Size(460, 20),
            Text = "Select Model:"
        };

        _cmbModel = new ComboBox
        {
            Location = new Point(10, 40),
            Size = new Size(460, 25),
            DropDownStyle = ComboBoxStyle.DropDownList
        };

        _lblModelStatus = new Label
        {
            Location = new Point(10, 75),
            Size = new Size(460, 35)
        };

        _btnRunFilter = new Button
        {
            Text = "Run Filter",
            Width = 100,
            Location = new Point(280, 115),
            DialogResult = DialogResult.OK
        };

        _btnModelCancel = new Button
        {
            Text = "Cancel",
            Width = 100,
            Location = new Point(390, 115),
            DialogResult = DialogResult.Cancel
        };

        Controls.AddRange(new Control[]
            { _lblModel, _cmbModel, _lblModelStatus, _btnRunFilter, _btnModelCancel });
        AcceptButton = _btnRunFilter;
        CancelButton = _btnModelCancel;

        if (_availableModels.Count == 0)
        {
            _cmbModel.Enabled = false;
            _btnRunFilter.Enabled = false;
            _lblModelStatus.Text = "No cached models. Go to NOAH > Settings to refresh models from API.";
            _lblModelStatus.ForeColor = Color.Red;
        }
        else
        {
            foreach (var model in _availableModels)
                _cmbModel.Items.Add($"{model.Name} ({model.Id})");

            int selectedIdx = 0;
            if (!string.IsNullOrWhiteSpace(_config.ModelId))
            {
                for (int i = 0; i < _availableModels.Count; i++)
                {
                    if (_availableModels[i].Id == _config.ModelId)
                    {
                        selectedIdx = i;
                        break;
                    }
                }
            }
            _cmbModel.SelectedIndex = selectedIdx;

            var outputFormat = _config.Output == "xml" ? "XML" : "HL7";
            _lblModelStatus.Text = $"Output format: {outputFormat} (change in Settings)";
            _lblModelStatus.ForeColor = Color.Gray;
        }

        _btnRunFilter.Click += (_, _) =>
        {
            if (_cmbModel.SelectedIndex >= 0 && _cmbModel.SelectedIndex < _availableModels.Count)
            {
                SelectedModel = _availableModels[_cmbModel.SelectedIndex];
                _config.ModelId = SelectedModel.Id;
                _noahService.SaveConfig(_config);
            }
        };
    }

    // =====================================================================
    //  CUSTOM PAYLOAD MODE
    // =====================================================================

    private void InitializeCustomPayloadLayout()
    {
        Text = "NOAH Custom Payload";
        Width = 600;
        Height = 400;
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimumSize = new Size(400, 300);

        _lblPayloadPrompt = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(560, 40),
            Text = "Enter the text you want to test against NOAH reportability:\n(This will be placed in the FinalDiagnosis OBX segment)"
        };

        _txtCustomText = new TextBox
        {
            Location = new Point(10, 55),
            Size = new Size(560, 250),
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            Font = new Font("Consolas", 10f),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
        };

        _btnTestNoah = new Button
        {
            Text = "Test with NOAH",
            Width = 120,
            Location = new Point(350, 315),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.OK
        };

        _btnPayloadCancel = new Button
        {
            Text = "Cancel",
            Width = 100,
            Location = new Point(480, 315),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.Cancel
        };

        Controls.AddRange(new Control[]
            { _lblPayloadPrompt, _txtCustomText, _btnTestNoah, _btnPayloadCancel });
        AcceptButton = _btnTestNoah;
        CancelButton = _btnPayloadCancel;

        _btnTestNoah.Click += (_, _) =>
        {
            var text = _txtCustomText.Text.Trim();
            CustomPayloadText = string.IsNullOrWhiteSpace(text) ? null : text;
        };
    }
}
