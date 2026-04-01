using System.Drawing;
using System.Windows.Forms;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Dialog for managing OBX skip codes (codes to filter out from HL7 OBX segments).
/// Ported from Show-ObxSkipConfigDialog and Show-AddSkipCodeDialog in lib/obx-skip-config.ps1.
/// </summary>
public class ObxSkipConfigForm : Form
{
    private readonly IConfigService _configService;
    private ListView _listView = null!;

    /// <summary>True if the config was saved on close.</summary>
    public bool ConfigSaved { get; private set; }

    public ObxSkipConfigForm(IConfigService configService)
    {
        _configService = configService;
        InitializeControls();
    }

    private void InitializeControls()
    {
        var config = _configService.GetObxSkipConfig();

        // ── Form properties ──────────────────────────────────────────────
        Text = "OBX Skip Codes Configuration";
        Width = 500;
        Height = 400;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        // ── Description label ────────────────────────────────────────────
        var lblDesc = new Label
        {
            Location = new Point(15, 15),
            Size = new Size(455, 40),
            Text = "Configure OBX-3.1 codes to skip when extracting text for site/laterality testing.\r\nOBX segments with these codes will be excluded from analysis."
        };
        Controls.Add(lblDesc);

        // ── ListView ─────────────────────────────────────────────────────
        _listView = new ListView
        {
            Location = new Point(15, 60),
            Size = new Size(350, 230),
            View = View.Details,
            FullRowSelect = true,
            GridLines = true,
            MultiSelect = false,
            HideSelection = false
        };
        _listView.Columns.Add("Code", 80);
        _listView.Columns.Add("Description", 250);

        foreach (var code in config.SkipCodes)
        {
            var item = new ListViewItem(code);
            var desc = config.SkipCodeDescriptions.TryGetValue(code, out var d) ? d : "";
            item.SubItems.Add(desc);
            _listView.Items.Add(item);
        }
        Controls.Add(_listView);

        // ── Add button ───────────────────────────────────────────────────
        var btnAdd = new Button
        {
            Text = "Add...",
            Width = 100,
            Location = new Point(375, 60)
        };
        btnAdd.Click += OnAddClick;
        Controls.Add(btnAdd);

        // ── Edit button ──────────────────────────────────────────────────
        var btnEdit = new Button
        {
            Text = "Edit...",
            Width = 100,
            Location = new Point(375, 95)
        };
        btnEdit.Click += OnEditClick;
        Controls.Add(btnEdit);

        // ── Remove button ────────────────────────────────────────────────
        var btnRemove = new Button
        {
            Text = "Remove",
            Width = 100,
            Location = new Point(375, 130)
        };
        btnRemove.Click += OnRemoveClick;
        Controls.Add(btnRemove);

        // ── OK button ────────────────────────────────────────────────────
        var btnOk = new Button
        {
            Text = "OK",
            Width = 80,
            Location = new Point(310, 320)
        };
        btnOk.Click += OnOkClick;
        AcceptButton = btnOk;
        Controls.Add(btnOk);

        // ── Cancel button ────────────────────────────────────────────────
        var btnCancel = new Button
        {
            Text = "Cancel",
            Width = 80,
            Location = new Point(400, 320),
            DialogResult = DialogResult.Cancel
        };
        CancelButton = btnCancel;
        Controls.Add(btnCancel);
    }

    private void OnAddClick(object? sender, EventArgs e)
    {
        using var addDialog = new AddSkipCodeDialog();
        if (addDialog.ShowDialog(this) != DialogResult.OK) return;

        var code = addDialog.ResultCode;
        var desc = addDialog.ResultDescription;

        // Check for duplicates
        foreach (ListViewItem existing in _listView.Items)
        {
            if (string.Equals(existing.Text, code, StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show(
                    $"Code '{code}' already exists.",
                    "Duplicate Code",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
        }

        var item = new ListViewItem(code);
        item.SubItems.Add(desc);
        _listView.Items.Add(item);
    }

    private void OnEditClick(object? sender, EventArgs e)
    {
        if (_listView.SelectedItems.Count == 0)
        {
            MessageBox.Show("Select a code to edit.", "Edit Code",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var selectedItem = _listView.SelectedItems[0];
        using var editDialog = new AddSkipCodeDialog(selectedItem.Text, selectedItem.SubItems[1].Text);
        if (editDialog.ShowDialog(this) != DialogResult.OK) return;

        selectedItem.Text = editDialog.ResultCode;
        selectedItem.SubItems[1].Text = editDialog.ResultDescription;
    }

    private void OnRemoveClick(object? sender, EventArgs e)
    {
        if (_listView.SelectedItems.Count > 0)
            _listView.Items.Remove(_listView.SelectedItems[0]);
    }

    private void OnOkClick(object? sender, EventArgs e)
    {
        var newConfig = new ObxSkipConfig { Version = 1 };

        foreach (ListViewItem item in _listView.Items)
        {
            var code = item.Text;
            var desc = item.SubItems[1].Text;
            newConfig.SkipCodes.Add(code);
            if (!string.IsNullOrWhiteSpace(desc))
                newConfig.SkipCodeDescriptions[code] = desc;
        }

        _configService.SaveObxSkipConfig(newConfig);
        ConfigSaved = true;

        MessageBox.Show(
            "OBX skip codes configuration saved.",
            "Configuration Saved",
            MessageBoxButtons.OK, MessageBoxIcon.Information);

        DialogResult = DialogResult.OK;
        Close();
    }
}

/// <summary>
/// Sub-dialog for adding or editing a single OBX skip code.
/// Ported from Show-AddSkipCodeDialog in lib/obx-skip-config.ps1.
/// </summary>
public class AddSkipCodeDialog : Form
{
    private TextBox _txtCode = null!;
    private TextBox _txtDesc = null!;

    public string ResultCode { get; private set; } = string.Empty;
    public string ResultDescription { get; private set; } = string.Empty;

    public AddSkipCodeDialog(string code = "", string description = "")
    {
        var isEdit = !string.IsNullOrEmpty(code);

        Text = isEdit ? "Edit Skip Code" : "Add Skip Code";
        Width = 350;
        Height = 180;
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        Controls.Add(new Label
        {
            Text = "Code:",
            Location = new Point(15, 20),
            Size = new Size(80, 20)
        });

        _txtCode = new TextBox
        {
            Location = new Point(100, 17),
            Size = new Size(220, 20),
            Text = code,
            MaxLength = 20
        };
        Controls.Add(_txtCode);

        Controls.Add(new Label
        {
            Text = "Description:",
            Location = new Point(15, 55),
            Size = new Size(80, 20)
        });

        _txtDesc = new TextBox
        {
            Location = new Point(100, 52),
            Size = new Size(220, 20),
            Text = description,
            MaxLength = 100
        };
        Controls.Add(_txtDesc);

        var btnOk = new Button
        {
            Text = "OK",
            Width = 80,
            Location = new Point(155, 100)
        };
        btnOk.Click += OnOkClick;
        AcceptButton = btnOk;
        Controls.Add(btnOk);

        var btnCancel = new Button
        {
            Text = "Cancel",
            Width = 80,
            Location = new Point(240, 100),
            DialogResult = DialogResult.Cancel
        };
        CancelButton = btnCancel;
        Controls.Add(btnCancel);
    }

    private void OnOkClick(object? sender, EventArgs e)
    {
        var code = _txtCode.Text.Trim().ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(code))
        {
            MessageBox.Show("Code is required.", "Validation Error",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        ResultCode = code;
        ResultDescription = _txtDesc.Text.Trim();
        DialogResult = DialogResult.OK;
        Close();
    }
}
