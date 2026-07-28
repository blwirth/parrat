using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class FolderLoadServiceTests : IDisposable
{
    private readonly string _folder;
    private readonly FolderLoadService _service;

    public FolderLoadServiceTests()
    {
        _folder = Path.Combine(Path.GetTempPath(), $"parrat-folder-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_folder);

        _service = new FolderLoadService(
            new Hl7FileService(new Hl7Parser()),
            new EpathParserService());
    }

    public void Dispose()
    {
        if (Directory.Exists(_folder))
            Directory.Delete(_folder, recursive: true);
    }

    // ── Scanning ─────────────────────────────────────────────────────────

    [Fact]
    public void ScanFolder_ClassifiesFilesByContentNotExtension()
    {
        WriteHl7("report-a.hl7", messageCount: 1);
        WriteHl7("report-b.txt", messageCount: 1);   // HL7 wearing a .txt extension
        WriteFile("notes.txt", "Just some narrative text about a specimen.\n");

        var scan = _service.ScanFolder(_folder);

        var hl7 = scan.FilesOfFormat(DetectedFileFormat.Hl7);
        Assert.Equal(2, hl7.Count);
        Assert.Contains(hl7, f => f.FileName == "report-b.txt");
        Assert.Contains(scan.SkippedFiles, f => f.FileName == "notes.txt");
    }

    [Fact]
    public void ScanFolder_IgnoresSubfolders()
    {
        WriteHl7("top.hl7", messageCount: 1);

        var nested = Path.Combine(_folder, "nested");
        Directory.CreateDirectory(nested);
        File.WriteAllText(Path.Combine(nested, "deep.hl7"), BuildHl7(1, "NESTED"));

        var scan = _service.ScanFolder(_folder);

        var hl7 = scan.FilesOfFormat(DetectedFileFormat.Hl7);
        Assert.Single(hl7);
        Assert.Equal("top.hl7", hl7[0].FileName);
    }

    [Fact]
    public void ScanFolder_EmptyFolder_ReportsNothingLoadable()
    {
        var scan = _service.ScanFolder(_folder);

        Assert.False(scan.HasLoadableFiles);
        Assert.Empty(scan.AvailableFormats);
    }

    [Fact]
    public void ScanFolder_UnsupportedFilesOnly_ReportsThemAsSkipped()
    {
        WriteFile("readme.txt", "A folder of reports.\n");

        var scan = _service.ScanFolder(_folder);

        Assert.False(scan.HasLoadableFiles);
        Assert.Single(scan.SkippedFiles);
    }

    [Fact]
    public void ScanFolder_MissingFolder_Throws()
    {
        var missing = Path.Combine(_folder, "does-not-exist");

        Assert.Throws<DirectoryNotFoundException>(() => _service.ScanFolder(missing));
    }

    [Fact]
    public void ScanFolder_ReturnsFilesInNameOrder()
    {
        WriteHl7("c.hl7", messageCount: 1);
        WriteHl7("a.hl7", messageCount: 1);
        WriteHl7("b.hl7", messageCount: 1);

        var scan = _service.ScanFolder(_folder);

        Assert.Equal(
            new[] { "a.hl7", "b.hl7", "c.hl7" },
            scan.FilesOfFormat(DetectedFileFormat.Hl7).Select(f => f.FileName));
    }

    // ── Loading ──────────────────────────────────────────────────────────

    [Fact]
    public void LoadHl7Files_MergesMessagesAndStampsSourceFile()
    {
        var first = WriteHl7("first.hl7", messageCount: 2);
        var second = WriteHl7("second.hl7", messageCount: 3);

        var result = _service.LoadHl7Files(new[] { first, second });

        Assert.Equal(5, result.Records.Count);
        Assert.Equal(2, result.FileCount);
        Assert.Empty(result.Failures);
        Assert.Equal(2, result.Records.Count(m => m.SourceFile == first));
        Assert.Equal(3, result.Records.Count(m => m.SourceFile == second));
    }

    [Fact]
    public void LoadHl7Files_RenumbersIndexesAcrossTheWholeSet()
    {
        var first = WriteHl7("first.hl7", messageCount: 2);
        var second = WriteHl7("second.hl7", messageCount: 2);

        var result = _service.LoadHl7Files(new[] { first, second });

        Assert.Equal(new[] { 0, 1, 2, 3 }, result.Records.Select(m => m.Index));
    }

    [Fact]
    public void LoadHl7Files_BatchWrappedFile_ExcludesEnvelopeSegments()
    {
        var path = Path.Combine(_folder, "batch.hl7");
        File.WriteAllText(path,
            "FHS|^~\\&|App|Fac\n" +
            "BHS|^~\\&|App|Fac\n" +
            BuildHl7(1, "BATCH") +
            "BTS|1\n" +
            "FTS|1\n");

        var result = _service.LoadHl7Files(new[] { path });

        Assert.Single(result.Records);
        Assert.DoesNotContain("BTS|", result.Records[0].RawContent);
        Assert.DoesNotContain("FTS|", result.Records[0].RawContent);
    }

    [Fact]
    public void LoadHl7Files_UnreadableFile_RecordsFailureAndKeepsGoing()
    {
        var good = WriteHl7("good.hl7", messageCount: 2);
        var empty = WriteFile("empty.hl7", "");

        var result = _service.LoadHl7Files(new[] { empty, good });

        Assert.Equal(2, result.Records.Count);
        Assert.Single(result.LoadedFiles);
        Assert.Single(result.Failures);
        Assert.Equal("empty.hl7", result.Failures[0].FileName);
        // The surviving file still gets a contiguous index range.
        Assert.Equal(new[] { 0, 1 }, result.Records.Select(m => m.Index));
    }

    [Fact]
    public void LoadHl7Files_MissingFile_RecordsFailure()
    {
        var missing = Path.Combine(_folder, "gone.hl7");

        var result = _service.LoadHl7Files(new[] { missing });

        Assert.Empty(result.Records);
        Assert.Single(result.Failures);
    }

    [Fact]
    public void LoadHl7Files_NoFiles_ReturnsEmptyResult()
    {
        var result = _service.LoadHl7Files(Array.Empty<string>());

        Assert.Empty(result.Records);
        Assert.Empty(result.Failures);
        Assert.Equal(0, result.FileCount);
    }

    [Fact]
    public void LoadHl7Files_PreservesFileOrderInMergedSet()
    {
        var first = WriteHl7("first.hl7", messageCount: 1, patientPrefix: "AAA");
        var second = WriteHl7("second.hl7", messageCount: 1, patientPrefix: "BBB");

        var result = _service.LoadHl7Files(new[] { first, second });

        Assert.Equal("AAA0", result.Records[0].PatientLastName);
        Assert.Equal("BBB0", result.Records[1].PatientLastName);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private string WriteHl7(string fileName, int messageCount, string patientPrefix = "Patient")
        => WriteFile(fileName, BuildHl7(messageCount, patientPrefix));

    private string WriteFile(string fileName, string content)
    {
        var path = Path.Combine(_folder, fileName);
        File.WriteAllText(path, content);
        return path;
    }

    private static string BuildHl7(int messageCount, string patientPrefix = "Patient")
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < messageCount; i++)
        {
            sb.Append($"MSH|^~\\&|App|Fac|||2024010{i + 1}||ORU^R01|{i + 1}|P|2.5.1\n");
            sb.Append($"PID|1||MRN{i:D3}||{patientPrefix}{i}^Test||19850315|F\n");
            sb.Append($"OBR|1||SP-{i:D3}|PATH^Pathology Report\n");
            sb.Append("OBX|1|TX|PATH_DX^Diagnosis||Carcinoma||||||F\n");
        }
        return sb.ToString();
    }
}
