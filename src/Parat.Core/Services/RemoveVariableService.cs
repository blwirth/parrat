using System.Xml;
using Parat.Core.Interfaces;

namespace Parat.Core.Services;

public class RemoveVariableService : IRemoveVariableService
{
    public List<string> GetUniqueNaaccrIds(XmlDocument xmlDoc, XmlNamespaceManager nsMgr)
    {
        var idSet = new HashSet<string>();

        var root = xmlDoc.DocumentElement;
        if (root == null) return new List<string>();

        // NaaccrData-level Items
        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName == "Item")
            {
                string? naaccrId = child.Attributes?["naaccrId"]?.Value;
                if (!string.IsNullOrEmpty(naaccrId))
                    idSet.Add(naaccrId);
            }
        }

        // Patient and Tumor level Items
        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName != "Patient") continue;

            foreach (XmlNode pChild in child.ChildNodes)
            {
                if (pChild.LocalName == "Item")
                {
                    string? naaccrId = pChild.Attributes?["naaccrId"]?.Value;
                    if (!string.IsNullOrEmpty(naaccrId))
                        idSet.Add(naaccrId);
                }
                else if (pChild.LocalName == "Tumor")
                {
                    foreach (XmlNode tChild in pChild.ChildNodes)
                    {
                        if (tChild.LocalName == "Item")
                        {
                            string? naaccrId = tChild.Attributes?["naaccrId"]?.Value;
                            if (!string.IsNullOrEmpty(naaccrId))
                                idSet.Add(naaccrId);
                        }
                    }
                }
            }
        }

        var result = idSet.ToList();
        result.Sort(StringComparer.OrdinalIgnoreCase);
        return result;
    }

    public void RemoveXmlVariable(XmlDocument xmlDoc, string[] naaccrIds, string outputPath)
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

        // Deep clone the document element
        var imported = newDoc.ImportNode(xmlDoc.DocumentElement!, true);
        newDoc.AppendChild(imported);

        // Set up namespace manager on the new document
        var nsMgr = new XmlNamespaceManager(newDoc.NameTable);
        string ns = newDoc.DocumentElement!.NamespaceURI;
        if (!string.IsNullOrEmpty(ns))
            nsMgr.AddNamespace("n", ns);

        // Find and remove all Item elements with matching naaccrIds
        foreach (string id in naaccrIds)
        {
            var nodes = newDoc.SelectNodes($"//n:Item[@naaccrId='{id}']", nsMgr);
            if (nodes != null)
            {
                // Collect into list first to avoid modifying during iteration
                var nodeList = new List<XmlNode>();
                foreach (XmlNode node in nodes)
                    nodeList.Add(node);

                foreach (var node in nodeList)
                    node.ParentNode?.RemoveChild(node);
            }
        }

        // Save with formatting
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
}
