using System.Xml;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class RemoveVariableServiceTests
{
    private readonly RemoveVariableService _service = new();
    private const string Ns = NaaccrXmlTestHelper.NaaccrNamespace;

    #region GetUniqueNaaccrIds

    [Fact]
    public void GetUniqueNaaccrIds_CollectsFromAllLevels()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Item naaccrId=""recordType"">I</Item>
  <Patient>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C509</Item>
      <Item naaccrId=""dateOfDiagnosis"">20240101</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        var (doc, nsMgr) = LoadDoc(xml);
        var ids = _service.GetUniqueNaaccrIds(doc, nsMgr);

        Assert.Contains("recordType", ids);
        Assert.Contains("nameLast", ids);
        Assert.Contains("primarySite", ids);
        Assert.Contains("dateOfDiagnosis", ids);
    }

    [Fact]
    public void GetUniqueNaaccrIds_ReturnsSortedAndUnique()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Tumor>
      <Item naaccrId=""nameLast"">Smith</Item>
      <Item naaccrId=""primarySite"">C509</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        var (doc, nsMgr) = LoadDoc(xml);
        var ids = _service.GetUniqueNaaccrIds(doc, nsMgr);

        // "nameLast" appears twice but should be in result only once
        Assert.Equal(2, ids.Count);
        // Should be sorted
        Assert.Equal("nameLast", ids[0]);
        Assert.Equal("primarySite", ids[1]);
    }

    [Fact]
    public void GetUniqueNaaccrIds_ReturnsEmptyForEmptyDoc()
    {
        var xml = $@"<?xml version=""1.0""?><NaaccrData xmlns=""{Ns}""></NaaccrData>";
        var (doc, nsMgr) = LoadDoc(xml);
        var ids = _service.GetUniqueNaaccrIds(doc, nsMgr);
        Assert.Empty(ids);
    }

    #endregion

    #region RemoveXmlVariable

    [Fact]
    public void RemoveXmlVariable_RemovesSpecifiedItems()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Item naaccrId=""nameFirst"">John</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C509</Item>
      <Item naaccrId=""dateOfDiagnosis"">20240101</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        var (doc, _) = LoadDoc(xml);
        var outputPath = Path.Combine(Path.GetTempPath(), $"parrat_rm_test_{Guid.NewGuid():N}.xml");

        try
        {
            _service.RemoveXmlVariable(doc, new[] { "nameFirst", "dateOfDiagnosis" }, outputPath);

            var outDoc = new XmlDocument();
            outDoc.Load(outputPath);
            var outNsMgr = new XmlNamespaceManager(outDoc.NameTable);
            outNsMgr.AddNamespace("n", Ns);

            // Removed items should be gone
            Assert.Null(outDoc.SelectSingleNode("//n:Item[@naaccrId='nameFirst']", outNsMgr));
            Assert.Null(outDoc.SelectSingleNode("//n:Item[@naaccrId='dateOfDiagnosis']", outNsMgr));

            // Remaining items should still be present
            Assert.NotNull(outDoc.SelectSingleNode("//n:Item[@naaccrId='nameLast']", outNsMgr));
            Assert.NotNull(outDoc.SelectSingleNode("//n:Item[@naaccrId='primarySite']", outNsMgr));
        }
        finally { if (File.Exists(outputPath)) File.Delete(outputPath); }
    }

    [Fact]
    public void RemoveXmlVariable_PreservesDocumentStructure()
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

        var (doc, _) = LoadDoc(xml);
        var outputPath = Path.Combine(Path.GetTempPath(), $"parrat_rm_test_{Guid.NewGuid():N}.xml");

        try
        {
            // Remove nothing — structure should survive intact
            _service.RemoveXmlVariable(doc, Array.Empty<string>(), outputPath);

            var outDoc = new XmlDocument();
            outDoc.Load(outputPath);
            var outNsMgr = new XmlNamespaceManager(outDoc.NameTable);
            outNsMgr.AddNamespace("n", Ns);

            Assert.NotNull(outDoc.SelectSingleNode("//n:Patient", outNsMgr));
            Assert.NotNull(outDoc.SelectSingleNode("//n:Tumor", outNsMgr));
            Assert.Equal("Smith", outDoc.SelectSingleNode("//n:Item[@naaccrId='nameLast']", outNsMgr)!.InnerText);
        }
        finally { if (File.Exists(outputPath)) File.Delete(outputPath); }
    }

    #endregion

    private static (XmlDocument doc, XmlNamespaceManager nsMgr) LoadDoc(string xml)
    {
        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", Ns);
        return (doc, nsMgr);
    }
}
