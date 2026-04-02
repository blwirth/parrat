using System.Xml;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class ConcatenateServiceTests : IDisposable
{
    private readonly ConcatenateService _service = new();
    private readonly string _tempDir;

    public ConcatenateServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_concat_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    #region GetXmlHeaderInfo

    [Fact]
    public void GetXmlHeaderInfo_ReturnsSuccessForValidFile()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Smith",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
        });
        var path = WriteFile("test.xml", xml);

        var info = _service.GetXmlHeaderInfo(path);
        Assert.True((bool)info["Success"]);
        Assert.Equal(1, (int)info["TumorCount"]);
    }

    [Fact]
    public void GetXmlHeaderInfo_ReturnsErrorForBadFile()
    {
        var path = WriteFile("bad.xml", "not xml");
        var info = _service.GetXmlHeaderInfo(path);
        Assert.False((bool)info["Success"]);
    }

    #endregion

    #region GetDuplicatePatientIds

    [Fact]
    public void GetDuplicatePatientIds_FindsDuplicatesAcrossFiles()
    {
        var xml1 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT001",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
        });
        var xml2 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT001",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" } }
        });

        var path1 = WriteFile("f1.xml", xml1);
        var path2 = WriteFile("f2.xml", xml2);

        var info1 = _service.GetXmlHeaderInfo(path1);
        var info2 = _service.GetXmlHeaderInfo(path2);

        var duplicates = _service.GetDuplicatePatientIds(new List<Dictionary<string, object>> { info1, info2 });
        Assert.Single(duplicates);
        Assert.Equal("PAT001", duplicates[0]);
    }

    [Fact]
    public void GetDuplicatePatientIds_NoDuplicates_ReturnsEmpty()
    {
        var xml1 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT001",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
        });
        var xml2 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            PatientIdNumber = "PAT002",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" } }
        });

        var path1 = WriteFile("f1.xml", xml1);
        var path2 = WriteFile("f2.xml", xml2);

        var duplicates = _service.GetDuplicatePatientIds(new List<Dictionary<string, object>>
        {
            _service.GetXmlHeaderInfo(path1),
            _service.GetXmlHeaderInfo(path2)
        });
        Assert.Empty(duplicates);
    }

    #endregion

    #region TestXmlHeaderAgainstReference

    [Fact]
    public void TestXmlHeaderAgainstReference_ValidWhenMatching()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var path = WriteFile("ref.xml", xml);
        var info = _service.GetXmlHeaderInfo(path);

        var (valid, error) = _service.TestXmlHeaderAgainstReference(info, info);
        Assert.True(valid);
        Assert.Null(error);
    }

    [Fact]
    public void TestXmlHeaderAgainstReference_InvalidWhenMismatched()
    {
        var xml1 = NaaccrXmlTestHelper.BuildNaaccrXml(recordType: "I", patients: new NaaccrXmlTestHelper.PatientData
        { Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } } });
        var xml2 = NaaccrXmlTestHelper.BuildNaaccrXml(recordType: "A", patients: new NaaccrXmlTestHelper.PatientData
        { Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } } });

        var path1 = WriteFile("f1.xml", xml1);
        var path2 = WriteFile("f2.xml", xml2);

        var info1 = _service.GetXmlHeaderInfo(path1);
        var info2 = _service.GetXmlHeaderInfo(path2);

        var (valid, error) = _service.TestXmlHeaderAgainstReference(info2, info1);
        Assert.False(valid);
        Assert.Contains("recordType", error!);
    }

    #endregion

    #region WriteConcatenatedXmlFromPaths

    [Fact]
    public void WriteConcatenatedXmlFromPaths_MergesPatients()
    {
        var xml1 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Smith",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
        });
        var xml2 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Jones",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" } }
        });

        var path1 = WriteFile("f1.xml", xml1);
        var path2 = WriteFile("f2.xml", xml2);
        var outputPath = Path.Combine(_tempDir, "merged.xml");

        _service.WriteConcatenatedXmlFromPaths(new[] { path1, path2 }, outputPath);

        var outDoc = new XmlDocument();
        outDoc.Load(outputPath);
        var nsMgr = new XmlNamespaceManager(outDoc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);

        var patients = outDoc.SelectNodes("//n:Patient", nsMgr)!;
        Assert.Equal(2, patients.Count);
    }

    #endregion

    #region GetHl7FileInfo

    [Fact]
    public void GetHl7FileInfo_CountsMessages()
    {
        var content = "MSH|^~\\&|App|Fac\nPID|1||001\nMSH|^~\\&|App|Fac\nPID|1||002\n";
        var path = WriteFile("test.hl7", content);

        var info = _service.GetHl7FileInfo(path);
        Assert.True((bool)info["Success"]);
        Assert.Equal(2, (int)info["MessageCount"]);
    }

    #endregion

    #region GetHl7MessagePreview

    [Fact]
    public void GetHl7MessagePreview_ShowsLimitedMessages()
    {
        var content = "MSH|^~\\&|A\nPID|1||001\nMSH|^~\\&|B\nPID|1||002\nMSH|^~\\&|C\nPID|1||003\nMSH|^~\\&|D\nPID|1||004\n";
        var preview = _service.GetHl7MessagePreview(content, 2);

        Assert.Contains("Message 1:", preview);
        Assert.Contains("Message 2:", preview);
        Assert.DoesNotContain("Message 3:", preview);
    }

    [Fact]
    public void GetHl7MessagePreview_ReturnsEmptyForEmptyContent()
    {
        Assert.Equal("", _service.GetHl7MessagePreview(""));
    }

    #endregion

    #region WriteConcatenatedHl7FromPaths

    [Fact]
    public void WriteConcatenatedHl7FromPaths_MergesFiles()
    {
        var path1 = WriteFile("a.hl7", "MSH|^~\\&|A\rPID|1||001");
        var path2 = WriteFile("b.hl7", "MSH|^~\\&|B\rPID|1||002");
        var outputPath = Path.Combine(_tempDir, "merged.hl7");

        _service.WriteConcatenatedHl7FromPaths(new[] { path1, path2 }, outputPath);

        var content = File.ReadAllText(outputPath);
        Assert.Contains("MSH|^~\\&|A", content);
        Assert.Contains("MSH|^~\\&|B", content);
    }

    #endregion

    #region GetTxtFileInfo

    [Fact]
    public void GetTxtFileInfo_ReturnsLineCountAndSize()
    {
        var path = WriteFile("test.txt", "line1\nline2\nline3");
        var info = _service.GetTxtFileInfo(path);

        Assert.True((bool)info["Success"]);
        Assert.Equal(3, (int)info["LineCount"]);
    }

    #endregion

    #region GetTxtFilePreview

    [Fact]
    public void GetTxtFilePreview_LimitsLines()
    {
        var content = "line1\nline2\nline3\nline4\nline5\nline6\nline7";
        var preview = _service.GetTxtFilePreview(content, 3);

        Assert.Contains("line1", preview);
        Assert.Contains("line3", preview);
        Assert.DoesNotContain("line4", preview);
    }

    #endregion

    private string WriteFile(string name, string content)
    {
        var path = Path.Combine(_tempDir, name);
        File.WriteAllText(path, content);
        return path;
    }
}
