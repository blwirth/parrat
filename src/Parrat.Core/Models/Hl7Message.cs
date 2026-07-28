namespace Parrat.Core.Models;

public class Hl7Message
{
    public int Index { get; set; }
    public string RawContent { get; set; } = string.Empty;

    /// <summary>
    /// Path of the file this message was read from. Set when a folder is loaded
    /// so a record can be traced back to its original report; empty otherwise.
    /// </summary>
    public string SourceFile { get; set; } = string.Empty;

    public Dictionary<string, List<string>> Segments { get; set; } = new();
    public List<string> AllSegments { get; set; } = new();
    public string PatientId { get; set; } = string.Empty;
    public string PatientName { get; set; } = string.Empty;
    public string PatientLastName { get; set; } = string.Empty;
    public string PatientFirstName { get; set; } = string.Empty;
    public string DateOfBirth { get; set; } = string.Empty;
    public string Sex { get; set; } = string.Empty;
    public string MessageType { get; set; } = string.Empty;
    public string MessageDateTime { get; set; } = string.Empty;
    public string SendingApplication { get; set; } = string.Empty;
    public string SendingFacility { get; set; } = string.Empty;
    public string AccessionNumber { get; set; } = string.Empty;
    public string OrderDateTime { get; set; } = string.Empty;
    public string OrderingProvider { get; set; } = string.Empty;
}
