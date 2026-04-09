using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class NaaccrDictionary : INaaccrDictionary
{
    private readonly Dictionary<int, Dictionary<string, NaaccrItem>> _versions = new();
    private int _activeVersion;

    public void Initialize(int version = 25)
    {
        if (_versions.ContainsKey(version))
        {
            _activeVersion = version;
            return;
        }

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

        var dict = new Dictionary<string, NaaccrItem>();
        using var doc = JsonDocument.Parse(jsonContent);
        foreach (var element in doc.RootElement.EnumerateArray())
        {
            var xmlId = element.GetProperty("id").GetString();
            if (string.IsNullOrWhiteSpace(xmlId)) continue;

            var numberStr = element.GetProperty("n").GetString() ?? string.Empty;
            int.TryParse(numberStr, out var numberInt);
            if (numberInt == 0) numberInt = 999999;

            dict[xmlId] = new NaaccrItem
            {
                Number = numberStr,
                NumberInt = numberInt,
                Name = element.GetProperty("name").GetString() ?? string.Empty,
                XmlId = xmlId,
                ParentElement = element.GetProperty("p").GetString() ?? string.Empty
            };
        }

        EnrichFromXmlDictionary(version, dict);

        _versions[version] = dict;
        _activeVersion = version;
    }

    private static void EnrichFromXmlDictionary(int version, Dictionary<string, NaaccrItem> dict)
    {
        var xmlPath = PathHelper.GetDictionaryPath($"naaccr-dictionary-{version}0.xml");
        if (!File.Exists(xmlPath)) return;

        XNamespace ns = "http://naaccr.org/naaccrxml";
        var xdoc = XDocument.Load(xmlPath);

        foreach (var itemDef in xdoc.Descendants(ns + "ItemDef"))
        {
            var xmlId = itemDef.Attribute("naaccrId")?.Value;
            if (xmlId == null || !dict.TryGetValue(xmlId, out var item)) continue;

            if (int.TryParse(itemDef.Attribute("length")?.Value, out var len))
                item.Length = len;

            item.DataType = itemDef.Attribute("dataType")?.Value ?? "text";
        }
    }

    public Dictionary<string, NaaccrItem> GetDictionary()
    {
        EnsureLoaded();
        return _versions[_activeVersion];
    }

    public NaaccrItem? GetItemByXmlId(string xmlId)
    {
        EnsureLoaded();
        return _versions[_activeVersion].TryGetValue(xmlId, out var item) ? item : null;
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
        if (_versions[_activeVersion].TryGetValue(xmlId, out var item) && !string.IsNullOrWhiteSpace(item.ParentElement))
        {
            return item.ParentElement;
        }

        // Default to Tumor for unknown fields
        return "Tumor";
    }

    public List<NaaccrItem> Search(string searchText)
    {
        EnsureLoaded();

        return _versions[_activeVersion].Values
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

    /// <summary>
    /// Gets the currently active dictionary version number.
    /// </summary>
    public int ActiveVersion => _activeVersion;

    private void EnsureLoaded()
    {
        if (!_versions.ContainsKey(_activeVersion))
        {
            Initialize();
        }
    }
}
