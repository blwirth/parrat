using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class CsvImportServiceTests : IDisposable
{
    private readonly string _originalRepoRoot;
    private readonly string _originalUserDir;
    private readonly NaaccrDictionary _dictionary;
    private readonly CsvImportService _service;

    public CsvImportServiceTests()
    {
        _originalRepoRoot = PathHelper.RepoRoot;
        _originalUserDir = PathHelper.UserDir;
        PathHelper.SetRepoRoot(TestEnvironment.FindRepoRoot());

        _dictionary = new NaaccrDictionary();
        _dictionary.Initialize();
        _service = new CsvImportService(_dictionary);
    }

    public void Dispose()
    {
        PathHelper.SetRepoRoot(_originalRepoRoot);
        PathHelper.SetUserDir(_originalUserDir);
    }

    // ── AutoMatch Tests ──────────────────────────────────────────────────

    [Fact]
    public void AutoMatch_ExactXmlId_Matches()
    {
        var headers = new[] { "patientIdNumber", "primarySite", "dateOfBirth" };
        var mappings = _service.AutoMatch(headers);

        Assert.Equal(3, mappings.Count);
        Assert.All(mappings, m => Assert.True(m.IsAutoMatched));
        Assert.Equal("patientIdNumber", mappings[0].MappedNaaccrId);
        Assert.Equal("primarySite", mappings[1].MappedNaaccrId);
        Assert.Equal("dateOfBirth", mappings[2].MappedNaaccrId);
    }

    [Fact]
    public void AutoMatch_DisplayName_Matches()
    {
        var headers = new[] { "Patient ID Number", "Primary Site" };
        var mappings = _service.AutoMatch(headers);

        Assert.Equal("patientIdNumber", mappings[0].MappedNaaccrId);
        Assert.Equal("primarySite", mappings[1].MappedNaaccrId);
    }

    [Fact]
    public void AutoMatch_NormalizedName_Matches()
    {
        var headers = new[] { "primary_site", "date-of-birth", "name last" };
        var mappings = _service.AutoMatch(headers);

        Assert.Equal("primarySite", mappings[0].MappedNaaccrId);
        Assert.Equal("dateOfBirth", mappings[1].MappedNaaccrId);
        Assert.Equal("nameLast", mappings[2].MappedNaaccrId);
    }

    [Fact]
    public void AutoMatch_CaseInsensitive_Matches()
    {
        var headers = new[] { "PRIMARYSITE", "PATIENTIDNUMBER" };
        var mappings = _service.AutoMatch(headers);

        Assert.Equal("primarySite", mappings[0].MappedNaaccrId);
        Assert.Equal("patientIdNumber", mappings[1].MappedNaaccrId);
    }

    [Fact]
    public void AutoMatch_UnknownHeader_RemainsUnmapped()
    {
        var headers = new[] { "patientIdNumber", "unknownColumn", "primarySite" };
        var mappings = _service.AutoMatch(headers);

        Assert.True(mappings[0].IsAutoMatched);
        Assert.Null(mappings[1].MappedNaaccrId);
        Assert.True(mappings[1].IsSkipped);
        Assert.False(mappings[1].IsAutoMatched);
        Assert.True(mappings[2].IsAutoMatched);
    }

    [Fact]
    public void AutoMatch_PreventsDuplicateMappings()
    {
        // Two columns with same header — only first should match
        var headers = new[] { "primarySite", "primarySite" };
        var mappings = _service.AutoMatch(headers);

        Assert.Equal("primarySite", mappings[0].MappedNaaccrId);
        Assert.Null(mappings[1].MappedNaaccrId);
    }

    // ── v26 AutoMatch Tests ─────────────────────────────────────────────

    [Fact]
    public void AutoMatch_V26_SexHeader_MatchesSexAssignedAtBirth()
    {
        var headers = new[] { "sex", "nameLast" };
        var mappings = _service.AutoMatch(headers, naaccrVersion: 26);

        Assert.Equal("sexAssignedAtBirth", mappings[0].MappedNaaccrId);
        Assert.True(mappings[0].IsAutoMatched);
        Assert.Equal("nameLast", mappings[1].MappedNaaccrId);
    }

    [Fact]
    public void AutoMatch_V25_SexHeader_MatchesSex()
    {
        var headers = new[] { "sex", "nameLast" };
        var mappings = _service.AutoMatch(headers, naaccrVersion: 25);

        Assert.Equal("sex", mappings[0].MappedNaaccrId);
    }

    [Fact]
    public void GenerateNaaccrXml_V26_UsesCorrectDictionaryUri()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast" },
            Rows = new List<string[]> { new[] { "Smith" } }
        };
        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings, naaccrVersion: 26);
        Assert.Contains("naaccr-dictionary-260.xml", doc.DocumentElement!.GetAttribute("baseDictionaryUri"));
    }

    // ── GenerateNaaccrXml Tests ──────────────────────────────────────────

    [Fact]
    public void GenerateNaaccrXml_SingleRow_CreatesOnePatientOneTumor()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast", "primarySite" },
            Rows = new List<string[]>
            {
                new[] { "Smith", "C509" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" },
            new() { CsvColumnIndex = 1, CsvHeader = "primarySite", MappedNaaccrId = "primarySite" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        // Root structure
        Assert.Equal("NaaccrData", doc.DocumentElement!.LocalName);
        Assert.Equal("A", doc.DocumentElement.GetAttribute("recordType"));

        // One patient
        var patients = doc.SelectNodes("//n:Patient", nsMgr)!;
        Assert.Equal(1, patients.Count);

        // Patient-level item
        var nameLast = patients[0]!.SelectSingleNode("./n:Item[@naaccrId='nameLast']", nsMgr);
        Assert.NotNull(nameLast);
        Assert.Equal("Smith", nameLast!.InnerText);

        // One tumor with primarySite
        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        Assert.Equal(1, tumors.Count);
        var site = tumors[0]!.SelectSingleNode("./n:Item[@naaccrId='primarySite']", nsMgr);
        Assert.NotNull(site);
        Assert.Equal("C509", site!.InnerText);
    }

    [Fact]
    public void GenerateNaaccrXml_GroupsByPatientId()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "patientIdNumber", "nameLast", "primarySite" },
            Rows = new List<string[]>
            {
                new[] { "P001", "Smith", "C509" },
                new[] { "P001", "Smith", "C504" },
                new[] { "P002", "Jones", "C180" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "patientIdNumber", MappedNaaccrId = "patientIdNumber" },
            new() { CsvColumnIndex = 1, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" },
            new() { CsvColumnIndex = 2, CsvHeader = "primarySite", MappedNaaccrId = "primarySite" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        var patients = doc.SelectNodes("//n:Patient", nsMgr)!;
        Assert.Equal(2, patients.Count);

        // First patient has 2 tumors
        var tumors1 = patients[0]!.SelectNodes("./n:Tumor", nsMgr)!;
        Assert.Equal(2, tumors1.Count);

        // Second patient has 1 tumor
        var tumors2 = patients[1]!.SelectNodes("./n:Tumor", nsMgr)!;
        Assert.Equal(1, tumors2.Count);
    }

    [Fact]
    public void GenerateNaaccrXml_NoPatientId_EachRowSeparatePatient()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast", "primarySite" },
            Rows = new List<string[]>
            {
                new[] { "Smith", "C509" },
                new[] { "Jones", "C180" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" },
            new() { CsvColumnIndex = 1, CsvHeader = "primarySite", MappedNaaccrId = "primarySite" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        var patients = doc.SelectNodes("//n:Patient", nsMgr)!;
        Assert.Equal(2, patients.Count);
    }

    [Fact]
    public void GenerateNaaccrXml_NaaccrDataLevelFields_OnRoot()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "recordType", "nameLast" },
            Rows = new List<string[]>
            {
                new[] { "I", "Smith" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "recordType", MappedNaaccrId = "recordType" },
            new() { CsvColumnIndex = 1, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        // recordType is NaaccrData-level — should be on root, not under Patient
        var rootItem = doc.DocumentElement!.SelectSingleNode("./n:Item[@naaccrId='recordType']", nsMgr);
        Assert.NotNull(rootItem);
        Assert.Equal("I", rootItem!.InnerText);
    }

    [Fact]
    public void GenerateNaaccrXml_SkippedMappings_AreIgnored()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast", "junkColumn" },
            Rows = new List<string[]>
            {
                new[] { "Smith", "ignored" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" },
            new() { CsvColumnIndex = 1, CsvHeader = "junkColumn", MappedNaaccrId = null }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        // Should only have nameLast, not junkColumn
        var items = doc.SelectNodes("//n:Item", nsMgr)!;
        Assert.Equal(1, items.Count);
    }

    [Fact]
    public void GenerateNaaccrXml_EmptyValues_AreNotAddedToXml()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast", "nameFirst" },
            Rows = new List<string[]>
            {
                new[] { "Smith", "" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" },
            new() { CsvColumnIndex = 1, CsvHeader = "nameFirst", MappedNaaccrId = "nameFirst" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        // Only nameLast should be present (nameFirst is empty)
        var patient = doc.SelectSingleNode("//n:Patient", nsMgr)!;
        var items = patient.SelectNodes("./n:Item", nsMgr)!;
        Assert.Equal(1, items.Count);
        Assert.Equal("nameLast", items[0]!.Attributes!["naaccrId"]!.Value);
    }

    [Fact]
    public void GenerateNaaccrXml_RoundTrip_LoadableByXmlFileService()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "patientIdNumber", "nameLast", "primarySite", "dateOfDiagnosis" },
            Rows = new List<string[]>
            {
                new[] { "P001", "Smith", "C509", "20240101" }
            }
        };

        var mappings = _service.AutoMatch(csv.Headers);
        var doc = _service.GenerateNaaccrXml(csv, mappings);

        // Save to temp file and reload with XmlFileService
        var tempPath = Path.GetTempFileName();
        try
        {
            doc.Save(tempPath);
            var xmlService = new XmlFileService();
            var (loadedDoc, tumors, nsMgr) = xmlService.LoadNaaccrXml(tempPath);

            Assert.Equal(1, tumors.Count);
            Assert.Equal("C509", xmlService.GetItemValue(tumors[0]!, "primarySite", nsMgr));

            var patient = xmlService.GetPatientForTumor(tumors[0]!);
            Assert.NotNull(patient);
            Assert.Equal("Smith", xmlService.GetItemValue(patient!, "nameLast", nsMgr));
        }
        finally
        {
            File.Delete(tempPath);
        }
    }

    [Fact]
    public void GenerateNaaccrXml_CustomRecordType_IsSet()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast" },
            Rows = new List<string[]> { new[] { "Smith" } }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings, recordType: "A");
        Assert.Equal("A", doc.DocumentElement!.GetAttribute("recordType"));
    }

    private static XmlNamespaceManager CreateNsMgr(XmlDocument doc)
    {
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml");
        return nsMgr;
    }
}
