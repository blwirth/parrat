using System.Xml;
using Parat.Core.Interfaces;

namespace Parat.Core.Services;

/// <summary>
/// Loads and manipulates NAACCR XML files with namespace handling.
/// Ported from XML loading logic in button-handlers/btnOpen.ps1 and lib/syntax-helpers.ps1.
/// </summary>
public class XmlFileService : IXmlFileService
{
    private const string NaaccrNamespace = "http://naaccr.org/naaccrxml";
    private const string NsPrefix = "n";

    public (XmlDocument doc, XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadNaaccrXml(string filePath)
    {
        var xml = new XmlDocument();
        xml.XmlResolver = null;
        xml.Load(filePath);

        var nsUri = xml.DocumentElement?.NamespaceURI ?? NaaccrNamespace;
        var nsMgr = new XmlNamespaceManager(xml.NameTable);
        nsMgr.AddNamespace(NsPrefix, nsUri);

        var tumors = xml.SelectNodes($"//{NsPrefix}:Tumor", nsMgr)!;

        return (xml, tumors, nsMgr);
    }

    public string GetItemValue(XmlNode tumorOrPatient, string naaccrId, XmlNamespaceManager nsMgr)
    {
        var node = tumorOrPatient.SelectSingleNode($"./n:Item[@naaccrId='{naaccrId}']", nsMgr);
        return node?.InnerText ?? "";
    }

    public void SetItemValue(XmlNode tumorOrPatient, string naaccrId, string value, XmlNamespaceManager nsMgr)
    {
        var node = tumorOrPatient.SelectSingleNode($"./n:Item[@naaccrId='{naaccrId}']", nsMgr);
        if (node != null)
        {
            node.InnerText = value;
        }
        else
        {
            // Create new Item element
            var doc = tumorOrPatient.OwnerDocument!;
            var nsUri = nsMgr.LookupNamespace(NsPrefix) ?? NaaccrNamespace;
            var newItem = doc.CreateElement("Item", nsUri);
            newItem.SetAttribute("naaccrId", naaccrId);
            newItem.InnerText = value;

            if (tumorOrPatient.HasChildNodes)
                tumorOrPatient.InsertBefore(newItem, tumorOrPatient.FirstChild);
            else
                tumorOrPatient.AppendChild(newItem);
        }
    }

    public XmlNode? GetPatientForTumor(XmlNode tumor)
    {
        var parent = tumor.ParentNode;
        while (parent != null && parent.LocalName != "Patient")
        {
            parent = parent.ParentNode;
        }
        return parent;
    }
}
