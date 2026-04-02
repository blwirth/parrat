using System.Xml;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class XmlFileServiceTests : IDisposable
{
    private readonly string _tempDir;

    public XmlFileServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_xml_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    #region LoadNaaccrXml

    [Fact]
    public void LoadNaaccrXml_LoadsFileAndReturnsTumors()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Smith",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" },
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" },
            }
        });

        var filePath = Path.Combine(_tempDir, "test.xml");
        File.WriteAllText(filePath, xml);

        var svc = new XmlFileService();
        var (doc, tumors, nsMgr) = svc.LoadNaaccrXml(filePath);

        Assert.NotNull(doc);
        Assert.Equal(2, tumors.Count);
        Assert.NotNull(nsMgr);
    }

    #endregion

    #region GetItemValue

    [Fact]
    public void GetItemValue_ReturnsValueWhenExists()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml(primarySite: "C509");
        var (tumors, nsMgr) = LoadTumors(xml);

        var svc = new XmlFileService();
        var value = svc.GetItemValue(tumors[0]!, "primarySite", nsMgr);
        Assert.Equal("C509", value);
    }

    [Fact]
    public void GetItemValue_ReturnsEmptyWhenMissing()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);

        var svc = new XmlFileService();
        var value = svc.GetItemValue(tumors[0]!, "nonExistentField", nsMgr);
        Assert.Equal("", value);
    }

    #endregion

    #region SetItemValue

    [Fact]
    public void SetItemValue_UpdatesExistingItem()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml(primarySite: "C509");
        var (tumors, nsMgr) = LoadTumors(xml);

        var svc = new XmlFileService();
        svc.SetItemValue(tumors[0]!, "primarySite", "C189", nsMgr);

        var value = svc.GetItemValue(tumors[0]!, "primarySite", nsMgr);
        Assert.Equal("C189", value);
    }

    [Fact]
    public void SetItemValue_CreatesNewItemWhenMissing()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);

        var svc = new XmlFileService();
        svc.SetItemValue(tumors[0]!, "laterality", "2", nsMgr);

        var value = svc.GetItemValue(tumors[0]!, "laterality", nsMgr);
        Assert.Equal("2", value);
    }

    #endregion

    #region GetPatientForTumor

    [Fact]
    public void GetPatientForTumor_ReturnsPatientNode()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml(nameLast: "Smith");
        var (tumors, nsMgr) = LoadTumors(xml);

        var svc = new XmlFileService();
        var patient = svc.GetPatientForTumor(tumors[0]!);

        Assert.NotNull(patient);
        Assert.Equal("Patient", patient!.LocalName);

        var name = svc.GetItemValue(patient, "nameLast", nsMgr);
        Assert.Equal("Smith", name);
    }

    #endregion

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        return (doc.SelectNodes("//n:Tumor", nsMgr)!, nsMgr);
    }
}
