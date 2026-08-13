using System.Xml;
using Parrat.Core.Models;

namespace Parrat.Core.Helpers;

/// <summary>
/// Turns a user-supplied list of key values — pasted text or a column pulled
/// out of a CSV — into the set of tumors those values identify, so a reviewed
/// worklist of 100+ cases can be checked for export in one step instead of
/// row by row.
/// </summary>
public static class ListSelectionHelper
{
    private static readonly char[] ValueSeparators = { '\r', '\n', ',', ';', '\t' };

    /// <summary>
    /// Splits pasted text into distinct key values. Accepts one value per line
    /// as well as comma/semicolon/tab-separated input, trims each value, and
    /// keeps the first spelling of any duplicate.
    /// </summary>
    public static List<string> ParseValues(string? text)
    {
        var values = new List<string>();
        if (string.IsNullOrWhiteSpace(text))
            return values;

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var raw in text.Split(ValueSeparators, StringSplitOptions.RemoveEmptyEntries))
        {
            var value = raw.Trim();
            if (value.Length > 0 && seen.Add(value))
                values.Add(value);
        }

        return values;
    }

    /// <summary>
    /// The distinct values appearing in one CSV column, in first-seen order —
    /// the choices offered when the user narrows the list by a status column.
    /// </summary>
    public static List<string> DistinctColumnValues(CsvParseResult csv, int columnIndex)
    {
        var values = new List<string>();
        if (columnIndex < 0 || columnIndex >= csv.ColumnCount)
            return values;

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var row in csv.Rows)
        {
            if (columnIndex >= row.Length) continue;

            var value = row[columnIndex].Trim();
            if (value.Length > 0 && seen.Add(value))
                values.Add(value);
        }

        return values;
    }

    /// <summary>
    /// Pulls the distinct key values out of a CSV column, optionally keeping
    /// only rows whose filter column holds one of the included values — "the
    /// rows we marked reportable", leaving the rest of the worklist behind.
    /// Pass a negative <paramref name="filterColumnIndex"/> to use every row.
    /// </summary>
    public static List<string> ExtractKeyValues(
        CsvParseResult csv, int keyColumnIndex,
        int filterColumnIndex = -1, IReadOnlyCollection<string>? includedFilterValues = null)
    {
        var values = new List<string>();
        if (keyColumnIndex < 0 || keyColumnIndex >= csv.ColumnCount)
            return values;

        bool filtering = filterColumnIndex >= 0 && filterColumnIndex < csv.ColumnCount;
        var included = filtering
            ? new HashSet<string>(
                (includedFilterValues ?? Array.Empty<string>()).Select(v => v.Trim()),
                StringComparer.OrdinalIgnoreCase)
            : null;

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var row in csv.Rows)
        {
            if (keyColumnIndex >= row.Length) continue;

            if (included != null)
            {
                var filterValue = filterColumnIndex < row.Length ? row[filterColumnIndex].Trim() : "";
                if (!included.Contains(filterValue))
                    continue;
            }

            var key = row[keyColumnIndex].Trim();
            if (key.Length > 0 && seen.Add(key))
                values.Add(key);
        }

        return values;
    }

    /// <summary>
    /// Finds every tumor whose <paramref name="fieldId"/> value appears in the
    /// list. The value is looked up on the Tumor first, then its Patient, then
    /// the file-level NaaccrData, so a key works no matter which level the file
    /// records it at — and a patient split across several Patient elements is
    /// still matched wherever their tumors are filed.
    /// </summary>
    public static ListMatchResult MatchTumors(
        XmlNodeList tumors, XmlNamespaceManager nsMgr, string fieldId,
        IEnumerable<string> values, bool caseInsensitive = true)
    {
        var comparer = caseInsensitive ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

        // Distinct list in given order, for reporting; counts keyed the same way.
        var searchList = new List<string>();
        var matchCounts = new Dictionary<string, int>(comparer);
        foreach (var raw in values)
        {
            var value = raw.Trim();
            if (value.Length > 0 && matchCounts.TryAdd(value, 0))
                searchList.Add(value);
        }

        var matchedIndices = new List<int>();

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i];
            if (tumor == null) continue;

            var value = TumorFieldReader.ReadValueAnyLevel(tumor, fieldId, nsMgr).Trim();
            if (value.Length == 0 || !matchCounts.ContainsKey(value))
                continue;

            matchedIndices.Add(i);
            matchCounts[value]++;
        }

        return new ListMatchResult
        {
            MatchedIndices = matchedIndices.ToArray(),
            UnmatchedValues = searchList.Where(v => matchCounts[v] == 0).ToList(),
            MultiMatchValues = searchList.Where(v => matchCounts[v] > 1).ToList(),
            ValueCount = searchList.Count
        };
    }

}
