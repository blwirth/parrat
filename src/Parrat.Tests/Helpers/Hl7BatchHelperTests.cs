using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class Hl7BatchHelperTests
{
    [Theory]
    [InlineData("FHS|^~\\&|SendingApp|SendingFac|||20240101")]
    [InlineData("BHS|^~\\&|SendingApp|SendingFac|||20240101")]
    [InlineData("BTS|2|Batch complete")]
    [InlineData("FTS|1")]
    public void IsEnvelopeSegment_EnvelopeSegments_ReturnsTrue(string line)
    {
        Assert.True(Hl7BatchHelper.IsEnvelopeSegment(line));
    }

    [Theory]
    [InlineData("MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1")]
    [InlineData("PID|1||MRN001||Smith^Jane||19850315|F")]
    [InlineData("OBX|1|TX|PATH_DX^Diagnosis||Carcinoma")]
    public void IsEnvelopeSegment_MessageSegments_ReturnsFalse(string line)
    {
        Assert.False(Hl7BatchHelper.IsEnvelopeSegment(line));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("FHS")]                              // too short to carry a separator
    [InlineData("FTSX|1")]                           // identifier is not exactly 3 chars
    [InlineData("BTS notes about the batch")]        // no field separator
    [InlineData("FHS is mentioned in this report")]  // narrative text, not a segment
    public void IsEnvelopeSegment_NonSegmentText_ReturnsFalse(string? line)
    {
        Assert.False(Hl7BatchHelper.IsEnvelopeSegment(line));
    }

    [Fact]
    public void IsEnvelopeSegment_LeadingWhitespace_StillRecognized()
    {
        Assert.True(Hl7BatchHelper.IsEnvelopeSegment("  FTS|1  "));
    }

    [Fact]
    public void StripEnvelopeSegments_RemovesWrapperKeepsMessages()
    {
        var content = "FHS|^~\\&|App|Fac|||20240101\n" +
                      "BHS|^~\\&|App|Fac|||20240101\n" +
                      "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n" +
                      "PID|1||MRN001||Smith^Jane||19850315|F\n" +
                      "BTS|1\n" +
                      "FTS|1\n";

        var result = Hl7BatchHelper.StripEnvelopeSegments(content);

        Assert.DoesNotContain("FHS|", result);
        Assert.DoesNotContain("BHS|", result);
        Assert.DoesNotContain("BTS|", result);
        Assert.DoesNotContain("FTS|", result);
        Assert.Contains("MSH|", result);
        Assert.Contains("PID|", result);
    }

    [Fact]
    public void StripEnvelopeSegments_MultipleBatches_RemovesEveryWrapper()
    {
        var content = "FHS|^~\\&|App|Fac\n" +
                      "BHS|^~\\&|App|Fac\n" +
                      "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n" +
                      "BTS|1\n" +
                      "BHS|^~\\&|App|Fac\n" +
                      "MSH|^~\\&|App|Fac|||20240102||ORU^R01|2|P|2.5.1\n" +
                      "BTS|1\n" +
                      "FTS|2\n";

        var result = Hl7BatchHelper.StripEnvelopeSegments(content);

        Assert.Equal(
            "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n" +
            "MSH|^~\\&|App|Fac|||20240102||ORU^R01|2|P|2.5.1\n",
            result);
    }

    [Fact]
    public void StripEnvelopeSegments_NoEnvelope_ReturnsContentUnchanged()
    {
        var content = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\r\n" +
                      "PID|1||MRN001||Smith^Jane||19850315|F\r\n";

        Assert.Equal(content, Hl7BatchHelper.StripEnvelopeSegments(content));
    }

    [Fact]
    public void ContainsEnvelopeSegment_DetectsWrapper()
    {
        Assert.True(Hl7BatchHelper.ContainsEnvelopeSegment("FHS|^~\\&|App\nMSH|^~\\&|App"));
        Assert.False(Hl7BatchHelper.ContainsEnvelopeSegment("MSH|^~\\&|App\nPID|1"));
    }
}
