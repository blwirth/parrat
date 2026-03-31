using System.Xml;
using Parat.Core.Helpers;
using Parat.Core.Models;
using Parat.Core.Services;
using Parat.Tests.Helpers;
using Xunit;

namespace Parat.Tests.Services;

public class ExportServiceTests : IDisposable
{
    private readonly string _tempDir;

    public ExportServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parat_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);

        // Re-anchor RepoRoot to the actual repo so NaaccrDictionary can find
        // data/dictionaries even when parallel test classes call SetRepoRoot.
        PathHelper.SetRepoRoot(FindRepoRoot());
    }

    private static string FindRepoRoot()
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        for (int i = 0; i < 10; i++)
        {
            if (Directory.Exists(Path.Combine(dir, "data")))
                return dir;
            var parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        return AppDomain.CurrentDomain.BaseDirectory;
    }

    public void Dispose()
    {
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

    private static (XmlDocument, XmlNamespaceManager) LoadXml(string xml)
    {
        var xmlDoc = new XmlDocument();
        xmlDoc.XmlResolver = null;
        xmlDoc.LoadXml(xml);

        var nsMgr = new XmlNamespaceManager(xmlDoc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);

        return (xmlDoc, nsMgr);
    }
}
