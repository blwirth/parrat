namespace Parrat.Core.Models;

/// <summary>
/// Represents a single parsed ePath flat file record with native field data.
/// Fields are stored as a dictionary keyed by NAACCR item number.
/// </summary>
public class EpathRecord
{
    public int Index { get; set; }
    public string RawLine { get; set; } = string.Empty;

    /// <summary>NAACCR item number → field value. Only non-empty fields are stored.</summary>
    public Dictionary<int, string> Fields { get; set; } = new();

    /// <summary>Field position → (name, value) for display. Includes all parsed fields.</summary>
    public List<EpathDisplayField> DisplayFields { get; set; } = new();

    // Convenience properties for grid display
    public string PatientLastName { get; set; } = string.Empty;
    public string PatientFirstName { get; set; } = string.Empty;
    public string DateOfBirth { get; set; } = string.Empty;
    public string Sex { get; set; } = string.Empty;
    public string PatientId { get; set; } = string.Empty;
    public string PathReportNumber { get; set; } = string.Empty;
    public string SendingFacility { get; set; } = string.Empty;
    public string FormatVersion { get; set; } = string.Empty; // "v2.2" or "NOAH v2"
}

public class EpathDisplayField
{
    public int Position { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
    public int ItemNumber { get; set; }
}
