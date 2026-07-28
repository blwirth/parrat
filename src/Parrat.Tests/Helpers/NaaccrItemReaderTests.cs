using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Helpers;

public class NaaccrItemReaderTests
{
    private const string Ns = "http://naaccr.org/naaccrxml";

    private static (XmlDocument doc, XmlNamespaceManager nsMgr) Load(string xml)
    {
        var doc = new XmlDocument { XmlResolver = null };
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", doc.DocumentElement!.NamespaceURI);
        return (doc, nsMgr);
    }

    private static string Wrap(string patientBody) => $@"
<NaaccrData xmlns=""{Ns}"" recordType=""A"">
  <Patient>
    {patientBody}
  </Patient>
</NaaccrData>";

    [Fact]
    public void ReadInto_ReadsRequestedItemsFromElement()
    {
        var (doc, nsMgr) = Load(Wrap(@"
      <Item naaccrId=""patientIdNumber"">00001</Item>
      <Item naaccrId=""nameLast"">Smith</Item>
      <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>"));

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var reader = new NaaccrItemReader(new[] { "primarySite" });

        var values = reader.Read(tumor);

        Assert.Equal("C509", values["primarySite"]);
    }

    [Fact]
    public void Read_TumorValueWinsOverPatient()
    {
        var (doc, nsMgr) = Load(Wrap(@"
      <Item naaccrId=""dateOfBirth"">19500101</Item>
      <Tumor><Item naaccrId=""dateOfBirth"">19601231</Item></Tumor>"));

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var patient = tumor.ParentNode;
        var reader = new NaaccrItemReader(new[] { "dateOfBirth" });

        Assert.Equal("19601231", reader.Read(tumor, patient)["dateOfBirth"]);
    }

    [Fact]
    public void Read_BlankTumorValueFallsThroughToPatient()
    {
        // Matches the old lookup, which treated an empty item as "not found"
        // and then consulted the patient.
        var (doc, nsMgr) = Load(Wrap(@"
      <Item naaccrId=""nameLast"">Smith</Item>
      <Tumor><Item naaccrId=""nameLast""></Item></Tumor>"));

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var patient = tumor.ParentNode;
        var reader = new NaaccrItemReader(new[] { "nameLast" });

        Assert.Equal("Smith", reader.Read(tumor, patient)["nameLast"]);
    }

    [Fact]
    public void Read_MissingItemIsAbsentFromResult()
    {
        var (doc, nsMgr) = Load(Wrap(@"<Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>"));

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var reader = new NaaccrItemReader(new[] { "primarySite", "dateOfDiagnosis" });

        var values = reader.Read(tumor);

        Assert.True(values.ContainsKey("primarySite"));
        Assert.False(values.ContainsKey("dateOfDiagnosis"));
    }

    [Fact]
    public void ReadInto_IgnoresNestedItemsOfChildElements()
    {
        // Tumor-level Items must not pick up Items nested inside the Tumor's
        // own children, matching the "./n:Item" scope of the old lookup.
        var (doc, nsMgr) = Load(Wrap(@"
      <Tumor>
        <Item naaccrId=""primarySite"">C509</Item>
        <SomeGroup><Item naaccrId=""dateOfDiagnosis"">20240101</Item></SomeGroup>
      </Tumor>"));

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var reader = new NaaccrItemReader(new[] { "primarySite", "dateOfDiagnosis" });

        var values = reader.Read(tumor);

        Assert.Equal("C509", values["primarySite"]);
        Assert.False(values.ContainsKey("dateOfDiagnosis"));
    }

    [Fact]
    public void ReadInto_NullNode_IsIgnored()
    {
        var reader = new NaaccrItemReader(new[] { "nameLast" });
        var values = new Dictionary<string, string>();

        reader.ReadInto(null, values);

        Assert.Empty(values);
    }

    [Fact]
    public void Read_MatchesGetItemValueAcrossManyFields()
    {
        // The reader replaces per-cell GetItemValue in the load path; the two
        // must agree field for field.
        var (doc, nsMgr) = Load(Wrap(@"
      <Item naaccrId=""patientIdNumber"">00001</Item>
      <Item naaccrId=""nameLast"">Smith</Item>
      <Item naaccrId=""nameFirst"">Jane</Item>
      <Item naaccrId=""dateOfBirth"">19850315</Item>
      <Tumor>
        <Item naaccrId=""primarySite"">C509</Item>
        <Item naaccrId=""dateOfDiagnosis"">20240101</Item>
        <Item naaccrId=""nameLast""></Item>
      </Tumor>"));

        var svc = new XmlFileService();
        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var patient = svc.GetPatientForTumor(tumor);

        string[] fields =
        {
            "patientIdNumber", "nameLast", "nameFirst", "dateOfBirth",
            "primarySite", "dateOfDiagnosis", "notPresentAnywhere"
        };

        var reader = new NaaccrItemReader(fields);
        var values = reader.Read(tumor, patient);

        foreach (var field in fields)
        {
            var expected = svc.GetItemValue(tumor, field, nsMgr);
            if (string.IsNullOrEmpty(expected) && patient != null)
                expected = svc.GetItemValue(patient, field, nsMgr);

            var actual = values.TryGetValue(field, out var v) ? v : "";

            Assert.Equal(expected, actual);
        }
    }

    [Fact]
    public void CollectAllItemText_GathersNonEmptyValuesInDocumentOrder()
    {
        var (doc, nsMgr) = Load(Wrap(@"
      <Tumor>
        <Item naaccrId=""primarySite"">C509</Item>
        <Item naaccrId=""blank""></Item>
        <Item naaccrId=""dateOfDiagnosis"">20240101</Item>
      </Tumor>"));

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var parts = new List<string>();

        NaaccrItemReader.CollectAllItemText(tumor, parts);

        Assert.Equal(new[] { "C509", "20240101" }, parts);
    }
}
