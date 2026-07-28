using System.Data;

namespace Parrat.Core.Interfaces;

public interface ISearchService
{
    string[] BuildSearchIndex(string fileType);

    /// <summary>
    /// 0-based indices of records matching the search text, or null when the
    /// search is blank and therefore constrains nothing.
    /// </summary>
    int[]? GetMatchingIndices(string searchText, string[] searchIndex);

    void ApplyFilter(string searchText, DataTable navTable, string[] searchIndex);
    void HighlightMatches(object richTextBox, string searchText);
}
