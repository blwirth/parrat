using System.Xml;

namespace Parat.Core.Interfaces;

public interface IFacilityAssignmentService
{
    string? GetFacilityFromFilename(string filePath);
    Dictionary<int, string> GetFacilityAssignments(XmlNodeList tumors, XmlNamespaceManager nsMgr,
        string facilityNumber, bool overwriteExisting = false);
    void WriteFacilityAssignedXml(XmlDocument xmlDoc, XmlNodeList tumors, Dictionary<int, string> assignments,
        XmlNamespaceManager nsMgr, string outputPath);
}
