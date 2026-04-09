using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IEpathParserService
{
    List<Hl7Message> ParseDatFile(string filePath);
}
