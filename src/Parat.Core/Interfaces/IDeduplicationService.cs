using System.Xml;
using Parat.Core.Models;

namespace Parat.Core.Interfaces;

public interface IDeduplicationService
{
    Dictionary<string, List<(int Index, XmlNode Tumor, XmlNode Patient)>> GetPatientTumorGroups(
        XmlNodeList tumors, XmlNamespaceManager nsMgr);
    string GetTumorFingerprint(XmlNode tumor, XmlNode patient, XmlNamespaceManager nsMgr);
    DeduplicationResult GetDuplicates(XmlNodeList tumors, XmlNamespaceManager nsMgr);
    DeduplicationResult GetDuplicatesByPrimaryKey(XmlNodeList tumors, XmlNamespaceManager nsMgr);
    DeduplicationResult GetDuplicatesByPathReport(XmlNodeList tumors, XmlNamespaceManager nsMgr);
    void WriteDedupedXml(XmlDocument xmlDoc, XmlNodeList tumors, HashSet<int> indicesToKeep, string outputPath);
}
