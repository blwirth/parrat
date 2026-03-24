using Parat.Core.Models;

namespace Parat.Core.Interfaces;

public interface IHl7Parser
{
    string GetField(string segment, int fieldIndex);
    string GetComponent(string field, int componentIndex);
    List<Hl7Message> Parse(string content);
    MshSegment ParseMsh(string mshSegment);
    PidSegment ParsePid(string pidSegment);
    ObrSegment ParseObr(string obrSegment);
    List<ObxSegment> ParseObx(List<string> obxSegments);
    string FormatDateTime(string hl7DateTime);
    string GetObxTextContent(List<string> obxSegments);
    string GetObx3Component1(string obxSegment);
    List<string> SelectObxSegments(List<string> obxSegments, List<string> skipCodes);
    string GetFilteredObxTextContent(List<string> obxSegments, List<string> skipCodes);
}
