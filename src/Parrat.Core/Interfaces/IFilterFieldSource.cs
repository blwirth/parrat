namespace Parrat.Core.Interfaces;

/// <summary>
/// Supplies the value of one field for one record, so the filter evaluator can
/// stay ignorant of whether it is walking NAACCR XML or HL7 messages.
/// </summary>
public interface IFilterFieldSource
{
    /// <summary>Number of records the filter runs over, in load order.</summary>
    int RecordCount { get; }

    /// <summary>
    /// The value of <paramref name="fieldId"/> for the record at
    /// <paramref name="recordIndex"/> (0-based). Missing fields, out-of-range
    /// indices, and unreadable records all yield an empty string — a filter
    /// scan never throws part way through.
    /// </summary>
    string GetValue(int recordIndex, string fieldId);
}
