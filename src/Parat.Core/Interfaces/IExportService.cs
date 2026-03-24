using System.Xml;
using Parat.Core.Models;

namespace Parat.Core.Interfaces;

public interface IExportService
{
    void ExportTumorsCsv(int[]? tumorIndices, XmlDocument xmlDoc, XmlNamespaceManager nsMgr,
        string outputPath, List<ExportField> fieldList, Dictionary<string, string>? customFields = null);
    void ExportSelectedCsv(int[] tumorIndices, XmlDocument xmlDoc, XmlNamespaceManager nsMgr,
        string outputPath, List<ExportField> fieldList, Dictionary<string, string>? customFields = null);
    void ExportAllCsv(XmlDocument xmlDoc, XmlNamespaceManager nsMgr,
        string outputPath, List<ExportField> fieldList, Dictionary<string, string>? customFields = null);
    void ExportHl7Csv(int[]? messageIndices, List<Hl7Message> messages, string outputPath);
    void ExportSelectedHl7Csv(int[] messageIndices, List<Hl7Message> messages, string outputPath);
    void ExportAllHl7Csv(List<Hl7Message> messages, string outputPath);
    void ExportSelectedXml(int[] tumorIndices, XmlDocument xmlDoc, XmlNamespaceManager nsMgr, string outputPath);
    void ExportSelectedHl7(int[] messageIndices, List<Hl7Message> messages, string outputPath);
}
