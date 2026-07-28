using System.Xml;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class FilterServiceTests
{
    private const string Ns = "http://naaccr.org/naaccrxml";

    private readonly FilterService _service = new();

    #region Fixtures

    // Two patients, four tumors. Sex and nameLast are patient level, registryId
    // is file level, so a filter on any of them must resolve from a tumor row.
    private const string Doc = $@"
<NaaccrData xmlns=""{Ns}"" recordType=""I"">
  <Item naaccrId=""registryId"">0000001234</Item>
  <Patient>
    <Item naaccrId=""patientIdNumber"">00001</Item>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Item naaccrId=""sex"">2</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C509</Item>
      <Item naaccrId=""dateOfDiagnosis"">20260315</Item>
    </Tumor>
    <Tumor>
      <Item naaccrId=""primarySite"">C502</Item>
      <Item naaccrId=""dateOfDiagnosis"">20251120</Item>
    </Tumor>
  </Patient>
  <Patient>
    <Item naaccrId=""patientIdNumber"">00002</Item>
    <Item naaccrId=""nameLast"">Jones</Item>
    <Item naaccrId=""sex"">1</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C619</Item>
      <Item naaccrId=""dateOfDiagnosis"">20260701</Item>
    </Tumor>
    <Tumor>
      <Item naaccrId=""primarySite"">C341</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var doc = new XmlDocument { XmlResolver = null };
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", doc.DocumentElement!.NamespaceURI);
        return (doc.SelectNodes("//n:Tumor", nsMgr)!, nsMgr);
    }

    /// <summary>Levels for the fields these tests filter on.</summary>
    private static string LevelOf(string fieldId) => fieldId switch
    {
        "registryId" => "NaaccrData",
        "patientIdNumber" or "nameLast" or "sex" => "Patient",
        _ => "Tumor"
    };

    private static XmlFilterFieldSource XmlSource(FilterDefinition filter, XmlNodeList tumors)
    {
        var fields = new FilterService().GetReferencedFields(filter);
        return new XmlFilterFieldSource(tumors, fields, LevelOf);
    }

    private static FilterDefinition XmlFilter(params FilterCondition[] conditions)
    {
        var filter = new FilterDefinition { FileType = "xml" };
        filter.Conditions.AddRange(conditions);
        return filter;
    }

    private static FilterCondition Condition(
        string fieldId, FilterOperator op, string value = "", string value2 = "",
        FieldPart part = FieldPart.Whole, FilterConjunction conjunction = FilterConjunction.And) =>
        new()
        {
            FieldId = fieldId,
            Operator = op,
            Value = value,
            Value2 = value2,
            Part = part,
            Conjunction = conjunction
        };

    // Three messages: two ORU with orders (2026 and 2025), one ADT with no OBR
    // at all so the "field is missing" case is covered.
    private const string Hl7Batch =
        "MSH|^~\\&|LAB|MAIN|EMR|HOSP|20260115120000||ORU^R01|1|P|2.3\n"
        + "PID|1||MRN001||Smith^Jane||19800215|F\n"
        + "OBR|1||ACC001|TISSUE|||20260114080000\n"
        + "MSH|^~\\&|LAB|MAIN|EMR|HOSP|20250210120000||ORU^R01|2|P|2.3\n"
        + "PID|1||MRN002||Jones^Bob||19751130|M\n"
        + "OBR|1||ACC002|TISSUE|||20250209080000\n"
        + "MSH|^~\\&|LAB|SAT|EMR|HOSP|20260320120000||ADT^A08|3|P|2.3\n"
        + "PID|1||MRN003||Brown^Ann||19801205|F\n";

    private static List<Hl7Message> BuildMessages() => new Hl7Parser().Parse(Hl7Batch);

    #endregion

    #region Empty and degenerate filters

    [Fact]
    public void GetMatchingIndices_EmptyFilterMatchesEveryRecord()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter();

        Assert.Equal(new[] { 0, 1, 2, 3 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_NullFilterMatchesEveryRecord()
    {
        var (tumors, _) = LoadTumors(Doc);

        Assert.Equal(new[] { 0, 1, 2, 3 },
            _service.GetMatchingIndices(null, new XmlFilterFieldSource(tumors, Array.Empty<string>(), LevelOf)));
    }

    [Fact]
    public void GetMatchingIndices_NullSourceReturnsNoMatches()
    {
        Assert.Empty(_service.GetMatchingIndices(XmlFilter(), null!));
    }

    [Fact]
    public void GetReferencedFields_ReturnsDistinctNonBlankFieldIds()
    {
        var filter = XmlFilter(
            Condition("primarySite", FilterOperator.Like, "C50%"),
            Condition("primarySite", FilterOperator.NotEquals, "C500"),
            Condition("", FilterOperator.IsEmpty));

        Assert.Equal(new[] { "primarySite" }, _service.GetReferencedFields(filter));
    }

    #endregion

    #region NAACCR XML

    [Fact]
    public void GetMatchingIndices_FiltersTumorLevelFieldByYear()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(Condition("dateOfDiagnosis", FilterOperator.Equals, "2026", part: FieldPart.Year));

        Assert.Equal(new[] { 0, 2 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_FiltersTumorLevelFieldByDateRange()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(
            Condition("dateOfDiagnosis", FilterOperator.Between, "20260101", "20261231"));

        Assert.Equal(new[] { 0, 2 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_ResolvesPatientLevelFieldsFromATumorRow()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(Condition("nameLast", FilterOperator.Equals, "Jones"));

        Assert.Equal(new[] { 2, 3 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_ResolvesFileLevelFieldsFromATumorRow()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(Condition("registryId", FilterOperator.Equals, "0000001234"));

        Assert.Equal(new[] { 0, 1, 2, 3 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_TreatsAnAbsentItemAsEmpty()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(Condition("dateOfDiagnosis", FilterOperator.IsEmpty));

        Assert.Equal(new[] { 3 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_TreatsAnUnknownFieldAsEmpty()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(Condition("noSuchField", FilterOperator.Equals, "anything"));

        Assert.Empty(_service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_CombinesConditionsAcrossLevelsWithAnd()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(
            Condition("sex", FilterOperator.Equals, "2"),
            Condition("primarySite", FilterOperator.Like, "C50%"));

        Assert.Equal(new[] { 0, 1 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_CombinesConditionsWithOr()
    {
        var (tumors, _) = LoadTumors(Doc);
        var filter = XmlFilter(
            Condition("primarySite", FilterOperator.Equals, "C509"),
            Condition("primarySite", FilterOperator.Equals, "C341", conjunction: FilterConjunction.Or));

        Assert.Equal(new[] { 0, 3 }, _service.GetMatchingIndices(filter, XmlSource(filter, tumors)));
    }

    [Fact]
    public void GetMatchingIndices_HandlesAnEmptyDocument()
    {
        var (tumors, _) = LoadTumors($@"<NaaccrData xmlns=""{Ns}"" recordType=""I""></NaaccrData>");
        var filter = XmlFilter(Condition("primarySite", FilterOperator.Like, "C%"));

        var source = XmlSource(filter, tumors);

        Assert.Equal(0, source.RecordCount);
        Assert.Empty(_service.GetMatchingIndices(filter, source));
    }

    [Fact]
    public void XmlFilterFieldSource_ReturnsEmptyForOutOfRangeRecords()
    {
        var (tumors, _) = LoadTumors(Doc);
        var source = new XmlFilterFieldSource(tumors, new[] { "primarySite" }, LevelOf);

        Assert.Equal("", source.GetValue(-1, "primarySite"));
        Assert.Equal("", source.GetValue(99, "primarySite"));
        Assert.Equal("C509", source.GetValue(0, "primarySite"));
    }

    [Fact]
    public void XmlFilterFieldSource_ServesRepeatedReadsOfTheSameRecord()
    {
        var (tumors, _) = LoadTumors(Doc);
        var source = new XmlFilterFieldSource(tumors, new[] { "primarySite", "nameLast" }, LevelOf);

        Assert.Equal("C509", source.GetValue(0, "primarySite"));
        Assert.Equal("Smith", source.GetValue(0, "nameLast"));
        Assert.Equal("C619", source.GetValue(2, "primarySite"));
        Assert.Equal("C509", source.GetValue(0, "primarySite"));
    }

    #endregion

    #region HL7

    private static FilterDefinition Hl7Filter(params FilterCondition[] conditions)
    {
        var filter = new FilterDefinition { FileType = "hl7" };
        filter.Conditions.AddRange(conditions);
        return filter;
    }

    [Fact]
    public void GetMatchingIndices_FiltersHl7ByBirthYear()
    {
        var source = new Hl7FilterFieldSource(BuildMessages());
        var filter = Hl7Filter(Condition("DateOfBirth", FilterOperator.Equals, "1980", part: FieldPart.Year));

        Assert.Equal(new[] { 0, 2 }, _service.GetMatchingIndices(filter, source));
    }

    [Fact]
    public void GetMatchingIndices_FiltersHl7ByMessageTypeWithLike()
    {
        var source = new Hl7FilterFieldSource(BuildMessages());
        var filter = Hl7Filter(Condition("MessageType", FilterOperator.Like, "ORU%"));

        Assert.Equal(new[] { 0, 1 }, _service.GetMatchingIndices(filter, source));
    }

    [Fact]
    public void GetMatchingIndices_FiltersHl7ByOrderDateRange()
    {
        var source = new Hl7FilterFieldSource(BuildMessages());
        var filter = Hl7Filter(Condition(
            "OrderDateTime", FilterOperator.Between, "20260101", "20261231", part: FieldPart.Date));

        Assert.Equal(new[] { 0 }, _service.GetMatchingIndices(filter, source));
    }

    [Fact]
    public void GetMatchingIndices_FiltersHl7ByMissingField()
    {
        var source = new Hl7FilterFieldSource(BuildMessages());
        var filter = Hl7Filter(Condition("AccessionNumber", FilterOperator.IsEmpty));

        Assert.Equal(new[] { 2 }, _service.GetMatchingIndices(filter, source));
    }

    [Fact]
    public void Hl7FilterFieldSource_ReturnsEmptyForUnknownFieldsAndIndices()
    {
        var source = new Hl7FilterFieldSource(BuildMessages());

        Assert.Equal("", source.GetValue(0, "primarySite"));
        Assert.Equal("", source.GetValue(99, "PatientId"));
        Assert.Equal("", source.GetValue(-1, "PatientId"));
    }

    [Fact]
    public void Hl7FilterFieldSource_HandlesANullMessageList()
    {
        var source = new Hl7FilterFieldSource(null);

        Assert.Equal(0, source.RecordCount);
        Assert.Equal("", source.GetValue(0, "PatientId"));
    }

    [Fact]
    public void Hl7FilterFieldSource_ReadsTheSourceFileNameOnly()
    {
        var messages = BuildMessages();
        messages[0].SourceFile = @"C:\reports\batch-a\report001.hl7";

        var source = new Hl7FilterFieldSource(messages);

        Assert.Equal("report001.hl7", source.GetValue(0, "SourceFile"));
        Assert.Equal("", source.GetValue(1, "SourceFile"));
    }

    #endregion
}
