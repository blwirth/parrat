using System.Xml;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class PidAssignmentServiceTests
{
    private readonly PidAssignmentService _service = new();
    private const string Ns = NaaccrXmlTestHelper.NaaccrNamespace;

    #region GetPatientIdAssignments — Sequential mode

    [Fact]
    public void GetPatientIdAssignments_Sequential_AssignsToMissingIds()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
  </Patient>
  <Patient>
    <Tumor><Item naaccrId=""primarySite"">C189</Item></Tumor>
  </Patient>
</NaaccrData>";

        var (tumors, nsMgr) = LoadTumors(xml);
        var assignments = _service.GetPatientIdAssignments(tumors, nsMgr, "sequential");

        Assert.Equal(2, assignments.Count);
        Assert.Equal("00000001", assignments[0]);
        Assert.Equal("00000002", assignments[1]);
    }

    [Fact]
    public void GetPatientIdAssignments_Sequential_SkipsExistingIds()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""patientIdNumber"">EXISTING</Item>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
  </Patient>
  <Patient>
    <Tumor><Item naaccrId=""primarySite"">C189</Item></Tumor>
  </Patient>
</NaaccrData>";

        var (tumors, nsMgr) = LoadTumors(xml);
        var assignments = _service.GetPatientIdAssignments(tumors, nsMgr, "sequential");

        Assert.Single(assignments); // Only the one without an ID
        Assert.Equal("00000001", assignments[1]);
    }

    #endregion

    #region GetPatientIdAssignments — OverwriteAll mode

    [Fact]
    public void GetPatientIdAssignments_OverwriteAll_AssignsToAll()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""patientIdNumber"">EXISTING</Item>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
  </Patient>
  <Patient>
    <Tumor><Item naaccrId=""primarySite"">C189</Item></Tumor>
  </Patient>
</NaaccrData>";

        var (tumors, nsMgr) = LoadTumors(xml);
        var assignments = _service.GetPatientIdAssignments(tumors, nsMgr, "OverwriteAll");

        Assert.Equal(2, assignments.Count);
        Assert.Equal("00000001", assignments[0]);
        Assert.Equal("00000002", assignments[1]);
    }

    #endregion

    #region GetPatientIdAssignments — ReplaceZeros mode

    [Fact]
    public void GetPatientIdAssignments_ReplaceZeros_ReplacesZeroIds()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""patientIdNumber"">00000000</Item>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
  </Patient>
  <Patient>
    <Item naaccrId=""patientIdNumber"">REAL_ID</Item>
    <Tumor><Item naaccrId=""primarySite"">C189</Item></Tumor>
  </Patient>
</NaaccrData>";

        var (tumors, nsMgr) = LoadTumors(xml);
        var assignments = _service.GetPatientIdAssignments(tumors, nsMgr, "ReplaceZeros");

        Assert.Single(assignments);
        Assert.Equal("90000001", assignments[0]); // Starts at 90000001
    }

    #endregion

    #region GetPatientIdAssignments — Multi-tumor patient

    [Fact]
    public void GetPatientIdAssignments_MultiTumorPatient_AssignedOnce()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
    <Tumor><Item naaccrId=""primarySite"">C189</Item></Tumor>
  </Patient>
</NaaccrData>";

        var (tumors, nsMgr) = LoadTumors(xml);
        var assignments = _service.GetPatientIdAssignments(tumors, nsMgr, "sequential");

        // Only one assignment for the patient (via first tumor index)
        Assert.Single(assignments);
        Assert.Equal("00000001", assignments[0]);
    }

    #endregion

    #region WritePatientIdXml

    [Fact]
    public void WritePatientIdXml_WritesIdsToOutput()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
  </Patient>
</NaaccrData>";

        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", Ns);
        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;

        var assignments = new Dictionary<int, string> { [0] = "00000001" };
        var outputPath = Path.Combine(Path.GetTempPath(), $"parrat_pid_test_{Guid.NewGuid():N}.xml");

        try
        {
            _service.WritePatientIdXml(doc, assignments, nsMgr, outputPath);

            var outDoc = new XmlDocument();
            outDoc.Load(outputPath);
            var outNsMgr = new XmlNamespaceManager(outDoc.NameTable);
            outNsMgr.AddNamespace("n", Ns);

            var pidNode = outDoc.SelectSingleNode("//n:Patient/n:Item[@naaccrId='patientIdNumber']", outNsMgr);
            Assert.NotNull(pidNode);
            Assert.Equal("00000001", pidNode!.InnerText);

            // Verify patient data preserved
            var nameNode = outDoc.SelectSingleNode("//n:Patient/n:Item[@naaccrId='nameLast']", outNsMgr);
            Assert.Equal("Smith", nameNode!.InnerText);
        }
        finally { if (File.Exists(outputPath)) File.Delete(outputPath); }
    }

    #endregion

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", Ns);
        return (doc.SelectNodes("//n:Tumor", nsMgr)!, nsMgr);
    }
}
