using System.Data;
using System.Windows.Forms;
using System.Xml;
using Parat.Core.Models;
using Parat.UI.Controls;

namespace Parat.UI.Services;

/// <summary>
/// Handles record navigation: displaying tumors and HL7 messages,
/// prev/next navigation, and grid selection sync.
/// Ported from Show-Tumor, Show-Hl7Message, and grid event logic in parat.ps1 / hl7-viewer.ps1.
/// </summary>
public class NavigationService
{
    private readonly AppState _state;

    public NavigationService(AppState state)
    {
        _state = state;
    }

    // ── Control references (set by MainForm after construction) ──────────

    public DataGridView GridNav { get; set; } = null!;
    public RichTextBox RtbPath { get; set; } = null!;
    public RichTextBox RtbItems { get; set; } = null!;
    public Button BtnPrev { get; set; } = null!;
    public Button BtnNext { get; set; } = null!;
    public Label LblIndex { get; set; } = null!;
    public TextBox TxtSearch { get; set; } = null!;
    public FlowLayoutPanel PnlCopyBar { get; set; } = null!;
    public Button[] BtnCopyFields { get; set; } = null!;

    // ── Show Tumor (XML record) ──────────────────────────────────────────

    /// <summary>
    /// Displays a formatted XML tumor record in the RichTextBox panels
    /// with syntax highlighting. Ported from Show-Tumor in parat.ps1.
    /// </summary>
    public void ShowTumor(int index)
    {
        var tumors = _state.Tumors;
        var nsMgr = _state.NsMgr;
        if (tumors == null || tumors.Count == 0) return;
        if (index < 0 || index >= tumors.Count) return;

        // Re-entry guard
        if (_state.IsShowingTumor) return;
        _state.IsShowingTumor = true;

        try
        {
            _state.CurrentIndex = index;
            var tumor = tumors[index]!;

            RtbPath.Clear();
            RtbItems.Clear();

            // Select corresponding grid row
            SelectGridRow(index);

            // === PATH PANEL: Text field content ===
            foreach (var textId in SyntaxHighlightingHelper.TextFieldIds)
            {
                var node = tumor.SelectSingleNode($"./n:Item[@naaccrId='{textId}']", nsMgr!);
                if (node != null)
                {
                    SyntaxHighlightingHelper.AddSectionHeader(RtbPath, textId);

                    var value = node.InnerText;
                    if (string.IsNullOrWhiteSpace(value))
                    {
                        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbPath, "(no text)");
                    }
                    else
                    {
                        var lines = value.Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None);
                        foreach (var line in lines)
                            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbPath, line);
                    }

                    SyntaxHighlightingHelper.AddLineToRichTextBox(RtbPath, "");
                }
            }

            // === ITEMS PANEL: Tumor and patient items ===
            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Tumor {index + 1} of {tumors.Count}", bold: true);
            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");

            // Patient items
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr!);
            string copyLast = "", copyFirst = "", copyDob = "", copyPathReport = "";

            if (patient != null)
            {
                var patientItems = patient.SelectNodes("./n:Item", nsMgr!);
                if (patientItems != null && patientItems.Count > 0)
                {
                    var sorted = SortItemsWithPriority(patientItems, PatientPriorityIds);
                    SyntaxHighlightingHelper.AddSectionHeader(RtbItems, "PATIENT ITEMS");
                    foreach (var item in sorted)
                    {
                        var id = item.Attributes?["naaccrId"]?.Value ?? "";
                        var value = item.InnerText;
                        bool isBold = SyntaxHighlightingHelper.BoldIds.Contains(id);
                        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"{id}: {value}", bold: isBold);

                        if (id == "nameLast") copyLast = value;
                        else if (id == "nameFirst") copyFirst = value;
                        else if (id == "dateOfBirth") copyDob = value;
                    }
                    SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");
                }
            }

            // Tumor items (excluding text fields)
            var tumorItemsAll = tumor.SelectNodes("./n:Item", nsMgr!);
            if (tumorItemsAll != null && tumorItemsAll.Count > 0)
            {
                var tumorItems = new List<XmlNode>();
                foreach (XmlNode item in tumorItemsAll)
                {
                    var id = item.Attributes?["naaccrId"]?.Value ?? "";
                    if (!SyntaxHighlightingHelper.TextFieldIds.Contains(id))
                        tumorItems.Add(item);
                }

                if (tumorItems.Count > 0)
                {
                    var sorted = SortItemsWithPriority(tumorItems, TumorPriorityIds);
                    SyntaxHighlightingHelper.AddSectionHeader(RtbItems, "TUMOR ITEMS");
                    foreach (var item in sorted)
                    {
                        var id = item.Attributes?["naaccrId"]?.Value ?? "";
                        var value = item.InnerText;
                        bool isBold = SyntaxHighlightingHelper.BoldIds.Contains(id);
                        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"{id}: {value}", bold: isBold);

                        if (id == "pathReportNumber1") copyPathReport = value;
                    }
                }
            }

            // Update copy buttons
            UpdateCopyButtons(copyLast, copyFirst, copyDob, copyPathReport);

            // Update index label and button states
            int selectedCount = GetSelectedCount();
            LblIndex.Text = $"Tumor {index + 1} of {tumors.Count} ({selectedCount} selected)";
            BtnPrev.Enabled = index > 0;
            BtnNext.Enabled = index < tumors.Count - 1;

            // Apply highlighting
            SyntaxHighlightingHelper.SetXmlPanelHighlighting(RtbItems);

            var searchText = TxtSearch?.Text;
            SyntaxHighlightingHelper.InvokeSearchHighlight(RtbPath, searchText);
            SyntaxHighlightingHelper.InvokeSearchHighlight(RtbItems, searchText);
        }
        finally
        {
            _state.IsShowingTumor = false;
        }
    }

    // ── Show HL7 Message ─────────────────────────────────────────────────

    /// <summary>
    /// Displays a formatted HL7 message in the RichTextBox panels
    /// with syntax highlighting. Ported from Show-Hl7Message in hl7-viewer.ps1.
    /// </summary>
    public void ShowHl7Message(int index)
    {
        var messages = _state.Hl7Messages;
        if (messages == null || messages.Count == 0)
        {
            MessageBox.Show("No HL7 messages loaded!", "Error");
            return;
        }
        if (index < 0 || index >= messages.Count)
        {
            MessageBox.Show($"Index out of range! Index: {index}, Count: {messages.Count}", "Error");
            return;
        }

        _state.CurrentIndex = index;
        var message = messages[index];

        RtbPath.Clear();
        RtbItems.Clear();

        // Select corresponding grid row
        SelectGridRow(index);

        // === PATH PANEL: Clean OBX text content ===
        SyntaxHighlightingHelper.AddSectionHeader(RtbPath, "PATHOLOGY REPORT TEXT");

        if (message.Segments.TryGetValue("OBX", out var obxSegments) && obxSegments.Count > 0)
        {
            var cleanText = GetObxTextContent(obxSegments);
            if (!string.IsNullOrWhiteSpace(cleanText))
            {
                var lines = cleanText.Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None);
                foreach (var line in lines)
                    SyntaxHighlightingHelper.AddLineToRichTextBox(RtbPath, line);
            }
            else
            {
                SyntaxHighlightingHelper.AddLineToRichTextBox(RtbPath, "(No text content in OBX segments)");
            }
        }
        else
        {
            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbPath, "(No OBX segments in this message)");
        }

        // === ITEMS PANEL: Metadata + raw segments ===
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Message {index + 1} of {messages.Count}", bold: true);
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");

        SyntaxHighlightingHelper.AddSectionHeader(RtbItems, "MESSAGE INFO");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Message Type: {message.MessageType}", bold: true);
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Date/Time: {FormatHl7DateTime(message.MessageDateTime)}");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Sending App: {message.SendingApplication}");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Sending Facility: {message.SendingFacility}");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");

        SyntaxHighlightingHelper.AddSectionHeader(RtbItems, "PATIENT INFO");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Patient ID: {message.PatientId}", bold: true);
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Name: {message.PatientName}", bold: true);
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Last Name: {message.PatientLastName}");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"First Name: {message.PatientFirstName}");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Date of Birth: {FormatHl7DateTime(message.DateOfBirth)}", bold: true);
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Sex: {message.Sex}");
        SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");

        // Order info (if present)
        if (!string.IsNullOrWhiteSpace(message.OrderDateTime) ||
            !string.IsNullOrWhiteSpace(message.OrderingProvider))
        {
            SyntaxHighlightingHelper.AddSectionHeader(RtbItems, "ORDER INFO");
            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Order Date/Time: {FormatHl7DateTime(message.OrderDateTime)}");
            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"Ordering Provider: {message.OrderingProvider}");
            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");
        }

        // NTE segments
        if (message.Segments.TryGetValue("NTE", out var nteSegments))
        {
            SyntaxHighlightingHelper.AddSectionHeader(RtbItems, "NOTES");
            foreach (var nte in nteSegments)
            {
                var fields = nte.Split('|');
                var noteText = fields.Length > 3 ? fields[3] : "";
                if (!string.IsNullOrWhiteSpace(noteText))
                    SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, noteText);
            }
            SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");
        }

        // Raw HL7 segments
        SyntaxHighlightingHelper.AddSectionHeader(RtbItems, "RAW HL7 SEGMENTS");

        var segmentOrder = new[] { "MSH", "PID", "PV1", "ORC", "OBR", "NTE", "OBX" };
        var displayedTypes = new HashSet<string>();

        foreach (var segType in segmentOrder)
        {
            if (message.Segments.TryGetValue(segType, out var segs))
            {
                SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"{segType} Segment(s)", bold: true);
                foreach (var seg in segs)
                    SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, FormatHl7SegmentForDisplay(seg));
                SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");
                displayedTypes.Add(segType);
            }
        }

        // Other segment types not in the standard order
        foreach (var segType in message.Segments.Keys)
        {
            if (!displayedTypes.Contains(segType))
            {
                SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, $"{segType} Segment(s)", bold: true);
                foreach (var seg in message.Segments[segType])
                    SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, FormatHl7SegmentForDisplay(seg));
                SyntaxHighlightingHelper.AddLineToRichTextBox(RtbItems, "");
            }
        }

        // Apply HL7 highlighting to the raw segments section
        var rtbText = RtbItems.Text;
        const string rawSectionMarker = "RAW HL7 SEGMENTS";
        int rawSectionStart = rtbText.IndexOf(rawSectionMarker, StringComparison.Ordinal);
        if (rawSectionStart >= 0)
        {
            SyntaxHighlightingHelper.SetHl7PanelHighlighting(RtbItems, rawSectionStart + rawSectionMarker.Length);
        }

        // Apply search highlighting
        var searchText = TxtSearch?.Text;
        SyntaxHighlightingHelper.InvokeSearchHighlight(RtbPath, searchText);
        SyntaxHighlightingHelper.InvokeSearchHighlight(RtbItems, searchText);

        // Update copy buttons for HL7
        UpdateCopyButtons(
            message.PatientLastName,
            message.PatientFirstName,
            message.DateOfBirth,
            "" // HL7 messages don't have pathReportNumber1
        );

        // Update index label and button states
        int selectedCount = GetSelectedCount();
        LblIndex.Text = $"Message {index + 1} of {messages.Count} ({selectedCount} selected)";
        BtnPrev.Enabled = index > 0;
        BtnNext.Enabled = index < messages.Count - 1;
    }

    // ── Navigation ───────────────────────────────────────────────────────

    /// <summary>
    /// Navigates to the previous record.
    /// </summary>
    public void NavigatePrevious()
    {
        if (_state.CurrentIndex > 0)
            ShowRecord(_state.CurrentIndex - 1);
    }

    /// <summary>
    /// Navigates to the next record.
    /// </summary>
    public void NavigateNext()
    {
        if (_state.CurrentIndex < _state.RecordCount - 1)
            ShowRecord(_state.CurrentIndex + 1);
    }

    /// <summary>
    /// Shows the appropriate record based on the current file type.
    /// </summary>
    public void ShowRecord(int index)
    {
        if (_state.FileType == "hl7")
            ShowHl7Message(index);
        else
            ShowTumor(index);
    }

    // ── Grid selection handler ───────────────────────────────────────────

    /// <summary>
    /// Handles grid row selection changes. Called from MainForm's grid SelectionChanged event.
    /// </summary>
    public void HandleGridSelectionChanged()
    {
        if (_state.IsLoadingData || _state.IsShowingTumor) return;

        int recordCount = _state.RecordCount;
        if (recordCount == 0) return;

        // Only navigate when exactly one row is selected
        if (GridNav.SelectedRows.Count != 1) return;

        var selectedRow = GridNav.SelectedRows[0];
        var indexValObj = selectedRow.Cells["Index"].Value;
        if (indexValObj == null) return;

        int recordIndex = Convert.ToInt32(indexValObj) - 1;
        if (recordIndex < 0 || recordIndex >= recordCount) return;
        if (recordIndex == _state.CurrentIndex) return;

        ShowRecord(recordIndex);
    }

    /// <summary>
    /// Updates the selected count label. Called when checkbox values change.
    /// </summary>
    public void UpdateSelectedCountLabel()
    {
        int selectedCount = GetSelectedCount();
        int totalCount = _state.RecordCount;
        string recordType = _state.FileType == "hl7" ? "Message" : "Tumor";
        LblIndex.Text = $"{recordType} {_state.CurrentIndex + 1} of {totalCount} ({selectedCount} selected)";
    }

    // ── Private helpers ──────────────────────────────────────────────────

    private void SelectGridRow(int index)
    {
        int targetIndexValue = index + 1;
        GridNav.ClearSelection();
        foreach (DataGridViewRow row in GridNav.Rows)
        {
            if (row.Cells["Index"].Value is int val && val == targetIndexValue)
            {
                row.Selected = true;
                GridNav.CurrentCell = row.Cells[0];
                break;
            }
        }
    }

    private int GetSelectedCount()
    {
        var dataTable = GridNav.DataSource as DataTable;
        if (dataTable == null) return 0;

        int count = 0;
        foreach (DataRow row in dataTable.Rows)
        {
            if (row["Selected"] is bool selected && selected)
                count++;
        }
        return count;
    }

    /// <summary>
    /// Formats an HL7 datetime string for display.
    /// </summary>
    private static string FormatHl7DateTime(string? hl7DateTime)
    {
        if (string.IsNullOrWhiteSpace(hl7DateTime)) return "";

        try
        {
            // HL7 datetime: YYYYMMDDHHMMSS or YYYYMMDD
            if (hl7DateTime.Length >= 8)
            {
                var datePart = $"{hl7DateTime[..4]}-{hl7DateTime[4..6]}-{hl7DateTime[6..8]}";
                if (hl7DateTime.Length >= 12)
                {
                    var timePart = $"{hl7DateTime[8..10]}:{hl7DateTime[10..12]}";
                    if (hl7DateTime.Length >= 14)
                        timePart += $":{hl7DateTime[12..14]}";
                    return $"{datePart} {timePart}";
                }
                return datePart;
            }
        }
        catch
        {
            // Fall through to return raw value
        }

        return hl7DateTime;
    }

    /// <summary>
    /// Formats an HL7 segment for display, preserving field structure.
    /// </summary>
    private static string FormatHl7SegmentForDisplay(string segment)
    {
        if (string.IsNullOrWhiteSpace(segment)) return "";

        var fields = segment.Split('|');
        var result = fields[0];
        for (int i = 1; i < fields.Length; i++)
            result += "|" + fields[i];

        return result;
    }

    /// <summary>
    /// Extracts clean text content from OBX segments.
    /// This is a simplified version; the full implementation is in Hl7Parser (Phase 2).
    /// </summary>
    private static string GetObxTextContent(List<string> obxSegments)
    {
        var lines = new List<string>();
        foreach (var obx in obxSegments)
        {
            var fields = obx.Split('|');
            // OBX-2 is value type, OBX-5 is the observation value
            if (fields.Length > 5)
            {
                var valueType = fields.Length > 2 ? fields[2] : "";
                if (string.Equals(valueType, "TX", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(valueType, "FT", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(valueType, "ST", StringComparison.OrdinalIgnoreCase))
                {
                    var text = fields[5];
                    if (!string.IsNullOrEmpty(text))
                    {
                        // Replace HL7 escape sequences
                        text = text.Replace("\\.br\\", "\n")
                                   .Replace("\\E\\", "\\")
                                   .Replace("\\S\\", "^")
                                   .Replace("\\T\\", "&")
                                   .Replace("\\R\\", "~")
                                   .Replace("\\F\\", "|");
                        lines.Add(text);
                    }
                }
            }
        }
        return string.Join("\n", lines);
    }

    // ── Copy button and item sorting helpers ────────────────────────────

    // IDs that should appear first in their respective groups
    private static readonly string[] PatientPriorityIds = { "nameLast", "nameFirst", "nameMiddle", "dateOfBirth" };
    private static readonly string[] TumorPriorityIds = { "pathReportNumber1" };

    // Button labels: [0]=Last, [1]=First, [2]=DOB, [3]=Path#
    private static readonly string[] CopyLabels = { "Last", "First", "DOB", "Path#" };

    /// <summary>
    /// Sorts XML items so priority IDs appear first (in order), followed by the rest in original order.
    /// </summary>
    private static List<XmlNode> SortItemsWithPriority(XmlNodeList items, string[] priorityIds)
    {
        var priorityItems = new XmlNode?[priorityIds.Length];
        var rest = new List<XmlNode>();

        foreach (XmlNode item in items)
        {
            var id = item.Attributes?["naaccrId"]?.Value ?? "";
            int priorityIndex = Array.IndexOf(priorityIds, id);
            if (priorityIndex >= 0)
                priorityItems[priorityIndex] = item;
            else
                rest.Add(item);
        }

        var result = new List<XmlNode>(items.Count);
        foreach (var item in priorityItems)
        {
            if (item != null)
                result.Add(item);
        }
        result.AddRange(rest);
        return result;
    }

    /// <summary>
    /// Overload for List&lt;XmlNode&gt; (used by tumor items after filtering).
    /// </summary>
    private static List<XmlNode> SortItemsWithPriority(List<XmlNode> items, string[] priorityIds)
    {
        var priorityItems = new XmlNode?[priorityIds.Length];
        var rest = new List<XmlNode>();

        foreach (var item in items)
        {
            var id = item.Attributes?["naaccrId"]?.Value ?? "";
            int priorityIndex = Array.IndexOf(priorityIds, id);
            if (priorityIndex >= 0)
                priorityItems[priorityIndex] = item;
            else
                rest.Add(item);
        }

        var result = new List<XmlNode>(items.Count);
        foreach (var item in priorityItems)
        {
            if (item != null)
                result.Add(item);
        }
        result.AddRange(rest);
        return result;
    }

    /// <summary>
    /// Updates the copy button bar with current record values.
    /// Buttons are hidden when their value is empty.
    /// </summary>
    private void UpdateCopyButtons(string nameLast, string nameFirst, string dob, string pathReport)
    {
        var values = new[] { nameLast, nameFirst, dob, pathReport };

        bool anyVisible = false;
        for (int i = 0; i < 4; i++)
        {
            var val = values[i]?.Trim() ?? "";
            bool hasValue = val.Length > 0;
            BtnCopyFields[i].Visible = hasValue;
            BtnCopyFields[i].Tag = val;
            BtnCopyFields[i].Text = hasValue ? $"{CopyLabels[i]}: {val}" : CopyLabels[i];
            anyVisible |= hasValue;
        }
        PnlCopyBar.Visible = anyVisible;
    }
}
