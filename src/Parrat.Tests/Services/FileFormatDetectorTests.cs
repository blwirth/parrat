using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class FileFormatDetectorTests
{
    private const string Hl7Content =
        "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n" +
        "PID|1||MRN001||Smith^Jane||19850315|F\n" +
        "OBR|1||SP-001|PATH^Pathology Report\n";

    private const string NaaccrXmlContent =
        "<?xml version=\"1.0\"?>\n" +
        "<NaaccrData baseDictionaryUri=\"http://naaccr.org/naaccrxml/naaccr-dictionary-240.xml\"\n" +
        "            recordType=\"A\" xmlns=\"http://naaccr.org/naaccrxml\">\n" +
        "  <Patient><Tumor><Item naaccrId=\"primarySite\">C509</Item></Tumor></Patient>\n" +
        "</NaaccrData>";

    // ── Content detection ────────────────────────────────────────────────

    [Fact]
    public void Detect_Hl7Message_ReturnsHl7()
    {
        Assert.Equal(DetectedFileFormat.Hl7, FileFormatDetector.Detect(Hl7Content));
    }

    [Theory]
    [InlineData("FHS|^~\\&|App|Fac\nMSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n")]
    [InlineData("BHS|^~\\&|App|Fac\nMSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n")]
    public void Detect_BatchWrappedHl7_ReturnsHl7(string content)
    {
        Assert.Equal(DetectedFileFormat.Hl7, FileFormatDetector.Detect(content));
    }

    [Fact]
    public void Detect_Hl7WithLeadingBlankLines_ReturnsHl7()
    {
        Assert.Equal(DetectedFileFormat.Hl7, FileFormatDetector.Detect("\n\n" + Hl7Content));
    }

    [Fact]
    public void Detect_NaaccrXml_ReturnsNaaccrXml()
    {
        Assert.Equal(DetectedFileFormat.NaaccrXml, FileFormatDetector.Detect(NaaccrXmlContent));
    }

    [Fact]
    public void Detect_NamespacePrefixedNaaccrXml_ReturnsNaaccrXml()
    {
        var content = "<?xml version=\"1.0\"?>\n" +
                      "<n:NaaccrData xmlns:n=\"http://naaccr.org/naaccrxml\"><n:Patient /></n:NaaccrData>";

        Assert.Equal(DetectedFileFormat.NaaccrXml, FileFormatDetector.Detect(content));
    }

    [Fact]
    public void Detect_NonNaaccrXml_ReturnsUnknown()
    {
        var content = "<?xml version=\"1.0\"?>\n<SomethingElse><Row /></SomethingElse>";

        Assert.Equal(DetectedFileFormat.Unknown, FileFormatDetector.Detect(content));
    }

    [Fact]
    public void Detect_EpathFlatFile_ReturnsEpathDat()
    {
        var content = "L|" + string.Join("|", Enumerable.Range(1, 90).Select(i => $"f{i}")) + "\n";

        Assert.Equal(DetectedFileFormat.EpathDat, FileFormatDetector.Detect(content));
    }

    [Fact]
    public void Detect_PathologyNarrative_ReturnsPlainText()
    {
        var content = "SURGICAL PATHOLOGY REPORT\n" +
                      "Specimen: left breast, lumpectomy\n" +
                      "Diagnosis: invasive ductal carcinoma\n";

        Assert.Equal(DetectedFileFormat.PlainText, FileFormatDetector.Detect(content));
    }

    [Fact]
    public void Detect_PipeDelimitedButTooFewFields_ReturnsPlainText()
    {
        // A narrative with a few pipes must not be mistaken for an ePath record.
        Assert.Equal(DetectedFileFormat.PlainText, FileFormatDetector.Detect("A|B|C|D\n"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   \n\n  ")]
    public void Detect_EmptyContent_ReturnsUnknown(string? content)
    {
        Assert.Equal(DetectedFileFormat.Unknown, FileFormatDetector.Detect(content));
    }

    // ── File detection ───────────────────────────────────────────────────

    [Fact]
    public void DetectFile_Hl7WithTxtExtension_ReturnsHl7()
    {
        var path = WriteTempFile("hl7-as-text", ".txt", Hl7Content);
        try
        {
            Assert.Equal(DetectedFileFormat.Hl7, FileFormatDetector.DetectFile(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void DetectFile_XmlWithWrongExtension_ReturnsNaaccrXml()
    {
        var path = WriteTempFile("xml-as-hl7", ".hl7", NaaccrXmlContent);
        try
        {
            Assert.Equal(DetectedFileFormat.NaaccrXml, FileFormatDetector.DetectFile(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void DetectFile_MissingFile_ReturnsUnknown()
    {
        var path = Path.Combine(Path.GetTempPath(), $"parrat-absent-{Guid.NewGuid():N}.hl7");

        Assert.Equal(DetectedFileFormat.Unknown, FileFormatDetector.DetectFile(path));
    }

    [Fact]
    public void DescribeFormat_ReturnsReadableNames()
    {
        Assert.Equal("HL7", FileFormatDetector.DescribeFormat(DetectedFileFormat.Hl7));
        Assert.Equal("NAACCR XML", FileFormatDetector.DescribeFormat(DetectedFileFormat.NaaccrXml));
        Assert.Equal("unrecognized", FileFormatDetector.DescribeFormat(DetectedFileFormat.Unknown));
    }

    [Theory]
    [InlineData(DetectedFileFormat.Hl7, "hl7")]
    [InlineData(DetectedFileFormat.NaaccrXml, "xml")]
    [InlineData(DetectedFileFormat.EpathDat, "epath")]
    public void ShortType_RoundTripsThroughParse(DetectedFileFormat format, string expected)
    {
        var shortType = FileFormatDetector.DescribeShortType(format);

        Assert.Equal(expected, shortType);
        Assert.Equal(format, FileFormatDetector.ParseShortType(shortType));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("something-else")]
    public void ParseShortType_UnrecognizedValue_ReturnsUnknown(string? shortType)
    {
        Assert.Equal(DetectedFileFormat.Unknown, FileFormatDetector.ParseShortType(shortType));
    }

    [Fact]
    public void DescribeRecordUnit_NamesTheRecordEachFormatIsCountedIn()
    {
        Assert.Equal("tumor", FileFormatDetector.DescribeRecordUnit(DetectedFileFormat.NaaccrXml));
        Assert.Equal("message", FileFormatDetector.DescribeRecordUnit(DetectedFileFormat.Hl7));
        Assert.Equal("record", FileFormatDetector.DescribeRecordUnit(DetectedFileFormat.EpathDat));
    }

    private static string WriteTempFile(string prefix, string extension, string content)
    {
        var path = Path.Combine(Path.GetTempPath(), $"parrat-{prefix}-{Guid.NewGuid():N}{extension}");
        File.WriteAllText(path, content);
        return path;
    }
}
