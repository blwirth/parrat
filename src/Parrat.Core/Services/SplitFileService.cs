using System.Xml;
using Parrat.Core.Interfaces;

namespace Parrat.Core.Services;

public class SplitFileService : ISplitFileService
{
    private readonly IParratLogger _logger;

    public SplitFileService() : this(NullParratLogger.Instance) { }

    public SplitFileService(IParratLogger logger)
    {
        _logger = logger;
    }

    private static readonly (char Start, char End, string Label)[][] RangeMaps = new[]
    {
        Array.Empty<(char, char, string)>(), // 0 placeholder
        Array.Empty<(char, char, string)>(), // 1 placeholder
        new[] { ('A', 'M', "A-M"), ('N', 'Z', "N-Z") },
        new[] { ('A', 'I', "A-I"), ('J', 'R', "J-R"), ('S', 'Z', "S-Z") },
        new[] { ('A', 'F', "A-F"), ('G', 'L', "G-L"), ('M', 'R', "M-R"), ('S', 'Z', "S-Z") },
        new[] { ('A', 'E', "A-E"), ('F', 'J', "F-J"), ('K', 'O', "K-O"), ('P', 'T', "P-T"), ('U', 'Z', "U-Z") }
    };

    public List<string> GetAlphabetRanges(int splitCount)
    {
        if (splitCount < 2 || splitCount > 5)
            throw new ArgumentOutOfRangeException(nameof(splitCount), "Split count must be between 2 and 5.");

        return RangeMaps[splitCount].Select(r => r.Label).ToList();
    }

    public int GetFileSplitBucket(string lastName, int splitCount)
    {
        if (splitCount < 2 || splitCount > 5)
            throw new ArgumentOutOfRangeException(nameof(splitCount));

        if (string.IsNullOrWhiteSpace(lastName))
            return splitCount - 1;

        string trimmed = lastName.Trim();
        if (string.IsNullOrEmpty(trimmed))
            return splitCount - 1;

        char firstChar = char.ToUpperInvariant(trimmed[0]);

        if (firstChar < 'A' || firstChar > 'Z')
            return splitCount - 1;

        var ranges = RangeMaps[splitCount];
        for (int i = 0; i < ranges.Length; i++)
        {
            if (firstChar >= ranges[i].Start && firstChar <= ranges[i].End)
                return i;
        }

        return splitCount - 1;
    }

    public Dictionary<string, object> GetXmlFileSplitInfo(string filePath)
    {
        try
        {
            var xml = new XmlDocument();
            xml.XmlResolver = null;
            xml.Load(filePath);

            var root = xml.DocumentElement;
            if (root == null || root.LocalName != "NaaccrData")
            {
                return new Dictionary<string, object>
                {
                    ["Success"] = false,
                    ["Error"] = "Not a valid NAACCR XML file (root element is not NaaccrData)"
                };
            }

            string xmlns = root.NamespaceURI;
            var nsMgr = new XmlNamespaceManager(xml.NameTable);
            nsMgr.AddNamespace("n", xmlns);

            // Get header info
            string xmlVersion = "1.0";
            foreach (XmlNode child in xml.ChildNodes)
            {
                if (child is XmlDeclaration decl)
                {
                    xmlVersion = decl.Version;
                    break;
                }
            }

            var xmlInfo = new Dictionary<string, string>
            {
                ["XmlVersion"] = xmlVersion,
                ["Xmlns"] = xmlns,
                ["BaseDictionaryUri"] = root.GetAttribute("baseDictionaryUri"),
                ["RecordType"] = root.GetAttribute("recordType"),
                ["SpecificationVersion"] = root.GetAttribute("specificationVersion")
            };

            var patients = xml.SelectNodes("//n:Patient", nsMgr)!;
            var patientData = new List<Dictionary<string, object>>();
            int totalTumors = 0;

            foreach (XmlNode patient in patients)
            {
                var nameLastNode = patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", nsMgr);
                string nameLast = nameLastNode?.InnerText ?? "";

                var tumors = patient.SelectNodes("./n:Tumor", nsMgr);
                int tumorCount = tumors?.Count ?? 0;
                totalTumors += tumorCount;

                patientData.Add(new Dictionary<string, object>
                {
                    ["LastName"] = nameLast,
                    ["TumorCount"] = tumorCount,
                    ["PatientNode"] = patient
                });
            }

            return new Dictionary<string, object>
            {
                ["Success"] = true,
                ["TotalPatients"] = patients.Count,
                ["TotalTumors"] = totalTumors,
                ["PatientData"] = patientData,
                ["XmlInfo"] = xmlInfo,
                ["XmlDoc"] = xml,
                ["NsMgr"] = nsMgr
            };
        }
        catch (Exception ex)
        {
            _logger.LogError($"Error scanning XML file for split: {filePath}", "SPLIT_XML_SCAN", ex);
            return new Dictionary<string, object>
            {
                ["Success"] = false,
                ["Error"] = $"Error scanning XML file: {ex.Message}"
            };
        }
    }

    public Dictionary<string, object> GetHl7FileSplitInfo(string filePath)
    {
        try
        {
            string content = File.ReadAllText(filePath);

            if (string.IsNullOrWhiteSpace(content))
            {
                return new Dictionary<string, object>
                {
                    ["Success"] = false,
                    ["Error"] = "File is empty"
                };
            }

            // Normalize line endings
            content = content.Replace("\r\n", "\n").Replace("\r", "\n");

            var messageData = new List<Dictionary<string, object>>();
            var currentMessageLines = new List<string>();

            foreach (var line in content.Split('\n'))
            {
                string trimmedLine = line.Trim();
                if (string.IsNullOrEmpty(trimmedLine)) continue;

                if (trimmedLine.StartsWith("MSH|"))
                {
                    if (currentMessageLines.Count > 0)
                    {
                        string msgText = string.Join("\n", currentMessageLines);
                        string lastName = GetHl7LastName(msgText);
                        messageData.Add(new Dictionary<string, object>
                        {
                            ["LastName"] = lastName,
                            ["MessageText"] = msgText
                        });
                        currentMessageLines.Clear();
                    }
                    currentMessageLines.Add(trimmedLine);
                }
                else if (currentMessageLines.Count > 0)
                {
                    currentMessageLines.Add(trimmedLine);
                }
            }

            // Last message
            if (currentMessageLines.Count > 0)
            {
                string msgText = string.Join("\n", currentMessageLines);
                string lastName = GetHl7LastName(msgText);
                messageData.Add(new Dictionary<string, object>
                {
                    ["LastName"] = lastName,
                    ["MessageText"] = msgText
                });
            }

            return new Dictionary<string, object>
            {
                ["Success"] = true,
                ["TotalMessages"] = messageData.Count,
                ["MessageData"] = messageData
            };
        }
        catch (Exception ex)
        {
            _logger.LogError($"Error scanning HL7 file for split: {filePath}", "SPLIT_HL7_SCAN", ex);
            return new Dictionary<string, object>
            {
                ["Success"] = false,
                ["Error"] = $"Error scanning HL7 file: {ex.Message}"
            };
        }
    }

    public Dictionary<string, int> GetSplitDistribution(List<string> lastNames, int splitCount)
    {
        var ranges = RangeMaps[splitCount];
        var distribution = new Dictionary<string, int>();

        foreach (var range in ranges)
            distribution[range.Label] = 0;

        foreach (var name in lastNames)
        {
            int bucket = GetFileSplitBucket(name, splitCount);
            distribution[ranges[bucket].Label]++;
        }

        return distribution;
    }

    public void SplitXmlFile(Dictionary<string, object> scanResult, string filePath, int splitCount, string outputDirectory)
    {
        var ranges = RangeMaps[splitCount];
        var xmlInfo = (Dictionary<string, string>)scanResult["XmlInfo"];

        string baseName = Path.GetFileNameWithoutExtension(filePath);
        string extension = Path.GetExtension(filePath);

        // Create output documents for each bucket
        var outputDocs = new List<(XmlDocument Doc, XmlElement Root, string Path, int PatientCount, int TumorCount)>();

        for (int i = 0; i < splitCount; i++)
        {
            string outputFileName = $"{baseName}_{ranges[i].Label}{extension}";
            string outputPath = System.IO.Path.Combine(outputDirectory, outputFileName);

            var newDoc = new XmlDocument();
            newDoc.XmlResolver = null;

            var decl = newDoc.CreateXmlDeclaration(xmlInfo["XmlVersion"], "UTF-8", null);
            newDoc.AppendChild(decl);

            var newRoot = newDoc.CreateElement("NaaccrData", xmlInfo["Xmlns"]);
            newRoot.SetAttribute("baseDictionaryUri", xmlInfo["BaseDictionaryUri"]);
            newRoot.SetAttribute("recordType", xmlInfo["RecordType"]);
            newRoot.SetAttribute("timeGenerated", DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffK"));
            if (!string.IsNullOrEmpty(xmlInfo["SpecificationVersion"]))
                newRoot.SetAttribute("specificationVersion", xmlInfo["SpecificationVersion"]);
            newDoc.AppendChild(newRoot);

            outputDocs.Add((newDoc, newRoot, outputPath, 0, 0));
        }

        // Distribute patients
        var patientData = (List<Dictionary<string, object>>)scanResult["PatientData"];
        foreach (var pd in patientData)
        {
            string lastName = (string)pd["LastName"];
            int tumorCount = (int)pd["TumorCount"];
            var patientNode = (XmlNode)pd["PatientNode"];
            int bucket = GetFileSplitBucket(lastName, splitCount);

            var target = outputDocs[bucket];
            var imported = target.Doc.ImportNode(patientNode, true);
            target.Root.AppendChild(imported);

            outputDocs[bucket] = (target.Doc, target.Root, target.Path,
                target.PatientCount + 1, target.TumorCount + tumorCount);
        }

        // Write output files
        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace,
            Encoding = System.Text.Encoding.UTF8
        };

        foreach (var (doc, _, path, _, _) in outputDocs)
        {
            using var writer = XmlWriter.Create(path, settings);
            doc.Save(writer);
        }
    }

    public void SplitHl7File(Dictionary<string, object> scanResult, string filePath, int splitCount, string outputDirectory)
    {
        var ranges = RangeMaps[splitCount];
        string baseName = Path.GetFileNameWithoutExtension(filePath);
        string extension = Path.GetExtension(filePath);

        var buckets = new List<List<string>>();
        for (int i = 0; i < splitCount; i++)
            buckets.Add(new List<string>());

        var messageData = (List<Dictionary<string, object>>)scanResult["MessageData"];
        foreach (var md in messageData)
        {
            string lastName = (string)md["LastName"];
            string messageText = (string)md["MessageText"];
            int bucket = GetFileSplitBucket(lastName, splitCount);
            buckets[bucket].Add(messageText);
        }

        for (int i = 0; i < splitCount; i++)
        {
            string outputFileName = $"{baseName}_{ranges[i].Label}{extension}";
            string outputPath = System.IO.Path.Combine(outputDirectory, outputFileName);
            string content = string.Join("\r\n\r\n", buckets[i]);
            File.WriteAllText(outputPath, content, System.Text.Encoding.ASCII);
        }
    }

    private static string GetHl7LastName(string messageText)
    {
        if (string.IsNullOrWhiteSpace(messageText))
            return "";

        foreach (var line in messageText.Split('\n'))
        {
            string trimmed = line.Trim();
            if (trimmed.StartsWith("PID|"))
            {
                var fields = trimmed.Split('|');
                if (fields.Length > 5)
                {
                    string nameField = fields[5];
                    var components = nameField.Split('^');
                    if (components.Length > 0)
                        return components[0];
                }
                break;
            }
        }

        return "";
    }
}
