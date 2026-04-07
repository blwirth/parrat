using System.Xml;
using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface ICsvImportService
{
    List<CsvImportMapping> AutoMatch(string[] csvHeaders, int naaccrVersion = 25);
    XmlDocument GenerateNaaccrXml(
        CsvParseResult csvData,
        List<CsvImportMapping> mappings,
        int naaccrVersion = 25,
        string recordType = "A");
}
