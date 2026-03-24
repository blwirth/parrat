using System.Text;
using System.Text.Json;
using Parat.Core.Helpers;
using Parat.Core.Interfaces;
using Parat.Core.Models;

namespace Parat.Core.Services;

public class NaaccrDictionary : INaaccrDictionary
{
    private readonly Dictionary<string, NaaccrItem> _dictionary = new();
    private bool _loaded;

    public void Initialize(int version = 25)
    {
        if (_loaded) return;

        var jsonPath = PathHelper.GetDictionaryPath($"naaccr-items-v{version}.json");

        if (!File.Exists(jsonPath))
        {
            throw new FileNotFoundException($"NAACCR dictionary not found at: {jsonPath}");
        }

        var jsonContent = File.ReadAllText(jsonPath, Encoding.UTF8);

        // The JSON has a BOM marker; JsonDocument handles it, but trim if present
        if (jsonContent.Length > 0 && jsonContent[0] == '\uFEFF')
        {
            jsonContent = jsonContent[1..];
        }

        using var doc = JsonDocument.Parse(jsonContent);
        foreach (var element in doc.RootElement.EnumerateArray())
        {
            var xmlId = element.GetProperty("id").GetString();
            if (string.IsNullOrWhiteSpace(xmlId)) continue;

            var numberStr = element.GetProperty("n").GetString() ?? string.Empty;
            int.TryParse(numberStr, out var numberInt);
            if (numberInt == 0) numberInt = 999999;

            _dictionary[xmlId] = new NaaccrItem
            {
                Number = numberStr,
                NumberInt = numberInt,
                Name = element.GetProperty("name").GetString() ?? string.Empty,
                XmlId = xmlId,
                ParentElement = element.GetProperty("p").GetString() ?? string.Empty
            };
        }

        _loaded = true;
    }

    public Dictionary<string, NaaccrItem> GetDictionary()
    {
        EnsureLoaded();
        return _dictionary;
    }

    public NaaccrItem? GetItemByXmlId(string xmlId)
    {
        EnsureLoaded();
        return _dictionary.TryGetValue(xmlId, out var item) ? item : null;
    }

    public string GetParentElement(string xmlId, Dictionary<string, string>? customFields = null)
    {
        EnsureLoaded();

        // Check custom fields first
        if (customFields != null && customFields.TryGetValue(xmlId, out var customParent))
        {
            return customParent;
        }

        // Check dictionary
        if (_dictionary.TryGetValue(xmlId, out var item) && !string.IsNullOrWhiteSpace(item.ParentElement))
        {
            return item.ParentElement;
        }

        // Default to Tumor for unknown fields
        return "Tumor";
    }

    public List<NaaccrItem> Search(string searchText)
    {
        EnsureLoaded();

        return _dictionary.Values
            .Where(item =>
                item.Name.Contains(searchText, StringComparison.OrdinalIgnoreCase) ||
                item.XmlId.Contains(searchText, StringComparison.OrdinalIgnoreCase) ||
                item.Number == searchText)
            .OrderBy(item => item.NumberInt)
            .ToList();
    }

    public string GetDisplayName(string xmlId)
    {
        var item = GetItemByXmlId(xmlId);
        return item != null
            ? $"{item.Name} ({item.XmlId})"
            : $"{xmlId} (custom)";
    }

    private void EnsureLoaded()
    {
        if (!_loaded)
        {
            Initialize();
        }
    }
}
