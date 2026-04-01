using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class PathHelperTests : IDisposable
{
    private readonly string _tempDir;
    private readonly string _originalRepoRoot;
    private readonly string _originalUserDir;

    public PathHelperTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_path_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);

        // Save current values so we can restore after each test
        _originalRepoRoot = PathHelper.RepoRoot;
        _originalUserDir = PathHelper.UserDir;
    }

    public void Dispose()
    {
        // Restore original paths
        PathHelper.SetRepoRoot(_originalRepoRoot);
        PathHelper.SetUserDir(_originalUserDir);

        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, true);
    }

    /// <summary>
    /// Regression test: ConfigDir and LogsDir must resolve under the per-user
    /// directory (%LOCALAPPDATA%\PARRAT), NOT under the exe/repo root.
    /// If someone accidentally changes these back to RepoRoot, every user on
    /// the server would share config and stomp on each other's settings.
    /// </summary>
    [Fact]
    public void ConfigDir_And_LogsDir_ResolveUnderUserDir_NotRepoRoot()
    {
        var fakeRepoRoot = Path.Combine(_tempDir, "app");
        var fakeUserDir = Path.Combine(_tempDir, "userdata");
        Directory.CreateDirectory(Path.Combine(fakeRepoRoot, "data"));
        Directory.CreateDirectory(fakeUserDir);

        PathHelper.SetRepoRoot(fakeRepoRoot);
        PathHelper.SetUserDir(fakeUserDir);

        // Config and logs must be under UserDir
        Assert.StartsWith(fakeUserDir, PathHelper.ConfigDir);
        Assert.StartsWith(fakeUserDir, PathHelper.LogsDir);
        Assert.StartsWith(fakeUserDir, PathHelper.ExportConfigDir);

        // Config and logs must NOT be under RepoRoot
        Assert.False(PathHelper.ConfigDir.StartsWith(fakeRepoRoot),
            "ConfigDir must not be under RepoRoot — config is per-user, not shared");
        Assert.False(PathHelper.LogsDir.StartsWith(fakeRepoRoot),
            "LogsDir must not be under RepoRoot — logs are per-user, not shared");
    }

    /// <summary>
    /// DataDir must resolve relative to RepoRoot (next to the exe), not under
    /// the user directory. Dictionaries and reference data are shared/read-only.
    /// </summary>
    [Fact]
    public void DataDir_ResolvesUnderRepoRoot_NotUserDir()
    {
        var fakeRepoRoot = Path.Combine(_tempDir, "app");
        var fakeUserDir = Path.Combine(_tempDir, "userdata");
        Directory.CreateDirectory(Path.Combine(fakeRepoRoot, "data"));
        Directory.CreateDirectory(fakeUserDir);

        PathHelper.SetRepoRoot(fakeRepoRoot);
        PathHelper.SetUserDir(fakeUserDir);

        // Data and dictionaries must be under RepoRoot
        Assert.StartsWith(fakeRepoRoot, PathHelper.DataDir);
        Assert.StartsWith(fakeRepoRoot, PathHelper.DictionariesDir);

        // Data must NOT be under UserDir
        Assert.False(PathHelper.DataDir.StartsWith(fakeUserDir),
            "DataDir must not be under UserDir — reference data is shared, not per-user");
    }
}
