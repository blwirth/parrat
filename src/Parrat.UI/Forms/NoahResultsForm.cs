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
public class NoahResultsForm : Form
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

    private readonly string _resultFilePath;
    private readonly string _workingFolder;
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

    private void InitializeLayout()
    {
        Text = $"NOAH Reportability Results - {_recordLabel} {_recordIndex + 1} of {_recordCount}";
        Width = 1400;
        Height = 900;
        StartPosition = FormStartPosition.CenterScreen;

        if (!File.Exists(_resultFilePath))
        {
            MessageBox.Show(
                $"Result file not found:\n{_resultFilePath}",
                "NOAH Results",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        // Parse result JSON
        JsonDocument resultDoc;
        try
        {
            var json = File.ReadAllText(_resultFilePath);
            resultDoc = JsonDocument.Parse(json);
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
            Orientation = Orientation.Vertical,
            Panel1MinSize = 250,
            Panel2MinSize = 300,
            SplitterDistance = 400
        };

        Shown += (_, _) =>
        {
            if (splitMain.Width > 400)
                splitMain.SplitterDistance = 400;
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

        var btnOpenFolder = new Button
        {
            Text = "Open Working Folder",
            Width = 150,
            Location = new Point(10, 12)
        };
        btnOpenFolder.Click += (_, _) =>
        {
            if (Directory.Exists(_workingFolder))
            {
                System.Diagnostics.Process.Start("explorer.exe", $"\"{_workingFolder}\"");
            }
        };

        var btnClose = new Button
        {
            Text = "Close",
            Width = 100,
            Location = new Point(170, 12)
        };
        btnClose.Click += (_, _) => Close();

        pnlButtons.Controls.AddRange(new Control[] { btnOpenFolder, btnClose });

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

        AddColoredLine(box, "=== CLASSIFICATION ===", bold: true);
        AddColoredLine(box, "");
        AddColoredLine(box, reportableText, bold: true, foreColor: reportableColor);
        AddColoredLine(box, "");

        // Flags
        AddColoredLine(box, "=== FLAGS ===", bold: true);
        AddColoredLine(box, $"ImpossibleCombination: {GetBool(root, "ImpossibleCombination")}");
        AddColoredLine(box, $"MetastaticReport: {GetBool(root, "MetastaticReport")}");
        AddColoredLine(box, $"PAYAC: {GetBool(root, "PAYAC")}");
        AddColoredLine(box, "");

        // Diagnosis info
        AddColoredLine(box, "=== DIAGNOSIS ===", bold: true);
        AddColoredLine(box, $"DiagnosisDate: {GetString(root, "DiagnosisDate")}");
        AddColoredLine(box, $"MessageID: {GetString(root, "MessageID")}");
        AddColoredLine(box, "");

        // Coded Result
        if (root.TryGetProperty("CodedResult", out var codedResult) &&
            codedResult.ValueKind == JsonValueKind.Object)
        {
            AddColoredLine(box, "=== CODED RESULT ===", bold: true);
            AddColoredLine(box, $"Histology: {GetString(codedResult, "Histology")}", bold: true);
            AddColoredLine(box, $"Site: {GetString(codedResult, "Site")}", bold: true);
            AddColoredLine(box, $"Behavior: {GetString(codedResult, "Behavior")}", bold: true);
            AddColoredLine(box, $"Laterality: {GetString(codedResult, "Laterality")}");
            AddColoredLine(box, $"IsSkinCase: {GetBool(codedResult, "IsSkinCase")}");
            AddColoredLine(box, "");
        }

        // Entity summary
        int entityCount = 0;
        JsonElement entitiesElement = default;
        if (root.TryGetProperty("Entities", out entitiesElement) &&
            entitiesElement.ValueKind == JsonValueKind.Array)
        {
            entityCount = entitiesElement.GetArrayLength();
        }

        AddColoredLine(box, "=== ENTITIES ===", bold: true);
        AddColoredLine(box, $"Total entities found: {entityCount}");
        AddColoredLine(box, "");

        // Color legend
        AddColoredLine(box, "=== COLOR LEGEND ===", bold: true);
        AddColoredLine(box, "Cancer terms (Type 0)", backColor: ColorType0);
        AddColoredLine(box, "Cytology terms (Type 1)", backColor: ColorType1);
        AddColoredLine(box, "Site terms (Type 2)", backColor: ColorType2);
        AddColoredLine(box, "Negated (any type)", backColor: ColorNegated);
        AddColoredLine(box, "");

        // Entity details
        if (entityCount > 0)
        {
            AddColoredLine(box, "=== ENTITY DETAILS ===", bold: true);
            foreach (var entity in entitiesElement.EnumerateArray())
            {
                bool isNegated = GetBool(entity, "IsNegated");
                int entityType = GetInt(entity, "EntityType");
                string entityPhrase = GetString(entity, "EntityPhrase");
                string code = GetString(entity, "Code");

                string negatedMarker = isNegated ? " [NEGATED]" : "";
                string typeLabel = entityType switch
                {
                    0 => "Cancer",
                    1 => "Cytology",
                    2 => "Site",
                    _ => $"Type{entityType}"
                };

                string line = $"{typeLabel}: '{entityPhrase}' (Code: {code}){negatedMarker}";

                Color backColor;
                if (isNegated)
                    backColor = ColorNegated;
                else
                    backColor = entityType switch
                    {
                        0 => ColorType0,
                        1 => ColorType1,
                        2 => ColorType2,
                        _ => Color.Empty
                    };

                AddColoredLine(box, line, backColor: backColor);
            }
        }
    }

    // ── Highlighted OBX text builder ─────────────────────────────────────

    private void BuildHighlightedOBXText(RichTextBox rtb, JsonElement root)
    {
        if (!root.TryGetProperty("OBXTexts", out var obxTexts) ||
            obxTexts.ValueKind != JsonValueKind.Object)
        {
            rtb.Text = "(No OBXTexts in result)";
            return;
        }

        // Build entities lookup by OBX segment
        var entitiesBySegment = new Dictionary<int, List<JsonElement>>();
        if (root.TryGetProperty("Entities", out var entities) &&
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

            if (!obxTexts.TryGetProperty(fieldName, out var textProp) ||
                textProp.ValueKind != JsonValueKind.String)
                continue;

            string textValue = textProp.GetString() ?? "";
            if (string.IsNullOrWhiteSpace(textValue))
                continue;

            // RichTextBox converts \r\n to \n internally
            string displayText = textValue.Replace("\r\n", "\n");

            // Add section header
            AddColoredLine(rtb, $"=== {fieldName} (Segment {segNum}) ===", bold: true);

            // Get entities for this segment, sorted by offset
            var segEntities = new List<JsonElement>();
            if (entitiesBySegment.TryGetValue(segNum, out var list))
            {
                segEntities = list.OrderBy(e => GetInt(e, "Offset")).ToList();
            }

            if (segEntities.Count == 0)
            {
                // No entities - plain text
                rtb.SelectionStart = rtb.TextLength;
                rtb.SelectionLength = 0;
                rtb.SelectionFont = rtb.Font;
                rtb.SelectionColor = rtb.ForeColor;
                rtb.SelectionBackColor = rtb.BackColor;
                rtb.AppendText(displayText + "\n");
            }
            else
            {
                // Record position before adding text
                int startPos = rtb.TextLength;

                // Add entire text as plain
                rtb.SelectionStart = rtb.TextLength;
                rtb.SelectionLength = 0;
                rtb.SelectionFont = rtb.Font;
                rtb.SelectionColor = rtb.ForeColor;
                rtb.SelectionBackColor = rtb.BackColor;
                rtb.AppendText(displayText);

                // Apply highlighting to each entity
                foreach (var entity in segEntities)
                {
                    int offset = GetInt(entity, "Offset");
                    int length = GetInt(entity, "Length");
                    string entityPhrase = GetString(entity, "EntityPhrase");

                    // Convert offset from original text (\r\n) to display text (\n only)
                    string textBeforeOffset = offset > 0 && offset <= textValue.Length
                        ? textValue.Substring(0, offset) : "";
                    int crlfCount = System.Text.RegularExpressions.Regex.Matches(textBeforeOffset, "\r\n").Count;
                    int displayOffset = offset - crlfCount;

                    // Verify offset by checking entity phrase match
                    int actualOffset = displayOffset;
                    if (displayOffset >= 0 && displayOffset + length <= displayText.Length)
                    {
                        string textAtOffset = displayText.Substring(
                            displayOffset,
                            Math.Min(length, displayText.Length - displayOffset));
                        if (textAtOffset != entityPhrase && !string.IsNullOrWhiteSpace(entityPhrase))
                        {
                            int foundIndex = displayText.IndexOf(
                                entityPhrase, StringComparison.OrdinalIgnoreCase);
                            if (foundIndex >= 0)
                                actualOffset = foundIndex;
                        }
                    }
                    else
                    {
                        if (!string.IsNullOrWhiteSpace(entityPhrase))
                        {
                            int foundIndex = displayText.IndexOf(
                                entityPhrase, StringComparison.OrdinalIgnoreCase);
                            if (foundIndex >= 0)
                                actualOffset = foundIndex;
                            else
                                continue;
                        }
                        else
                        {
                            continue;
                        }
                    }

                    int highlightStart = startPos + actualOffset;
                    int highlightLength = length;

                    if (highlightStart < startPos) continue;
                    int textEndPos = startPos + displayText.Length;
                    if (highlightStart + highlightLength > textEndPos)
                        highlightLength = textEndPos - highlightStart;
                    if (highlightLength <= 0) continue;

                    // Determine color
                    bool isNegated = GetBool(entity, "IsNegated");
                    int entityType = GetInt(entity, "EntityType");
                    Color backColor;
                    if (isNegated)
                        backColor = ColorNegated;
                    else
                        backColor = entityType switch
                        {
                            0 => ColorType0,
                            1 => ColorType1,
                            2 => ColorType2,
                            _ => ColorType0
                        };

                    rtb.SelectionStart = highlightStart;
                    rtb.SelectionLength = highlightLength;
                    rtb.SelectionBackColor = backColor;
                }

                // Add trailing newline after highlighting
                rtb.AppendText("\n");
            }

            AddColoredLine(rtb, "");
        }

        // Reset selection to start
        rtb.SelectionStart = 0;
        rtb.SelectionLength = 0;
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

    private static string GetString(JsonElement element, string propertyName)
    {
        if (element.TryGetProperty(propertyName, out var prop))
        {
            return prop.ValueKind == JsonValueKind.String
                ? prop.GetString() ?? ""
                : prop.ToString();
        }
        return "";
    }

    private static bool GetBool(JsonElement element, string propertyName)
    {
        if (element.TryGetProperty(propertyName, out var prop) &&
            prop.ValueKind is JsonValueKind.True or JsonValueKind.False)
            return prop.GetBoolean();
        return false;
    }

    private static int GetInt(JsonElement element, string propertyName)
    {
        if (element.TryGetProperty(propertyName, out var prop))
        {
            if (prop.ValueKind == JsonValueKind.Number)
                return prop.GetInt32();
            if (prop.ValueKind == JsonValueKind.String && int.TryParse(prop.GetString(), out int v))
                return v;
        }
        return 0;
    }
}
