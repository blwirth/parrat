using Parat.Core.Models;

namespace Parat.Core.Interfaces;

public interface INaaccrDictionary
{
    void Initialize(int version = 25);
    Dictionary<string, NaaccrItem> GetDictionary();
    NaaccrItem? GetItemByXmlId(string xmlId);
    string GetParentElement(string xmlId, Dictionary<string, string>? customFields = null);
    List<NaaccrItem> Search(string searchText);
    string GetDisplayName(string xmlId);
}
