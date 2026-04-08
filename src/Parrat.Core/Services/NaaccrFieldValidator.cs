using System.Text.RegularExpressions;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public static class NaaccrFieldValidator
{
    private static readonly Regex DigitsOnly = new(@"^\d*$", RegexOptions.Compiled);
    private static readonly Regex AlphaOnly = new(@"^[A-Za-z ]*$", RegexOptions.Compiled);
    private static readonly Regex NumericPattern = new(@"^-?\d*\.?\d+$", RegexOptions.Compiled);
    private static readonly Regex DatePattern = new(@"^\d{4}(\d{2}(\d{2})?)?$", RegexOptions.Compiled);

    /// <summary>
    /// Validates all mapped values against NAACCR field constraints (length, dataType).
    /// </summary>
    public static List<ValidationWarning> ValidateDataSet(
        CsvParseResult csvData,
        List<CsvImportMapping> mappings,
        INaaccrDictionary dictionary,
        int? maxRows = null)
    {
        var warnings = new List<ValidationWarning>();
        var rows = maxRows.HasValue ? csvData.Rows.Take(maxRows.Value).ToList() : csvData.Rows;

        foreach (var mapping in mappings)
        {
            if (!mapping.IsExportable) continue;

            var item = dictionary.GetItemByXmlId(mapping.MappedNaaccrId!);
            if (item == null) continue;

            for (int r = 0; r < rows.Count; r++)
            {
                var value = mapping.CsvColumnIndex < rows[r].Length
                    ? rows[r][mapping.CsvColumnIndex]
                    : "";

                if (string.IsNullOrEmpty(value)) continue;

                var cellWarnings = ValidateValue(value, item);
                foreach (var msg in cellWarnings)
                {
                    warnings.Add(new ValidationWarning
                    {
                        NaaccrId = mapping.MappedNaaccrId!,
                        CsvHeader = mapping.CsvHeader,
                        RowIndex = r,
                        Value = value,
                        Message = msg
                    });
                }
            }
        }

        return warnings;
    }

    /// <summary>
    /// Validates a single value against a NAACCR item's constraints.
    /// Returns a list of warning messages (empty if valid).
    /// </summary>
    public static List<string> ValidateValue(string value, NaaccrItem item)
    {
        var warnings = new List<string>();

        // Length check
        if (item.Length.HasValue && value.Length > item.Length.Value)
        {
            warnings.Add($"Exceeds max length {item.Length} (actual: {value.Length})");
        }

        // Type-specific checks
        switch (item.DataType)
        {
            case "date":
                ValidateDate(value, warnings);
                break;
            case "digits":
                if (!DigitsOnly.IsMatch(value))
                    warnings.Add("Expected digits only");
                break;
            case "alpha":
                if (!AlphaOnly.IsMatch(value))
                    warnings.Add("Expected alpha characters only");
                break;
            case "numeric":
                if (!NumericPattern.IsMatch(value))
                    warnings.Add("Expected numeric value");
                break;
            // "text" and "mixed" — no character validation
        }

        return warnings;
    }

    private static void ValidateDate(string value, List<string> warnings)
    {
        if (!DatePattern.IsMatch(value))
        {
            warnings.Add("Expected date format CCYYMMDD (4, 6, or 8 digits)");
            return;
        }

        // Validate month/day ranges
        if (value.Length >= 6)
        {
            var month = int.Parse(value[4..6]);
            if (month < 1 || month > 12)
                warnings.Add($"Invalid month: {month:D2}");
        }

        if (value.Length >= 8)
        {
            var day = int.Parse(value[6..8]);
            if (day < 1 || day > 31)
                warnings.Add($"Invalid day: {day:D2}");
        }
    }

    /// <summary>
    /// Aggregates per-cell warnings into per-column summaries for display.
    /// </summary>
    public static List<string> Summarize(List<ValidationWarning> warnings)
    {
        return warnings
            .GroupBy(w => new { w.NaaccrId, w.Message })
            .Select(g =>
            {
                var count = g.Count();
                var header = g.First().CsvHeader;
                return count == 1
                    ? $"{header} ({g.Key.NaaccrId}): {g.Key.Message} — row {g.First().RowIndex + 1}"
                    : $"{header} ({g.Key.NaaccrId}): {g.Key.Message} — {count} rows";
            })
            .ToList();
    }
}
