namespace Parrat.Tests.Helpers;

/// <summary>
/// Shared test infrastructure for locating the repo root and other
/// environment-dependent paths needed by integration tests.
/// </summary>
public static class TestEnvironment
{
    private static readonly Lazy<string> _repoRoot = new(LocateRepoRoot);

    public static string FindRepoRoot() => _repoRoot.Value;

    private static string LocateRepoRoot()
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        for (int i = 0; i < 10; i++)
        {
            if (Directory.Exists(Path.Combine(dir, "data", "dictionaries")))
                return dir;
            var parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }

        return AppDomain.CurrentDomain.BaseDirectory;
    }
}
