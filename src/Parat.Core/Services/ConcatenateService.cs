using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using Parat.Core.Interfaces;

namespace Parat.Core.Services;

/// <summary>
/// Concatenates multiple XML, HL7, or TXT files into one.
/// Ported from lib/concatenate-xml.ps1, lib/concatenate-hl7.ps1, lib/concatenate-txt.ps1.
/// </summary>
public class ConcatenateService : IConcatenateService
{
    #region XML Concatenation

    public Dictionary<string, object> GetXmlHeaderInfo(string filePath)
    {
        try
        {
            var xml = new XmlDocument();
            xml.XmlResolver = null;
            xml.Load(filePath);

            // Get XML declaration version
            var xmlVersion = "1.0";
            foreach (XmlNode child in xml.ChildNodes)
            {
                if (child is XmlDeclaration decl)
                {
                    xmlVersion = decl.Version;
                    break;
                }
            }

            var root = xml.DocumentElement;
            if (root == null || root.LocalName != "NaaccrData")
                throw new InvalidOperationException("Root element is not NaaccrData");

            var baseDictionaryUri = root.GetAttribute("baseDictionaryUri");
            var xmlns = root.NamespaceURI;
            var recordType = root.GetAttribute("recordType");

            var nsMgr = new XmlNamespaceManager(xml.NameTable);
            nsMgr.AddNamespace("n", xmlns);
            var tumors = xml.SelectNodes("//n:Tumor", nsMgr)!;

            return new Dictionary<string, object>
            {
                ["XmlVersion"] = xmlVersion,
                ["BaseDictionaryUri"] = baseDictionaryUri,
                ["Xmlns"] = xmlns,
                ["RecordType"] = recordType,
                ["TumorCount"] = tumors.Count,
                ["XmlDoc"] = xml,
                ["NsMgr"] = nsMgr,
                ["Tumors"] = tumors,
                ["Success"] = true
            };
        }
        catch (Exception ex)
        {
            return new Dictionary<string, object>
            {
                ["Success"] = false,
                ["Error"] = ex.Message
            };
        }
    }

    public List<string> GetDuplicatePatientIds(List<Dictionary<string, object>> headerInfos)
    {
        var patientIdCounts = new Dictionary<string, int>();

        foreach (var item in headerInfos)
        {
            if (!item.TryGetValue("XmlDoc", out var xmlDocObj) || xmlDocObj is not XmlDocument xmlDoc)
                continue;
            if (!item.TryGetValue("NsMgr", out var nsMgrObj) || nsMgrObj is not XmlNamespaceManager nsMgr)
                continue;

            var root = xmlDoc.DocumentElement;
            if (root == null) continue;

            var patients = root.SelectNodes("./n:Patient", nsMgr);
            if (patients == null) continue;

            foreach (XmlNode patient in patients)
            {
                var pidNode = patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", nsMgr);
                if (pidNode != null && !string.IsNullOrWhiteSpace(pidNode.InnerText))
                {
                    var val = pidNode.InnerText.Trim();
                    patientIdCounts[val] = patientIdCounts.TryGetValue(val, out var count) ? count + 1 : 1;
                }
            }
        }

        return patientIdCounts.Where(kvp => kvp.Value > 1).Select(kvp => kvp.Key).ToList();
    }

    public (bool Valid, string? Error) TestXmlHeaderAgainstReference(
        Dictionary<string, object> newInfo,
        Dictionary<string, object> referenceInfo)
    {
        var errors = new List<string>();

        CompareField(newInfo, referenceInfo, "XmlVersion", "XML version", errors);
        CompareField(newInfo, referenceInfo, "BaseDictionaryUri", "baseDictionaryUri", errors);
        CompareField(newInfo, referenceInfo, "Xmlns", "xmlns", errors);
        CompareField(newInfo, referenceInfo, "RecordType", "recordType", errors);

        if (errors.Count > 0)
            return (false, string.Join("\n", errors));

        return (true, null);
    }

    private static void CompareField(
        Dictionary<string, object> newInfo,
        Dictionary<string, object> refInfo,
        string key,
        string displayName,
        List<string> errors)
    {
        var newVal = newInfo.TryGetValue(key, out var nv) ? nv?.ToString() ?? "" : "";
        var refVal = refInfo.TryGetValue(key, out var rv) ? rv?.ToString() ?? "" : "";

        if (newVal != refVal)
            errors.Add($"{displayName} mismatch: '{newVal}' vs expected '{refVal}'");
    }

    public void WriteConcatenatedXml(
        List<Dictionary<string, object>> headerInfos,
        Dictionary<string, object> referenceInfo,
        string outputPath,
        bool showProgress = false,
        bool reassignPatientIds = false)
    {
        var refXmlVersion = referenceInfo.TryGetValue("XmlVersion", out var v) ? v?.ToString() ?? "1.0" : "1.0";
        var refXmlns = referenceInfo.TryGetValue("Xmlns", out var ns) ? ns?.ToString() ?? "" : "";
        var refBaseDictUri = referenceInfo.TryGetValue("BaseDictionaryUri", out var bdu) ? bdu?.ToString() ?? "" : "";
        var refRecordType = referenceInfo.TryGetValue("RecordType", out var rt) ? rt?.ToString() ?? "" : "";

        var newDoc = new XmlDocument();
        newDoc.XmlResolver = null;

        var decl = newDoc.CreateXmlDeclaration(refXmlVersion, "UTF-8", null);
        newDoc.AppendChild(decl);

        var newRoot = newDoc.CreateElement("NaaccrData", refXmlns);
        newRoot.SetAttribute("baseDictionaryUri", refBaseDictUri);
        newRoot.SetAttribute("recordType", refRecordType);
        newRoot.SetAttribute("timeGenerated", DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffK"));
        newRoot.SetAttribute("specificationVersion", "1.7");
        newDoc.AppendChild(newRoot);

        foreach (var item in headerInfos)
        {
            if (!item.TryGetValue("XmlDoc", out var xmlDocObj) || xmlDocObj is not XmlDocument xmlDoc)
                continue;
            if (!item.TryGetValue("NsMgr", out var nsMgrObj) || nsMgrObj is not XmlNamespaceManager nsMgr)
                continue;

            var root = xmlDoc.DocumentElement;
            if (root == null) continue;

            var patients = root.SelectNodes("./n:Patient", nsMgr);
            if (patients == null) continue;

            foreach (XmlNode patient in patients)
            {
                var imported = newDoc.ImportNode(patient, true);
                newRoot.AppendChild(imported);
            }
        }

        if (reassignPatientIds)
        {
            var newNsMgr = new XmlNamespaceManager(newDoc.NameTable);
            newNsMgr.AddNamespace("n", refXmlns);

            var allPatients = newRoot.SelectNodes("./n:Patient", newNsMgr);
            if (allPatients != null)
            {
                int patientId = 1;
                foreach (XmlNode patient in allPatients)
                {
                    var pidNode = patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", newNsMgr);
                    if (pidNode != null)
                    {
                        pidNode.InnerText = patientId.ToString().PadLeft(8, '0');
                    }
                    else
                    {
                        var newItem = newDoc.CreateElement("Item", refXmlns);
                        newItem.SetAttribute("naaccrId", "patientIdNumber");
                        newItem.InnerText = patientId.ToString().PadLeft(8, '0');

                        if (patient.HasChildNodes)
                            patient.InsertBefore(newItem, patient.FirstChild);
                        else
                            patient.AppendChild(newItem);
                    }
                    patientId++;
                }
            }
        }

        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace
        };

        using var writer = XmlWriter.Create(outputPath, settings);
        newDoc.Save(writer);
    }

    public void WriteConcatenatedXmlFromPaths(string[] filePaths, string outputPath)
    {
        if (filePaths.Length == 0)
            throw new ArgumentException("No files provided", nameof(filePaths));

        var refInfo = GetXmlHeaderInfo(filePaths[0]);
        if (!(bool)refInfo["Success"])
            throw new InvalidOperationException($"Failed to read first file: {refInfo["Error"]}");

        var refXmlVersion = refInfo["XmlVersion"]?.ToString() ?? "1.0";
        var refXmlns = refInfo["Xmlns"]?.ToString() ?? "";
        var refBaseDictUri = refInfo["BaseDictionaryUri"]?.ToString() ?? "";
        var refRecordType = refInfo["RecordType"]?.ToString() ?? "";

        var newDoc = new XmlDocument();
        newDoc.XmlResolver = null;

        var decl = newDoc.CreateXmlDeclaration(refXmlVersion, "UTF-8", null);
        newDoc.AppendChild(decl);

        var newRoot = newDoc.CreateElement("NaaccrData", refXmlns);
        newRoot.SetAttribute("baseDictionaryUri", refBaseDictUri);
        newRoot.SetAttribute("recordType", refRecordType);
        newRoot.SetAttribute("timeGenerated", DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffK"));
        newRoot.SetAttribute("specificationVersion", "1.7");
        newDoc.AppendChild(newRoot);

        foreach (var filePath in filePaths)
        {
            try
            {
                var xml = new XmlDocument();
                xml.XmlResolver = null;
                xml.Load(filePath);

                var root = xml.DocumentElement;
                if (root == null || root.LocalName != "NaaccrData")
                    continue;

                var fileRecordType = root.GetAttribute("recordType");
                if (fileRecordType != refRecordType)
                    continue;

                var xmlns = root.NamespaceURI;
                var nsMgr = new XmlNamespaceManager(xml.NameTable);
                nsMgr.AddNamespace("n", xmlns);

                var patients = root.SelectNodes("./n:Patient", nsMgr);
                if (patients == null) continue;

                foreach (XmlNode patient in patients)
                {
                    var imported = newDoc.ImportNode(patient, true);
                    newRoot.AppendChild(imported);
                }
            }
            catch
            {
                // Skip files that fail to load
            }
        }

        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace
        };

        using var writer = XmlWriter.Create(outputPath, settings);
        newDoc.Save(writer);
    }

    #endregion

    #region HL7 Concatenation

    public Dictionary<string, object> GetHl7FileInfo(string filePath)
    {
        try
        {
            var content = File.ReadAllText(filePath, Encoding.ASCII);
            var messageCount = Regex.Matches(content, @"(?m)^MSH\|").Count;
            var fileSize = new FileInfo(filePath).Length;

            return new Dictionary<string, object>
            {
                ["Success"] = true,
                ["MessageCount"] = messageCount,
                ["FileSize"] = fileSize,
                ["Content"] = content
            };
        }
        catch (Exception ex)
        {
            return new Dictionary<string, object>
            {
                ["Success"] = false,
                ["Error"] = ex.Message
            };
        }
    }

    public string GetHl7MessagePreview(string content, int maxMessages = 3)
    {
        if (string.IsNullOrEmpty(content))
            return "";

        // Split by MSH| at start of line
        var parts = Regex.Split(content, @"(?m)^MSH\|");
        var messages = parts.Where(p => !string.IsNullOrWhiteSpace(p)).ToList();

        var sb = new StringBuilder();
        var count = Math.Min(messages.Count, maxMessages);

        for (int i = 0; i < count; i++)
        {
            var msg = messages[i];
            if (!msg.StartsWith("MSH|"))
                msg = "MSH|" + msg;

            var preview = msg.Length > 200 ? msg[..200] + "..." : msg;
            sb.AppendLine($"Message {i + 1}:");
            sb.AppendLine(preview);
            sb.AppendLine();
        }

        return sb.ToString();
    }

    public void WriteConcatenatedHl7(
        List<Dictionary<string, object>> fileInfos,
        string outputPath,
        bool showProgress = false)
    {
        using var stream = new StreamWriter(outputPath, false, Encoding.ASCII);
        bool needsNewline = false;

        foreach (var item in fileInfos)
        {
            string? content = null;

            if (item.TryGetValue("Content", out var contentObj))
                content = contentObj?.ToString();

            if (string.IsNullOrEmpty(content))
                continue;

            var trimmedContent = content.TrimEnd('\r', '\n');
            if (string.IsNullOrEmpty(trimmedContent))
                continue;

            if (needsNewline)
                stream.Write("\r\n");

            stream.Write(trimmedContent);
            needsNewline = true;
        }
    }

    public void WriteConcatenatedHl7FromPaths(string[] filePaths, string outputPath)
    {
        using var stream = new StreamWriter(outputPath, false, Encoding.ASCII);
        bool needsNewline = false;

        foreach (var filePath in filePaths)
        {
            if (!File.Exists(filePath))
                continue;

            var content = File.ReadAllText(filePath, Encoding.ASCII);
            if (string.IsNullOrEmpty(content))
                continue;

            var trimmedContent = content.TrimEnd('\r', '\n');
            if (string.IsNullOrEmpty(trimmedContent))
                continue;

            if (needsNewline)
                stream.Write("\r\n");

            stream.Write(trimmedContent);
            needsNewline = true;
        }
    }

    #endregion

    #region TXT Concatenation

    public Dictionary<string, object> GetTxtFileInfo(string filePath)
    {
        try
        {
            var content = File.ReadAllText(filePath, Encoding.UTF8);
            var lineCount = Regex.Split(content, @"\r\n|\n|\r").Length;
            var fileSize = new FileInfo(filePath).Length;

            return new Dictionary<string, object>
            {
                ["Success"] = true,
                ["LineCount"] = lineCount,
                ["FileSize"] = fileSize,
                ["Content"] = content
            };
        }
        catch (Exception ex)
        {
            return new Dictionary<string, object>
            {
                ["Success"] = false,
                ["Error"] = ex.Message
            };
        }
    }

    public string GetTxtFilePreview(string content, int maxLines = 5)
    {
        if (string.IsNullOrEmpty(content))
            return "";

        var lines = Regex.Split(content, @"\r\n|\n|\r");
        var count = Math.Min(lines.Length, maxLines);
        var sb = new StringBuilder();

        for (int i = 0; i < count; i++)
        {
            var line = lines[i];
            var displayLine = line.Length > 200 ? line[..200] + "..." : line;
            sb.AppendLine(displayLine);
        }

        return sb.ToString();
    }

    public void WriteConcatenatedTxt(
        List<Dictionary<string, object>> fileInfos,
        string outputPath)
    {
        var sb = new StringBuilder();

        foreach (var item in fileInfos)
        {
            if (!item.TryGetValue("Content", out var contentObj))
                continue;

            var content = contentObj?.ToString() ?? "";
            sb.Append(content);

            if (!content.EndsWith("\r\n") && !content.EndsWith("\n") && !content.EndsWith("\r"))
                sb.Append("\r\n\r\n");
            else
                sb.Append("\r\n");
        }

        File.WriteAllText(outputPath, sb.ToString(), Encoding.UTF8);
    }

    #endregion
}
