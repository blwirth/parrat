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

        var utf8NoBom = new System.Text.UTF8Encoding(false);
        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace,
            Encoding = utf8NoBom
        };

        using var ms = new System.IO.MemoryStream();
        using (var xw = XmlWriter.Create(ms, settings))
        {
            doc.Save(xw);
        }
        return utf8NoBom.GetString(ms.ToArray());
    }
}
