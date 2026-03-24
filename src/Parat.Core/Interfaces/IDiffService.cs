using Parat.Core.Models;

namespace Parat.Core.Interfaces;

public interface IDiffService
{
    List<DiffLine> GetDiffLines(string[] linesA, string[] linesB);
    string GetTumorLabel(int index);
    string[] GetFormattedTumorXml(int index);
    string GetHl7MessageLabel(int index);
    string[] GetHl7MessageLines(int index);
}
