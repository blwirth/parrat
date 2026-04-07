using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IXlsxParserService
{
    CsvParseResult Parse(string filePath);
    CsvParseResult Parse(Stream stream);
}
