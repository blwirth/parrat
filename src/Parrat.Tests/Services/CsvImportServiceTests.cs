using System.Text;
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

    // ── Incompatible Mapping Tests ─────────────────────────────────────

    [Fact]
    public void GenerateNaaccrXml_IncompatibleMappings_AreExcluded()
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
            new() { CsvColumnIndex = 1, CsvHeader = "primarySite", MappedNaaccrId = "primarySite", IsIncompatible = true }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        // Only nameLast should be present — primarySite is incompatible
        var allItems = doc.SelectNodes("//n:Item", nsMgr)!;
        Assert.Equal(1, allItems.Count);
        Assert.Equal("nameLast", allItems[0]!.Attributes!["naaccrId"]!.Value);
    }

    [Fact]
    public void GenerateNaaccrXml_MixOfSkippedAndIncompatible_BothExcluded()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast", "junk", "primarySite" },
            Rows = new List<string[]>
            {
                new[] { "Smith", "ignored", "C509" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" },
            new() { CsvColumnIndex = 1, CsvHeader = "junk", MappedNaaccrId = null }, // skipped
            new() { CsvColumnIndex = 2, CsvHeader = "primarySite", MappedNaaccrId = "primarySite", IsIncompatible = true }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        var allItems = doc.SelectNodes("//n:Item", nsMgr)!;
        Assert.Equal(1, allItems.Count);
    }

    [Fact]
    public void IsExportable_ReflectsSkippedAndIncompatible()
    {
        var exportable = new CsvImportMapping { MappedNaaccrId = "nameLast", IsIncompatible = false };
        var skipped = new CsvImportMapping { MappedNaaccrId = null };
        var incompatible = new CsvImportMapping { MappedNaaccrId = "sex", IsIncompatible = true };

        Assert.True(exportable.IsExportable);
        Assert.False(skipped.IsExportable);
        Assert.False(incompatible.IsExportable);
    }

    // ── Version Incompatibility Tests ───────────────────────────────────

    [Fact]
    public void AutoMatch_V25_SexField_ExistsInDictionary()
    {
        _dictionary.Initialize(25);
        var dict = _dictionary.GetDictionary();
        Assert.True(dict.ContainsKey("sex"));
    }

    [Fact]
    public void AutoMatch_V26_SexField_DoesNotExistInDictionary()
    {
        _dictionary.Initialize(26);
        var dict = _dictionary.GetDictionary();
        Assert.False(dict.ContainsKey("sex"));
        Assert.True(dict.ContainsKey("sexAssignedAtBirth"));
    }

    [Fact]
    public void GenerateNaaccrXml_V25MappingSwitchedToV26_IncompatibleFieldExcluded()
    {
        // Simulate: user mapped "sex" in v25, then switched to v26
        var csv = new CsvParseResult
        {
            Headers = new[] { "sex", "nameLast" },
            Rows = new List<string[]>
            {
                new[] { "1", "Smith" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "sex", MappedNaaccrId = "sex", IsIncompatible = true },
            new() { CsvColumnIndex = 1, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" }
        };

        _dictionary.Initialize(26);
        var doc = _service.GenerateNaaccrXml(csv, mappings, naaccrVersion: 26);
        var nsMgr = CreateNsMgr(doc);

        // sex should NOT be in the output
        var sexItem = doc.SelectSingleNode("//n:Item[@naaccrId='sex']", nsMgr);
        Assert.Null(sexItem);

        // nameLast should still be there
        var nameItem = doc.SelectSingleNode("//n:Item[@naaccrId='nameLast']", nsMgr);
        Assert.NotNull(nameItem);
        Assert.Equal("Smith", nameItem!.InnerText);
    }

    // ── Full Round-Trip Tests ───────────────────────────────────────────

    [Fact]
    public void RoundTrip_FormatXmlAndWriteUtf8_LoadableByXmlFileService()
    {
        // This tests the actual save path: GenerateNaaccrXml → FormatXml → File.WriteAllText(UTF8) → LoadNaaccrXml
        var csv = new CsvParseResult
        {
            Headers = new[] { "patientIdNumber", "nameLast", "nameFirst", "primarySite", "dateOfDiagnosis" },
            Rows = new List<string[]>
            {
                new[] { "P001", "Smith", "John", "C509", "20240101" },
                new[] { "P001", "Smith", "John", "C504", "20240320" },
                new[] { "P002", "Jones", "Maria", "C180", "20240201" }
            }
        };

        var mappings = _service.AutoMatch(csv.Headers);
        var doc = _service.GenerateNaaccrXml(csv, mappings);

        // Use the actual save pipeline: FormatXml + WriteAllText with UTF-8
        var formattedXml = XmlFormattingHelper.FormatXml(doc.OuterXml);
        var tempPath = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempPath, formattedXml, Encoding.UTF8);

            var xmlService = new XmlFileService();
            var (loadedDoc, tumors, nsMgr) = xmlService.LoadNaaccrXml(tempPath);

            Assert.Equal(3, tumors.Count);

            // Verify patient grouping survived
            var patients = loadedDoc.SelectNodes("//n:Patient", nsMgr)!;
            Assert.Equal(2, patients.Count);

            // Verify values
            Assert.Equal("C509", xmlService.GetItemValue(tumors[0]!, "primarySite", nsMgr));
            Assert.Equal("C504", xmlService.GetItemValue(tumors[1]!, "primarySite", nsMgr));
            Assert.Equal("C180", xmlService.GetItemValue(tumors[2]!, "dateOfDiagnosis", nsMgr) != "" ? xmlService.GetItemValue(tumors[2]!, "primarySite", nsMgr) : "");

            var patient1 = xmlService.GetPatientForTumor(tumors[0]!);
            Assert.Equal("Smith", xmlService.GetItemValue(patient1!, "nameLast", nsMgr));
            Assert.Equal("John", xmlService.GetItemValue(patient1!, "nameFirst", nsMgr));
        }
        finally
        {
            File.Delete(tempPath);
        }
    }

    // ── Comprehensive All-Fields Test ───────────────────────────────────

    [Fact]
    public void GenerateNaaccrXml_AllMappedValues_PresentAtCorrectLevel()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "patientIdNumber", "nameLast", "nameFirst", "dateOfBirth", "primarySite", "dateOfDiagnosis", "behaviorCodeIcdO3" },
            Rows = new List<string[]>
            {
                new[] { "P001", "Smith", "John", "19650315", "C509", "20240115", "3" },
                new[] { "P001", "Smith", "John", "19650315", "C504", "20240320", "3" },
                new[] { "P002", "Jones", "Maria", "19780822", "C180", "20240201", "3" }
            }
        };

        var mappings = _service.AutoMatch(csv.Headers);
        Assert.All(mappings, m => Assert.True(m.IsAutoMatched));

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        var patients = doc.SelectNodes("//n:Patient", nsMgr)!;
        Assert.Equal(2, patients.Count);

        // ── Patient 1 (P001, 2 tumors) ──
        var p1 = patients[0]!;
        Assert.Equal("P001", GetItemValue(p1, "patientIdNumber", nsMgr));
        Assert.Equal("Smith", GetItemValue(p1, "nameLast", nsMgr));
        Assert.Equal("John", GetItemValue(p1, "nameFirst", nsMgr));
        Assert.Equal("19650315", GetItemValue(p1, "dateOfBirth", nsMgr));

        var p1Tumors = p1.SelectNodes("./n:Tumor", nsMgr)!;
        Assert.Equal(2, p1Tumors.Count);

        Assert.Equal("C509", GetItemValue(p1Tumors[0]!, "primarySite", nsMgr));
        Assert.Equal("20240115", GetItemValue(p1Tumors[0]!, "dateOfDiagnosis", nsMgr));
        Assert.Equal("3", GetItemValue(p1Tumors[0]!, "behaviorCodeIcdO3", nsMgr));

        Assert.Equal("C504", GetItemValue(p1Tumors[1]!, "primarySite", nsMgr));
        Assert.Equal("20240320", GetItemValue(p1Tumors[1]!, "dateOfDiagnosis", nsMgr));

        // ── Patient 2 (P002, 1 tumor) ──
        var p2 = patients[1]!;
        Assert.Equal("P002", GetItemValue(p2, "patientIdNumber", nsMgr));
        Assert.Equal("Jones", GetItemValue(p2, "nameLast", nsMgr));
        Assert.Equal("Maria", GetItemValue(p2, "nameFirst", nsMgr));

        var p2Tumors = p2.SelectNodes("./n:Tumor", nsMgr)!;
        Assert.Equal(1, p2Tumors.Count);
        Assert.Equal("C180", GetItemValue(p2Tumors[0]!, "primarySite", nsMgr));
        Assert.Equal("20240201", GetItemValue(p2Tumors[0]!, "dateOfDiagnosis", nsMgr));
    }

    [Fact]
    public void GenerateNaaccrXml_PatientLevelFields_NotDuplicatedOnTumors()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "patientIdNumber", "nameLast", "primarySite" },
            Rows = new List<string[]>
            {
                new[] { "P001", "Smith", "C509" },
                new[] { "P001", "Smith", "C504" }
            }
        };

        var mappings = _service.AutoMatch(csv.Headers);
        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);

        // nameLast is Patient-level — should be on Patient, not on Tumor
        var patient = doc.SelectSingleNode("//n:Patient", nsMgr)!;
        Assert.Equal("Smith", GetItemValue(patient, "nameLast", nsMgr));

        var tumors = patient.SelectNodes("./n:Tumor", nsMgr)!;
        for (int i = 0; i < tumors.Count; i++)
        {
            var tumorNameLast = tumors[i]!.SelectSingleNode("./n:Item[@naaccrId='nameLast']", nsMgr);
            Assert.Null(tumorNameLast); // Should NOT be on Tumor
        }

        // primarySite is Tumor-level — should be on each Tumor
        Assert.Equal("C509", GetItemValue(tumors[0]!, "primarySite", nsMgr));
        Assert.Equal("C504", GetItemValue(tumors[1]!, "primarySite", nsMgr));
    }

    [Fact]
    public void GenerateNaaccrXml_WhitespaceInValues_IsTrimmed()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "nameLast", "nameFirst" },
            Rows = new List<string[]>
            {
                new[] { "  Smith  ", "  Jane " }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "nameLast", MappedNaaccrId = "nameLast" },
            new() { CsvColumnIndex = 1, CsvHeader = "nameFirst", MappedNaaccrId = "nameFirst" }
        };

        var doc = _service.GenerateNaaccrXml(csv, mappings);
        var nsMgr = CreateNsMgr(doc);
        var patient = doc.SelectSingleNode("//n:Patient", nsMgr)!;

        Assert.Equal("Smith", GetItemValue(patient, "nameLast", nsMgr));
        Assert.Equal("Jane", GetItemValue(patient, "nameFirst", nsMgr));
    }

    // ── Helper ──────────────────────────────────────────────────────────

    private static string GetItemValue(XmlNode node, string naaccrId, XmlNamespaceManager nsMgr)
    {
        return node.SelectSingleNode($"./n:Item[@naaccrId='{naaccrId}']", nsMgr)?.InnerText ?? "";
    }

    private static XmlNamespaceManager CreateNsMgr(XmlDocument doc)
    {
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml");
        return nsMgr;
    }
}
