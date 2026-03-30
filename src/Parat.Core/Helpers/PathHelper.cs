namespace Parat.Core.Helpers;

public static class PathHelper
{
    private static string? _repoRoot;

    public static string RepoRoot
    {
        get
        {
            if (_repoRoot != null) return _repoRoot;

            // Try multiple starting points — for single-file published apps,
            // BaseDirectory points to a temp extraction folder, not the exe location.
            var candidates = new[]
            {
                Path.GetDirectoryName(Environment.ProcessPath),
                AppDomain.CurrentDomain.BaseDirectory
            };

            foreach (var start in candidates)
            {
                if (string.IsNullOrEmpty(start)) continue;
                var dir = start;
                for (int i = 0; i < 10; i++)
                {
                    if (Directory.Exists(Path.Combine(dir, "data")))
                    {
                        _repoRoot = dir;
                        return _repoRoot;
                    }
                    var parent = Directory.GetParent(dir);
                    if (parent == null) break;
                    dir = parent.FullName;
                }
            }

            // Fallback: use the exe's directory
            _repoRoot = Path.GetDirectoryName(Environment.ProcessPath)
                ?? AppDomain.CurrentDomain.BaseDirectory;
            return _repoRoot;
        }
    }

    private static string? _userDir;

    public static string UserDir
    {
        get
        {
            if (_userDir != null) return _userDir;
            _userDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "PARAT");
            Directory.CreateDirectory(_userDir);
            return _userDir;
        }
    }

    public static string DataDir => Path.Combine(RepoRoot, "data");
    public static string DictionariesDir => Path.Combine(DataDir, "dictionaries");
    public static string ConfigDir => Path.Combine(UserDir, "config");
    public static string LogsDir => Path.Combine(UserDir, "logs");
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

    /// <summary>
    /// Override the user directory for testing.
    /// </summary>
    public static void SetUserDir(string path)
    {
        _userDir = path;
    }
}
