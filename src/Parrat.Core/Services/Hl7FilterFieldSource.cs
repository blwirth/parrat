using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

/// <summary>
/// Reads filter values off the parsed properties of loaded HL7 messages. The
/// addressable set is <see cref="Hl7FilterFields"/>; anything outside it reads
/// as empty rather than failing, so a filter carried over from an XML load
/// simply matches nothing instead of throwing.
/// </summary>
public sealed class Hl7FilterFieldSource : IFilterFieldSource
{
    private readonly IReadOnlyList<Hl7Message> _messages;

    public Hl7FilterFieldSource(IReadOnlyList<Hl7Message>? messages)
    {
        _messages = messages ?? Array.Empty<Hl7Message>();
    }

    public int RecordCount => _messages.Count;

    public string GetValue(int recordIndex, string fieldId)
    {
        if (recordIndex < 0 || recordIndex >= _messages.Count)
            return string.Empty;

        if (!Hl7FilterFields.TryGet(fieldId, out var field))
            return string.Empty;

        return field!.Read(_messages[recordIndex]) ?? string.Empty;
    }
}
