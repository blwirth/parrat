using System.Drawing;
using System.Windows.Forms;
using Parat.Core.Models;
using Parat.UI.Controls;

namespace Parat.UI.Forms;

/// <summary>
/// Testing dialog for site/laterality coding rules.
/// Combines Show-TestSiteLateralityDialog (text input) and
/// Show-TestSiteLateralityResults (results display with highlighting)
/// from ui/test-site-laterality-ui.ps1.
/// </summary>
public class TestSiteLateralityForm : Form
{
    // ── TextInput mode controls ──────────────────────────────────────────
    private Label? _lblPrompt;
    private TextBox? _txtInput;
    private Button? _btnTest;
    private Button? _btnCancel;

    // ── Results mode fields ──────────────────────────────────────────────
    private readonly SiteLateralityTestResult? _result;
    private readonly string? _sourceText;
    private readonly string[]? _obxSegments;
    private readonly string[]? _skipCodes;

    /// <summary>The text the user entered (TextInput mode).</summary>
    public string? InputText { get; private set; }

    /// <summary>
    /// Initializes a text-input dialog for testing site/laterality heuristics.
    /// </summary>
    public TestSiteLateralityForm()
    {
        InitializeTextInputLayout();
    }

    /// <summary>
    /// Initializes a results dialog showing site/laterality test output.
    /// </summary>
    public TestSiteLateralityForm(
        SiteLateralityTestResult result,
        string? sourceText = null,
        string[]? obxSegments = null,
        string[]? skipCodes = null)
    {
        _result = result;
        _sourceText = sourceText;
        _obxSegments = obxSegments;
        _skipCodes = skipCodes;
        InitializeResultsLayout();
    }

    // =====================================================================
    //  TEXT INPUT MODE
    // =====================================================================

    private void InitializeTextInputLayout()
    {
        Text = "Test Site/Laterality Heuristics";
        Width = 600;
        Height = 400;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimumSize = new Size(400, 300);

        _lblPrompt = new Label
        {
            Location = new Point(10, 10),
            Size = new Size(560, 20),
            Text = "Enter pathology text to test:",
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };

        _txtInput = new TextBox
        {
            Location = new Point(10, 35),
            Size = new Size(560, 270),
            Multiline = true,
            ScrollBars = ScrollBars.Both,
            WordWrap = true,
            Font = new Font("Consolas", 10f),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
        };

        _btnTest = new Button
        {
            Text = "Test Heuristics",
            Width = 120,
            Location = new Point(340, 320),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.OK
        };

        _btnCancel = new Button
        {
            Text = "Cancel",
            Width = 100,
            Location = new Point(470, 320),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.Cancel
        };

        Controls.AddRange(new Control[] { _lblPrompt, _txtInput, _btnTest, _btnCancel });
        AcceptButton = _btnTest;
        CancelButton = _btnCancel;

        _btnTest.Click += (_, _) =>
        {
            var text = _txtInput!.Text.Trim();
            InputText = string.IsNullOrWhiteSpace(text) ? null : text;
        };
    }

    // =====================================================================
    //  RESULTS MODE
    // =====================================================================

    private void InitializeResultsLayout()
    {
        if (_result == null) return;

        bool hasObxSegments = _obxSegments is { Length: > 0 };
        bool hasSourceText = hasObxSegments || !string.IsNullOrWhiteSpace(_sourceText);

        Text = "Site/Laterality Test Results";
        Width = 800;
        Height = hasSourceText ? 900 : 350;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimumSize = new Size(900, 350);

        var mainPanel = new Panel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(10)
        };

        RichTextBox rtbResults;
        RichTextBox? rtbSourceText = null;
        SplitContainer? splitContainer = null;

        if (hasSourceText)
        {
            splitContainer = new SplitContainer
            {
                Dock = DockStyle.Fill,
                Orientation = Orientation.Horizontal,
                Panel1MinSize = 100,
                Panel2MinSize = 100
            };

            rtbResults = new RichTextBox
            {
                Dock = DockStyle.Fill,
                ReadOnly = true,
                Font = new Font("Consolas", 10f),
                BackColor = Color.White
            };

            var lblSourceText = new Label
            {
                Text = hasObxSegments
                    ? "OBX SEGMENTS (skipped in gray, matched phrases highlighted)"
                    : "SOURCE TEXT (matched phrases highlighted)",
                Dock = DockStyle.Top,
                Height = 20,
                Font = new Font("Segoe UI", 9f, FontStyle.Bold)
            };

            rtbSourceText = new RichTextBox
            {
                Dock = DockStyle.Fill,
                ReadOnly = true,
                Font = new Font("Consolas", 9f),
                BackColor = Color.White,
                WordWrap = true
            };

            splitContainer.Panel1.Controls.Add(rtbResults);
            splitContainer.Panel2.Controls.Add(rtbSourceText);
            splitContainer.Panel2.Controls.Add(lblSourceText);

            mainPanel.Controls.Add(splitContainer);
        }
        else
        {
            rtbResults = new RichTextBox
            {
                Dock = DockStyle.Fill,
                ReadOnly = true,
                Font = new Font("Consolas", 10f),
                BackColor = Color.White
            };

            mainPanel.Controls.Add(rtbResults);
        }

        // Build results text
        BuildResultsContent(rtbResults);

        // Populate source text with highlighting
        if (hasSourceText && rtbSourceText != null)
        {
            if (hasObxSegments)
                BuildHl7SourceContent(rtbSourceText);
            else
                BuildXmlSourceContent(rtbSourceText);
        }

        // ── Bottom panel ─────────────────────────────────────────────
        var bottomPanel = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 45
        };

        var lblLegendLabel = new Label
        {
            Text = "Legend:",
            Location = new Point(10, 14),
            AutoSize = true,
            Font = new Font("Segoe UI", 9f)
        };

        var pnlSiteColor = new Panel
        {
            Location = new Point(70, 14),
            Size = new Size(14, 14),
            BackColor = Color.LightGreen,
            BorderStyle = BorderStyle.FixedSingle
        };

        var lblSiteText = new Label
        {
            Text = "Site",
            Location = new Point(88, 14),
            AutoSize = true,
            Font = new Font("Segoe UI", 9f)
        };

        var pnlLatColor = new Panel
        {
            Location = new Point(125, 14),
            Size = new Size(14, 14),
            BackColor = Color.LightSkyBlue,
            BorderStyle = BorderStyle.FixedSingle
        };

        var lblLatText = new Label
        {
            Text = "Laterality",
            Location = new Point(143, 14),
            AutoSize = true,
            Font = new Font("Segoe UI", 9f)
        };

        var btnOk = new Button
        {
            Text = "OK",
            Width = 100,
            Location = new Point(570, 8),
            Anchor = AnchorStyles.Right | AnchorStyles.Bottom,
            DialogResult = DialogResult.OK
        };

        var btnCopy = new Button
        {
            Text = "Copy Results",
            Width = 100,
            Location = new Point(678, 8),
            Anchor = AnchorStyles.Right | AnchorStyles.Bottom
        };
        btnCopy.Click += (_, _) =>
        {
            if (!string.IsNullOrEmpty(rtbResults.Text))
                Clipboard.SetText(rtbResults.Text);
        };

        if (hasSourceText)
        {
            if (hasObxSegments)
            {
                // HL7 mode: include Skipped legend
                var pnlSkippedColor = new Panel
                {
                    Location = new Point(210, 14),
                    Size = new Size(14, 14),
                    BackColor = Color.Gray,
                    BorderStyle = BorderStyle.FixedSingle
                };
                var lblSkippedText = new Label
                {
                    Text = "Skipped",
                    Location = new Point(228, 14),
                    AutoSize = true,
                    Font = new Font("Segoe UI", 9f)
                };

                bottomPanel.Controls.AddRange(new Control[]
                {
                    lblLegendLabel, pnlSiteColor, lblSiteText,
                    pnlLatColor, lblLatText,
                    pnlSkippedColor, lblSkippedText,
                    btnOk, btnCopy
                });
            }
            else
            {
                bottomPanel.Controls.AddRange(new Control[]
                {
                    lblLegendLabel, pnlSiteColor, lblSiteText,
                    pnlLatColor, lblLatText,
                    btnOk, btnCopy
                });
            }
        }
        else
        {
            bottomPanel.Controls.AddRange(new Control[] { btnOk, btnCopy });
        }

        Controls.Add(mainPanel);
        Controls.Add(bottomPanel);
        AcceptButton = btnOk;

        // Set splitter distance after form is shown
        if (hasSourceText && splitContainer != null)
        {
            var sc = splitContainer;
            Shown += (_, _) =>
            {
                sc.SplitterDistance = sc.Height / 3;
            };
        }
    }

    // ── Results content builder ──────────────────────────────────────────

    private void BuildResultsContent(RichTextBox rtb)
    {
        if (_result == null) return;

        // Source info
        if (!string.IsNullOrEmpty(_result.SourceInfo))
        {
            rtb.SelectionFont = SyntaxHighlightingHelper.GetBoldFont(rtb.Font);
            rtb.AppendText("SOURCE\r\n");
            rtb.SelectionFont = rtb.Font;
            rtb.AppendText($"  Record:       {_result.SourceInfo}\r\n");
            rtb.AppendText("\r\n");
        }

        rtb.SelectionFont = SyntaxHighlightingHelper.GetBoldFont(rtb.Font);
        rtb.AppendText("PRIMARY SITE\r\n");
        rtb.SelectionFont = rtb.Font;

        if (!string.IsNullOrEmpty(_result.SiteCode))
        {
            rtb.AppendText($"  Code:         {_result.SiteCode}\r\n");

            string matchTypeDesc = _result.MatchType switch
            {
                "site-coding-rule" => "Site coding rule",
                "melanoma-dict" => "Melanoma dictionary",
                "standard-dict" => "Standard dictionary",
                _ => _result.MatchType ?? ""
            };
            rtb.AppendText($"  Match Type:   {matchTypeDesc}\r\n");

            if (_result.PatternPriority.HasValue)
                rtb.AppendText($"  Priority:     {_result.PatternPriority}\r\n");

            rtb.AppendText($"  Matched:      \"{_result.MatchedPhrase}\"\r\n");
        }
        else
        {
            rtb.AppendText("  (No match found)\r\n");
        }

        rtb.AppendText("\r\n");
        rtb.SelectionFont = SyntaxHighlightingHelper.GetBoldFont(rtb.Font);
        rtb.AppendText("LATERALITY\r\n");
        rtb.SelectionFont = rtb.Font;

        if (!string.IsNullOrEmpty(_result.LateralityCode))
        {
            rtb.AppendText($"  Code:         {_result.LateralityCode}\r\n");
            rtb.AppendText($"  Description:  {_result.LateralityDescription}\r\n");
            string requiresLat = _result.SiteRequiresLaterality ? "Yes" : "No";
            rtb.AppendText($"  Site requires laterality: {requiresLat}\r\n");
        }
        else
        {
            rtb.AppendText("  (No site to determine laterality)\r\n");
        }
    }

    // ── HL7 source content with highlighting ─────────────────────────────

    private void BuildHl7SourceContent(RichTextBox rtb)
    {
        if (_result == null || _obxSegments == null) return;

        var skipCodesUpper = (_skipCodes ?? Array.Empty<string>())
            .Select(c => c.ToUpperInvariant())
            .ToHashSet();

        foreach (var obx in _obxSegments)
        {
            var fields = obx.Split('|');
            string obx3 = fields.Length > 3 ? fields[3] : "";
            string obx5 = fields.Length > 5 ? fields[5] : "";

            // Get OBX-3.1 (first component before ^)
            string obx3Code = obx3.Split('^')[0].Trim().ToUpperInvariant();
            bool isSkipped = skipCodesUpper.Contains(obx3Code);

            // Build identifier line (truncate if too long)
            string identifierLine = $"OBX|{(fields.Length > 1 ? fields[1] : "")}|{(fields.Length > 2 ? fields[2] : "")}|{obx3}";
            if (identifierLine.Length > 80)
                identifierLine = identifierLine.Substring(0, 77) + "...";

            // Process OBX-5 text (handle HL7 escape sequences)
            string textContent = obx5;
            textContent = textContent.Replace("\\X0D\\", "\r");
            textContent = textContent.Replace("\\X0A\\", "\n");
            textContent = textContent.Replace("\\E\\", "\\");
            textContent = textContent.Replace("\\F\\", "|");
            textContent = textContent.Replace("\\S\\", "^");
            textContent = textContent.Replace("\\T\\", "&");
            textContent = textContent.Replace("\\R\\", "~");

            // Normalize line endings
            textContent = textContent.Replace("\r\n", "\n").Replace("\r", "\n");

            if (isSkipped)
            {
                rtb.SelectionColor = Color.Gray;
                rtb.AppendText($"{identifierLine} [SKIPPED]\n");
                if (!string.IsNullOrWhiteSpace(textContent))
                    rtb.AppendText($"{textContent}\n");
                rtb.AppendText("\n");
                rtb.SelectionColor = Color.Black;
            }
            else
            {
                rtb.SelectionFont = SyntaxHighlightingHelper.GetBoldFont(rtb.Font);
                rtb.SelectionColor = Color.DarkBlue;
                rtb.AppendText($"{identifierLine}\n");
                rtb.SelectionFont = rtb.Font;
                rtb.SelectionColor = Color.Black;

                if (!string.IsNullOrWhiteSpace(textContent))
                    rtb.AppendText($"{textContent}\n");
                rtb.AppendText("\n");
            }
        }

        // Apply highlighting
        ApplyMatchHighlighting(rtb);
    }

    // ── XML source content with highlighting ─────────────────────────────

    private void BuildXmlSourceContent(RichTextBox rtb)
    {
        if (_result == null || string.IsNullOrWhiteSpace(_sourceText)) return;

        // Normalize line endings
        string normalizedText = _sourceText.Replace("\r\n", "\n").Replace("\r", "\n");
        rtb.Text = normalizedText;

        // Bold XML item headers
        string[] xmlHeaders = { "textDxProcPath:", "textDxProcPe:", "textDxProcLabTests:" };
        foreach (var header in xmlHeaders)
            BoldAllOccurrences(rtb, header);

        // Apply highlighting
        ApplyMatchHighlighting(rtb);
    }

    // ── Shared highlighting helpers ──────────────────────────────────────

    private void ApplyMatchHighlighting(RichTextBox rtb)
    {
        if (_result == null) return;

        // Highlight matched site phrase in green
        if (!string.IsNullOrEmpty(_result.MatchedPhrase) &&
            _result.MatchedPhrase != "melanoma (fallback)" &&
            _result.MatchedPhrase != "biomarker combination (EGFR/PD-L1/ALK)")
        {
            HighlightAllOccurrences(rtb, _result.MatchedPhrase,
                Color.LightGreen, Color.Black);
        }

        // Highlight laterality keywords in blue
        if (_result.SiteRequiresLaterality)
        {
            HighlightAllOccurrences(rtb, "left", Color.LightSkyBlue, Color.Black, wholeWord: true);
            HighlightAllOccurrences(rtb, "right", Color.LightSkyBlue, Color.Black, wholeWord: true);
        }
    }

    private static void HighlightAllOccurrences(
        RichTextBox rtb, string searchText, Color backColor, Color foreColor, bool wholeWord = false)
    {
        if (string.IsNullOrEmpty(searchText)) return;

        string text = rtb.Text;
        string searchLower = searchText.ToLowerInvariant();
        string textLower = text.ToLowerInvariant();

        int startIndex = 0;
        while (true)
        {
            int foundIndex = textLower.IndexOf(searchLower, startIndex, StringComparison.Ordinal);
            if (foundIndex < 0) break;

            bool isWholeWord = true;
            if (wholeWord)
            {
                if (foundIndex > 0 && char.IsLetterOrDigit(text[foundIndex - 1]))
                    isWholeWord = false;
                int endPos = foundIndex + searchText.Length;
                if (endPos < text.Length && char.IsLetterOrDigit(text[endPos]))
                    isWholeWord = false;
            }

            if (isWholeWord)
            {
                rtb.SelectionStart = foundIndex;
                rtb.SelectionLength = searchText.Length;
                rtb.SelectionBackColor = backColor;
                rtb.SelectionColor = foreColor;
            }

            startIndex = foundIndex + 1;
        }

        rtb.SelectionStart = 0;
        rtb.SelectionLength = 0;
    }

    private static void BoldAllOccurrences(RichTextBox rtb, string searchText)
    {
        if (string.IsNullOrEmpty(searchText)) return;

        string textLower = rtb.Text.ToLowerInvariant();
        string searchLower = searchText.ToLowerInvariant();
        var boldFont = SyntaxHighlightingHelper.GetBoldFont(rtb.Font);

        int startIndex = 0;
        while (true)
        {
            int foundIndex = textLower.IndexOf(searchLower, startIndex, StringComparison.Ordinal);
            if (foundIndex < 0) break;

            rtb.SelectionStart = foundIndex;
            rtb.SelectionLength = searchText.Length;
            rtb.SelectionFont = boldFont;

            startIndex = foundIndex + 1;
        }

        rtb.SelectionStart = 0;
        rtb.SelectionLength = 0;
    }
}

/// <summary>
/// Result model for site/laterality test output.
/// Used to pass results from the service layer to the form.
/// </summary>
public class SiteLateralityTestResult
{
    public string? SourceInfo { get; set; }
    public string? SiteCode { get; set; }
    public string? MatchType { get; set; }
    public int? PatternPriority { get; set; }
    public string? MatchedPhrase { get; set; }
    public string? LateralityCode { get; set; }
    public string? LateralityDescription { get; set; }
    public bool SiteRequiresLaterality { get; set; }
}
