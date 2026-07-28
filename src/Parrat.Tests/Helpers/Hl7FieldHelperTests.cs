using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class Hl7FieldHelperTests
{
    private const string Obx =
        "OBX|1|TX|PATH_DX^Diagnosis||Invasive ductal carcinoma|units|range|A|||F";

    [Theory]
    [InlineData(0, "OBX")]
    [InlineData(1, "1")]
    [InlineData(2, "TX")]
    [InlineData(3, "PATH_DX^Diagnosis")]
    [InlineData(4, "")]
    [InlineData(5, "Invasive ductal carcinoma")]
    [InlineData(8, "A")]
    [InlineData(10, "")]
    [InlineData(11, "F")]
    public void GetField_ReturnsFieldAtIndex(int index, string expected)
    {
        Assert.Equal(expected, Hl7FieldHelper.GetField(Obx, index));
    }

    [Theory]
    [InlineData(12)]
    [InlineData(99)]
    [InlineData(-1)]
    public void GetField_OutOfRange_ReturnsEmpty(int index)
    {
        Assert.Equal("", Hl7FieldHelper.GetField(Obx, index));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void GetField_BlankSegment_ReturnsEmpty(string? segment)
    {
        Assert.Equal("", Hl7FieldHelper.GetField(segment, 1));
    }

    [Fact]
    public void GetField_TrailingSeparator_YieldsEmptyFinalField()
    {
        Assert.Equal("", Hl7FieldHelper.GetField("OBX|1|", 2));
        Assert.Equal("", Hl7FieldHelper.GetField("OBX|1|", 3));
    }

    [Theory]
    [InlineData("OBX|1|TX|PATH_DX^Diagnosis||Carcinoma|u|r|A|||F")]
    [InlineData("MSH|^~\\&|App|Fac|||20240101||ORU^R01|123|P|2.5.1")]
    [InlineData("PID|1||MRN001||Smith^Jane||19850315|F")]
    [InlineData("OBX|1|TX|||||||||")]
    [InlineData("SINGLEFIELD")]
    [InlineData("|leading|separator")]
    public void GetField_MatchesSplitIndexingForEveryField(string segment)
    {
        var expected = segment.Split('|');

        for (int i = 0; i < expected.Length + 3; i++)
        {
            var want = i < expected.Length ? expected[i] : "";
            Assert.Equal(want, Hl7FieldHelper.GetField(segment, i));
        }
    }

    [Fact]
    public void TryGetFieldBounds_LocatesFieldWithoutCopying()
    {
        Assert.True(Hl7FieldHelper.TryGetFieldBounds(Obx, 5, out var start, out var length));
        Assert.Equal("Invasive ductal carcinoma", Obx.Substring(start, length));
    }

    [Fact]
    public void TryGetFieldBounds_MissingField_ReturnsFalse()
    {
        Assert.False(Hl7FieldHelper.TryGetFieldBounds(Obx, 42, out _, out _));
        Assert.False(Hl7FieldHelper.TryGetFieldBounds("", 0, out _, out _));
    }

    [Fact]
    public void TryGetFieldBounds_EmptyField_ReturnsTrueWithZeroLength()
    {
        Assert.True(Hl7FieldHelper.TryGetFieldBounds(Obx, 4, out _, out var length));
        Assert.Equal(0, length);
    }
}
