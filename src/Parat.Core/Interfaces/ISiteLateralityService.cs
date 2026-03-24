using System.Xml;
using Parat.Core.Models;

namespace Parat.Core.Interfaces;

public interface ISiteLateralityService
{
    List<TopographyEntry> ReadTopographyJson(string path);
    Dictionary<string, bool> ReadLateralityJson(string path);
    List<SiteCodingRule> ReadSiteCodingRules(string path);
    SiteCodingTestResult TestSiteCodingRule(SiteCodingRule rule, string textLow, List<TopographyEntry>? topoMap = null);
    SiteAssignment GetBestCode(List<TopographyEntry> map, string textLow);
    string? GetLaterality(string textLow);
    List<SiteLateralityResult> GetMissingFields(XmlNodeList tumors, XmlNamespaceManager nsMgr);
    void WriteAssignedXml(XmlDocument xmlDoc, XmlNodeList tumors, Dictionary<int, SiteAssignment> assignments,
        XmlNamespaceManager nsMgr, string outputPath);
}
