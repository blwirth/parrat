using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IRecentFilesService
{
    List<RecentFileEntry> GetRecentFiles();
    void SaveRecentFiles(List<RecentFileEntry> files);
    void AddRecentFile(string filePath, string fileType);
    void ClearRecentFiles();
    string? GetLastOpenedDirectory();
}
