using System.Xml;
using Parrat.Core.Interfaces;

namespace Parrat.Core.Helpers;

/// <summary>
/// Scans loaded NAACCR tumors for the set of variables (naaccrId Items) that are
/// actually present, so the export UI can offer a "select all present variables"
/// shortcut instead of forcing the user to pick each field by hand.
/// </summary>
public static class VariableScanHelper
{
    /// <summary>
    /// Returns the distinct naaccrIds present across the given tumor indices, mapped to the
    /// element level they were found at ("Tumor", "Patient", or "NaaccrData").
    /// </summary>
    /// <param name="tumors">All Tumor nodes for the loaded file.</param>
    /// <param name="tumorIndices">Indices into <paramref name="tumors"/> to scan. Out-of-range
    /// indices are skipped.</param>
    /// <param name="nsMgr">Namespace manager with the NAACCR namespace bound to prefix "n".</param>
    public static Dictionary<string, string> ScanPresentVariables(
        XmlNodeList? tumors, int[]? tumorIndices, XmlNamespaceManager nsMgr)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);

        if (tumors == null || tumors.Count == 0 || tumorIndices == null || tumorIndices.Length == 0)
            return result;

        // NaaccrData (file) level Items are shared by every abstract; collect them once.
        var rootScanned = false;

        foreach (var tumorIndex in tumorIndices)
        {
            if (tumorIndex < 0 || tumorIndex >= tumors.Count) continue;

            var tumor = tumors[tumorIndex];
            if (tumor == null) continue;

            if (!rootScanned)
            {
                var root = tumor.OwnerDocument?.DocumentElement;
                CollectItemIds(root, "NaaccrData", nsMgr, result);
                rootScanned = true;
            }

            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
            CollectItemIds(patient, "Patient", nsMgr, result);

            CollectItemIds(tumor, "Tumor", nsMgr, result);
        }

        return result;
    }

    /// <summary>
    /// Orders field ids in canonical NAACCR order: by item number, with ids not found in the
    /// dictionary sorted last, ties broken by id. Used so auto-selected columns appear in a
    /// stable, report-friendly order.
    /// </summary>
    public static List<string> OrderByNaaccr(IEnumerable<string> ids, INaaccrDictionary dictionary)
    {
        return ids
            .OrderBy(id => dictionary.GetItemByXmlId(id)?.NumberInt ?? int.MaxValue)
            .ThenBy(id => id, StringComparer.Ordinal)
            .ToList();
    }

    /// <summary>
    /// Appends <paramref name="incoming"/> ids onto <paramref name="existing"/>, preserving the
    /// existing order and skipping any id already present (union without duplicates). Used when
    /// adding present variables to the current selection.
    /// </summary>
    public static List<string> MergePreservingOrder(IEnumerable<string> existing, IEnumerable<string> incoming)
    {
        var result = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        foreach (var id in existing)
            if (seen.Add(id)) result.Add(id);
        foreach (var id in incoming)
            if (seen.Add(id)) result.Add(id);

        return result;
    }

    private static void CollectItemIds(
        XmlNode? parent, string level, XmlNamespaceManager nsMgr, Dictionary<string, string> result)
    {
        if (parent == null) return;

        var items = parent.SelectNodes("./n:Item", nsMgr);
        if (items == null) return;

        foreach (XmlNode item in items)
        {
            var naaccrId = item.Attributes?["naaccrId"]?.Value;
            if (string.IsNullOrEmpty(naaccrId)) continue;

            // First level encountered wins (NAACCR assigns each item to a single level).
            if (!result.ContainsKey(naaccrId))
                result[naaccrId] = level;
        }
    }
}
