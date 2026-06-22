using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class ExportServiceTests : IDisposable
{
    private readonly string _tempDir;
    private readonly string _originalRepoRoot;
    private readonly string _originalUserDir;

    public ExportServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);

        _originalRepoRoot = PathHelper.RepoRoot;
        _originalUserDir = PathHelper.UserDir;

        // Re-anchor RepoRoot to the actual repo so NaaccrDictionary can find
        // data/dictionaries even when parallel test classes call SetRepoRoot.
        PathHelper.SetRepoRoot(TestEnvironment.FindRepoRoot());
    }

    public void Dispose()
    {
        PathHelper.SetRepoRoot(_originalRepoRoot);
        PathHelper.SetUserDir(_originalUserDir);

        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, true);
    }

    /// <summary>
    /// Regression test: Patient-level fields (nameLast, nameFirst, dateOfBirth, patientIdNumber)
    /// must appear in CSV output when ParentElement is correctly set to "Patient".
    /// This was broken when ParentElement defaulted to null/Tumor for standard Patient fields.
    /// </summary>
    [Fact]
    public void ExportAllCsv_PatientLevelFields_AreNotEmpty()
    {
        // Arrange
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT001",
            NameLast = "Smith",
            NameFirst = "John",
            DateOfBirth = "19800115",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData
                {
                    PrimarySite = "C509",
                    DateOfDiagnosis = "20240101"
                }
            }
        });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var outputPath = Path.Combine(_tempDir, "export.csv");

        // Fields with correct ParentElement — the way the fix now builds them
        var fields = new List<ExportField>
        {
            new() { XmlId = "patientIdNumber", ParentElement = "Patient" },
            new() { XmlId = "nameLast", ParentElement = "Patient" },
            new() { XmlId = "nameFirst", ParentElement = "Patient" },
            new() { XmlId = "dateOfBirth", ParentElement = "Patient" },
            new() { XmlId = "primarySite", ParentElement = "Tumor" },
            new() { XmlId = "dateOfDiagnosis", ParentElement = "Tumor" },
        };

        // Act
        var service = new ExportService();
        service.ExportAllCsv(xmlDoc, nsMgr, outputPath, fields);

        // Assert
        var lines = File.ReadAllLines(outputPath);
        Assert.Equal(2, lines.Length); // header + 1 data row

        var header = lines[0].Split(',');
        var values = lines[1].Split(',');

        Assert.Equal("patientIdNumber", header[0]);
        Assert.Equal("PAT001", values[0]);
        Assert.Equal("Smith", values[1]);
        Assert.Equal("John", values[2]);
        Assert.Equal("19800115", values[3]);
        Assert.Equal("C509", values[4]);
        Assert.Equal("20240101", values[5]);
    }

    /// <summary>
    /// Proves the old bug: if ParentElement is null (the broken default), Patient fields come back empty.
    /// This test ensures that if someone reintroduces null ParentElement for Patient fields, it fails.
    /// </summary>
    [Fact]
    public void ExportAllCsv_NullParentElement_PatientFieldsAreEmpty()
    {
        // Arrange
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT001",
            NameLast = "Smith",
            NameFirst = "John",
            DateOfBirth = "19800115",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData
                {
                    PrimarySite = "C509",
                    DateOfDiagnosis = "20240101"
                }
            }
        });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var outputPath = Path.Combine(_tempDir, "export_broken.csv");

        // Null ParentElement — reproduces the old broken behavior
        var fields = new List<ExportField>
        {
            new() { XmlId = "patientIdNumber", ParentElement = null },
            new() { XmlId = "nameLast", ParentElement = null },
            new() { XmlId = "nameFirst", ParentElement = null },
            new() { XmlId = "dateOfBirth", ParentElement = null },
            new() { XmlId = "primarySite", ParentElement = "Tumor" },
        };

        // Act
        var service = new ExportService();
        service.ExportAllCsv(xmlDoc, nsMgr, outputPath, fields);

        // Assert — Patient fields are empty because they defaulted to Tumor lookup
        var lines = File.ReadAllLines(outputPath);
        var values = lines[1].Split(',');

        Assert.Equal("", values[0]); // patientIdNumber — empty (wrong parent)
        Assert.Equal("", values[1]); // nameLast — empty
        Assert.Equal("", values[2]); // nameFirst — empty
        Assert.Equal("", values[3]); // dateOfBirth — empty
        Assert.Equal("C509", values[4]); // primarySite — still works (Tumor is correct)
    }

    /// <summary>
    /// Multi-patient export: each tumor row should carry its own patient's data.
    /// </summary>
    [Fact]
    public void ExportAllCsv_MultiplePatients_EachRowHasCorrectPatientData()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                PatientIdNumber = "PAT001",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" }
                }
            },
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Jones",
                PatientIdNumber = "PAT002",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" }
                }
            }
        });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var outputPath = Path.Combine(_tempDir, "export_multi.csv");

        var fields = new List<ExportField>
        {
            new() { XmlId = "patientIdNumber", ParentElement = "Patient" },
            new() { XmlId = "nameLast", ParentElement = "Patient" },
            new() { XmlId = "primarySite", ParentElement = "Tumor" },
        };

        var service = new ExportService();
        service.ExportAllCsv(xmlDoc, nsMgr, outputPath, fields);

        var lines = File.ReadAllLines(outputPath);
        Assert.Equal(3, lines.Length); // header + 2 data rows

        var row1 = lines[1].Split(',');
        Assert.Equal("PAT001", row1[0]);
        Assert.Equal("Smith", row1[1]);
        Assert.Equal("C509", row1[2]);

        var row2 = lines[2].Split(',');
        Assert.Equal("PAT002", row2[0]);
        Assert.Equal("Jones", row2[1]);
        Assert.Equal("C189", row2[2]);
    }

    /// <summary>
    /// Integration test: build ExportField list using NaaccrDictionary.GetParentElement()
    /// exactly as the UI does. This catches the original bug where ParentElement was only
    /// populated from custom field overrides and Patient fields resolved to null/Tumor.
    /// </summary>
    [Fact]
    public void ExportAllCsv_FieldsBuiltViaDictionary_PatientFieldsPopulated()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT999",
            NameLast = "Garcia",
            NameFirst = "Maria",
            DateOfBirth = "19751225",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData
                {
                    PrimarySite = "C220",
                    DateOfDiagnosis = "20230601"
                }
            }
        });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var outputPath = Path.Combine(_tempDir, "export_dict.csv");

        // Use the real NAACCR dictionary to resolve ParentElement — same as UI code path
        var dictionary = new NaaccrDictionary();
        dictionary.Initialize(25);

        var fieldIds = new[] { "patientIdNumber", "nameLast", "nameFirst", "dateOfBirth", "primarySite", "dateOfDiagnosis" };
        var exportFields = fieldIds.Select(id => new ExportField
        {
            XmlId = id,
            ParentElement = dictionary.GetParentElement(id)
        }).ToList();

        // Verify the dictionary resolved Patient fields correctly
        Assert.Equal("Patient", exportFields[0].ParentElement); // patientIdNumber
        Assert.Equal("Patient", exportFields[1].ParentElement); // nameLast
        Assert.Equal("Tumor", exportFields[4].ParentElement);   // primarySite

        // Act
        var service = new ExportService();
        service.ExportAllCsv(xmlDoc, nsMgr, outputPath, exportFields);

        // Assert
        var lines = File.ReadAllLines(outputPath);
        Assert.Equal(2, lines.Length);

        var values = lines[1].Split(',');
        Assert.Equal("PAT999", values[0]);
        Assert.Equal("Garcia", values[1]);
        Assert.Equal("Maria", values[2]);
        Assert.Equal("19751225", values[3]);
        Assert.Equal("C220", values[4]);
        Assert.Equal("20230601", values[5]);
    }

    /// <summary>
    /// NaaccrData-level fields (e.g. recordType, registryType) live on the root element,
    /// not under Patient or Tumor. Export must look up the document root for these.
    /// </summary>
    [Fact]
    public void ExportAllCsv_NaaccrDataLevelFields_AreNotEmpty()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(
            naaccrDataItems: new Dictionary<string, string>
            {
                { "recordType", "I" },
                { "registryType", "1" }
            },
            patients: new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" }
                }
            });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var outputPath = Path.Combine(_tempDir, "export_naaccrdata.csv");

        var fields = new List<ExportField>
        {
            new() { XmlId = "recordType", ParentElement = "NaaccrData" },
            new() { XmlId = "registryType", ParentElement = "NaaccrData" },
            new() { XmlId = "nameLast", ParentElement = "Patient" },
            new() { XmlId = "primarySite", ParentElement = "Tumor" },
        };

        var service = new ExportService();
        service.ExportAllCsv(xmlDoc, nsMgr, outputPath, fields);

        var lines = File.ReadAllLines(outputPath);
        Assert.Equal(2, lines.Length);

        var values = lines[1].Split(',');
        Assert.Equal("I", values[0]);       // recordType — NaaccrData level
        Assert.Equal("1", values[1]);       // registryType — NaaccrData level
        Assert.Equal("Smith", values[2]);   // nameLast — Patient level
        Assert.Equal("C509", values[3]);    // primarySite — Tumor level
    }

    // =====================================================================
    //  "Select all present variables" — scan -> fields -> CSV integration
    // =====================================================================

    /// <summary>
    /// Two-tumor file where the selected tumor has primarySite and the other has
    /// pathReportNumber1. Scanning only the selected tumor and exporting it must yield a
    /// CSV whose columns are exactly the present variables — the non-selected tumor's
    /// variable must NOT become a column.
    /// </summary>
    [Fact]
    public void ScanThenExportSelected_SelectedScope_ExcludesVariablesOnlyInOtherTumors()
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

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        var selected = new[] { 0 };

        var scan = VariableScanHelper.ScanPresentVariables(tumors, selected, nsMgr);
        var fields = BuildOrderedFields(scan, CreateDictionary());

        var outputPath = Path.Combine(_tempDir, "selected_scope.csv");
        new ExportService(tumors).ExportSelectedCsv(selected, xmlDoc, nsMgr, outputPath, fields);

        var header = File.ReadAllLines(outputPath)[0].Split(',');
        Assert.Contains("primarySite", header);
        Assert.Contains("nameLast", header);
        Assert.DoesNotContain("pathReportNumber1", header);
    }

    /// <summary>
    /// Same file, but scanning ALL loaded records (the "negative information" option) while
    /// still exporting only the selected tumor: pathReportNumber1 becomes a column even
    /// though it appears in no exported row — its cell is blank for the exported tumor.
    /// </summary>
    [Fact]
    public void ScanThenExportSelected_AllRecordsScope_IncludesNonSelectedVariableAsBlankColumn()
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

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        var selected = new[] { 0 };
        var allRecords = new[] { 0, 1 };

        var scan = VariableScanHelper.ScanPresentVariables(tumors, allRecords, nsMgr);
        var fields = BuildOrderedFields(scan, CreateDictionary());

        var outputPath = Path.Combine(_tempDir, "all_records_scope.csv");
        new ExportService(tumors).ExportSelectedCsv(selected, xmlDoc, nsMgr, outputPath, fields);

        var lines = File.ReadAllLines(outputPath);
        var header = lines[0].Split(',');
        var values = lines[1].Split(',');

        Assert.Equal(2, lines.Length); // header + 1 exported row
        var col = Array.IndexOf(header, "pathReportNumber1");
        Assert.True(col >= 0, "pathReportNumber1 should be a column under all-records scope");
        Assert.Equal("", values[col]); // present as a (blank) column for the exported row
    }

    /// <summary>
    /// The CSV columns produced from a scan must appear in canonical NAACCR order
    /// (by item number), matching how the export dialog orders auto-selected fields.
    /// </summary>
    [Fact]
    public void ScanThenExport_OrdersColumnsByNaaccrNumber()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT001",
            NameLast = "Smith",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509", DateOfDiagnosis = "20240101" }
            }
        });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;

        var scan = VariableScanHelper.ScanPresentVariables(tumors, new[] { 0 }, nsMgr);
        var dict = CreateDictionary();
        var fields = BuildOrderedFields(scan, dict);

        var outputPath = Path.Combine(_tempDir, "ordered.csv");
        new ExportService(tumors).ExportAllCsv(xmlDoc, nsMgr, outputPath, fields);

        var header = File.ReadAllLines(outputPath)[0].Split(',');

        // Header item numbers must be non-decreasing.
        var numbers = header
            .Select(id => dict.GetItemByXmlId(id)?.NumberInt ?? int.MaxValue)
            .ToList();
        var sorted = numbers.OrderBy(n => n).ToList();
        Assert.Equal(sorted, numbers);
    }

    /// <summary>
    /// A naaccrId present in the XML but absent from the dictionary must still export with
    /// its value when registered as a custom field at the level the scanner found it.
    /// </summary>
    [Fact]
    public void ScanThenExport_UnknownNaaccrId_ExportsValueViaCustomParent()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(
            naaccrDataItems: new Dictionary<string, string> { ["madeUpVariable"] = "XYZ" },
            patients: new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Doe",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
            });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;

        var scan = VariableScanHelper.ScanPresentVariables(tumors, new[] { 0 }, nsMgr);
        Assert.Equal("NaaccrData", scan["madeUpVariable"]); // found at file level

        var customFields = new Dictionary<string, string> { ["madeUpVariable"] = scan["madeUpVariable"] };
        var fields = new List<ExportField>
        {
            new() { XmlId = "madeUpVariable", IsCustom = true, ParentElement = "NaaccrData" }
        };

        var outputPath = Path.Combine(_tempDir, "unknown.csv");
        new ExportService(tumors).ExportAllCsv(xmlDoc, nsMgr, outputPath, fields, customFields);

        var lines = File.ReadAllLines(outputPath);
        Assert.Equal("madeUpVariable", lines[0]);
        Assert.Equal("XYZ", lines[1]);
    }

    /// <summary>
    /// Mirrors the export dialog's ordering: existing logic that turns a scan result into a
    /// canonically-ordered ExportField list (by NAACCR number, dictionary-unknown ids last).
    /// </summary>
    private static List<ExportField> BuildOrderedFields(
        Dictionary<string, string> scan, NaaccrDictionary dict)
    {
        // Use the same production ordering the export dialog uses.
        return VariableScanHelper.OrderByNaaccr(scan.Keys, dict)
            .Select(id => new ExportField
            {
                XmlId = id,
                IsCustom = dict.GetItemByXmlId(id) == null,
                ParentElement = dict.GetItemByXmlId(id)?.ParentElement is { Length: > 0 } p
                    ? p
                    : scan[id]
            })
            .ToList();
    }

    private static NaaccrDictionary CreateDictionary(int version = 25)
    {
        PathHelper.SetRepoRoot(TestEnvironment.FindRepoRoot());
        var dict = new NaaccrDictionary();
        dict.Initialize(version);
        return dict;
    }

    private static (XmlDocument, XmlNamespaceManager) LoadXml(string xml)
    {
        var xmlDoc = new XmlDocument();
        xmlDoc.XmlResolver = null;
        xmlDoc.LoadXml(xml);

        var nsMgr = new XmlNamespaceManager(xmlDoc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);

        return (xmlDoc, nsMgr);
    }

    // =====================================================================
    //  ExportHl7Csv
    // =====================================================================

    [Fact]
    public void ExportHl7Csv_WritesAllMessages()
    {
        var messages = new List<Hl7Message>
        {
            new() { PatientLastName = "Smith", PatientFirstName = "John", DateOfBirth = "19800101", MessageDateTime = "20240101120000" },
            new() { PatientLastName = "Jones", PatientFirstName = "Jane", DateOfBirth = "19900215", MessageDateTime = "20240102080000" },
        };
        var outputPath = Path.Combine(_tempDir, "hl7_export.csv");

        var service = new ExportService();
        service.ExportAllHl7Csv(messages, outputPath);

        var lines = File.ReadAllLines(outputPath);
        Assert.Equal(3, lines.Length); // header + 2 rows
        Assert.Equal("LastName,FirstName,DateOfBirth,MessageDateTime", lines[0]);
        Assert.Equal("Smith,John,19800101,20240101120000", lines[1]);
        Assert.Equal("Jones,Jane,19900215,20240102080000", lines[2]);
    }

    [Fact]
    public void ExportSelectedHl7Csv_WritesOnlySelectedMessages()
    {
        var messages = new List<Hl7Message>
        {
            new() { PatientLastName = "Smith", PatientFirstName = "John", DateOfBirth = "19800101", MessageDateTime = "20240101" },
            new() { PatientLastName = "Jones", PatientFirstName = "Jane", DateOfBirth = "19900215", MessageDateTime = "20240102" },
            new() { PatientLastName = "Brown", PatientFirstName = "Bob", DateOfBirth = "19750530", MessageDateTime = "20240103" },
        };
        var outputPath = Path.Combine(_tempDir, "hl7_selected.csv");

        var service = new ExportService();
        service.ExportSelectedHl7Csv(new[] { 0, 2 }, messages, outputPath);

        var lines = File.ReadAllLines(outputPath);
        Assert.Equal(3, lines.Length); // header + 2 selected rows
        Assert.Contains("Smith", lines[1]);
        Assert.Contains("Brown", lines[2]);
    }

    // =====================================================================
    //  ExportSelectedXml
    // =====================================================================

    [Fact]
    public void ExportSelectedXml_WritesOnlySelectedTumors()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" },
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" },
                }
            }
        });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var outputPath = Path.Combine(_tempDir, "selected.xml");

        var service = new ExportService();
        service.ExportSelectedXml(new[] { 0 }, xmlDoc, nsMgr, outputPath);

        var outDoc = new XmlDocument();
        outDoc.Load(outputPath);
        var outNsMgr = new XmlNamespaceManager(outDoc.NameTable);
        outNsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);

        var tumors = outDoc.SelectNodes("//n:Tumor", outNsMgr)!;
        Assert.Equal(1, tumors.Count);

        var site = tumors[0]!.SelectSingleNode("./n:Item[@naaccrId='primarySite']", outNsMgr);
        Assert.Equal("C509", site!.InnerText);
    }

    // =====================================================================
    //  ExportSelectedHl7
    // =====================================================================

    [Fact]
    public void ExportSelectedHl7_WritesRawContentOfSelectedMessages()
    {
        var messages = new List<Hl7Message>
        {
            new() { RawContent = "MSH|^~\\&|A\rPID|1||001\r" },
            new() { RawContent = "MSH|^~\\&|B\rPID|1||002\r" },
        };
        var outputPath = Path.Combine(_tempDir, "selected.hl7");

        var service = new ExportService();
        service.ExportSelectedHl7(new[] { 1 }, messages, outputPath);

        var content = File.ReadAllText(outputPath);
        Assert.Contains("MSH|^~\\&|B", content);
        Assert.DoesNotContain("MSH|^~\\&|A", content);
    }

    // =====================================================================
    //  ExportSelectedCsv (delegates to ExportTumorsCsv)
    // =====================================================================

    [Fact]
    public void ExportSelectedCsv_WritesOnlySelectedTumors()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" },
                    new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" },
                }
            }
        });

        var (xmlDoc, nsMgr) = LoadXml(xml);
        var outputPath = Path.Combine(_tempDir, "selected.csv");

        var fields = new List<ExportField>
        {
            new() { XmlId = "primarySite", ParentElement = "Tumor" },
        };

        var service = new ExportService();
        service.ExportSelectedCsv(new[] { 1 }, xmlDoc, nsMgr, outputPath, fields);

        var lines = File.ReadAllLines(outputPath);
        Assert.Equal(2, lines.Length); // header + 1 row
        Assert.Equal("C189", lines[1]);
    }
}
