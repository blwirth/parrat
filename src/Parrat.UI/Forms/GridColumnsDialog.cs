using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Dialog for customizing XML grid columns.
/// Users can add/remove NAACCR fields and reorder them via drag-and-drop or buttons.
/// </summary>
public class GridColumnsDialog : Form
{
    private readonly IGridSettingsService _gridSettingsService;
    private readonly INaaccrDictionary _naaccrDictionary;
    private readonly ListBox _lstActive;
    private readonly ListBox _lstAvailable;
    private readonly TextBox _txtSearch;
    private readonly Button _btnAdd;
    private readonly Button _btnRemove;
    private readonly Button _btnMoveUp;
    private readonly Button _btnMoveDown;
    private readonly Button _btnOk;
    private readonly Button _btnCancel;
    private readonly Button _btnReset;

    public bool SettingsChanged { get; private set; }

    public GridColumnsDialog(IGridSettingsService gridSettingsService, INaaccrDictionary naaccrDictionary)
    {
        _gridSettingsService = gridSettingsService;
        _naaccrDictionary = naaccrDictionary;

        Text = "Grid Columns (XML)";
        Size = new Size(580, 420);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        // ── Active columns (left) ──────────────────────────────────────
        var lblActive = new Label { Text = "Active Columns (drag to reorder):", Location = new Point(12, 12), AutoSize = true };
        _lstActive = new ListBox
        {
            Location = new Point(12, 32),
            Size = new Size(200, 280),
            AllowDrop = true
        };
        _lstActive.MouseDown += LstActive_MouseDown;
        _lstActive.DragEnter += LstActive_DragEnter;
        _lstActive.DragDrop += LstActive_DragDrop;

        // ── Move buttons (center-left) ─────────────────────────────────
        _btnMoveUp = new Button { Text = "\u25B2", Location = new Point(218, 100), Size = new Size(30, 30), Font = new Font("Segoe UI", 9f) };
        _btnMoveDown = new Button { Text = "\u25BC", Location = new Point(218, 136), Size = new Size(30, 30), Font = new Font("Segoe UI", 9f) };
        _btnAdd = new Button { Text = "\u25C0", Location = new Point(218, 190), Size = new Size(30, 30), Font = new Font("Segoe UI", 9f) };
        _btnRemove = new Button { Text = "\u25B6", Location = new Point(218, 226), Size = new Size(30, 30), Font = new Font("Segoe UI", 9f) };

        _btnMoveUp.Click += (_, _) => MoveActiveItem(-1);
        _btnMoveDown.Click += (_, _) => MoveActiveItem(1);
        _btnAdd.Click += (_, _) => AddSelectedColumn();
        _btnRemove.Click += (_, _) => RemoveSelectedColumn();

        // ── Available columns (right) ──────────────────────────────────
        var lblAvail = new Label { Text = "Available NAACCR Fields:", Location = new Point(260, 12), AutoSize = true };
        _txtSearch = new TextBox { Location = new Point(260, 32), Size = new Size(290, 23), PlaceholderText = "Search fields..." };
        _txtSearch.TextChanged += (_, _) => FilterAvailableColumns();

        _lstAvailable = new ListBox
        {
            Location = new Point(260, 60),
            Size = new Size(290, 252)
        };
        _lstAvailable.DoubleClick += (_, _) => AddSelectedColumn();

        // ── Bottom buttons ─────────────────────────────────────────────
        _btnReset = new Button { Text = "Reset to Defaults", Location = new Point(12, 345), Size = new Size(120, 28) };
        _btnOk = new Button { Text = "OK", Location = new Point(390, 345), Size = new Size(75, 28) };
        _btnCancel = new Button { Text = "Cancel", Location = new Point(475, 345), Size = new Size(75, 28), DialogResult = DialogResult.Cancel };

        _btnReset.Click += BtnReset_Click;
        _btnOk.Click += BtnOk_Click;
        CancelButton = _btnCancel;

        Controls.AddRange(new Control[] {
            lblActive, _lstActive,
            _btnMoveUp, _btnMoveDown, _btnAdd, _btnRemove,
            lblAvail, _txtSearch, _lstAvailable,
            _btnReset, _btnOk, _btnCancel
        });

        LoadCurrentSettings();
        PopulateAvailableColumns();
    }

    // ── Data loading ───────────────────────────────────────────────────

    private void LoadCurrentSettings()
    {
        var settings = _gridSettingsService.Load();
        _lstActive.Items.Clear();
        foreach (var col in settings.Xml.Columns)
            _lstActive.Items.Add(col.Id);
    }

    private void PopulateAvailableColumns()
    {
        var dict = _naaccrDictionary.GetDictionary();
        var activeSet = new HashSet<string>();
        foreach (string id in _lstActive.Items)
            activeSet.Add(id);

        var searchText = _txtSearch.Text.Trim().ToLowerInvariant();
        _lstAvailable.Items.Clear();

        foreach (var item in dict.Values.OrderBy(x => x.Name))
        {
            if (activeSet.Contains(item.XmlId)) continue;
            if (searchText.Length > 0 &&
                !item.Name.Contains(searchText, StringComparison.OrdinalIgnoreCase) &&
                !item.XmlId.Contains(searchText, StringComparison.OrdinalIgnoreCase))
                continue;

            _lstAvailable.Items.Add($"{item.XmlId}  ({item.Name})");
        }
    }

    private void FilterAvailableColumns() => PopulateAvailableColumns();

    // ── Column manipulation ────────────────────────────────────────────

    private void AddSelectedColumn()
    {
        if (_lstAvailable.SelectedItem == null) return;
        var display = _lstAvailable.SelectedItem.ToString()!;
        var xmlId = display.Split("  (")[0];

        _lstActive.Items.Add(xmlId);
        PopulateAvailableColumns();
    }

    private void RemoveSelectedColumn()
    {
        if (_lstActive.SelectedIndex < 0) return;
        var idx = _lstActive.SelectedIndex;
        _lstActive.Items.RemoveAt(idx);
        if (idx < _lstActive.Items.Count)
            _lstActive.SelectedIndex = idx;
        else if (_lstActive.Items.Count > 0)
            _lstActive.SelectedIndex = _lstActive.Items.Count - 1;
        PopulateAvailableColumns();
    }

    private void MoveActiveItem(int direction)
    {
        var idx = _lstActive.SelectedIndex;
        if (idx < 0) return;
        var newIdx = idx + direction;
        if (newIdx < 0 || newIdx >= _lstActive.Items.Count) return;

        var item = _lstActive.Items[idx];
        _lstActive.Items.RemoveAt(idx);
        _lstActive.Items.Insert(newIdx, item);
        _lstActive.SelectedIndex = newIdx;
    }

    // ── Drag and drop reordering ───────────────────────────────────────

    private void LstActive_MouseDown(object? sender, MouseEventArgs e)
    {
        if (_lstActive.SelectedItem == null) return;
        _lstActive.DoDragDrop(_lstActive.SelectedItem, DragDropEffects.Move);
    }

    private void LstActive_DragEnter(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetDataPresent(typeof(string)) == true)
            e.Effect = DragDropEffects.Move;
    }

    private void LstActive_DragDrop(object? sender, DragEventArgs e)
    {
        var pt = _lstActive.PointToClient(new Point(e.X, e.Y));
        int targetIdx = _lstActive.IndexFromPoint(pt);
        if (targetIdx < 0) targetIdx = _lstActive.Items.Count - 1;

        var data = e.Data?.GetData(typeof(string)) as string;
        if (data == null) return;

        int sourceIdx = _lstActive.Items.IndexOf(data);
        if (sourceIdx < 0 || sourceIdx == targetIdx) return;

        _lstActive.Items.RemoveAt(sourceIdx);
        _lstActive.Items.Insert(targetIdx, data);
        _lstActive.SelectedIndex = targetIdx;
    }

    // ── Save / Reset ───────────────────────────────────────────────────

    private void BtnOk_Click(object? sender, EventArgs e)
    {
        if (_lstActive.Items.Count == 0)
        {
            MessageBox.Show("At least one column is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var settings = _gridSettingsService.Load();
        settings.Xml.Columns = new List<GridColumnDef>();
        foreach (string id in _lstActive.Items)
            settings.Xml.Columns.Add(new GridColumnDef { Id = id, Width = -1 });

        _gridSettingsService.Save(settings);
        SettingsChanged = true;
        DialogResult = DialogResult.OK;
        Close();
    }

    private void BtnReset_Click(object? sender, EventArgs e)
    {
        var defaults = _gridSettingsService.GetDefaultXmlColumns();
        _lstActive.Items.Clear();
        foreach (var col in defaults.Columns)
            _lstActive.Items.Add(col.Id);
        PopulateAvailableColumns();
    }
}
