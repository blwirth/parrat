using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class XmlFormattingHelperTests
{
    [Fact]
    public void FormatXml_IndentsNestedElements()
    {
        var input = "<root><child><nested>value</nested></child></root>";
        var result = XmlFormattingHelper.FormatXml(input);

        Assert.Contains("  <child>", result);
        Assert.Contains("    <nested>", result);
    }

    [Fact]
    public void FormatXml_PreservesElementContent()
    {
        var input = "<root><item>Hello World</item></root>";
        var result = XmlFormattingHelper.FormatXml(input);

        Assert.Contains("Hello World", result);
    }

    [Fact]
    public void FormatXml_ReturnsNullForNull()
    {
        Assert.Null(XmlFormattingHelper.FormatXml(null!));
    }

    [Fact]
    public void FormatXml_ReturnsEmptyForEmpty()
    {
        Assert.Equal("", XmlFormattingHelper.FormatXml(""));
    }

    [Fact]
    public void FormatXml_ReturnsWhitespaceForWhitespace()
    {
        Assert.Equal("   ", XmlFormattingHelper.FormatXml("   "));
    }

    [Fact]
    public void FormatXml_HandlesAttributes()
    {
        var input = "<root attr=\"val\"><child name=\"test\">data</child></root>";
        var result = XmlFormattingHelper.FormatXml(input);

        Assert.Contains("attr=\"val\"", result);
        Assert.Contains("name=\"test\"", result);
    }

    [Fact]
    public void FormatXml_ProducesValidXml()
    {
        var input = "<root><a>1</a><b>2</b></root>";
        var result = XmlFormattingHelper.FormatXml(input);

        // Should be parseable XML
        var doc = new System.Xml.XmlDocument();
        var ex = Record.Exception(() => doc.LoadXml(result));
        Assert.Null(ex);
    }

    [Fact]
    public void FormatXml_UsesCrLfLineEndings()
    {
        var input = "<root><child>val</child></root>";
        var result = XmlFormattingHelper.FormatXml(input);

        Assert.Contains("\r\n", result);
    }

    [Fact]
    public void FormatXml_DeclaresUtf8Encoding()
    {
        var input = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><root><child>val</child></root>";
        var result = XmlFormattingHelper.FormatXml(input);

        Assert.Contains("encoding=\"utf-8\"", result);
        Assert.DoesNotContain("utf-16", result);
    }

    [Fact]
    public void FormatXml_OutputLoadableFromUtf8File()
    {
        var input = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><root><child>val</child></root>";
        var result = XmlFormattingHelper.FormatXml(input);

        // Simulate the actual save path: WriteAllText with UTF-8 → Load from file
        var tempPath = System.IO.Path.GetTempFileName();
        try
        {
            System.IO.File.WriteAllText(tempPath, result, System.Text.Encoding.UTF8);

            var doc = new System.Xml.XmlDocument();
            var ex = Record.Exception(() => doc.Load(tempPath));
            Assert.Null(ex);
            Assert.Equal("val", doc.SelectSingleNode("//child")!.InnerText);
        }
        finally
        {
            System.IO.File.Delete(tempPath);
        }
    }
}
