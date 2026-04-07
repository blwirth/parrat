using System.Text;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class CsvParserServiceTests
{
    private readonly CsvParserService _parser = new();

    private Stream ToStream(string content)
    {
        return new MemoryStream(Encoding.UTF8.GetBytes(content));
    }

    [Fact]
    public void Parse_BasicCsv_ReturnsHeadersAndRows()
    {
        var csv = "name,age,city\nAlice,30,Portland\nBob,25,Seattle\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Equal(new[] { "name", "age", "city" }, result.Headers);
        Assert.Equal(2, result.RowCount);
        Assert.Equal(3, result.ColumnCount);
        Assert.Equal(new[] { "Alice", "30", "Portland" }, result.Rows[0]);
        Assert.Equal(new[] { "Bob", "25", "Seattle" }, result.Rows[1]);
    }

    [Fact]
    public void Parse_QuotedFieldsWithCommas_ParsesCorrectly()
    {
        var csv = "name,address\n\"Smith, Jr.\",\"123 Main St, Apt 4\"\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Equal(new[] { "Smith, Jr.", "123 Main St, Apt 4" }, result.Rows[0]);
    }

    [Fact]
    public void Parse_EscapedQuotes_ParsesCorrectly()
    {
        var csv = "quote\n\"He said \"\"hello\"\"\"\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Single(result.Rows);
        Assert.Equal("He said \"hello\"", result.Rows[0][0]);
    }

    [Fact]
    public void Parse_NewlinesInQuotedFields_DoNotSplitRow()
    {
        var csv = "name,note\nAlice,\"line1\nline2\"\nBob,simple\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Equal(2, result.RowCount);
        Assert.Equal("line1\nline2", result.Rows[0][1]);
        Assert.Equal("Bob", result.Rows[1][0]);
    }

    [Fact]
    public void Parse_EmptyFields_PreservesEmpties()
    {
        var csv = "a,b,c\n1,,3\n,2,\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Equal(new[] { "1", "", "3" }, result.Rows[0]);
        Assert.Equal(new[] { "", "2", "" }, result.Rows[1]);
    }

    [Fact]
    public void Parse_TrailingNewline_DoesNotCreateExtraRow()
    {
        var csv = "h1,h2\nval1,val2\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Single(result.Rows);
    }

    [Fact]
    public void Parse_NoTrailingNewline_StillWorks()
    {
        var csv = "h1,h2\nval1,val2";
        var result = _parser.Parse(ToStream(csv));

        Assert.Single(result.Rows);
        Assert.Equal(new[] { "val1", "val2" }, result.Rows[0]);
    }

    [Fact]
    public void Parse_CrLfLineEndings_HandledCorrectly()
    {
        var csv = "a,b\r\n1,2\r\n3,4\r\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Equal(2, result.RowCount);
        Assert.Equal(new[] { "1", "2" }, result.Rows[0]);
        Assert.Equal(new[] { "3", "4" }, result.Rows[1]);
    }

    [Fact]
    public void Parse_HeaderOnly_ReturnsEmptyRows()
    {
        var csv = "col1,col2,col3\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Equal(new[] { "col1", "col2", "col3" }, result.Headers);
        Assert.Empty(result.Rows);
    }

    [Fact]
    public void Parse_EmptyContent_ReturnsEmptyResult()
    {
        var csv = "";
        var result = _parser.Parse(ToStream(csv));

        Assert.Empty(result.Headers);
        Assert.Empty(result.Rows);
    }

    [Fact]
    public void Parse_SingleColumn_Works()
    {
        var csv = "name\nAlice\nBob\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Single(result.Headers);
        Assert.Equal("name", result.Headers[0]);
        Assert.Equal(2, result.RowCount);
        Assert.Equal("Alice", result.Rows[0][0]);
    }

    [Fact]
    public void Parse_Utf8Bom_HandledCorrectly()
    {
        var bom = new byte[] { 0xEF, 0xBB, 0xBF };
        var csv = Encoding.UTF8.GetBytes("a,b\n1,2\n");
        var withBom = bom.Concat(csv).ToArray();
        var result = _parser.Parse(new MemoryStream(withBom));

        Assert.Equal(new[] { "a", "b" }, result.Headers);
        Assert.Equal(new[] { "1", "2" }, result.Rows[0]);
    }

    [Fact]
    public void Parse_QuotedFieldWithCrLf_HandledCorrectly()
    {
        var csv = "a,b\r\n\"line1\r\nline2\",val\r\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Single(result.Rows);
        Assert.Equal("line1\r\nline2", result.Rows[0][0]);
    }

    [Fact]
    public void Parse_ComplexMixedQuoting_HandledCorrectly()
    {
        // Mix of quoted and unquoted, with escaped quotes and commas
        var csv = "a,b,c\nunquoted,\"has, comma\",\"has \"\"quotes\"\"\"\n";
        var result = _parser.Parse(ToStream(csv));

        Assert.Equal("unquoted", result.Rows[0][0]);
        Assert.Equal("has, comma", result.Rows[0][1]);
        Assert.Equal("has \"quotes\"", result.Rows[0][2]);
    }
}
