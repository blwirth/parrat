using System.Text.RegularExpressions;
using Parrat.Core.Interfaces;

namespace Parrat.UI.Forms;

/// <summary>
/// Popup dialog for searching and selecting a NAACCR field.
///
/// Where the caller knows which fields the loaded file actually contains, the
/// list opens showing only those: picking from the dozen fields in front of you
/// beats scrolling 780 dictionary items, most of which the file has no value
/// for. The full dictionary is always one checkbox away.
/// </summary>
public class NaaccrFieldPickerDialog : ParratFormBase
{
    private readonly INaaccrDictionary _dictionary;
    private readonly HashSet<string>? _presentFieldIds;
    private readonly TextBox _txtSearch;
    private readonly ListBox _lstFields;
    private readonly CheckBox? _chkShowAll;

    /// <summary>Gets the selected NAACCR xmlId, or null if "unmapped" was chosen.</summary>
    public string? SelectedXmlId { get; private set; }

    public NaaccrFieldPickerDialog(INaaccrDictionary dictionary, string? currentXmlId)
        : this(dictionary, currentXmlId, null, allowUnmap: true) { }

    /// <param name="presentFieldIds">
    /// Field ids found in the loaded file, or null to always list the whole dictionary.
    /// </param>
    /// <param name="allowUnmap">Whether the dialog offers clearing the selection.</param>
    public NaaccrFieldPickerDialog(
        INaaccrDictionary dictionary,
        string? currentXmlId,
        IEnumerable<string>? presentFieldIds,
        bool allowUnmap)
    {
        _dictionary = dictionary;
        SelectedXmlId = currentXmlId;

        if (presentFieldIds != null)
            _presentFieldIds = new HashSet<string>(presentFieldIds, StringComparer.Ordinal);

        Text = "Select NAACCR Field";
        Width = 500;
        Height = 500;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;

        var lblSearch = new Label
        {
            Text = "Search (name, xmlId, or item number):",
            Location = new Point(10, 10),
            AutoSize = true
        };

        _txtSearch = new TextBox
        {
            Location = new Point(10, 30),
            Size = new Size(460, 23)
        };
        _txtSearch.TextChanged += (_, _) => PopulateList(_txtSearch.Text);

        _lstFields = new ListBox
        {
            Location = new Point(10, 60),
            Size = new Size(460, 340)
        };
        _lstFields.DoubleClick += (_, _) => AcceptSelection();

        var controls = new List<Control> { lblSearch, _txtSearch, _lstFields };

        if (_presentFieldIds != null)
        {
            _chkShowAll = new CheckBox
            {
                Text = "Show all dictionary fields",
                Location = new Point(10, 424),
                AutoSize = true
            };
            _chkShowAll.CheckedChanged += (_, _) => PopulateList(_txtSearch.Text);
            controls.Add(_chkShowAll);
        }

        var btnOk = new Button
        {
            Text = "OK",
            Location = new Point(200, 420),
            Width = 80,
            DialogResult = DialogResult.OK
        };
        btnOk.Click += (_, _) => AcceptSelection();
        controls.Add(btnOk);

        if (allowUnmap)
        {
            var btnClear = new Button
            {
                Text = "Unmap",
                Location = new Point(290, 420),
                Width = 80
            };
            btnClear.Click += (_, _) =>
            {
                SelectedXmlId = null;
                DialogResult = DialogResult.OK;
                Close();
            };
            controls.Add(btnClear);
        }

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new Point(380, 420),
            Width = 80,
            DialogResult = DialogResult.Cancel
        };
        controls.Add(btnCancel);

        Controls.AddRange(controls.ToArray());
        AcceptButton = btnOk;
        CancelButton = btnCancel;

        Shown += (_, _) =>
        {
            PopulateList("");
            _txtSearch.Focus();
        };
    }

    private void PopulateList(string filter)
    {
        _lstFields.BeginUpdate();
        _lstFields.Items.Clear();

        var items = string.IsNullOrWhiteSpace(filter)
            ? _dictionary.GetDictionary().Values.OrderBy(i => i.NumberInt).ToList()
            : _dictionary.Search(filter);

        bool restrict = _presentFieldIds != null && _chkShowAll?.Checked != true;
        if (restrict)
            items = items.Where(i => _presentFieldIds!.Contains(i.XmlId)).ToList();

        foreach (var item in items)
        {
            _lstFields.Items.Add($"{item.Number} - {item.Name} ({item.XmlId})");
        }

        // A field present in the file but absent from the dictionary — a custom
        // item — would otherwise be unreachable in the restricted list.
        if (restrict)
        {
            var known = new HashSet<string>(items.Select(i => i.XmlId), StringComparer.Ordinal);
            foreach (var id in _presentFieldIds!.Where(id => !known.Contains(id)).OrderBy(id => id, StringComparer.Ordinal))
            {
                if (string.IsNullOrWhiteSpace(filter) || id.Contains(filter, StringComparison.OrdinalIgnoreCase))
                    _lstFields.Items.Add($"CUSTOM - {id} ({id})");
            }
        }

        // Pre-select current if visible
        if (SelectedXmlId != null)
        {
            for (int i = 0; i < _lstFields.Items.Count; i++)
            {
                if (_lstFields.Items[i]?.ToString()?.Contains($"({SelectedXmlId})") == true)
                {
                    _lstFields.SelectedIndex = i;
                    break;
                }
            }
        }

        _lstFields.EndUpdate();
    }

    private void AcceptSelection()
    {
        if (_lstFields.SelectedItem == null) return;

        var text = _lstFields.SelectedItem.ToString() ?? "";
        var match = Regex.Match(text, @"\(([^)]+)\)$");
        if (match.Success)
        {
            SelectedXmlId = match.Groups[1].Value;
            DialogResult = DialogResult.OK;
            Close();
        }
    }
}
