using System.IO.Compression;
using System.Text;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class XlsxParserServiceTests
{
    private readonly XlsxParserService _parser = new();

    [Fact]
    public void Parse_BasicXlsx_ReturnsHeadersAndRows()
    {
        var xlsx = BuildXlsx(
            sharedStrings: new[] { "name", "age", "city", "Alice", "30", "Portland", "Bob", "25", "Seattle" },
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData>
                <row r=""1""><c r=""A1"" t=""s""><v>0</v></c><c r=""B1"" t=""s""><v>1</v></c><c r=""C1"" t=""s""><v>2</v></c></row>
                <row r=""2""><c r=""A2"" t=""s""><v>3</v></c><c r=""B2"" t=""s""><v>4</v></c><c r=""C2"" t=""s""><v>5</v></c></row>
                <row r=""3""><c r=""A3"" t=""s""><v>6</v></c><c r=""B3"" t=""s""><v>7</v></c><c r=""C3"" t=""s""><v>8</v></c></row>
              </sheetData>
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Equal(new[] { "name", "age", "city" }, result.Headers);
        Assert.Equal(2, result.RowCount);
        Assert.Equal(new[] { "Alice", "30", "Portland" }, result.Rows[0]);
        Assert.Equal(new[] { "Bob", "25", "Seattle" }, result.Rows[1]);
    }

    [Fact]
    public void Parse_NumericValues_ReturnedAsStrings()
    {
        var xlsx = BuildXlsx(
            sharedStrings: new[] { "id", "value" },
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData>
                <row r=""1""><c r=""A1"" t=""s""><v>0</v></c><c r=""B1"" t=""s""><v>1</v></c></row>
                <row r=""2""><c r=""A2""><v>42</v></c><c r=""B2""><v>3.14</v></c></row>
              </sheetData>
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Equal("42", result.Rows[0][0]);
        Assert.Equal("3.14", result.Rows[0][1]);
    }

    [Fact]
    public void Parse_SparseColumns_FillsGaps()
    {
        // Row with data in A and C but not B
        var xlsx = BuildXlsx(
            sharedStrings: new[] { "a", "b", "c", "v1", "v3" },
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData>
                <row r=""1""><c r=""A1"" t=""s""><v>0</v></c><c r=""B1"" t=""s""><v>1</v></c><c r=""C1"" t=""s""><v>2</v></c></row>
                <row r=""2""><c r=""A2"" t=""s""><v>3</v></c><c r=""C2"" t=""s""><v>4</v></c></row>
              </sheetData>
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Equal(new[] { "v1", "", "v3" }, result.Rows[0]);
    }

    [Fact]
    public void Parse_EmptySheet_ReturnsEmptyResult()
    {
        var xlsx = BuildXlsx(
            sharedStrings: Array.Empty<string>(),
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData />
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Empty(result.Headers);
        Assert.Empty(result.Rows);
    }

    [Fact]
    public void Parse_HeaderOnly_ReturnsEmptyRows()
    {
        var xlsx = BuildXlsx(
            sharedStrings: new[] { "col1", "col2" },
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData>
                <row r=""1""><c r=""A1"" t=""s""><v>0</v></c><c r=""B1"" t=""s""><v>1</v></c></row>
              </sheetData>
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Equal(new[] { "col1", "col2" }, result.Headers);
        Assert.Empty(result.Rows);
    }

    [Fact]
    public void Parse_WideColumns_HandlesAA()
    {
        // Test column beyond Z (AA = column 26)
        var xlsx = BuildXlsx(
            sharedStrings: new[] { "first", "last" },
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData>
                <row r=""1""><c r=""A1"" t=""s""><v>0</v></c><c r=""AA1"" t=""s""><v>1</v></c></row>
              </sheetData>
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Equal(27, result.ColumnCount); // A through AA = 27 columns
        Assert.Equal("first", result.Headers[0]);
        Assert.Equal("last", result.Headers[26]);
    }

    [Fact]
    public void Parse_InlineStrings_Handled()
    {
        var xlsx = BuildXlsx(
            sharedStrings: Array.Empty<string>(),
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData>
                <row r=""1""><c r=""A1"" t=""inlineStr""><is><t>header</t></is></c></row>
                <row r=""2""><c r=""A2"" t=""inlineStr""><is><t>value</t></is></c></row>
              </sheetData>
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Equal("header", result.Headers[0]);
        Assert.Equal("value", result.Rows[0][0]);
    }

    [Fact]
    public void Parse_NoSharedStringsFile_StillWorks()
    {
        // Some xlsx files with only numbers have no sharedStrings.xml
        var xlsx = BuildXlsx(
            sharedStrings: null, // Don't create the file at all
            sheetXml: @"
            <worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">
              <sheetData>
                <row r=""1""><c r=""A1""><v>1</v></c><c r=""B1""><v>2</v></c></row>
                <row r=""2""><c r=""A2""><v>10</v></c><c r=""B2""><v>20</v></c></row>
              </sheetData>
            </worksheet>");

        var result = _parser.Parse(xlsx);

        Assert.Equal(new[] { "1", "2" }, result.Headers);
        Assert.Equal(new[] { "10", "20" }, result.Rows[0]);
    }

    [Theory]
    [InlineData("A1", 0)]
    [InlineData("B1", 1)]
    [InlineData("Z1", 25)]
    [InlineData("AA1", 26)]
    [InlineData("AB1", 27)]
    [InlineData("AZ1", 51)]
    [InlineData("BA1", 52)]
    public void CellRefToColumnIndex_CorrectConversions(string cellRef, int expected)
    {
        Assert.Equal(expected, XlsxParserService.CellRefToColumnIndex(cellRef));
    }

    // ── Helper: Build a minimal .xlsx in memory ──────────────────────────

    private static Stream BuildXlsx(string[]? sharedStrings, string sheetXml)
    {
        var ms = new MemoryStream();
        using (var archive = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
        {
            // Shared strings
            if (sharedStrings != null)
            {
                var ssEntry = archive.CreateEntry("xl/sharedStrings.xml");
                using var ssWriter = new StreamWriter(ssEntry.Open(), Encoding.UTF8);
                ssWriter.Write(@"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>");
                ssWriter.Write(@"<sst xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">");
                foreach (var s in sharedStrings)
                {
                    ssWriter.Write($"<si><t>{EscapeXml(s)}</t></si>");
                }
                ssWriter.Write("</sst>");
            }

            // Worksheet
            var sheetEntry = archive.CreateEntry("xl/worksheets/sheet1.xml");
            using var sheetWriter = new StreamWriter(sheetEntry.Open(), Encoding.UTF8);
            sheetWriter.Write(@"<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>");
            sheetWriter.Write(sheetXml);
        }

        ms.Position = 0;
        return ms;
    }

    private static string EscapeXml(string s)
    {
        return s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
                .Replace("\"", "&quot;").Replace("'", "&apos;");
    }
}
