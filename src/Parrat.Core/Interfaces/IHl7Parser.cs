using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IHl7Parser
{
    string GetField(string segment, int fieldIndex);
    string GetComponent(string field, int componentIndex);
    List<Hl7Message> Parse(string content);

    /// <summary>
    /// Parses messages from a sequence of lines. Lets callers stream a file
    /// rather than buffering its whole text, which matters for large files.
    /// </summary>
    List<Hl7Message> ParseLines(IEnumerable<string> lines);
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
