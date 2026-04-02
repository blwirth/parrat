using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class ConvertTxtServiceTests : IDisposable
{
    private readonly ConvertTxtService _service = new();
    private readonly string _tempDir;

    public ConvertTxtServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_convert_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    #region ConvertPathologyTextToHl7 — Standard facility

    [Fact]
    public void ConvertPathologyTextToHl7_ParsesStandardCase()
    {
        var text = @"Parkland
PATIENT: SMITH JOHN M   ACCT: 12345   DOB: 01/15/1980   AGE/SEX: 44/M   U: A12345
SPEC# SP24-001 COLL: 01/10/2024
DIAGNOSIS: Adenocarcinoma of the colon
Case Signed At
some footer
";
        var inputPath = WriteFile("parkland.txt", text);
        var outputPath = Path.Combine(_tempDir, "parkland.hl7");

        var result = _service.ConvertPathologyTextToHl7(inputPath, outputPath, "Parkland");

        Assert.Contains("MSH|", result);
        Assert.Contains("PID|", result);
        Assert.Contains("OBR|", result);
        Assert.Contains("OBX|", result);
        Assert.Contains("SMITH", result);
        Assert.Contains("JOHN", result);
        Assert.True(File.Exists(outputPath));
    }

    [Fact]
    public void ConvertPathologyTextToHl7_PreviewOnly_DoesNotWriteFile()
    {
        var text = @"Parkland
PATIENT: DOE JANE   ACCT: 99999   DOB: 03/20/1990   AGE/SEX: 34/F   U: B99999
SPEC# SP24-002 COLL: 02/15/2024
DIAGNOSIS: Normal tissue
";
        var inputPath = WriteFile("preview.txt", text);
        var outputPath = Path.Combine(_tempDir, "should_not_exist.hl7");

        var result = _service.ConvertPathologyTextToHl7(inputPath, outputPath, "Parkland", previewOnly: true);

        Assert.Contains("Preview:", result);
        Assert.Contains("1 cases", result);
        Assert.False(File.Exists(outputPath));
    }

    [Fact]
    public void ConvertPathologyTextToHl7_ThrowsForMissingFile()
    {
        Assert.Throws<FileNotFoundException>(() =>
            _service.ConvertPathologyTextToHl7("/nonexistent/file.txt", null, "Parkland"));
    }

    [Fact]
    public void ConvertPathologyTextToHl7_ThrowsForUnknownFacility()
    {
        var inputPath = WriteFile("test.txt", "some content");
        Assert.Throws<ArgumentException>(() =>
            _service.ConvertPathologyTextToHl7(inputPath, null, "UnknownFacility"));
    }

    #endregion

    #region ConvertPathologyTextToHl7 — Multiple cases

    [Fact]
    public void ConvertPathologyTextToHl7_ParsesMultipleCases()
    {
        var text = @"Parkland
PATIENT: SMITH JOHN   ACCT: 11111   DOB: 01/15/1980   AGE/SEX: 44/M   U: A11111
SPEC# SP24-001 COLL: 01/10/2024
First case diagnosis
Parkland
PATIENT: JONES JANE   ACCT: 22222   DOB: 06/20/1990   AGE/SEX: 34/F   U: B22222
SPEC# SP24-002 COLL: 02/15/2024
Second case diagnosis
";
        var inputPath = WriteFile("multi.txt", text);
        var outputPath = Path.Combine(_tempDir, "multi.hl7");

        var result = _service.ConvertPathologyTextToHl7(inputPath, outputPath, "Parkland");

        // Should have 2 MSH segments (one per case)
        var mshCount = result.Split(new[] { "MSH|" }, StringSplitOptions.None).Length - 1;
        Assert.Equal(2, mshCount);
        Assert.Contains("SMITH", result);
        Assert.Contains("JONES", result);
    }

    #endregion

    #region ConvertPathologyTextToHl7 — Date conversion

    [Fact]
    public void ConvertPathologyTextToHl7_ConvertsDateFormats()
    {
        var text = @"Parkland
PATIENT: SMITH JOHN   ACCT: 11111   DOB: 01/15/1980   AGE/SEX: 44/M   U: A11111
SPEC# SP24-001 COLL: 03/25/2024
Diagnosis text
";
        var inputPath = WriteFile("dates.txt", text);

        var result = _service.ConvertPathologyTextToHl7(inputPath, null, "Parkland");

        // DOB 01/15/1980 → 19800115
        Assert.Contains("19800115", result);
        // Specimen date 03/25/2024 → 20240325
        Assert.Contains("20240325", result);
    }

    #endregion

    #region GetPreviewCases

    [Fact]
    public void GetPreviewCases_ReturnsCaseSummaries()
    {
        var text = @"Parkland
PATIENT: SMITH JOHN   ACCT: 11111   DOB: 01/15/1980   AGE/SEX: 44/M   U: A11111
SPEC# SP24-001 COLL: 01/10/2024
Diagnosis text
";
        var inputPath = WriteFile("preview_cases.txt", text);

        var cases = _service.GetPreviewCases(inputPath, "Parkland");

        Assert.Single(cases);
        Assert.Equal("SMITH", cases[0]["NameLast"]);
        Assert.Equal("JOHN", cases[0]["NameFirst"]);
        Assert.False(string.IsNullOrEmpty((string)cases[0]["PathReportID"]),
            "PathReportID should be parsed from the SPEC line");
    }

    [Fact]
    public void GetPreviewCases_ThrowsForMissingFile()
    {
        Assert.Throws<FileNotFoundException>(() =>
            _service.GetPreviewCases("/nonexistent/file.txt", "Parkland"));
    }

    #endregion

    #region ConvertPathologyTextToHl7 — SJH facility

    [Fact]
    public void ConvertPathologyTextToHl7_ParsesSJHFormat()
    {
        var text = @"NH24-00001 Patient: 12345 Smith, John Age: 65 Sex: M
DIAGNOSIS: Adenocarcinoma
Specimen received: 1/15/2024
Additional findings noted
";
        var inputPath = WriteFile("sjh.txt", text);
        var outputPath = Path.Combine(_tempDir, "sjh.hl7");

        var result = _service.ConvertPathologyTextToHl7(inputPath, outputPath, "SJH");

        Assert.Contains("MSH|", result);
        Assert.Contains("PID|", result);
        Assert.Contains("Smith", result);
        Assert.Contains("John", result);
    }

    #endregion

    #region ConvertPathologyTextToHl7 — Facility-specific CLIA

    [Fact]
    public void ConvertPathologyTextToHl7_UsesCorrectFacilityCLIA()
    {
        var text = @"Portsmouth
PATIENT: DOE JANE   ACCT: 99999   DOB: 03/20/1990   AGE/SEX: 34/F   U: B99999
SPEC# SP24-100 COLL: 05/01/2024
Some diagnosis
";
        var inputPath = WriteFile("portsmouth.txt", text);

        var result = _service.ConvertPathologyTextToHl7(inputPath, null, "Portsmouth");
        Assert.Contains("PORTSMOUTH REGIONAL HOSPITAL", result);
        Assert.Contains("30D1064878", result);
    }

    #endregion

    private string WriteFile(string name, string content)
    {
        var path = Path.Combine(_tempDir, name);
        File.WriteAllText(path, content);
        return path;
    }
}
