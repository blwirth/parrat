using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IEpathParserService
{
    /// <summary>Parse .dat file into native ePath records for display.</summary>
    List<EpathRecord> ParseDatFile(string filePath);

    /// <summary>Convert parsed ePath records to HL7 messages (only called on explicit user action).</summary>
    List<Hl7Message> ConvertToHl7(List<EpathRecord> records);
}
