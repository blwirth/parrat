using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class TumorFieldReaderTests
{
    // Levels used by the test fixtures, mirroring how the dictionary classifies these ids.
    private static string ResolveLevel(string fieldId) => fieldId switch
    {
        "registryId" => "NaaccrData",
        "nameLast" => "Patient",
        "patientIdNumber" => "Patient",
        _ => "Tumor"
    };

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var xmlDoc = new XmlDocument { XmlResolver = null };
        xmlDoc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(xmlDoc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        return (tumors, nsMgr);
    }

    private static (XmlNode tumor, XmlNode? patient) FirstTumor(XmlNodeList tumors, XmlNamespaceManager nsMgr)
    {
        var tumor = tumors[0]!;
        var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
        return (tumor, patient);
    }

    [Fact]
    public void ReadValue_ResolvesEachLevel()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(
            naaccrDataItems: new Dictionary<string, string> { ["registryId"] = "REG1" },
            patients: new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
            });

        var (tumors, nsMgr) = LoadTumors(xml);
        var (tumor, patient) = FirstTumor(tumors, nsMgr);

        Assert.Equal("REG1", TumorFieldReader.ReadValue(tumor, patient, "registryId", "NaaccrData", nsMgr));
        Assert.Equal("Smith", TumorFieldReader.ReadValue(tumor, patient, "nameLast", "Patient", nsMgr));
        Assert.Equal("C509", TumorFieldReader.ReadValue(tumor, patient, "primarySite", "Tumor", nsMgr));
    }

    [Fact]
    public void ReadValue_MissingItem_ReturnsEmpty()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);
        var (tumor, patient) = FirstTumor(tumors, nsMgr);

        Assert.Equal("", TumorFieldReader.ReadValue(tumor, patient, "notPresent", "Tumor", nsMgr));
    }

    [Fact]
    public void ReadValue_WrongLevel_DoesNotFindFileLevelItemOnTumor()
    {
        // Guards the bug class where NaaccrData-level items were looked up on the Tumor and
        // came back blank. Reading at the correct level finds it; the wrong level does not.
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(
            naaccrDataItems: new Dictionary<string, string> { ["registryId"] = "REG1" },
            patients: new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
            });

        var (tumors, nsMgr) = LoadTumors(xml);
        var (tumor, patient) = FirstTumor(tumors, nsMgr);

        Assert.Equal("REG1", TumorFieldReader.ReadValue(tumor, patient, "registryId", "NaaccrData", nsMgr));
        Assert.Equal("", TumorFieldReader.ReadValue(tumor, patient, "registryId", "Tumor", nsMgr));
    }

    [Fact]
    public void FindEmptyFields_PopulatedFileAndPatientLevelFields_AreNotFlaggedEmpty()
    {
        // Regression: a NaaccrData-level field that has data must NOT be reported as an empty
        // column (the preview bug would have flagged it because it checked the Tumor only).
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(
            naaccrDataItems: new Dictionary<string, string> { ["registryId"] = "REG1" },
            patients: new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Lee",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" },
                    new NaaccrXmlTestHelper.TumorData { PathReportNumber1 = "RPT-1" }
                }
            });

        var (tumors, nsMgr) = LoadTumors(xml);
        var fields = new[] { "registryId", "nameLast", "primarySite", "pathReportNumber1", "bogusField" };

        // Exporting only tumor 0: pathReportNumber1 (only on tumor 1) and bogusField are empty.
        var emptyForFirst = TumorFieldReader.FindEmptyFields(tumors, new[] { 0 }, fields, ResolveLevel, nsMgr);
        Assert.DoesNotContain("registryId", emptyForFirst);
        Assert.DoesNotContain("nameLast", emptyForFirst);
        Assert.DoesNotContain("primarySite", emptyForFirst);
        Assert.Contains("pathReportNumber1", emptyForFirst);
        Assert.Contains("bogusField", emptyForFirst);

        // Exporting both tumors: pathReportNumber1 now has data somewhere, only bogusField empty.
        var emptyForBoth = TumorFieldReader.FindEmptyFields(tumors, new[] { 0, 1 }, fields, ResolveLevel, nsMgr);
        Assert.Equal(new[] { "bogusField" }, emptyForBoth);
    }

    [Fact]
    public void FindEmptyFields_NoValidIndices_AllFieldsEmpty()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);
        var fields = new[] { "primarySite", "nameLast" };

        var result = TumorFieldReader.FindEmptyFields(tumors, new[] { 99, -1 }, fields, ResolveLevel, nsMgr);

        Assert.Equal(fields, result);
    }

    [Fact]
    public void FindEmptyFields_EmptyFieldList_ReturnsEmpty()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);

        var result = TumorFieldReader.FindEmptyFields(tumors, new[] { 0 }, Array.Empty<string>(), ResolveLevel, nsMgr);

        Assert.Empty(result);
    }
}
