using System.Xml;

namespace Parrat.Core.Helpers;

/// <summary>
/// Reads a set of NAACCR items for a tumor where each item lives at a known
/// level — NaaccrData, Patient, or Tumor — as the CSV export and its preview do.
///
/// Two costs are avoided compared with looking each field up individually:
///
/// Items at one level are gathered in a single pass over that element's
/// children instead of one XPath expression per field.
///
/// File-level items are read once for the whole document rather than once per
/// tumor. That lookup is the expensive one: the items sit among NaaccrData's
/// children alongside every Patient in the file, so an XPath for one of them
/// scans the entire patient list. Repeating that per tumor makes an export
/// quadratic in the number of records.
///
/// Construct one reader per export. The file-level values are cached on first
/// use, so a reader must not outlive edits to the document it read from.
/// </summary>
public sealed class NaaccrLeveledItemReader
{
    public const string NaaccrDataLevel = "NaaccrData";
    public const string PatientLevel = "Patient";
    public const string TumorLevel = "Tumor";

    private readonly NaaccrItemReader? _fileLevelReader;
    private readonly NaaccrItemReader? _patientLevelReader;
    private readonly NaaccrItemReader? _tumorLevelReader;

    private XmlNode? _cachedRoot;
    private Dictionary<string, string> _fileLevelValues = new(StringComparer.Ordinal);

    /// <summary>
    /// Groups the requested fields by the level they are read from. Where an id
    /// is listed more than once the last level given wins, matching the way a
    /// per-field loop would overwrite an earlier value.
    /// </summary>
    public NaaccrLeveledItemReader(IEnumerable<KeyValuePair<string, string>> fieldLevels)
    {
        var levelById = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var field in fieldLevels)
            levelById[field.Key] = field.Value;

        var fileIds = new List<string>();
        var patientIds = new List<string>();
        var tumorIds = new List<string>();

        foreach (var entry in levelById)
        {
            switch (entry.Value)
            {
                case NaaccrDataLevel: fileIds.Add(entry.Key); break;
                case PatientLevel: patientIds.Add(entry.Key); break;
                // Anything else is treated as tumor level, matching the previous
                // reader's else-branch.
                default: tumorIds.Add(entry.Key); break;
            }
        }

        _fileLevelReader = fileIds.Count > 0 ? new NaaccrItemReader(fileIds) : null;
        _patientLevelReader = patientIds.Count > 0 ? new NaaccrItemReader(patientIds) : null;
        _tumorLevelReader = tumorIds.Count > 0 ? new NaaccrItemReader(tumorIds) : null;
    }

    /// <summary>
    /// Reads every requested field for one tumor into <paramref name="into"/>,
    /// which the caller clears between rows. Fields with no value are absent
    /// rather than empty.
    /// </summary>
    public void ReadRow(XmlNode tumor, XmlNode? patient, IDictionary<string, string> into)
    {
        _tumorLevelReader?.ReadInto(tumor, into);
        _patientLevelReader?.ReadInto(patient, into);

        if (_fileLevelReader == null)
            return;

        foreach (var value in FileLevelValues(tumor))
        {
            if (!into.ContainsKey(value.Key))
                into[value.Key] = value.Value;
        }
    }

    /// <summary>
    /// The file-level items of the document this tumor belongs to, read once
    /// and reused for every subsequent row.
    /// </summary>
    private Dictionary<string, string> FileLevelValues(XmlNode tumor)
    {
        var root = tumor.OwnerDocument?.DocumentElement;
        if (root == null)
            return _fileLevelValues;

        if (!ReferenceEquals(root, _cachedRoot))
        {
            _cachedRoot = root;
            _fileLevelValues = new Dictionary<string, string>(StringComparer.Ordinal);
            _fileLevelReader!.ReadInto(root, _fileLevelValues);
        }

        return _fileLevelValues;
    }

    /// <summary>
    /// Walks up from a tumor to its Patient element. Equivalent to the
    /// "ancestor::n:Patient[1]" lookup it replaces, without the XPath.
    /// </summary>
    public static XmlNode? FindPatient(XmlNode tumor)
    {
        var node = tumor.ParentNode;
        while (node != null && !string.Equals(node.LocalName, PatientLevel, StringComparison.Ordinal))
            node = node.ParentNode;

        return node;
    }
}
