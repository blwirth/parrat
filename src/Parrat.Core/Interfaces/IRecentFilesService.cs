using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IRecentFilesService
{
    List<RecentFileEntry> GetRecentFiles();
    void SaveRecentFiles(List<RecentFileEntry> files);
    void AddRecentFile(string filePath, string fileType);

    /// <summary>
    /// Records a folder that was loaded as one set, together with the format it
    /// was loaded as so reopening can offer the same choice.
    /// </summary>
    void AddRecentFolder(string folderPath, string fileType);
    void ClearRecentFiles();
    string? GetLastOpenedDirectory();
}
