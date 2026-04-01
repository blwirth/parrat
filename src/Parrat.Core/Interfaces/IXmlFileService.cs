using System.Xml;

namespace Parrat.Core.Interfaces;

public interface IXmlFileService
{
    (XmlDocument doc, XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadNaaccrXml(string filePath);
    string GetItemValue(XmlNode tumorOrPatient, string naaccrId, XmlNamespaceManager nsMgr);
    void SetItemValue(XmlNode tumorOrPatient, string naaccrId, string value, XmlNamespaceManager nsMgr);
    XmlNode? GetPatientForTumor(XmlNode tumor);
}
