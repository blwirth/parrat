using Parat.Core.Helpers;
using Parat.Core.Models;
using Parat.Core.Services;
using Xunit;

namespace Parat.Tests.Services;

public class RecentFilesServiceTests : IDisposable
{
    private readonly string _tempDir;

    public RecentFilesServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parat_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        Directory.CreateDirectory(Path.Combine(_tempDir, "data"));
        Directory.CreateDirectory(Path.Combine(_tempDir, "config"));
        PathHelper.SetRepoRoot(_tempDir);
    }

    public void Dispose()
    {
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
}
