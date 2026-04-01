using System.Drawing;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace Parrat.UI.Controls;

/// <summary>
/// Provides syntax highlighting for XML (NAACCR) and HL7 content
/// displayed in RichTextBox controls.
/// Ported from lib/syntax-helpers.ps1.
/// </summary>
public static class SyntaxHighlightingHelper
{
    // ── Bold field IDs (NAACCR fields rendered in bold) ──────────────────

    public static readonly string[] BoldIds =
    {
        "nameFirst",
        "nameLast",
        "nameMiddle",
        "dateOfBirth",
        "dateOfDiagnosis",
        "primarySite",
        "laterality"
    };

    // ── Text field IDs (shown in the path/text panel) ────────────────────

    public static readonly string[] TextFieldIds =
    {
        "textDxProcPe",
        "textDxProcXRayScan",
        "textDxProcScopes",
        "textDxProcLabTests",
        "textDxProcOp",
        "textDxProcPath",
        "textPrimarySiteTitle",
        "textHistologyTitle",
        "textStaging",
        "rxTextSurgery",
        "rxTextRadiation",
        "rxTextRadiationOther",
        "rxTextChemo",
        "rxTextHormone",
        "rxTextBrm",
        "rxTextOther",
        "textRemarks",
        "textPlaceOfDiagnosis",
        "textUsualOccupation",
        "textUsualIndustry",
        "ehrReporting"
    };

    // ── Known HL7 segment names ──────────────────────────────────────────

    private static readonly string[] Hl7SegmentNames =
    {
        "MSH", "PID", "PV1", "PV2", "ORC", "OBR", "OBX", "NTE", "NK1",
        "IN1", "IN2", "GT1", "AL1", "DG1", "PR1", "ROL", "EVN", "MRG",
        "ZPD", "ZDS", "SPM", "TXA", "PD1", "DB1", "DRG", "FT1", "ACC"
    };

    // ── Colour constants ─────────────────────────────────────────────────

    private static readonly Color ColorNaaccrId = Color.Blue;
    private static readonly Color ColorValue = Color.FromArgb(0, 128, 128);       // Teal
    private static readonly Color ColorSegment = Color.Blue;
    private static readonly Color ColorSeparator = Color.FromArgb(128, 128, 128); // Gray
    private static readonly Color ColorMsh = Color.FromArgb(128, 0, 128);         // Purple
    private static readonly Color ColorPid = Color.FromArgb(0, 128, 0);           // Green
    private static readonly Color ColorObxId = Color.FromArgb(0, 128, 128);       // Teal

    // ── Cached bold font ─────────────────────────────────────────────────

    private static Font? _cachedBoldFont;
    private static string? _cachedBoldFontKey;

    /// <summary>
    /// Returns a bold version of the given base font, caching the result.
    /// </summary>
    public static Font GetBoldFont(Font baseFont)
    {
        var key = $"{baseFont.FontFamily.Name}|{baseFont.Size}";
        if (_cachedBoldFont != null && _cachedBoldFontKey == key)
            return _cachedBoldFont;

        _cachedBoldFont = new Font(baseFont.FontFamily, baseFont.Size, FontStyle.Bold);
        _cachedBoldFontKey = key;
        return _cachedBoldFont;
    }

    // ── RichTextBox line appender ────────────────────────────────────────

    /// <summary>
    /// Appends a line of text to a RichTextBox, optionally in bold.
    /// </summary>
    public static void AddLineToRichTextBox(RichTextBox box, string text, bool bold = false)
    {
        box.SelectionStart = box.TextLength;
        box.SelectionLength = 0;
        box.SelectionFont = bold ? GetBoldFont(box.Font) : box.Font;
        box.AppendText(text + "\r\n");
    }

    /// <summary>
    /// Adds a bold section header followed by a light gray separator line.
    /// </summary>
    public static void AddSectionHeader(RichTextBox box, string text)
    {
        box.SelectionStart = box.TextLength;
        box.SelectionLength = 0;
        box.SelectionFont = GetBoldFont(box.Font);
        box.AppendText(text + "\r\n");

        // Light gray thin separator
        box.SelectionStart = box.TextLength;
        box.SelectionLength = 0;
        box.SelectionFont = new Font(box.Font.FontFamily, 4f);
        box.SelectionColor = Color.DarkGray;
        box.AppendText(new string('\u2500', 40) + "\r\n");
        box.SelectionColor = box.ForeColor;
    }

    // ── XML syntax highlighting (full document view) ─────────────────────

    /// <summary>
    /// Applies syntax highlighting to formatted XML in a RichTextBox.
    /// Colors naaccrId attribute values blue and element text content teal.
    /// </summary>
    public static void SetXmlSyntaxHighlighting(RichTextBox richTextBox, string xmlText)
    {
        richTextBox.Text = xmlText;
        richTextBox.SelectAll();
        richTextBox.SelectionColor = Color.Black;
        richTextBox.SelectionFont = richTextBox.Font;

        var rtbText = richTextBox.Text;

        // Highlight naaccrId attribute values in blue
        const string prefix = "naaccrId=\"";
        int prefixLen = prefix.Length;
        int startIndex = 0;

        while (true)
        {
            int pos = rtbText.IndexOf(prefix, startIndex, StringComparison.Ordinal);
            if (pos < 0) break;

            int valueStart = pos + prefixLen;
            int valueEnd = rtbText.IndexOf('"', valueStart);
            if (valueEnd < 0) break;

            int valueLen = valueEnd - valueStart;
            if (valueLen > 0)
            {
                richTextBox.Select(valueStart, valueLen);
                richTextBox.SelectionColor = ColorNaaccrId;
            }

            startIndex = valueEnd + 1;
        }

        // Highlight element text content (between "> and </Item>) in teal
        const string closingTag = "</Item>";
        startIndex = 0;

        while (true)
        {
            int closePos = rtbText.IndexOf(closingTag, startIndex, StringComparison.Ordinal);
            if (closePos < 0) break;

            int searchStart = Math.Max(0, closePos - 500);
            var segment = rtbText.Substring(searchStart, closePos - searchStart);
            int openPos = segment.LastIndexOf("\">");

            if (openPos >= 0)
            {
                int valueStart = searchStart + openPos + 2; // +2 for ">
                int valueLen = closePos - valueStart;
                if (valueLen > 0)
                {
                    richTextBox.Select(valueStart, valueLen);
                    richTextBox.SelectionColor = ColorValue;
                }
            }

            startIndex = closePos + closingTag.Length;
        }

        richTextBox.Select(0, 0);
        richTextBox.ScrollToCaret();
    }

    // ── XML panel highlighting (naaccrId: value format) ──────────────────

    /// <summary>
    /// Highlights naaccrId names in the items panel (lines formatted as "naaccrId: value").
    /// </summary>
    public static void SetXmlPanelHighlighting(RichTextBox richTextBox)
    {
        var rtbText = richTextBox.Text;

        // Match lines of the form "naaccrId: value"
        var pattern = @"(?m)^([A-Za-z][A-Za-z0-9]*): ";
        var matches = Regex.Matches(rtbText, pattern);

        foreach (Match match in matches)
        {
            var idGroup = match.Groups[1];
            richTextBox.Select(idGroup.Index, idGroup.Length);
            richTextBox.SelectionColor = ColorNaaccrId;
        }

        richTextBox.Select(0, 0);
        richTextBox.ScrollToCaret();
    }

    // ── HL7 full syntax highlighting (raw HL7 view) ──────────────────────

    /// <summary>
    /// Applies full syntax highlighting to raw HL7 content in a RichTextBox.
    /// Colors segment names, PID-5, OBX-3.1, OBX-5.1, and separators.
    /// </summary>
    public static void SetHl7SyntaxHighlighting(RichTextBox richTextBox, string hl7Text)
    {
        richTextBox.Text = hl7Text;
        richTextBox.SelectAll();
        richTextBox.SelectionColor = Color.Black;
        richTextBox.SelectionFont = richTextBox.Font;

        // Re-read from RTB (normalizes line endings)
        hl7Text = richTextBox.Text;

        // Highlight segment names
        foreach (var segName in Hl7SegmentNames)
        {
            var pattern = $"(?m)^{segName}(?=\\|)";
            var matches = Regex.Matches(hl7Text, pattern);
            foreach (Match match in matches)
            {
                richTextBox.Select(match.Index, match.Length);
                richTextBox.SelectionColor = segName switch
                {
                    "MSH" => ColorMsh,
                    "PID" => ColorPid,
                    _ => ColorSegment
                };
                richTextBox.SelectionFont = GetBoldFont(richTextBox.Font);
            }
        }

        // Highlight PID-5 (Patient Name) - bold the entire field
        HighlightPidField5(richTextBox, hl7Text, 0);

        // Highlight OBX-3.1 and OBX-5.1
        HighlightObxFields(richTextBox, hl7Text, 0, boldObx5Component1Only: true);

        // Highlight all HL7 separators (|, ^, &, ~)
        var sepMatches = Regex.Matches(hl7Text, @"[\|\^&~]");
        foreach (Match match in sepMatches)
        {
            richTextBox.Select(match.Index, match.Length);
            richTextBox.SelectionColor = ColorSeparator;
        }

        richTextBox.Select(0, 0);
        richTextBox.ScrollToCaret();
    }

    // ── HL7 panel highlighting (partial, with offset) ────────────────────

    /// <summary>
    /// Applies HL7 syntax highlighting starting from a given offset in the RichTextBox.
    /// Used for the items panel where raw segments appear after metadata.
    /// </summary>
    public static void SetHl7PanelHighlighting(RichTextBox richTextBox, int startOffset = 0)
    {
        var rtbText = richTextBox.Text;
        if (startOffset >= rtbText.Length) return;

        var textToProcess = rtbText.Substring(startOffset);

        // Highlight segment names
        foreach (var segName in Hl7SegmentNames)
        {
            var pattern = $"(?m)^{segName}(?=\\|)";
            var matches = Regex.Matches(textToProcess, pattern);
            foreach (Match match in matches)
            {
                richTextBox.Select(startOffset + match.Index, match.Length);
                richTextBox.SelectionColor = segName switch
                {
                    "MSH" => ColorMsh,
                    "PID" => ColorPid,
                    _ => ColorSegment
                };
                richTextBox.SelectionFont = GetBoldFont(richTextBox.Font);
            }
        }

        // Highlight PID-5
        HighlightPidField5(richTextBox, textToProcess, startOffset);

        // Highlight OBX-3.1 and bold full OBX-5
        HighlightObxFields(richTextBox, textToProcess, startOffset, boldObx5Component1Only: false);

        // Highlight separators (| and ^)
        foreach (Match match in Regex.Matches(textToProcess, @"[\|\^]"))
        {
            richTextBox.Select(startOffset + match.Index, match.Length);
            richTextBox.SelectionColor = ColorSeparator;
        }

        richTextBox.Select(0, 0);
    }

    // ── Search text highlighting ─────────────────────────────────────────

    /// <summary>
    /// Highlights all occurrences of search text with a yellow background.
    /// </summary>
    public static void InvokeSearchHighlight(RichTextBox richTextBox, string? searchText)
    {
        if (richTextBox == null || richTextBox.TextLength == 0) return;

        // Clear previous highlights
        richTextBox.SelectAll();
        richTextBox.SelectionBackColor = richTextBox.BackColor;
        richTextBox.SelectionStart = 0;
        richTextBox.SelectionLength = 0;

        if (string.IsNullOrWhiteSpace(searchText)) return;

        var text = richTextBox.Text;
        var lower = text.ToLowerInvariant();
        var needle = searchText.ToLowerInvariant();
        int needleLen = needle.Length;
        int pos = 0;

        while (true)
        {
            pos = lower.IndexOf(needle, pos, StringComparison.Ordinal);
            if (pos < 0) break;

            richTextBox.Select(pos, needleLen);
            richTextBox.SelectionBackColor = Color.Yellow;
            pos += needleLen;
        }

        richTextBox.SelectionStart = 0;
        richTextBox.SelectionLength = 0;
    }

    // ── Private helpers ──────────────────────────────────────────────────

    /// <summary>
    /// Highlights PID-5 (Patient Name) field in bold.
    /// </summary>
    private static void HighlightPidField5(RichTextBox richTextBox, string text, int offset)
    {
        var pidMatches = Regex.Matches(text, @"(?m)^PID\|");
        foreach (Match pidMatch in pidMatches)
        {
            int lineEnd = text.IndexOf('\n', pidMatch.Index);
            if (lineEnd < 0) lineEnd = text.Length;
            var pidLine = text.Substring(pidMatch.Index, lineEnd - pidMatch.Index);

            var fields = pidLine.Split('|');
            if (fields.Length > 5)
            {
                int fieldStart = pidMatch.Index;
                for (int i = 0; i < 5; i++)
                    fieldStart += fields[i].Length + 1; // +1 for |

                int field5Length = fields[5].Length;
                if (field5Length > 0)
                {
                    richTextBox.Select(offset + fieldStart, field5Length);
                    richTextBox.SelectionFont = GetBoldFont(richTextBox.Font);
                }
            }
        }
    }

    /// <summary>
    /// Highlights OBX-3.1 in teal+bold and OBX-5 / OBX-5.1 in bold.
    /// </summary>
    private static void HighlightObxFields(
        RichTextBox richTextBox, string text, int offset,
        bool boldObx5Component1Only)
    {
        var obxMatches = Regex.Matches(text, @"(?m)^OBX\|");
        foreach (Match obxMatch in obxMatches)
        {
            int lineEnd = text.IndexOf('\n', obxMatch.Index);
            if (lineEnd < 0) lineEnd = text.Length;
            var obxLine = text.Substring(obxMatch.Index, lineEnd - obxMatch.Index);

            var fields = obxLine.Split('|');

            // OBX-3.1 (first component of field 3)
            if (fields.Length > 3 && fields[3].Length > 0)
            {
                int fieldStart = obxMatch.Index;
                for (int i = 0; i < 3; i++)
                    fieldStart += fields[i].Length + 1;

                var components = fields[3].Split('^');
                int comp1Length = components[0].Length;
                if (comp1Length > 0)
                {
                    richTextBox.Select(offset + fieldStart, comp1Length);
                    richTextBox.SelectionColor = ColorObxId;
                    richTextBox.SelectionFont = GetBoldFont(richTextBox.Font);
                }
            }

            // OBX-5 or OBX-5.1
            if (fields.Length > 5 && fields[5].Length > 0)
            {
                int fieldStart = obxMatch.Index;
                for (int i = 0; i < 5; i++)
                    fieldStart += fields[i].Length + 1;

                if (boldObx5Component1Only)
                {
                    var components = fields[5].Split('^');
                    int comp1Length = components[0].Length;
                    if (comp1Length > 0)
                    {
                        richTextBox.Select(offset + fieldStart, comp1Length);
                        richTextBox.SelectionFont = GetBoldFont(richTextBox.Font);
                    }
                }
                else
                {
                    int fullLength = fields[5].Length;
                    if (fullLength > 0)
                    {
                        richTextBox.Select(offset + fieldStart, fullLength);
                        richTextBox.SelectionFont = GetBoldFont(richTextBox.Font);
                    }
                }
            }
        }
    }
}
