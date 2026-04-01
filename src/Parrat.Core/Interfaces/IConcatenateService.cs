namespace Parrat.Core.Interfaces;

public interface IConcatenateService
{
    // XML concatenation
    Dictionary<string, object> GetXmlHeaderInfo(string filePath);
    List<string> GetDuplicatePatientIds(List<Dictionary<string, object>> headerInfos);
    (bool Valid, string? Error) TestXmlHeaderAgainstReference(Dictionary<string, object> newInfo, Dictionary<string, object> referenceInfo);
    void WriteConcatenatedXml(List<Dictionary<string, object>> headerInfos, Dictionary<string, object> referenceInfo,
        string outputPath, bool showProgress = false, bool reassignPatientIds = false);
    void WriteConcatenatedXmlFromPaths(string[] filePaths, string outputPath);

    // HL7 concatenation
    Dictionary<string, object> GetHl7FileInfo(string filePath);
    string GetHl7MessagePreview(string content, int maxMessages = 3);
    void WriteConcatenatedHl7(List<Dictionary<string, object>> fileInfos, string outputPath, bool showProgress = false);
    void WriteConcatenatedHl7FromPaths(string[] filePaths, string outputPath);

    // TXT concatenation
    Dictionary<string, object> GetTxtFileInfo(string filePath);
    string GetTxtFilePreview(string content, int maxLines = 5);
    void WriteConcatenatedTxt(List<Dictionary<string, object>> fileInfos, string outputPath);
}
