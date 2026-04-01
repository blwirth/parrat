using System.Text.RegularExpressions;
using System.Xml;
using Parrat.Core.Interfaces;

namespace Parrat.Core.Services;

public class FacilityAssignmentService : IFacilityAssignmentService
{
    public string? GetFacilityFromFilename(string filePath)
    {
        string fileName = Path.GetFileNameWithoutExtension(filePath);

        // Look for 7-digit number in filename
        var match = Regex.Match(fileName, @"(?<![0-9])\d{7}(?![0-9])");

        if (match.Success)
        {
            // Left-pad to 10 digits
            return match.Value.PadLeft(10, '0');
        }

        return null;
    }

    public Dictionary<int, string> GetFacilityAssignments(XmlNodeList tumors, XmlNamespaceManager nsMgr,
        string facilityNumber, bool overwriteExisting = false)
    {
        var assignments = new Dictionary<int, string>();

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;
            string currentFacility = (tumor.SelectSingleNode("./n:Item[@naaccrId='reportingFacility']", nsMgr)?.InnerText ?? "").Trim();

            bool needsUpdate = overwriteExisting ||
                               string.IsNullOrWhiteSpace(currentFacility) ||
                               Regex.IsMatch(currentFacility, @"^0+$");

            if (needsUpdate)
                assignments[i] = facilityNumber;
        }

        return assignments;
    }

    public void WriteFacilityAssignedXml(XmlDocument xmlDoc, XmlNodeList tumors, Dictionary<int, string> assignments,
        XmlNamespaceManager nsMgr, string outputPath)
    {
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

        // Copy non-Patient children
        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName != "Patient")
            {
                var imported = newDoc.ImportNode(child, true);
                newRoot.AppendChild(imported);
            }
        }

        // Process each Patient
        foreach (XmlNode patientNode in root.SelectNodes("./n:Patient", nsMgr)!)
        {
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

            var tumorsInPatient = patientNode.SelectNodes("./n:Tumor", nsMgr)!;
            foreach (XmlNode tumor in tumorsInPatient)
            {
                int tumorIndex = FindTumorIndex(tumors, tumor);
                var newTumor = newDoc.ImportNode(tumor, true);

                if (tumorIndex >= 0 && assignments.TryGetValue(tumorIndex, out var facilityNum))
                {
                    var facilityNode = newTumor.SelectSingleNode("./n:Item[@naaccrId='reportingFacility']", nsMgr);
                    if (facilityNode != null)
                    {
                        facilityNode.InnerText = facilityNum;
                    }
                    else
                    {
                        var itemNode = newDoc.CreateElement("Item", root.NamespaceURI);
                        var attr = newDoc.CreateAttribute("naaccrId");
                        attr.Value = "reportingFacility";
                        itemNode.Attributes!.Append(attr);
                        itemNode.InnerText = facilityNum;
                        newTumor.AppendChild(itemNode);
                    }
                }

                newPatient.AppendChild(newTumor);
            }

            newRoot.AppendChild(newPatient);
        }

        WriteXmlDocument(newDoc, outputPath);
    }

    private static int FindTumorIndex(XmlNodeList tumors, XmlNode tumor)
    {
        for (int i = 0; i < tumors.Count; i++)
        {
            if (tumors[i] == tumor)
                return i;
        }
        return -1;
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

    private static void WriteXmlDocument(XmlDocument doc, string outputPath)
    {
        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace
        };

        using var writer = XmlWriter.Create(outputPath, settings);
        doc.Save(writer);
    }
}
