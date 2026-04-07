using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface ICsvParserService
{
    CsvParseResult Parse(string filePath);
    CsvParseResult Parse(Stream stream);
}
