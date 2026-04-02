using System.Xml;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class FacilityAssignmentServiceTests
{
    private readonly FacilityAssignmentService _service = new();
    private const string Ns = NaaccrXmlTestHelper.NaaccrNamespace;

    #region GetFacilityFromFilename

    [Fact]
    public void GetFacilityFromFilename_Extracts7DigitNumber_PaddedTo10()
    {
        var result = _service.GetFacilityFromFilename("/path/to/1234567.xml");
        Assert.Equal("0001234567", result);
    }

    [Fact]
    public void GetFacilityFromFilename_FindsNumberInMiddleOfFilename()
    {
        var result = _service.GetFacilityFromFilename("/path/to/report_1234567_v2.xml");
        Assert.Equal("0001234567", result);
    }

    [Fact]
    public void GetFacilityFromFilename_ReturnsNullWhenNoSevenDigitNumber()
    {
        Assert.Null(_service.GetFacilityFromFilename("/path/to/report.xml"));
    }

    [Fact]
    public void GetFacilityFromFilename_ReturnsNullForSixDigitNumber()
    {
        Assert.Null(_service.GetFacilityFromFilename("/path/to/123456.xml"));
    }

    [Fact]
    public void GetFacilityFromFilename_ReturnsNullForEightDigitNumber()
    {
        // 8-digit number should not match the 7-digit pattern
        Assert.Null(_service.GetFacilityFromFilename("/path/to/12345678.xml"));
    }

    [Fact]
    public void GetFacilityFromFilename_HandlesPureNumberFilename()
    {
        var result = _service.GetFacilityFromFilename("9999999.xml");
        Assert.Equal("0009999999", result);
    }

    #endregion

    #region GetFacilityAssignments

    [Fact]
    public void GetFacilityAssignments_AssignsToEmptyFacility()
    {
        var (tumors, nsMgr) = BuildTumorsWithFacility("");
        var result = _service.GetFacilityAssignments(tumors, nsMgr, "0001234567");

        Assert.Single(result);
        Assert.Equal("0001234567", result[0]);
    }

    [Fact]
    public void GetFacilityAssignments_AssignsToAllZerosFacility()
    {
        var (tumors, nsMgr) = BuildTumorsWithFacility("0000000000");
        var result = _service.GetFacilityAssignments(tumors, nsMgr, "0001234567");

        Assert.Single(result);
        Assert.Equal("0001234567", result[0]);
    }

    [Fact]
    public void GetFacilityAssignments_SkipsExistingFacility()
    {
        var (tumors, nsMgr) = BuildTumorsWithFacility("0009876543");
        var result = _service.GetFacilityAssignments(tumors, nsMgr, "0001234567");

        Assert.Empty(result);
    }

    [Fact]
    public void GetFacilityAssignments_OverwritesWhenFlagged()
    {
        var (tumors, nsMgr) = BuildTumorsWithFacility("0009876543");
        var result = _service.GetFacilityAssignments(tumors, nsMgr, "0001234567", overwriteExisting: true);

        Assert.Single(result);
        Assert.Equal("0001234567", result[0]);
    }

    [Fact]
    public void GetFacilityAssignments_AssignsToTumorWithNoFacilityElement()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Tumor>
      <Item naaccrId=""primarySite"">C509</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        var (tumors, nsMgr) = LoadTumors(xml);
        var result = _service.GetFacilityAssignments(tumors, nsMgr, "0001234567");

        Assert.Single(result);
        Assert.Equal("0001234567", result[0]);
    }

    #endregion

    #region WriteFacilityAssignedXml

    [Fact]
    public void WriteFacilityAssignedXml_WritesFacilityToOutput()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C509</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        var (xmlDoc, tumors, nsMgr) = LoadDocAndTumors(xml);
        var assignments = new Dictionary<int, string> { [0] = "0001234567" };

        var outputPath = Path.Combine(Path.GetTempPath(), $"parrat_fac_test_{Guid.NewGuid():N}.xml");
        try
        {
            _service.WriteFacilityAssignedXml(xmlDoc, tumors, assignments, nsMgr, outputPath);

            var outputDoc = new XmlDocument();
            outputDoc.Load(outputPath);
            var outputNsMgr = new XmlNamespaceManager(outputDoc.NameTable);
            outputNsMgr.AddNamespace("n", Ns);

            var facilityNode = outputDoc.SelectSingleNode("//n:Tumor/n:Item[@naaccrId='reportingFacility']", outputNsMgr);
            Assert.NotNull(facilityNode);
            Assert.Equal("0001234567", facilityNode!.InnerText);

            // Verify patient data preserved
            var nameNode = outputDoc.SelectSingleNode("//n:Patient/n:Item[@naaccrId='nameLast']", outputNsMgr);
            Assert.NotNull(nameNode);
            Assert.Equal("Smith", nameNode!.InnerText);
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    #endregion

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) BuildTumorsWithFacility(string facilityValue)
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Tumor>
      <Item naaccrId=""reportingFacility"">{facilityValue}</Item>
      <Item naaccrId=""primarySite"">C509</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        return LoadTumors(xml);
    }

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var (_, tumors, nsMgr) = LoadDocAndTumors(xml);
        return (tumors, nsMgr);
    }

    private static (XmlDocument doc, XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadDocAndTumors(string xml)
    {
        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);

        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", Ns);

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        return (doc, tumors, nsMgr);
    }
}
