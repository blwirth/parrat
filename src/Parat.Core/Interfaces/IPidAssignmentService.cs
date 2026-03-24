using System.Xml;

namespace Parat.Core.Interfaces;

public interface IPidAssignmentService
{
    Dictionary<int, string> GetPatientIdAssignments(XmlNodeList tumors, XmlNamespaceManager nsMgr, string mode = "sequential");
    void WritePatientIdXml(XmlDocument xmlDoc, Dictionary<int, string> assignments, XmlNamespaceManager nsMgr, string outputPath);
}
