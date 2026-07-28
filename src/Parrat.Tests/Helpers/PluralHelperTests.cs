using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class PluralHelperTests
{
    [Theory]
    [InlineData(0, "files")]
    [InlineData(1, "file")]
    [InlineData(2, "files")]
    [InlineData(100, "files")]
    public void Noun_UsesSingularOnlyForExactlyOne(int count, string expected)
    {
        Assert.Equal(expected, PluralHelper.Noun(count, "file"));
    }

    [Fact]
    public void Noun_UsesExplicitPluralWhenGiven()
    {
        Assert.Equal("entry", PluralHelper.Noun(1, "entry", "entries"));
        Assert.Equal("entries", PluralHelper.Noun(3, "entry", "entries"));
    }

    [Theory]
    [InlineData(0, "0 files")]
    [InlineData(1, "1 file")]
    [InlineData(2, "2 files")]
    public void Count_CombinesNumberAndNoun(int count, string expected)
    {
        Assert.Equal(expected, PluralHelper.Count(count, "file"));
    }

    [Fact]
    public void Count_SeparatesThousands()
    {
        Assert.Equal("1,204 messages", PluralHelper.Count(1204, "message"));
        Assert.Equal("25,000 tumors", PluralHelper.Count(25000, "tumor"));
    }

    [Fact]
    public void Count_NeverEmitsParentheticalPlural()
    {
        Assert.DoesNotContain("(s)", PluralHelper.Count(1, "file"));
        Assert.DoesNotContain("(s)", PluralHelper.Count(7, "file"));
    }
}
