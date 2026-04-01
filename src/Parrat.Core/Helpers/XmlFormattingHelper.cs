using System.Xml;

namespace Parrat.Core.Helpers;

/// <summary>
/// Pretty-prints XML strings with proper indentation.
/// Ported from Format-Xml in lib/syntax-helpers.ps1.
/// </summary>
public static class XmlFormattingHelper
{
    /// <summary>
    /// Formats (pretty-prints) an XML string with indentation.
    /// Returns null/whitespace inputs unchanged.
    /// </summary>
    public static string FormatXml(string xml)
    {
        if (string.IsNullOrWhiteSpace(xml))
            return xml;

        var doc = new XmlDocument();
        doc.PreserveWhitespace = false;
        doc.LoadXml(xml);

        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace
        };

        using var sw = new System.IO.StringWriter();
        using var xw = XmlWriter.Create(sw, settings);
        doc.Save(xw);
        xw.Flush();
        return sw.ToString();
    }
}
