using System.Text.RegularExpressions;
using System.Xml;
using Parrat.Core.Interfaces;

namespace Parrat.Core.Services;

public class PidAssignmentService : IPidAssignmentService
{
    public Dictionary<int, string> GetPatientIdAssignments(XmlNodeList tumors, XmlNamespaceManager nsMgr, string mode = "sequential")
    {
        var assignments = new Dictionary<int, string>();
        var processedPatients = new HashSet<XmlNode>();
        int counter = 0;
        int startValue = mode.Equals("ReplaceZeros", StringComparison.OrdinalIgnoreCase) ? 90000001 : 1;

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
            if (patient == null) continue;

            if (processedPatients.Contains(patient))
                continue;

            processedPatients.Add(patient);

            string currentId = patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", nsMgr)?.InnerText ?? "";
            bool hasId = !string.IsNullOrWhiteSpace(currentId);

            bool shouldAssign = false;
            string idValue = "";

            if (mode.Equals("OverwriteAll", StringComparison.OrdinalIgnoreCase))
            {
                shouldAssign = true;
                counter++;
                idValue = (startValue + counter - 1).ToString("D8");
            }
            else if (mode.Equals("ReplaceZeros", StringComparison.OrdinalIgnoreCase))
            {
                if (!hasId || Regex.IsMatch(currentId, @"^0+$"))
                {
                    shouldAssign = true;
                    counter++;
                    idValue = (startValue + counter - 1).ToString("D8");
                }
            }
            else
            {
                // Default/sequential mode: only assign if patient doesn't have an ID
                if (!hasId)
                {
                    shouldAssign = true;
                    counter++;
                    idValue = counter.ToString("D8");
                }
            }

            if (shouldAssign)
            {
                // Use the tumor index i as a proxy key for the patient.
                // The interface uses int keys, so we store the first tumor index for the patient.
                assignments[i] = idValue;
            }
        }

        return assignments;
    }

    public void WritePatientIdXml(XmlDocument xmlDoc, Dictionary<int, string> assignments,
        XmlNamespaceManager nsMgr, string outputPath)
    {
        // Build a mapping from patient node -> id value
        // The assignments dict uses tumor index as key; we need to map that to the patient node.
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        var patientIdMap = new Dictionary<XmlNode, string>(ReferenceEqualityComparer.Instance);

        foreach (var kvp in assignments)
        {
            if (kvp.Key < tumors.Count)
            {
                var tumor = tumors[kvp.Key]!;
                var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
                if (patient != null && !patientIdMap.ContainsKey(patient))
                    patientIdMap[patient] = kvp.Value;
            }
        }

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

        var root = xmlDoc.DocumentElement!;
        var newRoot = newDoc.CreateElement(root.Prefix, root.LocalName, root.NamespaceURI);
        CopyAttributes(root, newRoot, newDoc);
        newDoc.AppendChild(newRoot);

        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName != "Patient")
            {
                var imported = newDoc.ImportNode(child, true);
                newRoot.AppendChild(imported);
            }
        }

        foreach (XmlNode patientNode in root.SelectNodes("./n:Patient", nsMgr)!)
        {
            var newPatient = newDoc.CreateElement(patientNode.Prefix, patientNode.LocalName, patientNode.NamespaceURI);
            CopyAttributes(patientNode, newPatient, newDoc);

            bool needsId = patientIdMap.TryGetValue(patientNode, out var patientIdValue);
            var tumorsInPatient = patientNode.SelectNodes("./n:Tumor", nsMgr)!;
            XmlNode? firstTumor = tumorsInPatient.Count > 0 ? tumorsInPatient[0] : null;
            bool patientIdAdded = false;

            foreach (XmlNode child in patientNode.ChildNodes)
            {
                if (child.LocalName == "Item")
                {
                    string idAttr = child.Attributes?["naaccrId"]?.Value ?? "";

                    if (idAttr == "patientIdNumber")
                    {
                        var imported = newDoc.ImportNode(child, true);
                        if (needsId)
                            imported.InnerText = patientIdValue!;
                        newPatient.AppendChild(imported);
                        patientIdAdded = true;
                    }
                    else
                    {
                        var imported = newDoc.ImportNode(child, true);
                        newPatient.AppendChild(imported);
                    }
                }
                else if (child.LocalName == "Tumor")
                {
                    // Before the first tumor, add patientIdNumber if needed and not already added
                    if (child == firstTumor && needsId && !patientIdAdded)
                    {
                        var item = newDoc.CreateElement("Item", root.NamespaceURI);
                        item.SetAttribute("naaccrId", "patientIdNumber");
                        item.SetAttribute("naaccrNum", "20");
                        item.InnerText = patientIdValue!;
                        newPatient.AppendChild(item);
                        patientIdAdded = true;
                    }

                    var importedTumor = newDoc.ImportNode(child, true);
                    newPatient.AppendChild(importedTumor);
                }
            }

            if (needsId && !patientIdAdded)
            {
                var item = newDoc.CreateElement("Item", root.NamespaceURI);
                item.SetAttribute("naaccrId", "patientIdNumber");
                item.SetAttribute("naaccrNum", "20");
                item.InnerText = patientIdValue!;
                newPatient.AppendChild(item);
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
