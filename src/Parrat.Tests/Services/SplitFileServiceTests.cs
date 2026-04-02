using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class SplitFileServiceTests : IDisposable
{
    private readonly SplitFileService _service = new();
    private readonly string _tempDir;

    public SplitFileServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_split_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    #region GetAlphabetRanges

    [Fact]
    public void GetAlphabetRanges_Returns2Ranges()
    {
        var ranges = _service.GetAlphabetRanges(2);
        Assert.Equal(2, ranges.Count);
        Assert.Equal("A-M", ranges[0]);
        Assert.Equal("N-Z", ranges[1]);
    }

    [Fact]
    public void GetAlphabetRanges_Returns5Ranges()
    {
        var ranges = _service.GetAlphabetRanges(5);
        Assert.Equal(5, ranges.Count);
        Assert.Equal("A-E", ranges[0]);
        Assert.Equal("U-Z", ranges[4]);
    }

    [Fact]
    public void GetAlphabetRanges_ThrowsForInvalidCount()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => _service.GetAlphabetRanges(1));
        Assert.Throws<ArgumentOutOfRangeException>(() => _service.GetAlphabetRanges(6));
    }

    #endregion

    #region GetFileSplitBucket

    [Fact]
    public void GetFileSplitBucket_CorrectBucketForTwoWaySplit()
    {
        Assert.Equal(0, _service.GetFileSplitBucket("Adams", 2));   // A = A-M
        Assert.Equal(0, _service.GetFileSplitBucket("Miller", 2));  // M = A-M
        Assert.Equal(1, _service.GetFileSplitBucket("Nelson", 2));  // N = N-Z
        Assert.Equal(1, _service.GetFileSplitBucket("Zane", 2));    // Z = N-Z
    }

    [Fact]
    public void GetFileSplitBucket_EmptyName_GoesToLastBucket()
    {
        Assert.Equal(1, _service.GetFileSplitBucket("", 2));
        Assert.Equal(2, _service.GetFileSplitBucket("", 3));
    }

    [Fact]
    public void GetFileSplitBucket_CaseInsensitive()
    {
        Assert.Equal(_service.GetFileSplitBucket("smith", 2), _service.GetFileSplitBucket("Smith", 2));
    }

    [Fact]
    public void GetFileSplitBucket_NonAlphaFirstChar_GoesToLastBucket()
    {
        Assert.Equal(1, _service.GetFileSplitBucket("123Name", 2));
    }

    #endregion

    #region GetSplitDistribution

    [Fact]
    public void GetSplitDistribution_CountsByBucket()
    {
        var names = new List<string> { "Adams", "Baker", "Nelson", "Smith", "Zane" };
        var dist = _service.GetSplitDistribution(names, 2);

        Assert.Equal(2, dist["A-M"]); // Adams, Baker
        Assert.Equal(3, dist["N-Z"]); // Nelson, Smith, Zane
    }

    #endregion

    #region GetXmlFileSplitInfo

    [Fact]
    public void GetXmlFileSplitInfo_ParsesValidXmlFile()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
            },
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Jones",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" } }
            }
        });

        var filePath = Path.Combine(_tempDir, "split_test.xml");
        File.WriteAllText(filePath, xml);

        var result = _service.GetXmlFileSplitInfo(filePath);
        Assert.True((bool)result["Success"]);
        Assert.Equal(2, (int)result["TotalPatients"]);
        Assert.Equal(2, (int)result["TotalTumors"]);
    }

    [Fact]
    public void GetXmlFileSplitInfo_ReturnsErrorForInvalidFile()
    {
        var filePath = Path.Combine(_tempDir, "bad.xml");
        File.WriteAllText(filePath, "not valid xml");

        var result = _service.GetXmlFileSplitInfo(filePath);
        Assert.False((bool)result["Success"]);
    }

    #endregion

    #region GetHl7FileSplitInfo

    [Fact]
    public void GetHl7FileSplitInfo_ParsesHl7Messages()
    {
        var hl7 = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|M1|P|2.5\rPID|1||001||Smith^John\r\rMSH|^~\\&|App|Fac|||20240102||ORU^R01|M2|P|2.5\rPID|1||002||Jones^Jane\r";
        var filePath = Path.Combine(_tempDir, "split_test.hl7");
        File.WriteAllText(filePath, hl7);

        var result = _service.GetHl7FileSplitInfo(filePath);
        Assert.True((bool)result["Success"]);
        Assert.Equal(2, (int)result["TotalMessages"]);
    }

    #endregion

    #region SplitXmlFile

    [Fact]
    public void SplitXmlFile_CreatesOutputFiles()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            new NaaccrXmlTestHelper.PatientData { NameLast = "Adams", Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } } },
            new NaaccrXmlTestHelper.PatientData { NameLast = "Zane", Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" } } },
        });

        var filePath = Path.Combine(_tempDir, "input.xml");
        File.WriteAllText(filePath, xml);

        var scanResult = _service.GetXmlFileSplitInfo(filePath);
        var outputDir = Path.Combine(_tempDir, "output");
        Directory.CreateDirectory(outputDir);

        _service.SplitXmlFile(scanResult, filePath, 2, outputDir);

        Assert.True(File.Exists(Path.Combine(outputDir, "input_A-M.xml")));
        Assert.True(File.Exists(Path.Combine(outputDir, "input_N-Z.xml")));
    }

    #endregion

    #region SplitHl7File

    [Fact]
    public void SplitHl7File_CreatesOutputFiles()
    {
        var hl7 = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|M1|P|2.5\nPID|1||001||Adams^John\n\nMSH|^~\\&|App|Fac|||20240102||ORU^R01|M2|P|2.5\nPID|1||002||Zane^Bob";
        var filePath = Path.Combine(_tempDir, "input.hl7");
        File.WriteAllText(filePath, hl7);

        var scanResult = _service.GetHl7FileSplitInfo(filePath);
        var outputDir = Path.Combine(_tempDir, "hl7output");
        Directory.CreateDirectory(outputDir);

        _service.SplitHl7File(scanResult, filePath, 2, outputDir);

        Assert.True(File.Exists(Path.Combine(outputDir, "input_A-M.hl7")));
        Assert.True(File.Exists(Path.Combine(outputDir, "input_N-Z.hl7")));
    }

    #endregion
}
