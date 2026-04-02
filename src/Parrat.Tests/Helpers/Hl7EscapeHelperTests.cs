using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class Hl7EscapeHelperTests
{
    [Fact]
    public void Unescape_ReplacesFieldSeparator()
    {
        Assert.Equal("value|other", Hl7EscapeHelper.Unescape(@"value\F\other"));
    }

    [Fact]
    public void Unescape_ReplacesComponentSeparator()
    {
        Assert.Equal("value^other", Hl7EscapeHelper.Unescape(@"value\S\other"));
    }

    [Fact]
    public void Unescape_ReplacesRepetitionSeparator()
    {
        Assert.Equal("value~other", Hl7EscapeHelper.Unescape(@"value\R\other"));
    }

    [Fact]
    public void Unescape_ReplacesEscapeCharacter()
    {
        Assert.Equal(@"value\other", Hl7EscapeHelper.Unescape(@"value\E\other"));
    }

    [Fact]
    public void Unescape_ReplacesSubcomponentSeparator()
    {
        Assert.Equal("value&other", Hl7EscapeHelper.Unescape(@"value\T\other"));
    }

    [Fact]
    public void Unescape_ReplacesCarriageReturn()
    {
        Assert.Equal("line1\rline2", Hl7EscapeHelper.Unescape(@"line1\X0D\line2"));
    }

    [Fact]
    public void Unescape_ReplacesLineFeed()
    {
        Assert.Equal("line1\nline2", Hl7EscapeHelper.Unescape(@"line1\X0A\line2"));
    }

    [Fact]
    public void Unescape_ReplacesLineBreak()
    {
        Assert.Equal("line1\r\nline2", Hl7EscapeHelper.Unescape(@"line1\.br\line2"));
    }

    [Fact]
    public void Unescape_ReplacesMultipleEscapes()
    {
        var result = Hl7EscapeHelper.Unescape(@"A\F\B\S\C\T\D");
        Assert.Equal("A|B^C&D", result);
    }

    [Fact]
    public void Unescape_ReturnsNullForNull()
    {
        Assert.Null(Hl7EscapeHelper.Unescape(null!));
    }

    [Fact]
    public void Unescape_ReturnsEmptyForEmpty()
    {
        Assert.Equal("", Hl7EscapeHelper.Unescape(""));
    }

    [Fact]
    public void Unescape_PreservesPlainText()
    {
        var input = "No escapes here";
        Assert.Equal(input, Hl7EscapeHelper.Unescape(input));
    }

    [Fact]
    public void Unescape_PreservesUnknownEscapeSequences()
    {
        // Unknown sequences should pass through unchanged
        var input = @"value\Z\other";
        Assert.Equal(input, Hl7EscapeHelper.Unescape(input));
    }
}
