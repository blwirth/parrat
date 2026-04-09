using Parrat.Core.Helpers;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class FileFormatValidatorTests
{
    // ═════════════════════════════════════════════════════════════════════
    //  HL7 VALIDATION
    // ═════════════════════════════════════════════════════════════════════

    [Fact]
    public void ValidateHl7_ValidMessage_ReturnsValid()
    {
        var content = "MSH|^~\\&|SendingApp|SendingFac|||20240101||ORU^R01|123|P|2.3.1\n" +
                      "PID|1||MRN001||Smith^Jane||19850315|F\n" +
                      "OBR|1||SP-001|PATH^Pathology Report\n" +
                      "OBX|1|TX|PATH_DX^Diagnosis||Carcinoma||||||F\n";

        var result = FileFormatValidator.ValidateHl7(content);

        Assert.True(result.IsValid);
        Assert.Empty(result.Errors);
    }

    [Fact]
    public void ValidateHl7_EmptyContent_ReturnsInvalid()
    {
        var result = FileFormatValidator.ValidateHl7("");

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("empty"));
    }

    [Fact]
    public void ValidateHl7_NoMshSegment_ReturnsInvalid()
    {
        var content = "PID|1||MRN001||Smith^Jane||19850315|F\n" +
                      "OBX|1|TX|PATH_DX^Diagnosis||Carcinoma||||||F\n";

        var result = FileFormatValidator.ValidateHl7(content);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("MSH"));
    }

    [Fact]
    public void ValidateHl7_NonStandardEncoding_WarnsButValid()
    {
        var content = "MSH|^~\\!|SendingApp|SendingFac|||20240101||ORU^R01|123|P|2.3.1\n" +
                      "PID|1||MRN001||Smith^Jane||19850315|F\n";

        var result = FileFormatValidator.ValidateHl7(content);

        Assert.True(result.IsValid);
        Assert.Contains(result.Warnings, w => w.Contains("encoding"));
    }

    [Fact]
    public void ValidateHl7_MissingPid_WarnsButValid()
    {
        var content = "MSH|^~\\&|SendingApp|SendingFac|||20240101||ORU^R01|123|P|2.3.1\n" +
                      "OBX|1|TX|PATH_DX^Diagnosis||Carcinoma||||||F\n";

        var result = FileFormatValidator.ValidateHl7(content);

        Assert.True(result.IsValid);
        Assert.Contains(result.Warnings, w => w.Contains("PID"));
    }

    [Fact]
    public void ValidateHl7_MultipleMessages_Validates()
    {
        var content = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.3.1\n" +
                      "PID|1||MRN001||Smith^Jane||19850315|F\n" +
                      "MSH|^~\\&|App|Fac|||20240102||ORU^R01|2|P|2.3.1\n" +
                      "PID|1||MRN002||Doe^John||19900101|M\n";

        var result = FileFormatValidator.ValidateHl7(content);

        Assert.True(result.IsValid);
    }

    [Fact]
    public void ValidateHl7_PlainTextFile_ReturnsInvalid()
    {
        var content = "This is just a plain text file\nwith no HL7 content at all.\n";

        var result = FileFormatValidator.ValidateHl7(content);

        Assert.False(result.IsValid);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  NAACCR XML VALIDATION
    // ═════════════════════════════════════════════════════════════════════

    [Fact]
    public void ValidateNaaccrXml_ValidFile_ReturnsValid()
    {
        var content = @"<?xml version=""1.0""?>
<NaaccrData baseDictionaryUri=""http://naaccr.org/naaccrxml/naaccr-dictionary-240.xml""
            recordType=""A"" xmlns=""http://naaccr.org/naaccrxml"">
  <Patient>
    <Item naaccrId=""patientIdNumber"">00001</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C509</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        var result = FileFormatValidator.ValidateNaaccrXml(content);

        Assert.True(result.IsValid);
        Assert.Empty(result.Errors);
    }

    [Fact]
    public void ValidateNaaccrXml_EmptyContent_ReturnsInvalid()
    {
        var result = FileFormatValidator.ValidateNaaccrXml("");

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("empty"));
    }

    [Fact]
    public void ValidateNaaccrXml_MalformedXml_ReturnsInvalid()
    {
        var content = "<NaaccrData><Patient><unclosed>";

        var result = FileFormatValidator.ValidateNaaccrXml(content);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("Not valid XML"));
    }

    [Fact]
    public void ValidateNaaccrXml_WrongRootElement_ReturnsInvalid()
    {
        var content = @"<?xml version=""1.0""?><Root><Data>test</Data></Root>";

        var result = FileFormatValidator.ValidateNaaccrXml(content);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("NaaccrData"));
    }

    [Fact]
    public void ValidateNaaccrXml_NoPatients_ReturnsInvalid()
    {
        var content = @"<?xml version=""1.0""?>
<NaaccrData baseDictionaryUri=""http://naaccr.org/naaccrxml/naaccr-dictionary-240.xml""
            recordType=""A"" xmlns=""http://naaccr.org/naaccrxml"">
</NaaccrData>";

        var result = FileFormatValidator.ValidateNaaccrXml(content);

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("Patient"));
    }

    [Fact]
    public void ValidateNaaccrXml_MissingNamespace_WarnsButValid()
    {
        var content = @"<?xml version=""1.0""?>
<NaaccrData baseDictionaryUri=""http://naaccr.org/naaccrxml/naaccr-dictionary-240.xml"" recordType=""A"">
  <Patient>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
  </Patient>
</NaaccrData>";

        var result = FileFormatValidator.ValidateNaaccrXml(content);

        Assert.True(result.IsValid);
        Assert.Contains(result.Warnings, w => w.Contains("namespace"));
    }

    [Fact]
    public void ValidateNaaccrXml_MissingDictionaryUri_WarnsButValid()
    {
        var content = @"<?xml version=""1.0""?>
<NaaccrData recordType=""A"" xmlns=""http://naaccr.org/naaccrxml"">
  <Patient>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
  </Patient>
</NaaccrData>";

        var result = FileFormatValidator.ValidateNaaccrXml(content);

        Assert.True(result.IsValid);
        Assert.Contains(result.Warnings, w => w.Contains("baseDictionaryUri"));
    }

    [Fact]
    public void ValidateNaaccrXml_Hl7Content_ReturnsInvalid()
    {
        var content = "MSH|^~\\&|SendingApp|SendingFac|||20240101||ORU^R01|123|P|2.3.1\nPID|1||MRN001\n";

        var result = FileFormatValidator.ValidateNaaccrXml(content);

        Assert.False(result.IsValid);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  ePATH .DAT VALIDATION
    // ═════════════════════════════════════════════════════════════════════

    [Fact]
    public void ValidateEpathDat_ValidV22_ReturnsValid()
    {
        SetupPathHelper();

        var fields = new string[85];
        fields[0] = "L";
        fields[1] = "3";
        fields[2] = "99D1234567";
        fields[9] = "Smith";
        fields[10] = "Jane";

        var content = string.Join("|", fields.Select(f => f ?? ""));
        var result = FileFormatValidator.ValidateEpathDat(content);

        Assert.True(result.IsValid);
    }

    [Fact]
    public void ValidateEpathDat_EmptyContent_ReturnsInvalid()
    {
        var result = FileFormatValidator.ValidateEpathDat("");

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("empty"));
    }

    [Fact]
    public void ValidateEpathDat_NoPipes_ReturnsInvalid()
    {
        var result = FileFormatValidator.ValidateEpathDat("This is just plain text with no pipes");

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("pipe"));
    }

    [Fact]
    public void ValidateEpathDat_TooFewFields_ReturnsInvalid()
    {
        var result = FileFormatValidator.ValidateEpathDat("L|3|CLIA|Lab|Street");

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("fields"));
    }

    [Fact]
    public void ValidateEpathDat_NonStandardRecordType_Warns()
    {
        SetupPathHelper();

        var fields = new string[85];
        fields[0] = "X";
        fields[9] = "Smith";

        var content = string.Join("|", fields.Select(f => f ?? ""));
        var result = FileFormatValidator.ValidateEpathDat(content);

        Assert.True(result.IsValid);
        Assert.Contains(result.Warnings, w => w.Contains("record type"));
    }

    [Fact]
    public void ValidateEpathDat_NoahV2Detected()
    {
        SetupPathHelper();

        var fields = new string[118];
        fields[0] = "L";
        fields[10] = "Smith";

        var content = string.Join("|", fields.Select(f => f ?? ""));
        var result = FileFormatValidator.ValidateEpathDat(content);

        Assert.True(result.IsValid);
        Assert.Contains(result.Warnings, w => w.Contains("NOAH v2"));
    }

    [Fact]
    public void ValidateEpathDat_XmlContent_ReturnsInvalid()
    {
        var content = @"<?xml version=""1.0""?><NaaccrData><Patient></Patient></NaaccrData>";

        var result = FileFormatValidator.ValidateEpathDat(content);

        Assert.False(result.IsValid);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  CROSS-FORMAT DETECTION
    // ═════════════════════════════════════════════════════════════════════

    [Fact]
    public void ValidateHl7_XmlContent_ReturnsInvalid()
    {
        var content = @"<?xml version=""1.0""?><NaaccrData xmlns=""http://naaccr.org/naaccrxml""><Patient><Tumor/></Patient></NaaccrData>";

        var result = FileFormatValidator.ValidateHl7(content);

        Assert.False(result.IsValid);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private static void SetupPathHelper()
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        for (int i = 0; i < 10; i++)
        {
            if (Directory.Exists(Path.Combine(dir, "data", "dictionaries")))
            {
                PathHelper.SetRepoRoot(dir);
                return;
            }
            var parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("Could not find repo root");
    }
}
