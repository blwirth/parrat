using System.Text.Json;
using Parat.Core.Helpers;
using Parat.Core.Interfaces;
using Parat.Core.Models;

namespace Parat.Core.Services;

public class RecentFilesService : IRecentFilesService
{
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
        catch
        {
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
        catch
        {
            // Silent fail
        }
    }

    public void AddRecentFile(string filePath, string fileType)
    {
        if (string.IsNullOrWhiteSpace(filePath)) return;

        string normalizedPath;
        try
        {
            normalizedPath = Path.GetFullPath(filePath);
        }
        catch
        {
            normalizedPath = filePath;
        }

        var files = GetRecentFiles();

        // Remove any existing entry for this file (case-insensitive)
        files.RemoveAll(f => string.Equals(f.FilePath, normalizedPath, StringComparison.OrdinalIgnoreCase));

        // Add to beginning (most recent first)
        files.Insert(0, new RecentFileEntry
        {
            FilePath = normalizedPath,
            FileType = fileType,
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
            var dir = Path.GetDirectoryName(mostRecent.FilePath);
            if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
            {
                return dir;
            }
        }
        catch
        {
            // Ignore path errors
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
