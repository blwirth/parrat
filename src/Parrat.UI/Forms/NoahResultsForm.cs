using System.Drawing;
using System.Text.Json;
using System.Windows.Forms;
using Parrat.Core.Interfaces;
using Parrat.UI.Controls;

namespace Parrat.UI.Forms;

/// <summary>
/// Results viewer for NOAH classification output.
/// Displays the NOAH result file with syntax-highlighted OBX text,
/// entity annotations (color-coded: Negated, Type0, Type1, Type2),
/// and classification summary.
/// Ported from Show-NoahResultsWindow in lib/noah-results-viewer.ps1.
/// </summary>
public class NoahResultsForm : ParratFormBase
{
    // ── OBX segment number -> field name mapping ─────────────────────────
    private static readonly Dictionary<int, string> OBXSegmentMap = new()
    {
        [0] = "ClinicalHistory",
        [1] = "TextDiagnosis",
        [2] = "FinalDiagnosis",
        [3] = "GrossPathology",
        [4] = "MicroPathology",
        [5] = "Comment",
        [6] = "NatureOfSpecimen",
        [7] = "Supplemental",
        [8] = "Addendum"
    };

    // ── Entity type colors ───────────────────────────────────────────────
    private static readonly Color ColorNegated = Color.LightBlue;
    private static readonly Color ColorType0 = Color.FromArgb(255, 200, 200);  // Light red/pink (cancer)
    private static readonly Color ColorType1 = Color.FromArgb(255, 220, 180);  // Light orange (cytology)
    private static readonly Color ColorType2 = Color.FromArgb(220, 200, 255);  // Light purple (site)

    private readonly string? _resultFilePath;
    private readonly string? _workingFolder;
    private readonly string? _jsonContent;
    private readonly string? _fallbackObxText;
    private readonly string _recordLabel;
    private readonly int _recordIndex;
    private readonly int _recordCount;
    private readonly IParratLogger? _logger;

    public NoahResultsForm(
        string resultFilePath,
        string workingFolder,
        string recordLabel = "Record",
        int recordIndex = 0,
        int recordCount = 1,
        IParratLogger? logger = null)
    {
        _resultFilePath = resultFilePath;
        _workingFolder = workingFolder;
        _recordLabel = recordLabel;
        _recordIndex = recordIndex;
        _recordCount = recordCount;
        _logger = logger;

        InitializeLayout();
    }

    public static NoahResultsForm FromJson(
        string jsonContent,
        string recordLabel = "Record",
        int recordIndex = 0,
        int recordCount = 1,
        IParratLogger? logger = null,
        string? fallbackObxText = null)
    {
        return new NoahResultsForm(jsonContent, recordLabel, recordIndex, recordCount, logger, fallbackObxText);
    }

    private NoahResultsForm(
        string jsonContent,
        string recordLabel,
        int recordIndex,
        int recordCount,
        IParratLogger? logger,
        string? fallbackObxText)
    {
        _jsonContent = jsonContent;
        _fallbackObxText = fallbackObxText;
        _recordLabel = recordLabel;
        _recordIndex = recordIndex;
        _recordCount = recordCount;
        _logger = logger;

        InitializeLayout();
    }

    private void InitializeLayout()
    {
        Text = $"NOAH Reportability Results - {_recordLabel} {_recordIndex + 1} of {_recordCount}";
        Width = 1400;
        Height = 900;
        StartPosition = FormStartPosition.CenterScreen;

        JsonDocument resultDoc;
        try
        {
            if (_jsonContent != null)
            {
                resultDoc = JsonDocument.Parse(_jsonContent);
            }
            else if (_resultFilePath != null && File.Exists(_resultFilePath))
            {
                var json = File.ReadAllText(_resultFilePath);
                resultDoc = JsonDocument.Parse(json);
            }
            else
            {
                MessageBox.Show(
                    $"Result file not found:\n{_resultFilePath}",
                    "NOAH Results",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return;
            }
        }
        catch (Exception ex)
        {
            _logger?.LogError("Failed to parse NOAH result JSON", "NOAH", ex);
            MessageBox.Show(
                $"Failed to parse result JSON:\n{ex.Message}",
                "NOAH Results",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        var root = resultDoc.RootElement;

        // ── Main split container: left (summary) | right (OBX text) ──
        var splitMain = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical
        };

        Shown += (_, _) =>
        {
            try
            {
                splitMain.SplitterDistance = Math.Max(1, Math.Min(400, splitMain.Width - 204));
            }
            catch { }
        };

        // === LEFT PANEL: Summary ===
        var rtbSummary = new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            Font = new Font("Consolas", 10f),
            WordWrap = true
        };

        BuildSummaryContent(rtbSummary, root);
        splitMain.Panel1.Controls.Add(rtbSummary);

        // === RIGHT PANEL: OBX Text with highlighting ===
        var rtbText = new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            Font = new Font("Consolas", 10f),
            WordWrap = true,
            ScrollBars = RichTextBoxScrollBars.Both
        };

        BuildHighlightedOBXText(rtbText, root);
        splitMain.Panel2.Controls.Add(rtbText);

        // ── Bottom panel with buttons ────────────────────────────────
        var pnlButtons = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 50
        };

        var btnClose = new Button
        {
            Text = "Close",
            Width = 100,
            Location = new Point(10, 12)
        };
        btnClose.Click += (_, _) => Close();

        if (!string.IsNullOrEmpty(_workingFolder))
        {
            var btnOpenFolder = new Button
            {
                Text = "Open Working Folder",
                Width = 150,
                Location = new Point(10, 12)
            };
            btnOpenFolder.Click += (_, _) =>
            {
                if (Directory.Exists(_workingFolder))
                    System.Diagnostics.Process.Start("explorer.exe", $"\"{_workingFolder}\"");
            };
            btnClose.Location = new Point(170, 12);
            pnlButtons.Controls.Add(btnOpenFolder);
        }

        pnlButtons.Controls.Add(btnClose);

        Controls.Add(splitMain);
        Controls.Add(pnlButtons);

        resultDoc.Dispose();
    }

    // ── Summary content builder ──────────────────────────────────────────

    private void BuildSummaryContent(RichTextBox box, JsonElement root)
    {
        bool reportable = GetBool(root, "Reportable");
        string reportableText = reportable ? "REPORTABLE" : "NON-REPORTABLE";
        var reportableColor = reportable ? Color.DarkGreen : Color.DarkRed;

        SyntaxHighlightingHelper.AddSectionHeader(box, "CLASSIFICATION");
        AddColoredLine(box, reportableText, bold: true, foreColor: reportableColor);
        AddColoredLine(box, "");

        SyntaxHighlightingHelper.AddSectionHeader(box, "FLAGS");
        AddColoredLine(box, $"ImpossibleCombination: {GetBool(root, "ImpossibleCombination")}");
        AddColoredLine(box, $"MetastaticReport: {GetBool(root, "MetastaticReport")}");
        AddColoredLine(box, $"PAYAC: {GetBool(root, "PAYAC")}");
        AddColoredLine(box, "");

        SyntaxHighlightingHelper.AddSectionHeader(box, "DIAGNOSIS");
        AddColoredLine(box, $"DiagnosisDate: {GetString(root, "DiagnosisDate")}");
        AddColoredLine(box, $"MessageID: {GetString(root, "MessageID")}");
        AddColoredLine(box, "");

        // Coded Result
        if (TryGetProp(root, "CodedResult", out var codedResult) &&
            codedResult.ValueKind == JsonValueKind.Object)
        {
            SyntaxHighlightingHelper.AddSectionHeader(box, "CODED RESULT");
            AddColoredLine(box, $"Histology: {GetString(codedResult, "Histology")}", bold: true);
            AddColoredLine(box, $"Site: {GetString(codedResult, "Site")}", bold: true);
            AddColoredLine(box, $"Behavior: {GetString(codedResult, "Behavior")}", bold: true);
            AddColoredLine(box, $"Laterality: {GetString(codedResult, "Laterality")}");
            AddColoredLine(box, $"IsSkinCase: {GetBool(codedResult, "IsSkinCase")}");
            AddColoredLine(box, "");
        }

        // Entity count
        int entityCount = 0;
        if (TryGetProp(root, "Entities", out var entitiesElement) &&
            entitiesElement.ValueKind == JsonValueKind.Array)
            entityCount = entitiesElement.GetArrayLength();

        SyntaxHighlightingHelper.AddSectionHeader(box, "ENTITIES");
        AddColoredLine(box, $"Total entities found: {entityCount}");
        AddColoredLine(box, "");

        SyntaxHighlightingHelper.AddSectionHeader(box, "COLOR LEGEND");
        AddColoredLine(box, "Histology", backColor: ColorType0);
        AddColoredLine(box, "Behavior", backColor: ColorType1);
        AddColoredLine(box, "Site", backColor: ColorType2);
        AddColoredLine(box, "Negated", backColor: ColorNegated);
    }

    // ── Highlighted OBX text builder ─────────────────────────────────────

    private void BuildHighlightedOBXText(RichTextBox rtb, JsonElement root)
    {
        bool hasObxTexts = TryGetProp(root, "OBXTexts", out var obxTexts) &&
                           obxTexts.ValueKind == JsonValueKind.Object;

        bool obxTextsEmpty = !hasObxTexts || obxTexts.EnumerateObject()
            .All(p => p.Value.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(p.Value.GetString()));

        if (obxTextsEmpty && !string.IsNullOrWhiteSpace(_fallbackObxText))
        {
            // Build entities list for highlighting the fallback text
            var fallbackEntities = new List<JsonElement>();
            if (TryGetProp(root, "Entities", out var fbEntities) &&
                fbEntities.ValueKind == JsonValueKind.Array)
            {
                foreach (var e in fbEntities.EnumerateArray())
                    fallbackEntities.Add(e);
                fallbackEntities = fallbackEntities.OrderBy(e => GetInt(e, "Offset")).ToList();
            }

            SyntaxHighlightingHelper.AddSectionHeader(rtb, "Custom Payload Text");
            int startPos = rtb.TextLength;
            string displayText = _fallbackObxText.Replace("\r\n", "\n");

            rtb.SelectionStart = rtb.TextLength;
            rtb.SelectionFont = rtb.Font;
            rtb.SelectionColor = rtb.ForeColor;
            rtb.SelectionBackColor = rtb.BackColor;
            rtb.AppendText(displayText + "\n");

            ApplyEntityHighlighting(rtb, fallbackEntities, displayText, _fallbackObxText, startPos);
            rtb.SelectionStart = 0;
            rtb.SelectionLength = 0;
            return;
        }

        if (obxTextsEmpty)
        {
            SyntaxHighlightingHelper.AddSectionHeader(rtb, "RAW API RESPONSE");
            rtb.SelectionStart = rtb.TextLength;
            rtb.SelectionFont = rtb.Font;
            rtb.SelectionColor = Color.Gray;
            rtb.AppendText(_jsonContent ?? "(No response data)");
            return;
        }

        // Build entities lookup by OBX segment
        var entitiesBySegment = new Dictionary<int, List<JsonElement>>();
        if (TryGetProp(root, "Entities", out var entities) &&
            entities.ValueKind == JsonValueKind.Array)
        {
            foreach (var entity in entities.EnumerateArray())
            {
                int segNum = GetInt(entity, "OBXSegment");
                if (!entitiesBySegment.ContainsKey(segNum))
                    entitiesBySegment[segNum] = new List<JsonElement>();
                entitiesBySegment[segNum].Add(entity);
            }
        }

        // Process each OBX text field in order
        for (int segNum = 0; segNum <= 8; segNum++)
        {
            if (!OBXSegmentMap.TryGetValue(segNum, out var fieldName))
                continue;

            if (!TryGetProp(obxTexts, fieldName, out var textProp) ||
                textProp.ValueKind != JsonValueKind.String)
                continue;

            string textValue = textProp.GetString() ?? "";
            if (string.IsNullOrWhiteSpace(textValue))
                continue;

            // RichTextBox converts \r\n to \n internally
            string displayText = textValue.Replace("\r\n", "\n");

            SyntaxHighlightingHelper.AddSectionHeader(rtb, $"{fieldName} (Segment {segNum})");

            // Get entities for this segment, sorted by offset
            var segEntities = new List<JsonElement>();
            if (entitiesBySegment.TryGetValue(segNum, out var list))
            {
                segEntities = list.OrderBy(e => GetInt(e, "Offset")).ToList();
            }

            int startPos = rtb.TextLength;

            rtb.SelectionStart = rtb.TextLength;
            rtb.SelectionLength = 0;
            rtb.SelectionFont = rtb.Font;
            rtb.SelectionColor = rtb.ForeColor;
            rtb.SelectionBackColor = rtb.BackColor;
            rtb.AppendText(displayText + "\n");

            if (segEntities.Count > 0)
                ApplyEntityHighlighting(rtb, segEntities, displayText, textValue, startPos);

            AddColoredLine(rtb, "");
        }

        // Reset selection to start
        rtb.SelectionStart = 0;
        rtb.SelectionLength = 0;
    }

    // ── Entity highlighting ────────────────────────────────────────────

    private static void ApplyEntityHighlighting(
        RichTextBox rtb, List<JsonElement> entities, string displayText, string originalText, int startPos)
    {
        string rtbText = rtb.Text;
        int regionEnd = Math.Min(startPos + displayText.Length + 50, rtbText.Length);

        foreach (var entity in entities)
        {
            string entityPhrase = GetString(entity, "EntityPhrase");
            if (string.IsNullOrWhiteSpace(entityPhrase)) continue;

            int searchFrom = startPos;
            int foundAt = rtbText.IndexOf(entityPhrase, searchFrom,
                Math.Max(0, regionEnd - searchFrom), StringComparison.OrdinalIgnoreCase);

            if (foundAt < 0) continue;

            bool isNegated = GetBool(entity, "IsNegated");
            int entityType = GetInt(entity, "EntityType");
            Color backColor = isNegated ? ColorNegated : entityType switch
            {
                0 => ColorType0,
                1 => ColorType1,
                2 => ColorType2,
                _ => ColorType0
            };

            rtb.SelectionStart = foundAt;
            rtb.SelectionLength = entityPhrase.Length;
            rtb.SelectionBackColor = backColor;
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private static void AddColoredLine(
        RichTextBox box,
        string text,
        bool bold = false,
        Color foreColor = default,
        Color backColor = default)
    {
        box.SelectionStart = box.TextLength;
        box.SelectionLength = 0;

        box.SelectionFont = bold
            ? SyntaxHighlightingHelper.GetBoldFont(box.Font)
            : box.Font;

        box.SelectionColor = foreColor != default ? foreColor : box.ForeColor;
        box.SelectionBackColor = backColor != default ? backColor : box.BackColor;

        box.AppendText(text + "\r\n");
    }

    private static bool TryGetProp(JsonElement element, string propertyName, out JsonElement prop)
    {
        if (element.TryGetProperty(propertyName, out prop)) return true;
        if (element.ValueKind != JsonValueKind.Object) return false;
        foreach (var p in element.EnumerateObject())
        {
            if (p.Name.Equals(propertyName, StringComparison.OrdinalIgnoreCase))
            {
                prop = p.Value;
                return true;
            }
        }
        return false;
    }

    private static string GetString(JsonElement element, string propertyName)
    {
        if (TryGetProp(element, propertyName, out var prop))
        {
            return prop.ValueKind == JsonValueKind.String
                ? prop.GetString() ?? ""
                : prop.ToString();
        }
        return "";
    }

    private static bool GetBool(JsonElement element, string propertyName)
    {
        if (TryGetProp(element, propertyName, out var prop) &&
            prop.ValueKind is JsonValueKind.True or JsonValueKind.False)
            return prop.GetBoolean();
        return false;
    }

    private static int GetInt(JsonElement element, string propertyName)
    {
        if (TryGetProp(element, propertyName, out var prop))
        {
            if (prop.ValueKind == JsonValueKind.Number)
                return prop.GetInt32();
            if (prop.ValueKind == JsonValueKind.String && int.TryParse(prop.GetString(), out int v))
                return v;
        }
        return 0;
    }
}
