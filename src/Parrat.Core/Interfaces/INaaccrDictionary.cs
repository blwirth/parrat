using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface INaaccrDictionary
{
    void Initialize(int version = 25);
    int ActiveVersion { get; }
    Dictionary<string, NaaccrItem> GetDictionary();
    NaaccrItem? GetItemByXmlId(string xmlId);
    string GetParentElement(string xmlId, Dictionary<string, string>? customFields = null);
    List<NaaccrItem> Search(string searchText);
    string GetDisplayName(string xmlId);
}
