using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class RecentFilesServiceTests : IDisposable
{
    private readonly string _tempDir;
    private readonly string _originalRepoRoot;
    private readonly string _originalUserDir;

    public RecentFilesServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        Directory.CreateDirectory(Path.Combine(_tempDir, "data"));
        Directory.CreateDirectory(Path.Combine(_tempDir, "config"));

        _originalRepoRoot = PathHelper.RepoRoot;
        _originalUserDir = PathHelper.UserDir;
        PathHelper.SetRepoRoot(_tempDir);
        PathHelper.SetUserDir(_tempDir);
    }

    public void Dispose()
    {
        PathHelper.SetRepoRoot(_originalRepoRoot);
        PathHelper.SetUserDir(_originalUserDir);
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    [Fact]
    public void GetRecentFiles_ReturnsEmptyListWhenNoFile()
    {
        var service = new RecentFilesService();
        var files = service.GetRecentFiles();
        Assert.Empty(files);
    }

    [Fact]
    public void AddRecentFile_AddsFileAndPersists()
    {
        var service = new RecentFilesService();
        service.AddRecentFile("/tmp/test.hl7", "hl7");

        var files = service.GetRecentFiles();
        Assert.Single(files);
        Assert.Contains("test.hl7", files[0].FilePath);
        Assert.Equal("hl7", files[0].FileType);
    }

    [Fact]
    public void AddRecentFile_MostRecentFirst()
    {
        var service = new RecentFilesService();
        service.AddRecentFile("/tmp/first.hl7", "hl7");
        service.AddRecentFile("/tmp/second.xml", "xml");

        var files = service.GetRecentFiles();
        Assert.Equal(2, files.Count);
        Assert.Contains("second.xml", files[0].FilePath);
        Assert.Contains("first.hl7", files[1].FilePath);
    }

    [Fact]
    public void AddRecentFile_RemovesDuplicates()
    {
        var service = new RecentFilesService();
        service.AddRecentFile("/tmp/test.hl7", "hl7");
        service.AddRecentFile("/tmp/other.xml", "xml");
        service.AddRecentFile("/tmp/test.hl7", "hl7"); // Re-add

        var files = service.GetRecentFiles();
        Assert.Equal(2, files.Count);
        Assert.Contains("test.hl7", files[0].FilePath); // Should be first now
    }

    [Fact]
    public void AddRecentFile_TrimsToMaxTenItems()
    {
        var service = new RecentFilesService();
        for (int i = 0; i < 12; i++)
        {
            service.AddRecentFile($"/tmp/file{i}.hl7", "hl7");
        }

        var files = service.GetRecentFiles();
        Assert.Equal(10, files.Count);
    }

    [Fact]
    public void ClearRecentFiles_RemovesAll()
    {
        var service = new RecentFilesService();
        service.AddRecentFile("/tmp/test.hl7", "hl7");
        service.ClearRecentFiles();

        var files = service.GetRecentFiles();
        Assert.Empty(files);
    }

    [Fact]
    public void GetLastOpenedDirectory_ReturnsNullWhenEmpty()
    {
        var service = new RecentFilesService();
        Assert.Null(service.GetLastOpenedDirectory());
    }

    [Fact]
    public void GetLastOpenedDirectory_ReturnsDirOfMostRecent()
    {
        var service = new RecentFilesService();
        // Use the temp directory which exists
        var testFile = Path.Combine(_tempDir, "test.hl7");
        service.AddRecentFile(testFile, "hl7");

        var dir = service.GetLastOpenedDirectory();
        Assert.Equal(_tempDir, dir);
    }

    [Fact]
    public void GetLastOpenedDirectory_ReturnsNullWhenDirDoesNotExist()
    {
        var service = new RecentFilesService();
        service.AddRecentFile("/nonexistent/path/test.hl7", "hl7");

        var dir = service.GetLastOpenedDirectory();
        Assert.Null(dir);
    }

    [Fact]
    public void SaveRecentFiles_PersistsAcrossInstances()
    {
        var service1 = new RecentFilesService();
        service1.AddRecentFile("/tmp/persist.xml", "xml");

        var service2 = new RecentFilesService();
        var files = service2.GetRecentFiles();
        Assert.Single(files);
        Assert.Contains("persist.xml", files[0].FilePath);
    }

    // ── Corrupt or unexpected recent-files.json ──────────────────────────

    private static void WriteRecentJson(string content)
    {
        Directory.CreateDirectory(PathHelper.ConfigDir);
        File.WriteAllText(Path.Combine(PathHelper.ConfigDir, "recent-files.json"), content);
    }

    [Theory]
    [InlineData("not json at all")]
    [InlineData("{ \"files\": ")]
    [InlineData("{ \"files\": \"not-an-array\" }")]
    [InlineData("[]")]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("null")]
    public void GetRecentFiles_CorruptFile_ReturnsEmptyWithoutThrowing(string content)
    {
        WriteRecentJson(content);

        var files = new RecentFilesService().GetRecentFiles();

        Assert.Empty(files);
    }

    [Fact]
    public void GetRecentFiles_WrongTypeOnIsFolder_ReturnsEmptyWithoutThrowing()
    {
        WriteRecentJson("""
        { "version": 1, "files": [
          { "filePath": "C:\\a.xml", "fileType": "xml", "isFolder": "yes" }
        ] }
        """);

        Assert.Empty(new RecentFilesService().GetRecentFiles());
    }

    [Fact]
    public void GetRecentFiles_EntriesMissingAPath_AreDroppedNotReturned()
    {
        WriteRecentJson("""
        { "version": 1, "files": [
          { "fileType": "xml" },
          { "filePath": null, "fileType": "hl7" },
          { "filePath": "", "fileType": "hl7" },
          { "filePath": "C:\\good.xml", "fileType": "xml" }
        ] }
        """);

        var entry = Assert.Single(new RecentFilesService().GetRecentFiles());
        Assert.Equal(@"C:\good.xml", entry.FilePath);
    }

    [Fact]
    public void AddRecentFile_AfterACorruptFile_StillRecordsTheNewEntry()
    {
        WriteRecentJson("not json at all");

        var service = new RecentFilesService();
        service.AddRecentFile("/tmp/after-corruption.xml", "xml");

        var entry = Assert.Single(service.GetRecentFiles());
        Assert.Contains("after-corruption.xml", entry.FilePath);
    }

    // ── Folder entries ───────────────────────────────────────────────────

    [Fact]
    public void AddRecentFolder_MarksTheEntryAsAFolderAndKeepsItsFormat()
    {
        var folder = Path.Combine(_tempDir, "qa-batch");
        Directory.CreateDirectory(folder);

        var service = new RecentFilesService();
        service.AddRecentFolder(folder, "hl7");

        var entry = Assert.Single(service.GetRecentFiles());
        Assert.True(entry.IsFolder);
        Assert.Equal("hl7", entry.FileType);
        Assert.Equal(folder, entry.FilePath);
    }

    [Fact]
    public void AddRecentFile_LeavesEntriesMarkedAsNotFolders()
    {
        var service = new RecentFilesService();
        service.AddRecentFile("/tmp/cases.xml", "xml");

        Assert.False(service.GetRecentFiles()[0].IsFolder);
    }

    [Fact]
    public void AddRecentFolder_StripsTrailingSeparatorSoTheEntryHasAName()
    {
        var folder = Path.Combine(_tempDir, "qa-batch");
        Directory.CreateDirectory(folder);

        var service = new RecentFilesService();
        service.AddRecentFolder(folder + Path.DirectorySeparatorChar, "xml");

        var entry = Assert.Single(service.GetRecentFiles());
        Assert.Equal("qa-batch", Path.GetFileName(entry.FilePath));
    }

    [Fact]
    public void AddRecentFolder_ReopeningTheSameFolderDoesNotDuplicateIt()
    {
        var folder = Path.Combine(_tempDir, "qa-batch");
        Directory.CreateDirectory(folder);

        var service = new RecentFilesService();
        service.AddRecentFolder(folder, "hl7");
        service.AddRecentFolder(folder, "xml");

        var entry = Assert.Single(service.GetRecentFiles());
        // The most recent choice wins.
        Assert.Equal("xml", entry.FileType);
    }

    [Fact]
    public void GetLastOpenedDirectory_ForAFolderEntry_ReturnsTheFolderItself()
    {
        var folder = Path.Combine(_tempDir, "qa-batch");
        Directory.CreateDirectory(folder);

        var service = new RecentFilesService();
        service.AddRecentFolder(folder, "hl7");

        Assert.Equal(folder, service.GetLastOpenedDirectory());
    }

    [Fact]
    public void GetRecentFiles_EntriesWrittenBeforeFolderSupport_LoadAsFiles()
    {
        // recent-files.json predating folder loading has no isFolder field.
        var path = Path.Combine(PathHelper.ConfigDir, "recent-files.json");
        Directory.CreateDirectory(PathHelper.ConfigDir);
        File.WriteAllText(path, """
        {
          "version": 1,
          "maxItems": 10,
          "files": [
            { "filePath": "C:\\reports\\cases.xml", "fileType": "xml", "openedAt": "2026-01-01T00:00:00Z" }
          ]
        }
        """);

        var entry = Assert.Single(new RecentFilesService().GetRecentFiles());

        Assert.False(entry.IsFolder);
        Assert.Equal("xml", entry.FileType);
    }
}
