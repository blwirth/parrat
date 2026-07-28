using System.Xml;
using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class NaaccrLeveledItemReaderTests
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

    private const string ThreeLevelDoc = $@"
<NaaccrData xmlns=""{Ns}"" recordType=""I"">
  <Item naaccrId=""registryId"">0000001234</Item>
  <Item naaccrId=""naaccrRecordVersion"">240</Item>
  <Patient>
    <Item naaccrId=""patientIdNumber"">00001</Item>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C509</Item>
      <Item naaccrId=""dateOfDiagnosis"">20240101</Item>
    </Tumor>
    <Tumor>
      <Item naaccrId=""primarySite"">C619</Item>
    </Tumor>
  </Patient>
  <Patient>
    <Item naaccrId=""patientIdNumber"">00002</Item>
    <Item naaccrId=""nameLast"">Jones</Item>
    <Tumor>
      <Item naaccrId=""primarySite"">C341</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

    private static readonly KeyValuePair<string, string>[] Fields =
    {
        new("registryId", NaaccrLeveledItemReader.NaaccrDataLevel),
        new("naaccrRecordVersion", NaaccrLeveledItemReader.NaaccrDataLevel),
        new("patientIdNumber", NaaccrLeveledItemReader.PatientLevel),
        new("nameLast", NaaccrLeveledItemReader.PatientLevel),
        new("primarySite", NaaccrLeveledItemReader.TumorLevel),
        new("dateOfDiagnosis", NaaccrLeveledItemReader.TumorLevel)
    };

    [Fact]
    public void ReadRow_ReadsEachFieldFromItsOwnLevel()
    {
        var (doc, nsMgr) = Load(ThreeLevelDoc);
        var tumor = doc.SelectNodes("//n:Tumor", nsMgr)![0]!;

        var reader = new NaaccrLeveledItemReader(Fields);
        var values = new Dictionary<string, string>();
        reader.ReadRow(tumor, NaaccrLeveledItemReader.FindPatient(tumor), values);

        Assert.Equal("0000001234", values["registryId"]);
        Assert.Equal("240", values["naaccrRecordVersion"]);
        Assert.Equal("00001", values["patientIdNumber"]);
        Assert.Equal("Smith", values["nameLast"]);
        Assert.Equal("C509", values["primarySite"]);
        Assert.Equal("20240101", values["dateOfDiagnosis"]);
    }

    [Fact]
    public void ReadRow_ResolvesEachRowAgainstItsOwnPatientAndTumor()
    {
        var (doc, nsMgr) = Load(ThreeLevelDoc);
        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;

        var reader = new NaaccrLeveledItemReader(Fields);
        var rows = new List<Dictionary<string, string>>();

        for (int i = 0; i < tumors.Count; i++)
        {
            var values = new Dictionary<string, string>();
            reader.ReadRow(tumors[i]!, NaaccrLeveledItemReader.FindPatient(tumors[i]!), values);
            rows.Add(values);
        }

        Assert.Equal(3, rows.Count);
        Assert.Equal(new[] { "C509", "C619", "C341" }, rows.Select(r => r["primarySite"]));
        Assert.Equal(new[] { "Smith", "Smith", "Jones" }, rows.Select(r => r["nameLast"]));
        // File-level values are cached after the first row; every row still gets them.
        Assert.All(rows, r => Assert.Equal("0000001234", r["registryId"]));
    }

    [Fact]
    public void ReadRow_MissingField_IsAbsentRatherThanEmpty()
    {
        var (doc, nsMgr) = Load(ThreeLevelDoc);
        // The second tumor has no dateOfDiagnosis.
        var tumor = doc.SelectNodes("//n:Tumor", nsMgr)![1]!;

        var reader = new NaaccrLeveledItemReader(Fields);
        var values = new Dictionary<string, string>();
        reader.ReadRow(tumor, NaaccrLeveledItemReader.FindPatient(tumor), values);

        Assert.False(values.ContainsKey("dateOfDiagnosis"));
        Assert.Equal("C619", values["primarySite"]);
    }

    [Fact]
    public void ReadRow_DoesNotReadAcrossLevels()
    {
        // A field declared at Patient level must not pick up a same-named item
        // on the tumor, which is what the level-specific lookup guarantees.
        var (doc, nsMgr) = Load($@"
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""nameLast"">PatientValue</Item>
    <Tumor><Item naaccrId=""nameLast"">TumorValue</Item></Tumor>
  </Patient>
</NaaccrData>");

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var reader = new NaaccrLeveledItemReader(new[]
        {
            new KeyValuePair<string, string>("nameLast", NaaccrLeveledItemReader.PatientLevel)
        });

        var values = new Dictionary<string, string>();
        reader.ReadRow(tumor, NaaccrLeveledItemReader.FindPatient(tumor), values);

        Assert.Equal("PatientValue", values["nameLast"]);
    }

    [Fact]
    public void ReadRow_DuplicateFieldId_UsesTheLastLevelGiven()
    {
        // Mirrors a per-field loop assigning row[id] repeatedly: the last
        // mapping wins.
        var (doc, nsMgr) = Load($@"
<NaaccrData xmlns=""{Ns}"">
  <Patient>
    <Item naaccrId=""nameLast"">PatientValue</Item>
    <Tumor><Item naaccrId=""nameLast"">TumorValue</Item></Tumor>
  </Patient>
</NaaccrData>");

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;
        var reader = new NaaccrLeveledItemReader(new[]
        {
            new KeyValuePair<string, string>("nameLast", NaaccrLeveledItemReader.PatientLevel),
            new KeyValuePair<string, string>("nameLast", NaaccrLeveledItemReader.TumorLevel)
        });

        var values = new Dictionary<string, string>();
        reader.ReadRow(tumor, NaaccrLeveledItemReader.FindPatient(tumor), values);

        Assert.Equal("TumorValue", values["nameLast"]);
    }

    [Fact]
    public void ReadRow_UnknownLevel_IsTreatedAsTumorLevel()
    {
        var (doc, nsMgr) = Load(ThreeLevelDoc);
        var tumor = doc.SelectNodes("//n:Tumor", nsMgr)![0]!;

        var reader = new NaaccrLeveledItemReader(new[]
        {
            new KeyValuePair<string, string>("primarySite", "SomethingElse")
        });

        var values = new Dictionary<string, string>();
        reader.ReadRow(tumor, NaaccrLeveledItemReader.FindPatient(tumor), values);

        Assert.Equal("C509", values["primarySite"]);
    }

    [Fact]
    public void FindPatient_WalksUpFromTumor()
    {
        var (doc, nsMgr) = Load(ThreeLevelDoc);
        var tumor = doc.SelectNodes("//n:Tumor", nsMgr)![2]!;

        var patient = NaaccrLeveledItemReader.FindPatient(tumor);

        Assert.NotNull(patient);
        Assert.Equal("Patient", patient!.LocalName);
        Assert.Equal(
            "00002",
            patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", nsMgr)!.InnerText);
    }

    [Fact]
    public void FindPatient_MatchesTheXPathAncestorLookupItReplaces()
    {
        var (doc, nsMgr) = Load(ThreeLevelDoc);
        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;

        for (int i = 0; i < tumors.Count; i++)
        {
            var expected = tumors[i]!.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
            Assert.Same(expected, NaaccrLeveledItemReader.FindPatient(tumors[i]!));
        }
    }

    [Fact]
    public void FindPatient_TumorOutsideAPatient_ReturnsNull()
    {
        var (doc, nsMgr) = Load($@"
<NaaccrData xmlns=""{Ns}"">
  <Tumor><Item naaccrId=""primarySite"">C509</Item></Tumor>
</NaaccrData>");

        var tumor = doc.SelectSingleNode("//n:Tumor", nsMgr)!;

        Assert.Null(NaaccrLeveledItemReader.FindPatient(tumor));
    }
}
