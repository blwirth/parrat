using System.Xml;

namespace Parrat.Core.Helpers;

/// <summary>
/// Reads NAACCR Item values for a tumor, honoring the element level the item lives at
/// (NaaccrData/Patient/Tumor). This is the single source of truth shared by the CSV export
/// writer and the export preview/field tools so the two can never disagree.
/// </summary>
public static class TumorFieldReader
{
    /// <summary>
    /// Returns the value of <paramref name="fieldId"/> for one tumor, looking it up at the
    /// given <paramref name="parentElement"/> level ("NaaccrData", "Patient", or "Tumor").
    /// Returns an empty string when the item is absent.
    /// </summary>
    public static string ReadValue(
        XmlNode tumor, XmlNode? patient, string fieldId, string parentElement, XmlNamespaceManager nsMgr)
    {
        XmlNode? node;
        if (parentElement == "NaaccrData")
        {
            var root = tumor.OwnerDocument?.DocumentElement;
            node = root?.SelectSingleNode($"./n:Item[@naaccrId='{fieldId}']", nsMgr);
        }
        else if (parentElement == "Patient")
        {
            node = patient?.SelectSingleNode($"./n:Item[@naaccrId='{fieldId}']", nsMgr);
        }
        else
        {
            node = tumor.SelectSingleNode($"./n:Item[@naaccrId='{fieldId}']", nsMgr);
        }

        return node?.InnerText ?? "";
    }

    /// <summary>
    /// Returns the subset of <paramref name="fieldIds"/> that are blank for every one of the
    /// given tumor indices — i.e. columns that would be entirely empty in the export. Variables
    /// populated at any level (including file-level NaaccrData) for at least one exported case
    /// are NOT reported. <paramref name="parentElementResolver"/> maps a field id to its level.
    /// </summary>
    public static List<string> FindEmptyFields(
        XmlNodeList? tumors, int[]? tumorIndices, IReadOnlyList<string> fieldIds,
        Func<string, string> parentElementResolver, XmlNamespaceManager nsMgr)
    {
        var populated = new HashSet<string>(StringComparer.Ordinal);

        if (tumors != null && tumorIndices != null && fieldIds.Count > 0)
        {
            var reader = new NaaccrLeveledItemReader(
                fieldIds.Select(id => new KeyValuePair<string, string>(id, parentElementResolver(id))));

            var values = new Dictionary<string, string>(fieldIds.Count, StringComparer.Ordinal);

            foreach (var tumorIndex in tumorIndices)
            {
                if (tumorIndex < 0 || tumorIndex >= tumors.Count) continue;

                var tumor = tumors[tumorIndex];
                if (tumor == null) continue;

                values.Clear();
                reader.ReadRow(tumor, NaaccrLeveledItemReader.FindPatient(tumor), values);

                // Only non-empty values are recorded by the reader, so anything
                // present here counts as populated.
                foreach (var value in values)
                    populated.Add(value.Key);

                // Every field has been seen with a value; nothing left to find.
                if (populated.Count == fieldIds.Count)
                    break;
            }
        }

        return fieldIds.Where(id => !populated.Contains(id)).ToList();
    }
}
