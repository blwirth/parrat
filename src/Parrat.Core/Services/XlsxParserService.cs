using System.IO.Compression;
using System.Xml;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

/// <summary>
/// Parses .xlsx (Office Open XML) files using only built-in .NET libraries.
/// An .xlsx file is a ZIP archive containing XML files:
///   - xl/sharedStrings.xml — shared string table
///   - xl/worksheets/sheet1.xml — cell data for the first sheet
/// </summary>
public class XlsxParserService : IXlsxParserService
{
    public CsvParseResult Parse(string filePath)
    {
        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Parse(stream);
    }

    public CsvParseResult Parse(Stream stream)
    {
        using var archive = new ZipArchive(stream, ZipArchiveMode.Read);

        var sharedStrings = ReadSharedStrings(archive);
        var rows = ReadSheet(archive, sharedStrings);

        if (rows.Count == 0)
            return new CsvParseResult();

        var headers = rows[0];
        rows.RemoveAt(0);

        return new CsvParseResult
        {
            Headers = headers,
            Rows = rows
        };
    }

    private static List<string> ReadSharedStrings(ZipArchive archive)
    {
        var strings = new List<string>();

        var entry = archive.GetEntry("xl/sharedStrings.xml");
        if (entry == null) return strings;

        using var entryStream = entry.Open();
        var doc = new XmlDocument();
        doc.Load(entryStream);

        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        var nsUri = doc.DocumentElement?.NamespaceURI ?? "";
        if (!string.IsNullOrEmpty(nsUri))
            nsMgr.AddNamespace("s", nsUri);

        // Each <si> element is a shared string. It may contain:
        //   <t>simple text</t>
        //   or <r><t>rich text run</t></r><r><t>another run</t></r>
        var siNodes = string.IsNullOrEmpty(nsUri)
            ? doc.SelectNodes("//si")
            : doc.SelectNodes("//s:si", nsMgr);

        if (siNodes == null) return strings;

        foreach (XmlNode si in siNodes)
        {
            // Concatenate all <t> elements (handles both simple and rich text)
            var tNodes = si.SelectNodes(".//t", nsMgr) ?? si.SelectNodes(".//s:t", nsMgr);
            if (tNodes == null || tNodes.Count == 0)
            {
                // Try without namespace prefix
                tNodes = si.SelectNodes(".//*[local-name()='t']");
            }

            if (tNodes != null && tNodes.Count > 0)
            {
                var text = string.Concat(tNodes.Cast<XmlNode>().Select(t => t.InnerText));
                strings.Add(text);
            }
            else
            {
                strings.Add(si.InnerText);
            }
        }

        return strings;
    }

    private static List<string[]> ReadSheet(ZipArchive archive, List<string> sharedStrings)
    {
        // Try sheet1.xml first, fall back to finding the first sheet
        var entry = archive.GetEntry("xl/worksheets/sheet1.xml");
        if (entry == null)
        {
            // Find any worksheet
            entry = archive.Entries.FirstOrDefault(e =>
                e.FullName.StartsWith("xl/worksheets/sheet", StringComparison.OrdinalIgnoreCase) &&
                e.FullName.EndsWith(".xml", StringComparison.OrdinalIgnoreCase));
        }

        if (entry == null) return new List<string[]>();

        using var entryStream = entry.Open();
        var doc = new XmlDocument();
        doc.Load(entryStream);

        var nsUri = doc.DocumentElement?.NamespaceURI ?? "";
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        if (!string.IsNullOrEmpty(nsUri))
            nsMgr.AddNamespace("s", nsUri);

        var rowNodes = !string.IsNullOrEmpty(nsUri)
            ? doc.SelectNodes("//s:sheetData/s:row", nsMgr)
            : doc.SelectNodes("//sheetData/row");

        if (rowNodes == null || rowNodes.Count == 0)
            return new List<string[]>();

        // First pass: determine max column count
        int maxCol = 0;
        var parsedRows = new List<(int rowNum, List<(int col, string value)> cells)>();

        foreach (XmlNode rowNode in rowNodes)
        {
            var rowNum = int.Parse(rowNode.Attributes?["r"]?.Value ?? "0");
            var cells = new List<(int col, string value)>();

            var cellNodes = !string.IsNullOrEmpty(nsUri)
                ? rowNode.SelectNodes("s:c", nsMgr)
                : rowNode.SelectNodes("c");

            if (cellNodes == null) continue;

            foreach (XmlNode cell in cellNodes)
            {
                var cellRef = cell.Attributes?["r"]?.Value ?? "";
                var colIndex = CellRefToColumnIndex(cellRef);
                if (colIndex > maxCol) maxCol = colIndex;

                var cellType = cell.Attributes?["t"]?.Value ?? "";
                var valueNode = !string.IsNullOrEmpty(nsUri)
                    ? cell.SelectSingleNode("s:v", nsMgr)
                    : cell.SelectSingleNode("v");

                string cellValue;
                if (cellType == "s" && valueNode != null)
                {
                    // Shared string reference
                    if (int.TryParse(valueNode.InnerText, out var ssIndex) && ssIndex < sharedStrings.Count)
                        cellValue = sharedStrings[ssIndex];
                    else
                        cellValue = valueNode.InnerText;
                }
                else if (cellType == "inlineStr")
                {
                    // Inline string: look for <is><t>text</t></is>
                    var tNode = cell.SelectSingleNode(".//*[local-name()='t']");
                    cellValue = tNode?.InnerText ?? "";
                }
                else
                {
                    cellValue = valueNode?.InnerText ?? "";
                }

                cells.Add((colIndex, cellValue));
            }

            if (cells.Count > 0)
                parsedRows.Add((rowNum, cells));
        }

        // Second pass: build string arrays with correct column alignment
        int columnCount = maxCol + 1;
        var result = new List<string[]>();

        foreach (var (_, cells) in parsedRows)
        {
            var row = new string[columnCount];
            Array.Fill(row, "");
            foreach (var (col, value) in cells)
            {
                if (col < columnCount)
                    row[col] = value;
            }
            result.Add(row);
        }

        // Trim trailing empty rows
        while (result.Count > 0 && result[^1].All(string.IsNullOrEmpty))
            result.RemoveAt(result.Count - 1);

        return result;
    }

    /// <summary>
    /// Converts an Excel cell reference like "A1", "B2", "AA3" to a 0-based column index.
    /// A=0, B=1, ..., Z=25, AA=26, AB=27, etc.
    /// </summary>
    public static int CellRefToColumnIndex(string cellRef)
    {
        int col = 0;
        for (int i = 0; i < cellRef.Length; i++)
        {
            char c = cellRef[i];
            if (c >= 'A' && c <= 'Z')
                col = col * 26 + (c - 'A' + 1);
            else if (c >= 'a' && c <= 'z')
                col = col * 26 + (c - 'a' + 1);
            else
                break; // Hit the numeric part
        }
        return col - 1; // Convert to 0-based
    }
}
