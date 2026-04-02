using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class NoahServiceTests : IDisposable
{
    private readonly NoahService _service = new();
    private readonly string _tempDir;
    private readonly string _originalRepoRoot;
    private readonly string _originalUserDir;

    public NoahServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_noah_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
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

    #region GetConfig / SaveConfig

    [Fact]
    public void GetConfig_ReturnsDefaultsWhenNoFile()
    {
        var config = _service.GetConfig();
        Assert.NotNull(config);
        Assert.Equal("http://localhost:4000", config.ApiServerUrl);
        Assert.Equal("hl7", config.Output);
    }

    [Fact]
    public void SaveAndGetConfig_Roundtrips()
    {
        var config = new NoahConfig
        {
            ExePath = "/usr/local/bin/noah",
            ModelId = "test-model-id",
            ApiServerUrl = "http://localhost:5000",
            Output = "xml"
        };

        _service.SaveConfig(config);
        var loaded = _service.GetConfig();

        Assert.Equal("/usr/local/bin/noah", loaded.ExePath);
        Assert.Equal("test-model-id", loaded.ModelId);
        Assert.Equal("http://localhost:5000", loaded.ApiServerUrl);
        Assert.Equal("xml", loaded.Output);
    }

    [Fact]
    public void GetConfig_ReturnsDefaultsForMalformedJson()
    {
        File.WriteAllText(PathHelper.GetConfigPath("noah-config.json"), "not json {{{");
        var config = _service.GetConfig();
        Assert.Equal("http://localhost:4000", config.ApiServerUrl);
    }

    #endregion

    #region GetCachedModels / SaveCachedModels

    [Fact]
    public void GetCachedModels_ReturnsEmptyWhenNoFile()
    {
        var cached = _service.GetCachedModels();
        Assert.NotNull(cached);
        Assert.Empty(cached.Models);
    }

    [Fact]
    public void SaveAndGetCachedModels_Roundtrips()
    {
        var models = new List<NoahModel>
        {
            new() { Id = "model-1", Name = "Test Model" },
            new() { Id = "model-2", Name = "Another Model" },
        };

        _service.SaveCachedModels(models);
        var cached = _service.GetCachedModels();

        Assert.Equal(2, cached.Models.Count);
        Assert.Equal("model-1", cached.Models[0].Id);
        Assert.Equal("Test Model", cached.Models[0].Name);
        Assert.NotNull(cached.LastUpdated);
    }

    #endregion

    #region CreateWorkingFolders

    [Fact]
    public void CreateWorkingFolders_CreatesDirectoryStructure()
    {
        var folders = _service.CreateWorkingFolders("hl7", _tempDir);

        Assert.True(Directory.Exists(folders.Base));
        Assert.True(Directory.Exists(folders.Source));
        Assert.True(Directory.Exists(folders.Reportable));
        Assert.True(Directory.Exists(folders.NonReportable));
        Assert.True(Directory.Exists(folders.Reports));
        Assert.Equal("hl7", folders.OutputFormat);
    }

    [Fact]
    public void CreateWorkingFolders_PathsAreUnderWorkingRoot()
    {
        var folders = _service.CreateWorkingFolders("xml", _tempDir);

        Assert.StartsWith(_tempDir, folders.Base);
        Assert.StartsWith(folders.Base, folders.Source);
        Assert.StartsWith(folders.Base, folders.Reportable);
    }

    #endregion

    #region CreateMinimalHl7Message

    [Fact]
    public void CreateMinimalHl7Message_ContainsRequiredSegments()
    {
        var msg = _service.CreateMinimalHl7Message("Test observation text");

        Assert.Contains("MSH|", msg);
        Assert.Contains("PID|", msg);
        Assert.Contains("OBR|", msg);
        Assert.Contains("OBX|", msg);
        Assert.Contains("Test observation text", msg);
    }

    [Fact]
    public void CreateMinimalHl7Message_UsesProvidedPatientId()
    {
        var msg = _service.CreateMinimalHl7Message("text", patientId: "PAT999");
        Assert.Contains("PAT999", msg);
    }

    [Fact]
    public void CreateMinimalHl7Message_UsesProvidedAccessionNumber()
    {
        var msg = _service.CreateMinimalHl7Message("text", accessionNumber: "ACC-123");
        Assert.Contains("ACC-123", msg);
    }

    [Fact]
    public void CreateMinimalHl7Message_UsesDefaultsWhenNotProvided()
    {
        var msg = _service.CreateMinimalHl7Message("text");
        Assert.Contains("TEST000001", msg);
        Assert.Contains("TEST-ACC-001", msg);
    }

    [Fact]
    public void CreateMinimalHl7Message_SegmentsSeparatedByCarriageReturn()
    {
        var msg = _service.CreateMinimalHl7Message("text");
        var segments = msg.Split('\r');
        Assert.Equal(4, segments.Length);
        Assert.StartsWith("MSH|", segments[0]);
        Assert.StartsWith("PID|", segments[1]);
        Assert.StartsWith("OBR|", segments[2]);
        Assert.StartsWith("OBX|", segments[3]);
    }

    #endregion

    #region StartServer — validation only (no actual process)

    [Fact]
    public void StartServer_ThrowsWhenExePathEmpty()
    {
        var config = new NoahConfig { ExePath = "" };
        Assert.Throws<InvalidOperationException>(() => _service.StartServer(config));
    }

    [Fact]
    public void StartServer_ThrowsWhenExePathNotFound()
    {
        var config = new NoahConfig { ExePath = "/nonexistent/noah.exe" };
        Assert.Throws<InvalidOperationException>(() => _service.StartServer(config));
    }

    #endregion
}
