using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class Hl7ParserTests
{
    private readonly Hl7Parser _parser = new();

    #region GetField

    [Fact]
    public void GetField_ReturnsFieldAtGivenIndex()
    {
        var segment = "MSH|^~\\&|SendApp|SendFac|RecvApp|RecvFac|20240101120000";
        Assert.Equal("SendApp", _parser.GetField(segment, 2));
    }

    [Fact]
    public void GetField_ReturnsEmptyForOutOfRangeIndex()
    {
        Assert.Equal("", _parser.GetField("PID|1|123", 99));
    }

    [Fact]
    public void GetField_ReturnsEmptyForNullSegment()
    {
        Assert.Equal("", _parser.GetField(null!, 0));
    }

    [Fact]
    public void GetField_ReturnsEmptyForWhitespaceSegment()
    {
        Assert.Equal("", _parser.GetField("   ", 0));
    }

    [Fact]
    public void GetField_ReturnsSegmentNameAtIndex0()
    {
        Assert.Equal("OBX", _parser.GetField("OBX|1|TX|CODE^Text", 0));
    }

    #endregion

    #region GetComponent

    [Fact]
    public void GetComponent_ReturnsComponentAtGivenIndex()
    {
        Assert.Equal("John", _parser.GetComponent("Smith^John^M", 1));
    }

    [Fact]
    public void GetComponent_ReturnsEmptyForOutOfRangeIndex()
    {
        Assert.Equal("", _parser.GetComponent("Smith^John", 5));
    }

    [Fact]
    public void GetComponent_ReturnsEmptyForNullField()
    {
        Assert.Equal("", _parser.GetComponent(null!, 0));
    }

    [Fact]
    public void GetComponent_ReturnsFirstComponentAtIndex0()
    {
        Assert.Equal("CODE", _parser.GetComponent("CODE^Description^System", 0));
    }

    [Fact]
    public void GetComponent_HandlesSingleComponentFields()
    {
        Assert.Equal("OnlyValue", _parser.GetComponent("OnlyValue", 0));
    }

    #endregion

    #region ParseMsh

    [Fact]
    public void ParseMsh_ParsesFullMshSegment()
    {
        var msh = "MSH|^~\\&|SendApp|SendFac|RecvApp|RecvFac|20240115143022||ORU^R01|MSG001|P|2.5";
        var result = _parser.ParseMsh(msh);

        Assert.Equal("SendApp", result.SendingApplication);
        Assert.Equal("SendFac", result.SendingFacility);
        Assert.Equal("20240115143022", result.MessageDateTime);
        Assert.Equal("ORU^R01", result.MessageType);
        Assert.Equal("MSG001", result.MessageControlId);
    }

    [Fact]
    public void ParseMsh_HandlesMinimalMshWithFewFields()
    {
        var result = _parser.ParseMsh("MSH|^~\\&");
        Assert.Equal("", result.SendingApplication);
        Assert.Equal("", result.SendingFacility);
    }

    [Fact]
    public void ParseMsh_HandlesEmptyString()
    {
        var result = _parser.ParseMsh("");
        Assert.Equal("", result.SendingApplication);
    }

    #endregion

    #region ParsePid

    [Fact]
    public void ParsePid_ParsesPatientNameWithFirstLastAndMiddle()
    {
        var pid = "PID|1||12345||Smith^John^M||19800215|M";
        var result = _parser.ParsePid(pid);

        Assert.Equal("12345", result.PatientId);
        Assert.Equal("Smith", result.LastName);
        Assert.Equal("John", result.FirstName);
        Assert.Equal("M", result.MiddleName);
        Assert.Equal("Smith, John M", result.PatientName);
        Assert.Equal("19800215", result.DateOfBirth);
        Assert.Equal("M", result.Sex);
    }

    [Fact]
    public void ParsePid_ParsesPatientNameWithoutMiddleName()
    {
        var pid = "PID|1||12345||Doe^Jane||19900101|F";
        var result = _parser.ParsePid(pid);

        Assert.Equal("Doe, Jane", result.PatientName);
        Assert.Equal("", result.MiddleName);
    }

    [Fact]
    public void ParsePid_HandlesEmptyPidSegment()
    {
        var result = _parser.ParsePid("");
        Assert.Equal("", result.PatientId);
        Assert.Equal("", result.LastName);
        Assert.Equal("", result.FirstName);
    }

    [Fact]
    public void ParsePid_HandlesPidWithMissingNameField()
    {
        var result = _parser.ParsePid("PID|1||99999");
        Assert.Equal("99999", result.PatientId);
        Assert.Equal("", result.LastName);
    }

    #endregion

    #region ParseObr

    [Fact]
    public void ParseObr_ParsesOrderingProviderWithId()
    {
        var obr = "OBR|1|ORD001|FILL001|PROC001||20240101|20240102|||||||||1234^Jones^Mary";
        var result = _parser.ParseObr(obr);

        Assert.Equal("20240102", result.OrderDateTime);
        Assert.Contains("Jones", result.OrderingProvider);
        Assert.Contains("Mary", result.OrderingProvider);
        Assert.Contains("1234", result.OrderingProvider);
    }

    [Fact]
    public void ParseObr_HandlesEmptyObrSegment()
    {
        var result = _parser.ParseObr("");
        Assert.Equal("", result.OrderDateTime);
    }

    [Fact]
    public void ParseObr_HandlesObrWithFewFields()
    {
        var result = _parser.ParseObr("OBR|1");
        Assert.Equal("", result.OrderDateTime);
        Assert.Equal("", result.AccessionNumber);
    }

    [Fact]
    public void ParseObr_ExtractsAccessionNumberFromField3()
    {
        var obr = "OBR|1|ORD001|PATH-2024-001|88305^Surgical Pathology|||20240101";
        var result = _parser.ParseObr(obr);

        Assert.Equal("PATH-2024-001", result.AccessionNumber);
    }

    [Fact]
    public void ParseObr_AccessionNumberIsEmptyWhenFieldMissing()
    {
        var obr = "OBR|1||";
        var result = _parser.ParseObr(obr);

        Assert.Equal("", result.AccessionNumber);
    }

    [Fact]
    public void Parse_MapsAccessionNumberToHl7Message()
    {
        var hl7 = "MSH|^~\\&|App|Fac||Recv|20240101||ORU^R01|MSG1|P|2.3\r" +
                  "PID|||PAT1||Smith^John||19800101|M\r" +
                  "OBR|1||SP-2024-555|88305|||20240101\r" +
                  "OBX|1|TX|Path||Test text||||||F\r";

        var messages = _parser.Parse(hl7);

        Assert.Single(messages);
        Assert.Equal("SP-2024-555", messages[0].AccessionNumber);
    }

    #endregion

    #region ParseObx

    [Fact]
    public void ParseObx_ParsesMultipleObxSegments()
    {
        var obxSegments = new List<string>
        {
            "OBX|1|TX|CODE1^Description1||Value1|units1|ref1|N",
            "OBX|2|NM|CODE2^Description2||42|mg/dL|10-50|"
        };
        var result = _parser.ParseObx(obxSegments);

        Assert.Equal(2, result.Count);
        Assert.Equal("1", result[0].SetId);
        Assert.Equal("TX", result[0].ValueType);
        Assert.Equal("CODE1^Description1", result[0].ObservationId);
        Assert.Equal("Value1", result[0].ObservationValue);
        Assert.Equal("units1", result[0].Units);
        Assert.Equal("42", result[1].ObservationValue);
        Assert.Equal("mg/dL", result[1].Units);
    }

    [Fact]
    public void ParseObx_HandlesEmptyArray()
    {
        var result = _parser.ParseObx(new List<string>());
        Assert.Empty(result);
    }

    #endregion

    #region FormatDateTime

    [Fact]
    public void FormatDateTime_FormatsFullDateTime()
    {
        Assert.Equal("2024-01-15 14:30:22", _parser.FormatDateTime("20240115143022"));
    }

    [Fact]
    public void FormatDateTime_FormatsDateOnly()
    {
        Assert.Equal("2024-01-15", _parser.FormatDateTime("20240115"));
    }

    [Fact]
    public void FormatDateTime_ReturnsEmptyForNull()
    {
        Assert.Equal("", _parser.FormatDateTime(null!));
    }

    [Fact]
    public void FormatDateTime_ReturnsEmptyForWhitespace()
    {
        Assert.Equal("", _parser.FormatDateTime("   "));
    }

    [Fact]
    public void FormatDateTime_ReturnsOriginalForShortStrings()
    {
        Assert.Equal("2024", _parser.FormatDateTime("2024"));
    }

    #endregion

    #region GetObxTextContent

    [Fact]
    public void GetObxTextContent_CombinesObx5ValuesWithCrlf()
    {
        var segments = new List<string>
        {
            "OBX|1|TX|RPT||Line one|||",
            "OBX|2|TX|RPT||Line two|||"
        };
        Assert.Equal("Line one\r\nLine two", _parser.GetObxTextContent(segments));
    }

    [Fact]
    public void GetObxTextContent_SkipsEmptyObx5()
    {
        var segments = new List<string>
        {
            "OBX|1|TX|RPT||Text here|||",
            "OBX|2|TX|RPT|||||",
            "OBX|3|TX|RPT||More text|||"
        };
        Assert.Equal("Text here\r\nMore text", _parser.GetObxTextContent(segments));
    }

    [Fact]
    public void GetObxTextContent_ReturnsEmptyForNull()
    {
        Assert.Equal("", _parser.GetObxTextContent(null!));
    }

    [Fact]
    public void GetObxTextContent_ReturnsEmptyForEmptyList()
    {
        Assert.Equal("", _parser.GetObxTextContent(new List<string>()));
    }

    [Fact]
    public void GetObxTextContent_HandlesHl7EscapeSequences()
    {
        var segments = new List<string> { "OBX|1|TX|RPT||Text\\F\\with\\S\\escapes|||" };
        Assert.Equal("Text|with^escapes", _parser.GetObxTextContent(segments));
    }

    [Fact]
    public void GetObxTextContent_HandlesBackslashEscape()
    {
        var segments = new List<string> { "OBX|1|TX|RPT||path\\E\\file|||" };
        Assert.Equal("path\\file", _parser.GetObxTextContent(segments));
    }

    [Fact]
    public void GetObxTextContent_HandlesAmpersandEscape()
    {
        var segments = new List<string> { "OBX|1|TX|RPT||A\\T\\B|||" };
        Assert.Equal("A&B", _parser.GetObxTextContent(segments));
    }

    [Fact]
    public void GetObxTextContent_HandlesTildeEscape()
    {
        var segments = new List<string> { "OBX|1|TX|RPT||A\\R\\B|||" };
        Assert.Equal("A~B", _parser.GetObxTextContent(segments));
    }

    #endregion

    #region GetObx3Component1

    [Fact]
    public void GetObx3Component1_ExtractsFirstComponent()
    {
        Assert.Equal("PATHREPORT", _parser.GetObx3Component1("OBX|1|TX|PATHREPORT^Pathology Report||text|||"));
    }

    [Fact]
    public void GetObx3Component1_ReturnsEmptyForNull()
    {
        Assert.Equal("", _parser.GetObx3Component1(null!));
    }

    [Fact]
    public void GetObx3Component1_ReturnsEmptyForWhitespace()
    {
        Assert.Equal("", _parser.GetObx3Component1("   "));
    }

    [Fact]
    public void GetObx3Component1_ReturnsEmptyWhenFewerThan4Fields()
    {
        Assert.Equal("", _parser.GetObx3Component1("OBX|1|TX"));
    }

    [Fact]
    public void GetObx3Component1_ReturnsEmptyWhenObx3IsEmpty()
    {
        Assert.Equal("", _parser.GetObx3Component1("OBX|1|TX||sub|value"));
    }

    [Fact]
    public void GetObx3Component1_HandlesNoCaret()
    {
        Assert.Equal("SIMPLECODE", _parser.GetObx3Component1("OBX|1|TX|SIMPLECODE||value|||"));
    }

    #endregion

    #region SelectObxSegments

    [Fact]
    public void SelectObxSegments_FiltersOutMatchingSkipCodes()
    {
        var segments = new List<string>
        {
            "OBX|1|TX|KEEP^Text||val1|||",
            "OBX|2|TX|SKIP^Text||val2|||",
            "OBX|3|TX|KEEP2^Text||val3|||"
        };
        var result = _parser.SelectObxSegments(segments, new List<string> { "SKIP" });

        Assert.Equal(2, result.Count);
        Assert.Contains("KEEP", result[0]);
        Assert.Contains("KEEP2", result[1]);
    }

    [Fact]
    public void SelectObxSegments_IsCaseInsensitive()
    {
        var segments = new List<string> { "OBX|1|TX|MyCode^Text||val|||" };
        var result = _parser.SelectObxSegments(segments, new List<string> { "mycode" });
        Assert.Empty(result);
    }

    [Fact]
    public void SelectObxSegments_ReturnsAllWhenSkipCodesEmpty()
    {
        var segments = new List<string>
        {
            "OBX|1|TX|CODE1^Text||val|||",
            "OBX|2|TX|CODE2^Text||val|||"
        };
        var result = _parser.SelectObxSegments(segments, new List<string>());
        Assert.Equal(2, result.Count);
    }

    [Fact]
    public void SelectObxSegments_ReturnsEmptyForNullInput()
    {
        var result = _parser.SelectObxSegments(null!, new List<string> { "CODE" });
        Assert.Empty(result);
    }

    [Fact]
    public void SelectObxSegments_ReturnsAllWhenSkipCodesNull()
    {
        var segments = new List<string> { "OBX|1|TX|CODE^Text||val|||" };
        var result = _parser.SelectObxSegments(segments, null!);
        Assert.Single(result);
    }

    #endregion

    #region GetFilteredObxTextContent

    [Fact]
    public void GetFilteredObxTextContent_CombinesFilteringAndExtraction()
    {
        var segments = new List<string>
        {
            "OBX|1|TX|RPT^Report||Report text|||",
            "OBX|2|TX|HEADER^Header||Header text|||",
            "OBX|3|TX|RPT^Report||More report|||"
        };
        var result = _parser.GetFilteredObxTextContent(segments, new List<string> { "HEADER" });
        Assert.Equal("Report text\r\nMore report", result);
    }

    #endregion

    #region Parse (full message parsing)

    [Fact]
    public void Parse_ParsesSingleHl7Message()
    {
        var content = "MSH|^~\\&|SendApp|SendFac|||20240115143022||ORU^R01|MSG001|P|2.5\nPID|1||12345||Smith^John^M||19800215|M\nOBR|1|ORD001|FILL001|PROC001\nOBX|1|TX|RPT^Report||Test result|||";
        var messages = _parser.Parse(content);

        Assert.Single(messages);
        Assert.Equal("12345", messages[0].PatientId);
        Assert.Equal("Smith", messages[0].PatientLastName);
        Assert.Equal("John", messages[0].PatientFirstName);
        Assert.Equal("ORU^R01", messages[0].MessageType);
        Assert.Equal("SendApp", messages[0].SendingApplication);
        Assert.Equal("SendFac", messages[0].SendingFacility);
    }

    [Fact]
    public void Parse_ParsesMultipleMessages()
    {
        var content = "MSH|^~\\&|App1|Fac1|||20240101||ORU^R01|M1|P|2.5\nPID|1||111||Alpha^First||19900101|F\n\nMSH|^~\\&|App2|Fac2|||20240102||ORU^R01|M2|P|2.5\nPID|1||222||Beta^Second||19850601|M";
        var messages = _parser.Parse(content);

        Assert.Equal(2, messages.Count);
        Assert.Equal("Alpha", messages[0].PatientLastName);
        Assert.Equal("Beta", messages[1].PatientLastName);
    }

    [Fact]
    public void Parse_HandlesCrlfLineEndings()
    {
        var content = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|M1|P|2.5\r\nPID|1||123||Test^Patient||19900101|M";
        var messages = _parser.Parse(content);

        Assert.Single(messages);
        Assert.Equal("Test", messages[0].PatientLastName);
    }

    [Fact]
    public void Parse_SkipsBlankLinesBetweenSegments()
    {
        var content = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|M1|P|2.5\n\nPID|1||123||Test^Patient||19900101|M\n\nOBR|1|ORD1||PROC1";
        var messages = _parser.Parse(content);

        Assert.Single(messages);
        Assert.True(messages[0].Segments.ContainsKey("PID"),
            "Segments dictionary should contain 'PID' after parsing message with blank lines between segments");
        Assert.True(messages[0].Segments.ContainsKey("OBR"),
            "Segments dictionary should contain 'OBR' after parsing message with blank lines between segments");
    }

    [Fact]
    public void Parse_ReturnsEmptyForEmptyContent()
    {
        Assert.Empty(_parser.Parse(""));
    }

    [Fact]
    public void Parse_AssignsSequentialIndexStartingAt0()
    {
        var content = "MSH|^~\\&|A|B|||20240101||ORU^R01|1|P|2.5\nPID|1||1||A^B||19900101|M\nMSH|^~\\&|A|B|||20240102||ORU^R01|2|P|2.5\nPID|1||2||C^D||19900101|F";
        var messages = _parser.Parse(content);

        Assert.Equal(0, messages[0].Index);
        Assert.Equal(1, messages[1].Index);
    }

    #endregion

    #region Batch envelope (FHS/BHS/BTS/FTS)

    [Fact]
    public void Parse_BatchWrappedFile_ExcludesEnvelopeFromMessages()
    {
        var content = "FHS|^~\\&|App|Fac|||20240101\n" +
                      "BHS|^~\\&|App|Fac|||20240101\n" +
                      "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n" +
                      "PID|1||123||Test^Patient||19900101|M\n" +
                      "BTS|1\n" +
                      "FTS|1";

        var messages = _parser.Parse(content);

        Assert.Single(messages);
        Assert.False(messages[0].Segments.ContainsKey("BTS"),
            "Batch trailer must not be absorbed into the last message");
        Assert.False(messages[0].Segments.ContainsKey("FTS"),
            "File trailer must not be absorbed into the last message");
        Assert.DoesNotContain("BTS|", messages[0].RawContent);
        Assert.DoesNotContain("FTS|", messages[0].RawContent);
        Assert.Equal(2, messages[0].AllSegments.Count);
    }

    [Fact]
    public void Parse_MultipleBatches_ParsesEveryMessage()
    {
        var content = "FHS|^~\\&|App|Fac\n" +
                      "BHS|^~\\&|App|Fac\n" +
                      "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n" +
                      "PID|1||123||Test^Patient||19900101|M\n" +
                      "BTS|1\n" +
                      "BHS|^~\\&|App|Fac\n" +
                      "MSH|^~\\&|App|Fac|||20240102||ORU^R01|2|P|2.5.1\n" +
                      "PID|1||456||Other^Patient||19850101|F\n" +
                      "BTS|1\n" +
                      "FTS|2";

        var messages = _parser.Parse(content);

        Assert.Equal(2, messages.Count);
        Assert.Equal("123", messages[0].PatientId);
        Assert.Equal("456", messages[1].PatientId);
        Assert.All(messages, m => Assert.Equal(2, m.AllSegments.Count));
    }

    [Fact]
    public void Parse_ObxNarrativeResemblingTrailer_IsPreserved()
    {
        // OBX text that happens to start with an envelope identifier must survive.
        var content = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|1|P|2.5.1\n" +
                      "PID|1||123||Test^Patient||19900101|M\n" +
                      "OBX|1|TX|PATH_DX||FTS was noted in the specimen||||||F";

        var messages = _parser.Parse(content);

        Assert.Single(messages);
        Assert.True(messages[0].Segments.ContainsKey("OBX"));
        Assert.Contains("FTS was noted", messages[0].RawContent);
    }

    #endregion
}
