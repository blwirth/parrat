using System.Data;

namespace Parat.Core.Interfaces;

public interface ISearchService
{
    string[] BuildSearchIndex(string fileType);
    void ApplyFilter(string searchText, DataTable navTable, string[] searchIndex);
    void HighlightMatches(object richTextBox, string searchText);
}
