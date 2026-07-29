using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;

namespace Parrat.Core.Services;

/// <summary>
/// Reads filter values out of a loaded NAACCR XML document, one tumor per
/// record. Values are looked up at the level the field lives at, so a filter on
/// a patient-level field such as sex works from a tumor row without the caller
/// knowing where the item sits.
///
/// Every field the filter touches is read in one pass per record via
/// <see cref="NaaccrLeveledItemReader"/> and cached for that record, so a
/// multi-condition filter costs one walk of the tumor and its patient rather
/// than one XPath per condition. Construct one source per filter run: the
/// underlying reader caches file-level items and must not outlive edits to the
/// document.
/// </summary>
public sealed class XmlFilterFieldSource : IFilterFieldSource
{
    private readonly XmlNodeList? _tumors;
    private readonly NaaccrLeveledItemReader? _reader;
    private readonly Dictionary<string, string> _values = new(StringComparer.Ordinal);

    private int _cachedIndex = -1;

    /// <param name="tumors">Tumor nodes in load order — the same list the nav grid is built from.</param>
    /// <param name="fieldIds">Every field id the filter refers to.</param>
    /// <param name="parentElementResolver">Maps a field id to its level ("NaaccrData", "Patient", or "Tumor").</param>
    public XmlFilterFieldSource(
        XmlNodeList? tumors,
        IEnumerable<string> fieldIds,
        Func<string, string> parentElementResolver)
    {
        _tumors = tumors;

        var ids = fieldIds?.Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).ToList()
                  ?? new List<string>();

        if (ids.Count > 0)
        {
            _reader = new NaaccrLeveledItemReader(
                ids.Select(id => new KeyValuePair<string, string>(id, parentElementResolver(id))));
        }
    }

    public int RecordCount => _tumors?.Count ?? 0;

    public string GetValue(int recordIndex, string fieldId)
    {
        if (_reader == null || _tumors == null || recordIndex < 0 || recordIndex >= _tumors.Count)
            return string.Empty;

        if (recordIndex != _cachedIndex)
        {
            _values.Clear();
            _cachedIndex = recordIndex;

            var tumor = _tumors[recordIndex];
            if (tumor != null)
                _reader.ReadRow(tumor, NaaccrLeveledItemReader.FindPatient(tumor), _values);
        }

        return _values.TryGetValue(fieldId, out var value) ? value : string.Empty;
    }
}
