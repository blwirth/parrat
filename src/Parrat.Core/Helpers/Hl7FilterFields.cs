using Parrat.Core.Models;

namespace Parrat.Core.Helpers;

/// <summary>
/// The HL7 fields a filter can address: the values <see cref="Hl7Parser"/>
/// already pulls out of each message, plus the source file name so a folder
/// load can be narrowed to one report.
///
/// Raw segment addressing (OBX-5, PID-3.1, and the like) is deliberately not
/// here yet — the parsed set covers the questions asked of a message list, and
/// the catalogue is the only thing that would need to grow to add the rest.
/// </summary>
public static class Hl7FilterFields
{
    public sealed record Hl7FilterField(string Id, string DisplayName, Func<Hl7Message, string> Read);

    public static IReadOnlyList<Hl7FilterField> All { get; } = new List<Hl7FilterField>
    {
        new("PatientId", "Patient ID (PID-3)", m => m.PatientId),
        new("PatientLastName", "Last Name (PID-5.1)", m => m.PatientLastName),
        new("PatientFirstName", "First Name (PID-5.2)", m => m.PatientFirstName),
        new("PatientName", "Patient Name (PID-5)", m => m.PatientName),
        new("DateOfBirth", "Date of Birth (PID-7)", m => m.DateOfBirth),
        new("Sex", "Sex (PID-8)", m => m.Sex),
        new("MessageType", "Message Type (MSH-9)", m => m.MessageType),
        new("MessageDateTime", "Message Date/Time (MSH-7)", m => m.MessageDateTime),
        new("SendingApplication", "Sending Application (MSH-3)", m => m.SendingApplication),
        new("SendingFacility", "Sending Facility (MSH-4)", m => m.SendingFacility),
        new("AccessionNumber", "Accession Number", m => m.AccessionNumber),
        new("OrderDateTime", "Order Date/Time (OBR-7)", m => m.OrderDateTime),
        new("OrderingProvider", "Ordering Provider (OBR-16)", m => m.OrderingProvider),
        new("SourceFile", "Source File Name", m => Path.GetFileName(m.SourceFile ?? string.Empty))
    };

    private static readonly Dictionary<string, Hl7FilterField> ById =
        All.ToDictionary(f => f.Id, StringComparer.OrdinalIgnoreCase);

    public static bool TryGet(string? fieldId, out Hl7FilterField? field)
    {
        field = null;
        return !string.IsNullOrEmpty(fieldId) && ById.TryGetValue(fieldId, out field);
    }

    /// <summary>The label shown in a picker, falling back to the raw id.</summary>
    public static string GetDisplayName(string? fieldId) =>
        TryGet(fieldId, out var field) ? field!.DisplayName : fieldId ?? string.Empty;
}
