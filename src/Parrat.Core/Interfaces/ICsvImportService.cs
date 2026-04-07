using System.Xml;
using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface ICsvImportService
{
    List<CsvImportMapping> AutoMatch(string[] csvHeaders);
    XmlDocument GenerateNaaccrXml(
        CsvParseResult csvData,
        List<CsvImportMapping> mappings,
        string recordType = "A",
        string baseDictionaryUri = "http://naaccr.org/naaccrxml/naaccr-dictionary-250.xml");
}
