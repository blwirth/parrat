namespace Parat.Core.Helpers;

public static class PathHelper
{
    private static string? _repoRoot;

    public static string RepoRoot
    {
        get
        {
            if (_repoRoot != null) return _repoRoot;

            // Walk up from the executing assembly location to find the repo root
            // The repo root contains data/, config/, and logs/ directories
            var dir = AppDomain.CurrentDomain.BaseDirectory;
            for (int i = 0; i < 10; i++)
            {
                if (Directory.Exists(Path.Combine(dir, "data")) &&
                    Directory.Exists(Path.Combine(dir, "config")))
                {
                    _repoRoot = dir;
                    return _repoRoot;
                }
                var parent = Directory.GetParent(dir);
                if (parent == null) break;
                dir = parent.FullName;
            }

            // Fallback: assume repo root is three levels up from bin output (src/Parat.UI/bin/...)
            _repoRoot = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", ".."));
            return _repoRoot;
        }
    }

    public static string DataDir => Path.Combine(RepoRoot, "data");
    public static string DictionariesDir => Path.Combine(DataDir, "dictionaries");
    public static string ConfigDir => Path.Combine(RepoRoot, "config");
    public static string LogsDir => Path.Combine(RepoRoot, "logs");
    public static string ExportConfigDir => Path.Combine(ConfigDir, "export-configs");

    public static string GetDictionaryPath(string filename) => Path.Combine(DictionariesDir, filename);
    public static string GetConfigPath(string filename) => Path.Combine(ConfigDir, filename);

    public static void EnsureDirectoryExists(string path)
    {
        if (!Directory.Exists(path))
            Directory.CreateDirectory(path);
    }

    /// <summary>
    /// Override the repo root for testing or published single-file scenarios.
    /// </summary>
    public static void SetRepoRoot(string path)
    {
        _repoRoot = path;
    }
}
