using System.Xml;

namespace Parat.Core.Interfaces;

public interface IUnifiedAssignmentService
{
    (Dictionary<int, Dictionary<string, string>> TumorAssignments,
     Dictionary<int, Dictionary<string, string>> PatientAssignments,
     List<Dictionary<string, object>> Report) GetUnifiedAssignments(
        XmlNodeList tumors, XmlNamespaceManager nsMgr, Dictionary<string, object> options);

    void WriteUnifiedAssignedXml(XmlDocument xmlDoc, XmlNodeList tumors,
        Dictionary<int, Dictionary<string, string>> tumorAssignments,
        Dictionary<int, Dictionary<string, string>> patientAssignments,
        XmlNamespaceManager nsMgr, string outputPath);

    string GetFileSuffix(Dictionary<string, object> options, List<Dictionary<string, object>> report);
}
