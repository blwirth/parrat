namespace Parat.Core.Interfaces;

public interface ISplitFileService
{
    List<string> GetAlphabetRanges(int splitCount);
    int GetFileSplitBucket(string lastName, int splitCount);
    Dictionary<string, object> GetXmlFileSplitInfo(string filePath);
    Dictionary<string, object> GetHl7FileSplitInfo(string filePath);
    Dictionary<string, int> GetSplitDistribution(List<string> lastNames, int splitCount);
    void SplitXmlFile(Dictionary<string, object> scanResult, string filePath, int splitCount, string outputDirectory);
    void SplitHl7File(Dictionary<string, object> scanResult, string filePath, int splitCount, string outputDirectory);
}
