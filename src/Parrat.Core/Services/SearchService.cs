using System.Data;
using System.Text;
using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class SearchService : ISearchService
{
    private readonly IParratLogger _logger;
    private readonly XmlNodeList? _tumors;
    private readonly XmlNamespaceManager? _nsMgr;
    private readonly List<Hl7Message>? _hl7Messages;

    public SearchService() : this(NullParratLogger.Instance) { }

    public SearchService(IParratLogger logger)
    {
        _logger = logger;
    }

    public SearchService(XmlNodeList? tumors, XmlNamespaceManager? nsMgr, List<Hl7Message>? hl7Messages = null)
        : this(NullParratLogger.Instance, tumors, nsMgr, hl7Messages) { }

    public SearchService(IParratLogger logger, XmlNodeList? tumors, XmlNamespaceManager? nsMgr, List<Hl7Message>? hl7Messages = null)
    {
        _logger = logger;
        _tumors = tumors;
        _nsMgr = nsMgr;
        _hl7Messages = hl7Messages;
    }

    /// <summary>
    /// Appends a range of text in lower case, separating entries with a space
    /// so joined values do not run together. Empty ranges append nothing,
    /// matching the old behaviour of skipping blank parts before joining.
    /// </summary>
    private static void AppendLower(StringBuilder buffer, string? text, int start, int length)
    {
        if (string.IsNullOrEmpty(text) || length <= 0)
            return;

        if (buffer.Length > 0)
            buffer.Append(' ');

        for (int i = start; i < start + length; i++)
            buffer.Append(char.ToLower(text[i]));
    }

    public string[] BuildSearchIndex(string fileType)
    {
        try
        {
            if (fileType == "xml")
            {
                if (_tumors == null || _tumors.Count == 0 || _nsMgr == null)
                    return Array.Empty<string>();

                var index = new string[_tumors.Count];

                // Child elements are walked directly rather than via XPath: at
                // thousands of tumors, compiling "./n:Item" per record costs far
                // more than the walk itself.
                var parts = new List<string>();

                for (int i = 0; i < _tumors.Count; i++)
                {
                    parts.Clear();
                    var tumor = _tumors[i]!;

                    // Walk up to Patient node
                    var patient = tumor.ParentNode;
                    while (patient != null && patient.LocalName != "Patient")
                        patient = patient.ParentNode;

                    NaaccrItemReader.CollectAllItemText(patient, parts);
                    NaaccrItemReader.CollectAllItemText(tumor, parts);

                    index[i] = string.Join(" ", parts).ToLower();
                }

                return index;
            }
            else if (fileType == "hl7")
            {
                if (_hl7Messages == null || _hl7Messages.Count == 0)
                    return Array.Empty<string>();

                var index = new string[_hl7Messages.Count];

                // Built into a reused buffer, lowercasing as we go. Joining the
                // parts and then lowercasing the result would materialize every
                // report narrative twice more than necessary, which is the
                // dominant allocation once a load holds thousands of messages.
                var buffer = new StringBuilder(1024);

                for (int i = 0; i < _hl7Messages.Count; i++)
                {
                    var msg = _hl7Messages[i];
                    buffer.Clear();

                    // Add parsed fields
                    string[] fieldProps = { msg.PatientId, msg.PatientLastName, msg.PatientFirstName,
                        msg.DateOfBirth, msg.Sex, msg.MessageType,
                        msg.SendingApplication, msg.SendingFacility,
                        msg.OrderDateTime, msg.OrderingProvider };

                    foreach (var val in fieldProps)
                        AppendLower(buffer, val, 0, val?.Length ?? 0);

                    // Source file name, so a folder load can be filtered down to
                    // the records that came from one report.
                    if (!string.IsNullOrEmpty(msg.SourceFile))
                    {
                        var name = Path.GetFileName(msg.SourceFile);
                        AppendLower(buffer, name, 0, name.Length);
                    }

                    // OBX-5 (observation value) carries the report text.
                    if (msg.Segments.TryGetValue("OBX", out var obxSegs) && obxSegs.Count > 0)
                    {
                        foreach (var seg in obxSegs)
                        {
                            if (Hl7FieldHelper.TryGetFieldBounds(seg, 5, out var start, out var length))
                                AppendLower(buffer, seg, start, length);
                        }
                    }

                    index[i] = buffer.ToString();
                }

                return index;
            }
            else
            {
                return Array.Empty<string>();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError($"Failed to build search index for file type '{fileType}'", "SEARCH_INDEX_BUILD", ex);
            return Array.Empty<string>();
        }
    }

    public void ApplyFilter(string searchText, DataTable navTable, string[] searchIndex)
    {
        if (navTable == null) return;

        if (string.IsNullOrWhiteSpace(searchText))
        {
            navTable.DefaultView.RowFilter = "";
            return;
        }

        string lowerSearch = searchText.ToLower();
        var matchingIndices = new List<int>();

        for (int i = 0; i < searchIndex.Length; i++)
        {
            if (searchIndex[i].Contains(lowerSearch))
                matchingIndices.Add(i + 1); // 1-based Index column
        }

        try
        {
            if (matchingIndices.Count == 0)
            {
                navTable.DefaultView.RowFilter = "Index = -1";
            }
            else
            {
                navTable.DefaultView.RowFilter = $"Index IN ({string.Join(",", matchingIndices)})";
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to apply search filter to navigation table", "SEARCH_FILTER", ex);
        }
    }

    public void HighlightMatches(object richTextBox, string searchText)
    {
        // This method uses dynamic to avoid a hard dependency on System.Windows.Forms.
        // The interface accepts 'object' for the RichTextBox parameter.
        if (richTextBox == null) return;

        dynamic rtb = richTextBox;

        try
        {
            if ((int)rtb.TextLength == 0) return;

            // Clear previous highlights
            rtb.SelectAll();
            rtb.SelectionBackColor = rtb.BackColor;
            rtb.SelectionStart = 0;
            rtb.SelectionLength = 0;

            if (string.IsNullOrWhiteSpace(searchText)) return;

            string text = (string)rtb.Text;
            string lower = text.ToLower();
            string needle = searchText.ToLower();
            int needleLen = needle.Length;
            int pos = 0;

            while (true)
            {
                pos = lower.IndexOf(needle, pos, StringComparison.Ordinal);
                if (pos < 0) break;

                rtb.Select(pos, needleLen);
                rtb.SelectionBackColor = System.Drawing.Color.Yellow;
                pos += needleLen;
            }

            rtb.SelectionStart = 0;
            rtb.SelectionLength = 0;
        }
        catch (Exception ex)
        {
            _logger.Log("WARN", "Failed to highlight search matches in text control", "SEARCH_HIGHLIGHT", ex.Message);
        }
    }
}
