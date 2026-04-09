using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class EpathParserServiceTests
{
    #region SplitEpathLine

    [Fact]
    public void SplitEpathLine_SplitsBasicPipeDelimitedLine()
    {
        var line = "L|3|CLIA123|Lab Name|123 Main St";
        var fields = EpathParserService.SplitEpathLine(line);

        Assert.Equal(5, fields.Length);
        Assert.Equal("L", fields[0]);
        Assert.Equal("3", fields[1]);
        Assert.Equal("CLIA123", fields[2]);
        Assert.Equal("Lab Name", fields[3]);
        Assert.Equal("123 Main St", fields[4]);
    }

    [Fact]
    public void SplitEpathLine_HandlesEscapedPipes()
    {
        var line = "field1|text with \\| pipe|field3";
        var fields = EpathParserService.SplitEpathLine(line);

        Assert.Equal(3, fields.Length);
        Assert.Equal("field1", fields[0]);
        Assert.Equal("text with | pipe", fields[1]);
        Assert.Equal("field3", fields[2]);
    }

    [Fact]
    public void SplitEpathLine_HandlesEmptyFields()
    {
        var line = "L||CLIA123|||";
        var fields = EpathParserService.SplitEpathLine(line);

        Assert.Equal(6, fields.Length);
        Assert.Equal("L", fields[0]);
        Assert.Equal("", fields[1]);
        Assert.Equal("CLIA123", fields[2]);
        Assert.Equal("", fields[3]);
        Assert.Equal("", fields[4]);
        Assert.Equal("", fields[5]);
    }

    [Fact]
    public void SplitEpathLine_HandlesSingleField()
    {
        var fields = EpathParserService.SplitEpathLine("L");
        Assert.Single(fields);
        Assert.Equal("L", fields[0]);
    }

    [Fact]
    public void SplitEpathLine_HandlesMultipleEscapedPipesInOneField()
    {
        var line = "a|b \\| c \\| d|e";
        var fields = EpathParserService.SplitEpathLine(line);

        Assert.Equal(3, fields.Length);
        Assert.Equal("b | c | d", fields[1]);
    }

    [Fact]
    public void SplitEpathLine_HandlesEmptyString()
    {
        var fields = EpathParserService.SplitEpathLine("");
        Assert.Single(fields);
        Assert.Equal("", fields[0]);
    }

    [Fact]
    public void SplitEpathLine_HandlesTrailingPipe()
    {
        var fields = EpathParserService.SplitEpathLine("a|b|");
        Assert.Equal(3, fields.Length);
        Assert.Equal("a", fields[0]);
        Assert.Equal("b", fields[1]);
        Assert.Equal("", fields[2]);
    }

    #endregion

    #region ParseDatFile — native EpathRecord

    [Fact]
    public void ParseDatFile_ReturnsEpathRecords()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[0] = "L";
        fields[1] = "3";
        fields[2] = "99D1234567";
        fields[3] = "Test Lab";
        fields[9] = "Smith";
        fields[10] = "Jane";
        fields[11] = "M";
        fields[17] = "19850315";
        fields[20] = "F";
        fields[21] = "MRN001";
        fields[22] = "SP-2024-001";
        fields[53] = "Invasive ductal carcinoma";
        fields[58] = "Final Diagnosis: Invasive ductal carcinoma";
        fields[62] = "20240301120000";

        var records = ParseSingleLine(fields);

        Assert.Single(records);
        var rec = records[0];

        Assert.Equal("Smith", rec.PatientLastName);
        Assert.Equal("Jane", rec.PatientFirstName);
        Assert.Equal("19850315", rec.DateOfBirth);
        Assert.Equal("F", rec.Sex);
        Assert.Equal("MRN001", rec.PatientId);
        Assert.Equal("SP-2024-001", rec.AccessionNumber);
        Assert.Equal("Test Lab", rec.SendingFacility);
        Assert.Equal("v2.2", rec.FormatVersion);
    }

    [Fact]
    public void ParseDatFile_StoresFieldMapByItemNumber()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[2] = "99D1234567";  // CLIA (item 7010)
        fields[9] = "Smith";       // Last Name (item 2230)
        fields[22] = "SP-001";     // Accession (item 7090)

        var records = ParseSingleLine(fields);
        var rec = records[0];

        Assert.Equal("99D1234567", rec.Fields[7010]);
        Assert.Equal("Smith", rec.Fields[2230]);
        Assert.Equal("SP-001", rec.Fields[7090]);
    }

    [Fact]
    public void ParseDatFile_BuildsDisplayFields()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith";
        fields[10] = "Jane";

        var records = ParseSingleLine(fields);
        var rec = records[0];

        Assert.True(rec.DisplayFields.Count >= 2);
        var lastNameField = rec.DisplayFields.FirstOrDefault(f => f.ItemNumber == 2230);
        Assert.NotNull(lastNameField);
        Assert.Equal("Smith", lastNameField!.Value);
        Assert.Equal("Name Last", lastNameField.Name);
    }

    [Fact]
    public void ParseDatFile_NoHl7InRawLine()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith";

        var records = ParseSingleLine(fields);

        // RawLine should be the original pipe-delimited content, NOT HL7
        Assert.DoesNotContain("MSH|", records[0].RawLine);
        Assert.Contains("|Smith|", records[0].RawLine);
    }

    [Fact]
    public void ParseDatFile_ParsesMultipleRecords()
    {
        SetupPathHelper();

        var f1 = MakeV22Fields();
        f1[9] = "Doe";
        f1[10] = "John";
        f1[21] = "MRN-A";

        var f2 = MakeV22Fields();
        f2[9] = "Smith";
        f2[10] = "Jane";
        f2[21] = "MRN-B";

        var content = JoinFields(f1) + "\n" + JoinFields(f2);
        var records = ParseContent(content);

        Assert.Equal(2, records.Count);
        Assert.Equal("Doe", records[0].PatientLastName);
        Assert.Equal("Smith", records[1].PatientLastName);
        Assert.Equal(0, records[0].Index);
        Assert.Equal(1, records[1].Index);
    }

    [Fact]
    public void ParseDatFile_SkipsEmptyLines()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Test";

        var content = "\n" + JoinFields(fields) + "\n\n";
        var records = ParseContent(content);

        Assert.Single(records);
    }

    [Fact]
    public void ParseDatFile_HandlesCrLfLineEndings()
    {
        SetupPathHelper();

        var f1 = MakeV22Fields();
        f1[9] = "Doe";
        var f2 = MakeV22Fields();
        f2[9] = "Smith";

        var content = JoinFields(f1) + "\r\n" + JoinFields(f2) + "\r\n";
        var records = ParseContent(content);

        Assert.Equal(2, records.Count);
    }

    [Fact]
    public void ParseDatFile_ShortLineParsesWithAvailableFields()
    {
        SetupPathHelper();

        var fields = new string[20];
        fields[0] = "L";
        fields[9] = "ShortLine";
        fields[10] = "Test";

        var records = ParseSingleLine(fields);

        Assert.Single(records);
        Assert.Equal("ShortLine", records[0].PatientLastName);
    }

    #endregion

    #region Format auto-detection

    [Fact]
    public void ParseDatFile_V22DetectedCorrectly()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith";

        var records = ParseSingleLine(fields);
        Assert.Equal("v2.2", records[0].FormatVersion);
    }

    [Fact]
    public void ParseDatFile_NoahV2DetectedCorrectly()
    {
        SetupPathHelper();

        var fields = MakeNoahV2Fields();
        fields[10] = "Johnson";
        fields[15] = "MRN-NOAH";
        fields[19] = "19900101";
        fields[21] = "M";
        fields[65] = "NOAH-SP-001";

        var records = ParseSingleLine(fields);

        Assert.Single(records);
        Assert.Equal("NOAH v2", records[0].FormatVersion);
        Assert.Equal("Johnson", records[0].PatientLastName);
        Assert.Equal("MRN-NOAH", records[0].PatientId);
        Assert.Equal("NOAH-SP-001", records[0].AccessionNumber);
    }

    [Fact]
    public void ParseDatFile_SameItemsMappedAcrossFormats()
    {
        SetupPathHelper();

        var v22 = MakeV22Fields();
        v22[9] = "Smith";       // v2.2 pos 10 → item 2230
        v22[21] = "MRN-V22";    // v2.2 pos 22 → item 2300

        var noah = MakeNoahV2Fields();
        noah[10] = "Smith";      // NOAH pos 11 → item 2230
        noah[15] = "MRN-NOAH";   // NOAH pos 16 → item 2300

        var v22Recs = ParseSingleLine(v22);
        var noahRecs = ParseSingleLine(noah);

        Assert.Equal("Smith", v22Recs[0].PatientLastName);
        Assert.Equal("Smith", noahRecs[0].PatientLastName);
    }

    #endregion

    #region ConvertToHl7 — explicit conversion

    [Fact]
    public void ConvertToHl7_ProducesHl7Messages()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith";
        fields[10] = "Jane";
        fields[17] = "19850315";
        fields[20] = "F";
        fields[21] = "MRN001";
        fields[22] = "SP-001";
        fields[58] = "Final Diagnosis: Carcinoma";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7Messages = parser.ConvertToHl7(records);

        Assert.Single(hl7Messages);
        var msg = hl7Messages[0];

        Assert.Equal("Smith", msg.PatientLastName);
        Assert.Equal("ORU^R01", msg.MessageType);
        Assert.Equal("EPATH", msg.SendingApplication);
        Assert.Contains("MSH|", msg.RawContent);
        Assert.Contains("PID|", msg.RawContent);
        Assert.Contains("OBR|", msg.RawContent);
        Assert.Contains("OBX|", msg.RawContent);
        Assert.Contains("Smith^Jane", msg.RawContent);
        Assert.Contains("FINAL_DX^Final Diagnosis", msg.RawContent);
    }

    [Fact]
    public void ConvertToHl7_V22ProducesHl7Version231()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);

        Assert.Contains("|2.3.1", hl7[0].RawContent);
    }

    [Fact]
    public void ConvertToHl7_NoahV2ProducesHl7Version251()
    {
        SetupPathHelper();

        var fields = MakeNoahV2Fields();
        fields[10] = "Johnson";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);

        Assert.Contains("|2.5.1", hl7[0].RawContent);
    }

    [Fact]
    public void ConvertToHl7_EscapesSpecialCharsInHl7Output()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "O'Brien & Sons";
        fields[10] = "Mary~Jane";
        fields[3] = "Lab^Name";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);
        var raw = hl7[0].RawContent;

        Assert.Contains("O'Brien \\T\\ Sons", raw);
        Assert.Contains("Mary\\R\\Jane", raw);
        Assert.Contains("Lab\\S\\Name", raw);
    }

    [Fact]
    public void ConvertToHl7_EscapedPipeInSourceBecomesHl7Escape()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "PLACEHOLDER";
        var line = JoinFields(fields).Replace("PLACEHOLDER", "Smith\\|Jones");

        var records = ParseContent(line);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);

        Assert.Contains("Smith\\F\\Jones", hl7[0].RawContent);
    }

    [Fact]
    public void ConvertToHl7_TextFieldsCreateObxSegments()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[53] = "Text diagnosis";
        fields[54] = "Patient history";
        fields[58] = "FINAL: Carcinoma";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);
        var raw = hl7[0].RawContent;

        Assert.Contains("PATH_DX^Path Text Diagnosis", raw);
        Assert.Contains("CLIN_HX^Clinical History", raw);
        Assert.Contains("FINAL_DX^Final Diagnosis", raw);
    }

    [Fact]
    public void ConvertToHl7_ObrContainsPathologistData()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[22] = "ACC-001";
        fields[39] = "PathLast";
        fields[40] = "PathFirst";
        fields[43] = "PATH-LIC";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);
        var obr = hl7[0].Segments["OBR"][0];

        Assert.Contains("ACC-001", obr);
        Assert.Contains("PathLast", obr);
        Assert.Contains("PATH-LIC", obr);
    }

    [Fact]
    public void ConvertToHl7_Pv1OmittedWhenNoPhysicians()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);

        Assert.False(hl7[0].Segments.ContainsKey("PV1"));
    }

    [Fact]
    public void ConvertToHl7_SnomedIcdCptCodes()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[47] = "M8500/3";
        fields[49] = "C50.911";
        fields[51] = "88305";

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);
        var raw = hl7[0].RawContent;

        Assert.Contains("SNOMED^SNOMED CT Code", raw);
        Assert.Contains("ICD^ICD-CM Code", raw);
        Assert.Contains("CPT^CPT Code", raw);
    }

    [Fact]
    public void ConvertToHl7_LargeTextFieldPreserved()
    {
        SetupPathHelper();

        var largeText = new string('X', 5000);
        var fields = MakeV22Fields();
        fields[58] = largeText;

        var records = ParseSingleLine(fields);
        var parser = new EpathParserService();
        var hl7 = parser.ConvertToHl7(records);

        Assert.Contains(largeText, hl7[0].RawContent);
    }

    #endregion

    #region Helpers

    private static void SetupPathHelper()
    {
        PathHelper.SetRepoRoot(FindRepoRoot());
    }

    private static string[] MakeV22Fields() => new string[85];
    private static string[] MakeNoahV2Fields() => new string[118];

    private static string JoinFields(string[] fields)
        => string.Join("|", fields.Select(f => f ?? ""));

    private static List<EpathRecord> ParseSingleLine(string[] fields)
        => ParseContent(JoinFields(fields));

    private static List<EpathRecord> ParseContent(string content)
    {
        var tempPath = Path.Combine(Path.GetTempPath(), $"test_epath_{Guid.NewGuid()}.dat");
        try
        {
            File.WriteAllText(tempPath, content);
            return new EpathParserService().ParseDatFile(tempPath);
        }
        finally
        {
            File.Delete(tempPath);
        }
    }

    private static string FindRepoRoot()
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        for (int i = 0; i < 10; i++)
        {
            if (Directory.Exists(Path.Combine(dir, "data", "dictionaries")))
                return dir;
            var parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("Could not find repo root with data/dictionaries");
    }

    #endregion
}
