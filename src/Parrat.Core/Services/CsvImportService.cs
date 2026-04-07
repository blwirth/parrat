using System.Text.RegularExpressions;
using System.Xml;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class CsvImportService : ICsvImportService
{
    private const string NaaccrNamespace = "http://naaccr.org/naaccrxml";

    private static readonly Dictionary<int, string> BaseDictionaryUris = new()
    {
        [25] = "http://naaccr.org/naaccrxml/naaccr-dictionary-250.xml",
        [26] = "http://naaccr.org/naaccrxml/naaccr-dictionary-260.xml"
    };

    private readonly INaaccrDictionary _dictionary;

    public CsvImportService(INaaccrDictionary dictionary)
    {
        _dictionary = dictionary;
    }

    public List<CsvImportMapping> AutoMatch(string[] csvHeaders, int naaccrVersion = 25)
    {
        _dictionary.Initialize(naaccrVersion);
        var dict = _dictionary.GetDictionary();
        var mappings = new List<CsvImportMapping>();
        var usedXmlIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (int i = 0; i < csvHeaders.Length; i++)
        {
            var header = csvHeaders[i].Trim();
            var mapping = new CsvImportMapping
            {
                CsvColumnIndex = i,
                CsvHeader = header
            };

            var matchedId = TryMatchHeader(header, dict, usedXmlIds, naaccrVersion);
            if (matchedId != null)
            {
                mapping.MappedNaaccrId = matchedId;
                mapping.IsAutoMatched = true;
                usedXmlIds.Add(matchedId);
            }

            mappings.Add(mapping);
        }

        return mappings;
    }

    public XmlDocument GenerateNaaccrXml(
        CsvParseResult csvData,
        List<CsvImportMapping> mappings,
        int naaccrVersion = 25,
        string recordType = "A")
    {
        _dictionary.Initialize(naaccrVersion);
        var baseDictionaryUri = BaseDictionaryUris.GetValueOrDefault(naaccrVersion,
            BaseDictionaryUris[25]);

        var doc = new XmlDocument();
        doc.AppendChild(doc.CreateXmlDeclaration("1.0", "UTF-8", null));

        var root = doc.CreateElement("NaaccrData", NaaccrNamespace);
        root.SetAttribute("baseDictionaryUri", baseDictionaryUri);
        root.SetAttribute("recordType", recordType);
        doc.AppendChild(root);

        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", NaaccrNamespace);

        // Partition mappings by parent element
        var activeMappings = mappings.Where(m => !m.IsSkipped).ToList();
        var naaccrDataMappings = new List<CsvImportMapping>();
        var patientMappings = new List<CsvImportMapping>();
        var tumorMappings = new List<CsvImportMapping>();

        foreach (var m in activeMappings)
        {
            var parent = _dictionary.GetParentElement(m.MappedNaaccrId!);
            switch (parent)
            {
                case "NaaccrData":
                    naaccrDataMappings.Add(m);
                    break;
                case "Patient":
                    patientMappings.Add(m);
                    break;
                default:
                    tumorMappings.Add(m);
                    break;
            }
        }

        // NaaccrData-level items from first row
        if (csvData.Rows.Count > 0)
        {
            foreach (var m in naaccrDataMappings)
            {
                var value = GetCellValue(csvData.Rows[0], m.CsvColumnIndex);
                if (!string.IsNullOrEmpty(value))
                    AddItem(doc, root, m.MappedNaaccrId!, value);
            }
        }

        // Group rows into patients
        var patientIdMapping = patientMappings
            .FirstOrDefault(m => m.MappedNaaccrId == "patientIdNumber");

        var patientGroups = GroupRowsByPatient(csvData.Rows, patientIdMapping);

        foreach (var group in patientGroups)
        {
            var patientNode = doc.CreateElement("Patient", NaaccrNamespace);
            root.AppendChild(patientNode);

            // Patient-level items from first row in group
            var firstRow = group[0];
            foreach (var m in patientMappings)
            {
                var value = GetCellValue(firstRow, m.CsvColumnIndex);
                if (!string.IsNullOrEmpty(value))
                    AddItem(doc, patientNode, m.MappedNaaccrId!, value);
            }

            // Each row becomes a Tumor
            foreach (var row in group)
            {
                var tumorNode = doc.CreateElement("Tumor", NaaccrNamespace);
                patientNode.AppendChild(tumorNode);

                foreach (var m in tumorMappings)
                {
                    var value = GetCellValue(row, m.CsvColumnIndex);
                    if (!string.IsNullOrEmpty(value))
                        AddItem(doc, tumorNode, m.MappedNaaccrId!, value);
                }
            }
        }

        return doc;
    }

    private string? TryMatchHeader(string header, Dictionary<string, NaaccrItem> dict,
        HashSet<string> usedXmlIds, int naaccrVersion)
    {
        // For v26: also try matching "sex" header to "sexAssignedAtBirth"
        if (naaccrVersion >= 26)
        {
            var normalizedHeader = Normalize(header);
            if (normalizedHeader == "sex" && !usedXmlIds.Contains("sexAssignedAtBirth")
                && dict.ContainsKey("sexAssignedAtBirth"))
            {
                return "sexAssignedAtBirth";
            }
        }

        // 1. Exact match on xmlId (case-insensitive)
        foreach (var item in dict.Values)
        {
            if (!usedXmlIds.Contains(item.XmlId) &&
                string.Equals(header, item.XmlId, StringComparison.OrdinalIgnoreCase))
            {
                return item.XmlId;
            }
        }

        // 2. Exact match on Name (case-insensitive)
        foreach (var item in dict.Values)
        {
            if (!usedXmlIds.Contains(item.XmlId) &&
                string.Equals(header, item.Name, StringComparison.OrdinalIgnoreCase))
            {
                return item.XmlId;
            }
        }

        // 3. Normalized match: strip non-alphanumeric, lowercase, compare
        var normalizedHdr = Normalize(header);
        if (string.IsNullOrEmpty(normalizedHdr))
            return null;

        foreach (var item in dict.Values)
        {
            if (!usedXmlIds.Contains(item.XmlId) &&
                (normalizedHdr == Normalize(item.XmlId) || normalizedHdr == Normalize(item.Name)))
            {
                return item.XmlId;
            }
        }

        return null;
    }

    private static string Normalize(string value)
    {
        return Regex.Replace(value, @"[^a-zA-Z0-9]", "").ToLowerInvariant();
    }

    private static List<List<string[]>> GroupRowsByPatient(
        List<string[]> rows,
        CsvImportMapping? patientIdMapping)
    {
        if (patientIdMapping == null)
        {
            // Each row is its own patient
            return rows.Select(r => new List<string[]> { r }).ToList();
        }

        var groups = new List<List<string[]>>();
        var groupIndex = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var row in rows)
        {
            var patientId = GetCellValue(row, patientIdMapping.CsvColumnIndex);
            if (string.IsNullOrEmpty(patientId))
                patientId = $"__empty_{groups.Count}__";

            if (groupIndex.TryGetValue(patientId, out var idx))
            {
                groups[idx].Add(row);
            }
            else
            {
                groupIndex[patientId] = groups.Count;
                groups.Add(new List<string[]> { row });
            }
        }

        return groups;
    }

    private static string GetCellValue(string[] row, int columnIndex)
    {
        return columnIndex < row.Length ? row[columnIndex] : "";
    }

    private static void AddItem(XmlDocument doc, XmlElement parent, string naaccrId, string value)
    {
        var item = doc.CreateElement("Item", NaaccrNamespace);
        item.SetAttribute("naaccrId", naaccrId);
        item.InnerText = value;
        parent.AppendChild(item);
    }
}
