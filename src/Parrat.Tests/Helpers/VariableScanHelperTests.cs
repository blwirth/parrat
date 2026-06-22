using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class VariableScanHelperTests
{
    private static NaaccrDictionary CreateDictionary(int version = 25)
    {
        PathHelper.SetRepoRoot(TestEnvironment.FindRepoRoot());
        var dict = new NaaccrDictionary();
        dict.Initialize(version);
        return dict;
    }

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var xmlDoc = new XmlDocument { XmlResolver = null };
        xmlDoc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(xmlDoc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        return (tumors, nsMgr);
    }

    [Fact]
    public void ScanPresentVariables_CapturesEachLevelWithCorrectMapping()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(
            naaccrDataItems: new Dictionary<string, string> { ["registryId"] = "0000000001" },
            patients: new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                PatientIdNumber = "PAT001",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509", DateOfDiagnosis = "20240101" }
                }
            });

        var (tumors, nsMgr) = LoadTumors(xml);

        var result = VariableScanHelper.ScanPresentVariables(tumors, new[] { 0 }, nsMgr);

        Assert.Equal("NaaccrData", result["registryId"]);
        Assert.Equal("Patient", result["nameLast"]);
        Assert.Equal("Patient", result["patientIdNumber"]);
        Assert.Equal("Tumor", result["primarySite"]);
        Assert.Equal("Tumor", result["dateOfDiagnosis"]);
    }

    [Fact]
    public void ScanPresentVariables_DedupesVariablesSharedAcrossTumorsOfSamePatient()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Jones",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" },
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C619" }
            }
        });

        var (tumors, nsMgr) = LoadTumors(xml);

        var result = VariableScanHelper.ScanPresentVariables(tumors, new[] { 0, 1 }, nsMgr);

        // nameLast (shared patient item) and primarySite appear once each.
        Assert.Single(result, kvp => kvp.Key == "nameLast");
        Assert.Single(result, kvp => kvp.Key == "primarySite");
    }

    [Fact]
    public void ScanPresentVariables_HonorsSubset_VariableOnlyInNonSelectedTumorIsExcluded()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Lee",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" },
                new NaaccrXmlTestHelper.TumorData { PathReportNumber1 = "RPT-1" }
            }
        });

        var (tumors, nsMgr) = LoadTumors(xml);

        var subset = VariableScanHelper.ScanPresentVariables(tumors, new[] { 0 }, nsMgr);
        Assert.True(subset.ContainsKey("primarySite"));
        Assert.False(subset.ContainsKey("pathReportNumber1"));

        var all = VariableScanHelper.ScanPresentVariables(tumors, new[] { 0, 1 }, nsMgr);
        Assert.True(all.ContainsKey("primarySite"));
        Assert.True(all.ContainsKey("pathReportNumber1"));
    }

    [Fact]
    public void ScanPresentVariables_SkipsOutOfRangeAndNegativeIndices()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);

        var result = VariableScanHelper.ScanPresentVariables(tumors, new[] { -1, 0, 99 }, nsMgr);

        // Only index 0 was valid; primarySite from the single tumor should be present.
        Assert.True(result.ContainsKey("primarySite"));
    }

    [Fact]
    public void ScanPresentVariables_EmptyOrNullInputs_ReturnEmpty()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);

        Assert.Empty(VariableScanHelper.ScanPresentVariables(tumors, Array.Empty<int>(), nsMgr));
        Assert.Empty(VariableScanHelper.ScanPresentVariables(tumors, null, nsMgr));
        Assert.Empty(VariableScanHelper.ScanPresentVariables(null, new[] { 0 }, nsMgr));
    }

    [Fact]
    public void OrderByNaaccr_SortsByItemNumber_UnknownIdsLast()
    {
        var dict = CreateDictionary();

        // patientIdNumber is item #20; primarySite is a higher-numbered item; the made-up id
        // is absent from the dictionary and must sort last regardless of input order.
        var ordered = VariableScanHelper.OrderByNaaccr(
            new[] { "zzMadeUpId", "primarySite", "patientIdNumber" }, dict);

        Assert.Equal("zzMadeUpId", ordered[^1]);
        Assert.True(
            ordered.IndexOf("patientIdNumber") < ordered.IndexOf("primarySite"),
            "Lower NAACCR item numbers must come first");
    }

    [Fact]
    public void MergePreservingOrder_KeepsExistingOrder_AppendsNew_NoDuplicates()
    {
        var merged = VariableScanHelper.MergePreservingOrder(
            new[] { "a", "b" },
            new[] { "b", "c", "a", "d" });

        Assert.Equal(new[] { "a", "b", "c", "d" }, merged);
    }
}
