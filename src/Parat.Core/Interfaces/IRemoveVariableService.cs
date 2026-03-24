using System.Xml;

namespace Parat.Core.Interfaces;

public interface IRemoveVariableService
{
    List<string> GetUniqueNaaccrIds(XmlDocument xmlDoc, XmlNamespaceManager nsMgr);
    void RemoveXmlVariable(XmlDocument xmlDoc, string[] naaccrIds, string outputPath);
}
