using System.Drawing;
using System.Windows.Forms;
using System.Xml;
using Parat.Core.Helpers;
using Parat.UI.Controls;

namespace Parat.UI.Forms;

/// <summary>
/// Raw record viewer for both XML and HL7 formats.
/// For XML: shows the raw XML of a single tumor record with syntax highlighting.
/// For HL7: shows the raw HL7 message segments with syntax highlighting.
/// Ported from Show-RawXmlForTumor (lib/xml-viewer.ps1) and
/// Show-RawHl7ForMessage (lib/hl7-viewer.ps1).
/// </summary>
public class RawRecordForm : Form
{
    /// <summary>
    /// Creates a raw XML viewer for a single tumor record.
    /// Extracts the selected tumor's Patient subtree into a minimal NAACCR document.
    /// </summary>
    public static RawRecordForm CreateXmlViewer(
        XmlDocument xmlDoc,
        XmlNode tumor,
        XmlNamespaceManager nsMgr,
        string label)
    {
        var form = new RawRecordForm();
        form.Text = $"Raw XML - {label}";
        form.Width = 1400;
        form.Height = 900;
        form.StartPosition = FormStartPosition.CenterScreen;

        var rtb = CreateRichTextBox();

        // Build minimal NAACCR document with just this tumor's Patient
        string finalXml = BuildMinimalNaaccrXml(xmlDoc, tumor, nsMgr);

        // Apply syntax highlighting
        SyntaxHighlightingHelper.SetXmlSyntaxHighlighting(rtb, finalXml);

        form.Controls.Add(rtb);
        return form;
    }

    /// <summary>
    /// Creates a raw HL7 viewer for a single message.
    /// </summary>
    public static RawRecordForm CreateHl7Viewer(string rawContent, string label)
    {
        var form = new RawRecordForm();
        form.Text = $"Raw HL7 - {label}";
        form.Width = 1400;
        form.Height = 900;
        form.StartPosition = FormStartPosition.CenterScreen;

        var rtb = CreateRichTextBox();

        // Apply syntax highlighting
        SyntaxHighlightingHelper.SetHl7SyntaxHighlighting(rtb, rawContent);

        form.Controls.Add(rtb);
        return form;
    }

    private RawRecordForm()
    {
        // Use factory methods
    }

    // ── Shared RichTextBox creation ──────────────────────────────────────

    private static RichTextBox CreateRichTextBox()
    {
        return new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            Font = new Font("Consolas", 10f),
            WordWrap = false,
            ScrollBars = RichTextBoxScrollBars.Both
        };
    }

    // ── XML document builder ─────────────────────────────────────────────

    /// <summary>
    /// Builds a minimal NAACCR XML document containing only the selected
    /// tumor's Patient subtree plus root-level non-Patient children.
    /// </summary>
    private static string BuildMinimalNaaccrXml(
        XmlDocument origDoc, XmlNode tumor, XmlNamespaceManager nsMgr)
    {
        var root = origDoc.DocumentElement;
        if (root == null)
            return "(No root element found)";

        var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
        if (patient == null)
            return "(Patient node not found for selected tumor)";

        var newDoc = new XmlDocument();
        newDoc.XmlResolver = null;

        // Create NaaccrData root with same name/ns/attributes
        var newRoot = newDoc.CreateElement(root.Prefix, root.LocalName, root.NamespaceURI);
        foreach (XmlAttribute attr in root.Attributes)
        {
            var newAttr = newDoc.CreateAttribute(attr.Prefix, attr.LocalName, attr.NamespaceURI);
            newAttr.Value = attr.Value;
            newRoot.Attributes.Append(newAttr);
        }
        newDoc.AppendChild(newRoot);

        // Copy top-level non-Patient children (e.g. root-level Item nodes)
        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName == "Patient") continue;
            var imported = newDoc.ImportNode(child, true);
            newRoot.AppendChild(imported);
        }

        // Import only the selected Patient subtree
        var importedPatient = newDoc.ImportNode(patient, true);
        newRoot.AppendChild(importedPatient);

        // Serialize new document; reuse original XML declaration if present
        string bodyXml = newDoc.OuterXml;

        XmlDeclaration? declNode = null;
        foreach (XmlNode child in origDoc.ChildNodes)
        {
            if (child is XmlDeclaration decl)
            {
                declNode = decl;
                break;
            }
        }

        string finalXml = declNode != null
            ? declNode.OuterXml + "\r\n" + bodyXml
            : bodyXml;

        // Pretty-print
        finalXml = XmlFormattingHelper.FormatXml(finalXml);

        return finalXml;
    }
}
