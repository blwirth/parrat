using System.Text.Json;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class RecentFilesService : IRecentFilesService
{
    private readonly IParratLogger _logger;

    public RecentFilesService() : this(NullParratLogger.Instance) { }

    public RecentFilesService(IParratLogger logger)
    {
        _logger = logger;
    }

    private const int MaxItems = 10;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private string GetRecentFilesPath()
    {
        var configDir = PathHelper.ConfigDir;
        PathHelper.EnsureDirectoryExists(configDir);
        return Path.Combine(configDir, "recent-files.json");
    }

    public List<RecentFileEntry> GetRecentFiles()
    {
        var path = GetRecentFilesPath();
        if (!File.Exists(path)) return new List<RecentFileEntry>();

        try
        {
            var content = File.ReadAllText(path);
            if (string.IsNullOrWhiteSpace(content)) return new List<RecentFileEntry>();

            var wrapper = JsonSerializer.Deserialize<RecentFilesWrapper>(content, ReadOptions);
            return wrapper?.Files ?? new List<RecentFileEntry>();
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to read recent files list", "RECENT_FILES_LOAD", ex);
            return new List<RecentFileEntry>();
        }
    }

    public void SaveRecentFiles(List<RecentFileEntry> files)
    {
        var path = GetRecentFilesPath();
        PathHelper.EnsureDirectoryExists(Path.GetDirectoryName(path)!);

        var wrapper = new RecentFilesWrapper
        {
            Version = 1,
            MaxItems = MaxItems,
            Files = files
        };

        try
        {
            var json = JsonSerializer.Serialize(wrapper, JsonOptions);
            File.WriteAllText(path, json);
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to save recent files list", "RECENT_FILES_SAVE", ex);
        }
    }

    public void AddRecentFile(string filePath, string fileType)
        => AddRecent(filePath, fileType, isFolder: false);

    public void AddRecentFolder(string folderPath, string fileType)
        => AddRecent(folderPath, fileType, isFolder: true);

    private void AddRecent(string path, string fileType, bool isFolder)
    {
        if (string.IsNullOrWhiteSpace(path)) return;

        string normalizedPath;
        try
        {
            normalizedPath = Path.GetFullPath(path);

            // A trailing separator would leave the entry with no name to show.
            // Drives keep theirs, since "C:" alone means something different.
            if (isFolder)
            {
                var trimmed = normalizedPath.TrimEnd(
                    Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

                if (trimmed.Length > 0 && !trimmed.EndsWith(Path.VolumeSeparatorChar))
                    normalizedPath = trimmed;
            }
        }
        catch (Exception ex)
        {
            _logger.Log("WARN", "Failed to normalize path, using raw path", "RECENT_FILES_PATH", ex.Message);
            normalizedPath = path;
        }

        var files = GetRecentFiles();

        // Remove any existing entry for this file (case-insensitive)
        files.RemoveAll(f => string.Equals(f.FilePath, normalizedPath, StringComparison.OrdinalIgnoreCase));

        // Add to beginning (most recent first)
        files.Insert(0, new RecentFileEntry
        {
            FilePath = normalizedPath,
            FileType = fileType,
            IsFolder = isFolder,
            OpenedAt = DateTime.UtcNow
        });

        // Trim to max items
        if (files.Count > MaxItems)
        {
            files = files.Take(MaxItems).ToList();
        }

        SaveRecentFiles(files);
    }

    public void ClearRecentFiles()
    {
        SaveRecentFiles(new List<RecentFileEntry>());
    }

    public string? GetLastOpenedDirectory()
    {
        var files = GetRecentFiles();
        if (files.Count == 0) return null;

        var mostRecent = files[0];
        if (string.IsNullOrEmpty(mostRecent.FilePath)) return null;

        try
        {
            // A folder entry is already the directory to return to.
            var dir = mostRecent.IsFolder
                ? mostRecent.FilePath
                : Path.GetDirectoryName(mostRecent.FilePath);
            if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
            {
                return dir;
            }
        }
        catch (Exception ex)
        {
            _logger.Log("WARN", "Failed to resolve last opened directory from recent file path", "RECENT_FILES_DIR", ex.Message);
        }

        return null;
    }

    private class RecentFilesWrapper
    {
        public int Version { get; set; } = 1;
        public int MaxItems { get; set; } = 10;
        public List<RecentFileEntry> Files { get; set; } = new();
    }
}
