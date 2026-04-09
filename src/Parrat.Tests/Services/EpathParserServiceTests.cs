using Parrat.Core.Helpers;
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

    #region ParseDatFile — basic

    [Fact]
    public void ParseDatFile_ParsesSampleFile()
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
        fields[53] = "Invasive ductal carcinoma of the left breast";
        fields[58] = "Final Diagnosis: Invasive ductal carcinoma";
        fields[62] = "20240301120000";

        var messages = ParseSingleLine(fields);

        Assert.Single(messages);
        var msg = messages[0];

        Assert.Equal("Smith", msg.PatientLastName);
        Assert.Equal("Jane", msg.PatientFirstName);
        Assert.Equal("19850315", msg.DateOfBirth);
        Assert.Equal("F", msg.Sex);
        Assert.Equal("MRN001", msg.PatientId);
        Assert.Equal("SP-2024-001", msg.AccessionNumber);
        Assert.Equal("ORU^R01", msg.MessageType);
        Assert.Equal("EPATH", msg.SendingApplication);

        Assert.True(msg.Segments.ContainsKey("MSH"));
        Assert.True(msg.Segments.ContainsKey("PID"));
        Assert.True(msg.Segments.ContainsKey("OBR"));
        Assert.True(msg.Segments.ContainsKey("OBX"));
        Assert.Contains("MSH|", msg.RawContent);
        Assert.Contains("PID|", msg.RawContent);
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
        var messages = ParseContent(content);

        Assert.Equal(2, messages.Count);
        Assert.Equal("Doe", messages[0].PatientLastName);
        Assert.Equal("Smith", messages[1].PatientLastName);
        Assert.Equal(0, messages[0].Index);
        Assert.Equal(1, messages[1].Index);
    }

    [Fact]
    public void ParseDatFile_SkipsEmptyLines()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Test";

        var content = "\n" + JoinFields(fields) + "\n\n";
        var messages = ParseContent(content);

        Assert.Single(messages);
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
        var messages = ParseContent(content);

        Assert.Equal(2, messages.Count);
        Assert.Equal("Doe", messages[0].PatientLastName);
        Assert.Equal("Smith", messages[1].PatientLastName);
    }

    [Fact]
    public void ParseDatFile_ShortLineParsesWithAvailableFields()
    {
        SetupPathHelper();

        // Only 20 fields — fewer than expected 85, but should still parse what's there
        var fields = new string[20];
        fields[0] = "L";
        fields[9] = "ShortLine";
        fields[10] = "Test";

        var messages = ParseSingleLine(fields);

        Assert.Single(messages);
        Assert.Equal("ShortLine", messages[0].PatientLastName);
        Assert.Equal("Test", messages[0].PatientFirstName);
    }

    #endregion

    #region HL7 version

    [Fact]
    public void ParseDatFile_V22ProducesHl7Version231()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith";

        var messages = ParseSingleLine(fields);
        Assert.Contains("|2.3.1", messages[0].RawContent);
    }

    [Fact]
    public void ParseDatFile_NoahV2ProducesHl7Version251()
    {
        SetupPathHelper();

        var fields = MakeNoahV2Fields();
        fields[10] = "Johnson";

        var messages = ParseSingleLine(fields);
        Assert.Contains("|2.5.1", messages[0].RawContent);
    }

    #endregion

    #region HL7 escape handling

    [Fact]
    public void ParseDatFile_EscapesSpecialCharsInHl7Output()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "O'Brien & Sons";   // ampersand
        fields[10] = "Mary~Jane";        // tilde (HL7 repetition separator)
        fields[3] = "Lab^Name";          // caret (HL7 component separator)

        var messages = ParseSingleLine(fields);
        var hl7 = messages[0].RawContent;

        // Ampersand escaped to \T\
        Assert.Contains("O'Brien \\T\\ Sons", hl7);
        // Tilde escaped to \R\
        Assert.Contains("Mary\\R\\Jane", hl7);
        // Caret escaped to \S\
        Assert.Contains("Lab\\S\\Name", hl7);
    }

    [Fact]
    public void ParseDatFile_EscapedPipeInSourcePreservedInHl7()
    {
        SetupPathHelper();

        // Build a raw line with an escaped pipe (\|) in the last name field (pos 10, index 9)
        // Must construct the raw line manually since array-based join can't represent this
        var fields = MakeV22Fields();
        fields[9] = "PLACEHOLDER";
        var line = JoinFields(fields);
        // Replace PLACEHOLDER with a value containing an escaped pipe
        line = line.Replace("PLACEHOLDER", "Smith\\|Jones");

        var messages = ParseContent(line);
        var hl7 = messages[0].RawContent;

        // SplitEpathLine unescapes \| to |, then HL7 escaper converts | to \F\
        Assert.Contains("Smith\\F\\Jones", hl7);
    }

    #endregion

    #region MSH segment

    [Fact]
    public void ParseDatFile_MshContainsFacilityAndClia()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[2] = "99D5551234";
        fields[3] = "Acme Pathology";
        fields[62] = "20240615143000";
        fields[64] = "MSG-CTRL-001";
        fields[65] = "P";

        var messages = ParseSingleLine(fields);
        var msh = messages[0].Segments["MSH"][0];

        Assert.StartsWith("MSH|^~\\&|EPATH|", msh);
        Assert.Contains("Acme Pathology", msh);
        Assert.Contains("99D5551234", msh);
        Assert.Contains("20240615143000", msh);
        Assert.Contains("MSG-CTRL-001", msh);
        Assert.Contains("ORU^R01", msh);
    }

    #endregion

    #region PID segment

    [Fact]
    public void ParseDatFile_PidContainsFullPatientData()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Doe";           // Last
        fields[10] = "John";         // First
        fields[11] = "Q";            // Middle
        fields[12] = "123 Oak St";   // Street
        fields[13] = "Springfield";  // City
        fields[14] = "IL";           // State
        fields[15] = "62704";        // Zip
        fields[16] = "2175551234";   // Phone
        fields[17] = "19750815";     // DOB
        fields[19] = "999887777";    // SSN
        fields[20] = "M";            // Sex
        fields[21] = "MRN-42";       // MRN
        fields[66] = "2";            // Race (pos 67)
        fields[77] = "1";            // Ethnicity (pos 78)
        fields[78] = "M";            // Marital (pos 79)

        var messages = ParseSingleLine(fields);
        var pid = messages[0].Segments["PID"][0];

        Assert.Contains("Doe^John^Q", pid);
        Assert.Contains("19750815", pid);
        Assert.Contains("MRN-42", pid);
        Assert.Contains("123 Oak St", pid);
        Assert.Contains("Springfield", pid);
        Assert.Contains("IL", pid);
        Assert.Contains("62704", pid);
        Assert.Contains("2175551234", pid);
        Assert.Contains("999887777", pid);
    }

    #endregion

    #region PV1 segment

    [Fact]
    public void ParseDatFile_Pv1PresentWhenPhysiciansProvided()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[68] = "LIC001";  // Physician Managing (pos 69)
        fields[69] = "LIC002";  // Physician Follow-up (pos 70)
        fields[81] = "LIC003";  // Physician Surgeon (pos 82)

        var messages = ParseSingleLine(fields);

        Assert.True(messages[0].Segments.ContainsKey("PV1"));
        var pv1 = messages[0].Segments["PV1"][0];
        Assert.Contains("LIC001", pv1);
        Assert.Contains("LIC003", pv1);
        Assert.Contains("LIC002", pv1);
    }

    [Fact]
    public void ParseDatFile_Pv1OmittedWhenNoPhysicians()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[9] = "Smith"; // just patient data, no physicians

        var messages = ParseSingleLine(fields);

        Assert.False(messages[0].Segments.ContainsKey("PV1"));
    }

    #endregion

    #region ORC segment (ordering facility)

    [Fact]
    public void ParseDatFile_OrcContainsOrderingFacilityData()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[32] = "FAC001";        // Ordering Fac No (pos 33)
        fields[33] = "City Hospital"; // Ordering Fac Name (pos 34)
        fields[34] = "456 Elm Ave";   // Ordering Fac Street (pos 35)
        fields[35] = "Chicago";       // Ordering Fac City (pos 36)
        fields[36] = "IL";            // Ordering Fac State (pos 37)
        fields[37] = "60601";         // Ordering Fac Zip (pos 38)

        var messages = ParseSingleLine(fields);
        var orc = messages[0].Segments["ORC"][0];

        Assert.Contains("City Hospital", orc);
        Assert.Contains("FAC001", orc);
        Assert.Contains("456 Elm Ave", orc);
        Assert.Contains("Chicago", orc);
        Assert.Contains("60601", orc);
    }

    #endregion

    #region OBR segment

    [Fact]
    public void ParseDatFile_ObrContainsPathologistAndOrderingProvider()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[22] = "ACC-001";        // Accession (pos 23)
        fields[23] = "LIC-ORD";        // Ordering Physician Lic (pos 24)
        fields[24] = "OrderLast";      // Ordering Last (pos 25)
        fields[25] = "OrderFirst";     // Ordering First (pos 26)
        fields[39] = "PathLast";       // Pathologist Last (pos 40)
        fields[40] = "PathFirst";      // Pathologist First (pos 41)
        fields[43] = "PATH-LIC";       // Pathologist Lic (pos 44)
        fields[44] = "IL";             // Pathologist Lic State (pos 45)
        fields[45] = "20240301080000"; // Collection Date (pos 46)
        fields[82] = "20240302";       // Specimen Received Date (pos 83)

        var messages = ParseSingleLine(fields);
        var obr = messages[0].Segments["OBR"][0];

        Assert.Contains("ACC-001", obr);
        Assert.Contains("LIC-ORD", obr);
        Assert.Contains("OrderLast", obr);
        Assert.Contains("OrderFirst", obr);
        Assert.Contains("PathLast", obr);
        Assert.Contains("PathFirst", obr);
        Assert.Contains("PATH-LIC", obr);
        Assert.Contains("20240301080000", obr);
    }

    [Fact]
    public void ParseDatFile_OrderingProviderDisplayBuiltCorrectly()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[23] = "LIC-999";     // License (pos 24)
        fields[24] = "Williams";    // Last (pos 25)
        fields[25] = "Robert";      // First (pos 26)

        var messages = ParseSingleLine(fields);

        Assert.Equal("LIC-999 - Williams, Robert", messages[0].OrderingProvider);
    }

    #endregion

    #region OBX segments — text fields

    [Fact]
    public void ParseDatFile_TextFieldsCreateSeparateObxSegments()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[53] = "Text diagnosis content";     // Path Text Diagnosis (pos 54)
        fields[54] = "Patient history";              // Clinical History (pos 55)
        fields[55] = "Skin, left arm";               // Nature of Specimen (pos 56)
        fields[56] = "3.2 cm tissue fragment";       // Gross Pathology (pos 57)
        fields[57] = "Invasive ductal carcinoma";    // Micro Pathology (pos 58)
        fields[58] = "FINAL: Invasive carcinoma";    // Final Diagnosis (pos 59)
        fields[59] = "Comment about specimen";       // Comment (pos 60)
        fields[60] = "Supplemental info";            // Supplemental Reports (pos 61)
        fields[61] = "Stage IIA";                    // Text Staging (pos 62)

        var messages = ParseSingleLine(fields);
        var obxSegments = messages[0].Segments["OBX"];

        // Should have 9 text OBX segments
        Assert.True(obxSegments.Count >= 9);

        var hl7 = messages[0].RawContent;
        Assert.Contains("PATH_DX^Path Text Diagnosis", hl7);
        Assert.Contains("CLIN_HX^Clinical History", hl7);
        Assert.Contains("SPECIMEN^Nature of Specimen", hl7);
        Assert.Contains("GROSS^Gross Pathology", hl7);
        Assert.Contains("MICRO^Micro Pathology", hl7);
        Assert.Contains("FINAL_DX^Final Diagnosis", hl7);
        Assert.Contains("COMMENT^Comment Section", hl7);
        Assert.Contains("SUPPL^Supplemental Reports", hl7);
        Assert.Contains("STAGING^Text Staging", hl7);
    }

    [Fact]
    public void ParseDatFile_EmptyTextFieldsOmitted()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[58] = "Only final diagnosis present"; // Final Diagnosis (pos 59)

        var messages = ParseSingleLine(fields);
        var hl7 = messages[0].RawContent;

        // Only Final Diagnosis OBX should exist for text fields
        Assert.Contains("FINAL_DX^Final Diagnosis", hl7);
        Assert.DoesNotContain("PATH_DX^Path Text Diagnosis", hl7);
        Assert.DoesNotContain("CLIN_HX^Clinical History", hl7);
        Assert.DoesNotContain("GROSS^Gross Pathology", hl7);
    }

    #endregion

    #region OBX segments — code fields

    [Fact]
    public void ParseDatFile_SnomedIcdCptCodesCreateObxSegments()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[47] = "M8500/3";     // SNOMED (pos 48)
        fields[48] = "20240101";    // SNOMED Version (pos 49)
        fields[49] = "C50.911";     // ICD-CM (pos 50)
        fields[50] = "10";          // ICD Version (pos 51)
        fields[51] = "88305";       // CPT (pos 52)
        fields[52] = "2024";        // CPT Version (pos 53)

        var messages = ParseSingleLine(fields);
        var hl7 = messages[0].RawContent;

        Assert.Contains("SNOMED^SNOMED CT Code", hl7);
        Assert.Contains("M8500/3", hl7);
        Assert.Contains("ICD^ICD-CM Code", hl7);
        Assert.Contains("C50.911", hl7);
        Assert.Contains("CPT^CPT Code", hl7);
        Assert.Contains("88305", hl7);
    }

    [Fact]
    public void ParseDatFile_AgeAndUnitsCreateObxSegment()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[18] = "057";   // Age (pos 19)
        fields[71] = "yr";    // Age Units (pos 72)

        var messages = ParseSingleLine(fields);
        var hl7 = messages[0].RawContent;

        Assert.Contains("AGE^Patient Age at Specimen||057|yr", hl7);
    }

    [Fact]
    public void ParseDatFile_ProducerIdCreateObxSegment()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[83] = "99D0001111"; // Producer ID CLIA (pos 84)

        var messages = ParseSingleLine(fields);
        var hl7 = messages[0].RawContent;

        Assert.Contains("PRODUCER^Producer ID (CLIA)||99D0001111", hl7);
    }

    #endregion

    #region Large text fields

    [Fact]
    public void ParseDatFile_LargeTextFieldPreserved()
    {
        SetupPathHelper();

        // Simulate a large Final Diagnosis field (5000 chars)
        var largeText = new string('X', 5000);
        var fields = MakeV22Fields();
        fields[58] = largeText; // Final Diagnosis (pos 59)

        var messages = ParseSingleLine(fields);
        var hl7 = messages[0].RawContent;

        Assert.Contains(largeText, hl7);
    }

    #endregion

    #region NOAH v2 auto-detection

    [Fact]
    public void ParseDatFile_AutoDetectsNoahV2Format()
    {
        SetupPathHelper();

        var fields = MakeNoahV2Fields();
        fields[0] = "V2";
        fields[2] = "99D9999999";
        fields[3] = "Noah Lab";
        fields[10] = "Johnson";
        fields[11] = "Bob";
        fields[15] = "MRN-NOAH";
        fields[19] = "19900101";
        fields[21] = "M";
        fields[65] = "NOAH-SP-001";
        fields[91] = "Final Diagnosis: Melanoma";

        var messages = ParseSingleLine(fields);

        Assert.Single(messages);
        var msg = messages[0];

        Assert.Equal("Johnson", msg.PatientLastName);
        Assert.Equal("Bob", msg.PatientFirstName);
        Assert.Equal("MRN-NOAH", msg.PatientId);
        Assert.Equal("19900101", msg.DateOfBirth);
        Assert.Equal("M", msg.Sex);
        Assert.Equal("NOAH-SP-001", msg.AccessionNumber);
        Assert.Contains("Johnson^Bob", msg.RawContent);
        Assert.Contains("FINAL_DX^Final Diagnosis", msg.RawContent);
    }

    [Fact]
    public void ParseDatFile_NoahV2SameItemNumbersMappedCorrectly()
    {
        SetupPathHelper();

        // Verify fields that exist in both formats but at different positions
        // map to the same NAACCR items and produce the same HL7 output
        var v22 = MakeV22Fields();
        v22[9] = "Smith";          // Last Name (v2.2 pos 10, item 2230)
        v22[21] = "MRN-V22";       // MRN (v2.2 pos 22, item 2300)

        var noah = MakeNoahV2Fields();
        noah[10] = "Smith";         // Last Name (NOAH pos 11, item 2230)
        noah[15] = "MRN-NOAH";      // MRN (NOAH pos 16, item 2300)

        var v22Msgs = ParseSingleLine(v22);
        var noahMsgs = ParseSingleLine(noah);

        // Both should produce PID with "Smith" as last name
        Assert.Equal("Smith", v22Msgs[0].PatientLastName);
        Assert.Equal("Smith", noahMsgs[0].PatientLastName);
    }

    #endregion

    #region SendingFacility property

    [Fact]
    public void ParseDatFile_SendingFacilityCombinesNameAndClia()
    {
        SetupPathHelper();

        var fields = MakeV22Fields();
        fields[2] = "99D1234567";
        fields[3] = "Metro Path Lab";

        var messages = ParseSingleLine(fields);

        Assert.Equal("Metro Path Lab^99D1234567", messages[0].SendingFacility);
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

    private static List<Parrat.Core.Models.Hl7Message> ParseSingleLine(string[] fields)
    {
        var line = JoinFields(fields);
        return ParseContent(line);
    }

    private static List<Parrat.Core.Models.Hl7Message> ParseContent(string content)
    {
        var tempPath = Path.Combine(Path.GetTempPath(), $"test_epath_{Guid.NewGuid()}.dat");
        try
        {
            File.WriteAllText(tempPath, content);
            var parser = new EpathParserService();
            return parser.ParseDatFile(tempPath);
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
