using System.Globalization;
using System.Text;
using System.Xml;
using Parat.Core.Interfaces;
using Parat.Core.Models;

namespace Parat.Core.Services;

/// <summary>
/// Unified export service implementing IExportService.
/// Handles CSV, XML, and HL7 exports for both tumor and HL7 message data.
/// </summary>
public class ExportService : IExportService
{
    private readonly XmlNodeList? _tumors;

    public ExportService()
    {
    }

    /// <summary>
    /// Create with a reference to loaded tumors for index validation.
    /// </summary>
    public ExportService(XmlNodeList? tumors)
    {
        _tumors = tumors;
    }

    public void ExportTumorsCsv(int[]? tumorIndices, XmlDocument xmlDoc, XmlNamespaceManager nsMgr,
        string outputPath, List<ExportField> fieldList, Dictionary<string, string>? customFields = null)
    {
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        var effectiveTumors = _tumors ?? tumors;

        // If no indices provided, export all
        if (tumorIndices == null || tumorIndices.Length == 0)
            tumorIndices = Enumerable.Range(0, effectiveTumors.Count).ToArray();

        WriteTumorCsv(tumorIndices, effectiveTumors, nsMgr, outputPath, fieldList, customFields);
    }

    public void ExportSelectedCsv(int[] tumorIndices, XmlDocument xmlDoc, XmlNamespaceManager nsMgr,
        string outputPath, List<ExportField> fieldList, Dictionary<string, string>? customFields = null)
    {
        ExportTumorsCsv(tumorIndices, xmlDoc, nsMgr, outputPath, fieldList, customFields);
    }

    public void ExportAllCsv(XmlDocument xmlDoc, XmlNamespaceManager nsMgr,
        string outputPath, List<ExportField> fieldList, Dictionary<string, string>? customFields = null)
    {
        ExportTumorsCsv(null, xmlDoc, nsMgr, outputPath, fieldList, customFields);
    }

    public void ExportHl7Csv(int[]? messageIndices, List<Hl7Message> messages, string outputPath)
    {
        if (messages == null || messages.Count == 0)
            return;

        if (messageIndices == null || messageIndices.Length == 0)
            messageIndices = Enumerable.Range(0, messages.Count).ToArray();

        WriteHl7Csv(messageIndices, messages, outputPath);
    }

    public void ExportSelectedHl7Csv(int[] messageIndices, List<Hl7Message> messages, string outputPath)
    {
        ExportHl7Csv(messageIndices, messages, outputPath);
    }

    public void ExportAllHl7Csv(List<Hl7Message> messages, string outputPath)
    {
        ExportHl7Csv(null, messages, outputPath);
    }

    public void ExportSelectedXml(int[] tumorIndices, XmlDocument xmlDoc, XmlNamespaceManager nsMgr, string outputPath)
    {
        if (tumorIndices.Length == 0)
            return;

        var tumors = _tumors ?? xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        var root = xmlDoc.DocumentElement!;

        var newDoc = new XmlDocument();
        newDoc.XmlResolver = null;

        // Copy XML declaration
        foreach (XmlNode child in xmlDoc.ChildNodes)
        {
            if (child is XmlDeclaration decl)
            {
                var newDecl = newDoc.CreateXmlDeclaration(decl.Version, decl.Encoding, decl.Standalone);
                newDoc.AppendChild(newDecl);
                break;
            }
        }

        var newRoot = newDoc.CreateElement(root.Prefix, root.LocalName, root.NamespaceURI);
        CopyAttributes(root, newRoot, newDoc);
        newDoc.AppendChild(newRoot);

        // Copy non-Patient children of root
        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName != "Patient")
            {
                var imported = newDoc.ImportNode(child, true);
                newRoot.AppendChild(imported);
            }
        }

        // Group tumors by patient
        var patientsMap = new Dictionary<XmlNode, List<int>>(ReferenceEqualityComparer.Instance);

        foreach (int tumorIndex in tumorIndices)
        {
            if (tumorIndex < 0 || tumorIndex >= tumors.Count) continue;

            var tumor = tumors[tumorIndex]!;
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
            if (patient == null) continue;

            if (!patientsMap.ContainsKey(patient))
                patientsMap[patient] = new List<int>();
            patientsMap[patient].Add(tumorIndex);
        }

        foreach (var kvp in patientsMap)
        {
            var patientNode = kvp.Key;
            var newPatient = newDoc.CreateElement(patientNode.Prefix, patientNode.LocalName, patientNode.NamespaceURI);
            CopyAttributes(patientNode, newPatient, newDoc);

            foreach (XmlNode child in patientNode.ChildNodes)
            {
                if (child.LocalName == "Item")
                {
                    var imported = newDoc.ImportNode(child, true);
                    newPatient.AppendChild(imported);
                }
            }

            foreach (int tumorIndex in kvp.Value)
            {
                var tumor = tumors[tumorIndex]!;
                var importedTumor = newDoc.ImportNode(tumor, true);
                newPatient.AppendChild(importedTumor);
            }

            newRoot.AppendChild(newPatient);
        }

        var settings = new XmlWriterSettings
        {
            Indent = true,
            IndentChars = "  ",
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace
        };

        using var writer = XmlWriter.Create(outputPath, settings);
        newDoc.Save(writer);
    }

    public void ExportSelectedHl7(int[] messageIndices, List<Hl7Message> messages, string outputPath)
    {
        if (messageIndices.Length == 0)
            return;

        var exportedMessages = new List<string>();

        foreach (int messageIndex in messageIndices)
        {
            if (messageIndex < 0 || messageIndex >= messages.Count) continue;
            exportedMessages.Add(messages[messageIndex].RawContent);
        }

        if (exportedMessages.Count == 0)
            return;

        string combinedContent = string.Join("", exportedMessages);
        File.WriteAllText(outputPath, combinedContent, Encoding.ASCII);
    }

    // --- Private helpers ---

    private static void WriteTumorCsv(int[] tumorIndices, XmlNodeList tumors, XmlNamespaceManager nsMgr,
        string outputPath, List<ExportField> fieldList, Dictionary<string, string>? customFields)
    {
        var rows = new List<Dictionary<string, string>>();

        foreach (int tumorIndex in tumorIndices)
        {
            if (tumorIndex < 0 || tumorIndex >= tumors.Count) continue;

            var tumor = tumors[tumorIndex]!;
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
            if (patient == null) continue;

            var row = new Dictionary<string, string>();

            foreach (var field in fieldList)
            {
                string value = "";
                string parentElement = field.ParentElement ?? "Tumor";

                // Check custom fields mapping
                if (customFields != null && customFields.TryGetValue(field.XmlId, out var customParent))
                    parentElement = customParent;

                if (parentElement == "Patient")
                {
                    var node = patient.SelectSingleNode($"./n:Item[@naaccrId='{field.XmlId}']", nsMgr);
                    if (node != null) value = node.InnerText;
                }
                else
                {
                    var node = tumor.SelectSingleNode($"./n:Item[@naaccrId='{field.XmlId}']", nsMgr);
                    if (node != null) value = node.InnerText;
                }

                row[field.XmlId] = value;
            }

            rows.Add(row);
        }

        // Write CSV manually (matching PS behavior)
        var csvContent = new List<string>();

        // Header row
        csvContent.Add(string.Join(",", fieldList.Select(f => f.XmlId)));

        // Data rows
        foreach (var row in rows)
        {
            var csvRow = new List<string>();
            foreach (var field in fieldList)
            {
                string value = row.TryGetValue(field.XmlId, out var v) ? v : "";
                if (value.IndexOfAny(new[] { ',', '"', '\r', '\n' }) >= 0)
                    value = "\"" + value.Replace("\"", "\"\"") + "\"";
                csvRow.Add(value);
            }
            csvContent.Add(string.Join(",", csvRow));
        }

        File.WriteAllLines(outputPath, csvContent, Encoding.UTF8);
    }

    private static void WriteHl7Csv(int[] messageIndices, List<Hl7Message> messages, string outputPath)
    {
        var csvContent = new List<string>();

        // Header
        csvContent.Add("LastName,FirstName,DateOfBirth,MessageDateTime");

        foreach (int messageIndex in messageIndices)
        {
            if (messageIndex < 0 || messageIndex >= messages.Count) continue;

            var message = messages[messageIndex];
            string lastName = message.PatientLastName ?? "";
            string firstName = message.PatientFirstName ?? "";
            string dateOfBirth = message.DateOfBirth ?? "";
            string messageDateTime = message.MessageDateTime ?? "";

            var fields = new[] { lastName, firstName, dateOfBirth, messageDateTime };
            var csvRow = fields.Select(f =>
            {
                if (f.IndexOfAny(new[] { ',', '"', '\r', '\n' }) >= 0)
                    return "\"" + f.Replace("\"", "\"\"") + "\"";
                return f;
            });

            csvContent.Add(string.Join(",", csvRow));
        }

        File.WriteAllLines(outputPath, csvContent, Encoding.UTF8);
    }

    private static void CopyAttributes(XmlNode source, XmlElement target, XmlDocument newDoc)
    {
        if (source.Attributes == null) return;
        foreach (XmlAttribute attr in source.Attributes)
        {
            var newAttr = newDoc.CreateAttribute(attr.Prefix, attr.LocalName, attr.NamespaceURI);
            newAttr.Value = attr.Value;
            target.Attributes.Append(newAttr);
        }
    }
}
