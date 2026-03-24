using System.Xml;
using Parat.Core.Interfaces;
using Parat.Core.Models;

namespace Parat.Core.Services;

public class DiffService : IDiffService
{
    private readonly XmlNodeList? _tumors;
    private readonly XmlNamespaceManager? _nsMgr;
    private readonly List<Hl7Message>? _hl7Messages;

    public DiffService()
    {
    }

    public DiffService(XmlNodeList? tumors, XmlNamespaceManager? nsMgr, List<Hl7Message>? hl7Messages = null)
    {
        _tumors = tumors;
        _nsMgr = nsMgr;
        _hl7Messages = hl7Messages;
    }

    public List<DiffLine> GetDiffLines(string[] linesA, string[] linesB)
    {
        linesA ??= Array.Empty<string>();
        linesB ??= Array.Empty<string>();

        int lenA = linesA.Length;
        int lenB = linesB.Length;

        // LCS dynamic programming matrix
        var lcs = new int[lenA + 1, lenB + 1];

        for (int i = 1; i <= lenA; i++)
        {
            for (int j = 1; j <= lenB; j++)
            {
                if (linesA[i - 1] == linesB[j - 1])
                    lcs[i, j] = lcs[i - 1, j - 1] + 1;
                else
                    lcs[i, j] = Math.Max(lcs[i - 1, j], lcs[i, j - 1]);
            }
        }

        // Backtrack to build diff
        var diffLines = new List<DiffLine>();
        int ii = lenA, jj = lenB;

        while (ii > 0 || jj > 0)
        {
            if (ii > 0 && jj > 0 && linesA[ii - 1] == linesB[jj - 1])
            {
                diffLines.Insert(0, new DiffLine
                {
                    LineNumA = ii,
                    LineNumB = jj,
                    Status = DiffStatus.Unchanged,
                    ContentA = linesA[ii - 1],
                    ContentB = linesB[jj - 1]
                });
                ii--;
                jj--;
            }
            else if (jj > 0 && (ii == 0 || lcs[ii, jj - 1] >= lcs[ii - 1, jj]))
            {
                diffLines.Insert(0, new DiffLine
                {
                    LineNumA = null,
                    LineNumB = jj,
                    Status = DiffStatus.Added,
                    ContentA = "",
                    ContentB = linesB[jj - 1]
                });
                jj--;
            }
            else if (ii > 0)
            {
                diffLines.Insert(0, new DiffLine
                {
                    LineNumA = ii,
                    LineNumB = null,
                    Status = DiffStatus.Deleted,
                    ContentA = linesA[ii - 1],
                    ContentB = ""
                });
                ii--;
            }
        }

        return diffLines;
    }

    public string GetTumorLabel(int index)
    {
        if (_tumors == null || _tumors.Count == 0)
            throw new InvalidOperationException("No tumors loaded.");
        if (index < 0 || index >= _tumors.Count)
            throw new ArgumentOutOfRangeException(nameof(index), $"Index {index} is out of range (0..{_tumors.Count - 1}).");

        var tumor = _tumors[index]!;
        var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", _nsMgr);

        string nameLast = "";
        string nameFirst = "";
        string dxDate = "";
        string pathReportNumber1 = "";

        if (patient != null)
        {
            nameLast = patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", _nsMgr)?.InnerText ?? "";
            nameFirst = patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", _nsMgr)?.InnerText ?? "";
        }

        dxDate = tumor.SelectSingleNode("./n:Item[@naaccrId='dateOfDiagnosis']", _nsMgr)?.InnerText ?? "";
        pathReportNumber1 = tumor.SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", _nsMgr)?.InnerText ?? "";

        return $"Idx {index + 1} - {nameLast}, {nameFirst} - Dx {dxDate} - Path Number {pathReportNumber1}";
    }

    public string[] GetFormattedTumorXml(int index)
    {
        if (_tumors == null || _nsMgr == null)
            throw new InvalidOperationException("No tumors loaded.");

        var tumor = _tumors[index]!;
        var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", _nsMgr);
        var nodeToFormat = patient ?? tumor;

        var settings = new XmlWriterSettings
        {
            Indent = true,
            IndentChars = "  ",
            NewLineChars = "\n",
            OmitXmlDeclaration = true
        };

        using var sw = new System.IO.StringWriter();
        using (var xw = XmlWriter.Create(sw, settings))
        {
            nodeToFormat.WriteTo(xw);
        }

        string formatted = sw.ToString();
        return formatted.Split('\n').Select(l => l.TrimEnd('\r', ' ')).ToArray();
    }

    public string GetHl7MessageLabel(int index)
    {
        if (_hl7Messages == null || _hl7Messages.Count == 0)
            throw new InvalidOperationException("No HL7 messages loaded.");
        if (index < 0 || index >= _hl7Messages.Count)
            throw new ArgumentOutOfRangeException(nameof(index), $"Index {index} is out of range (0..{_hl7Messages.Count - 1}).");

        var message = _hl7Messages[index];
        return $"Idx {index + 1} - {message.PatientName} ({message.MessageType}) - ID: {message.PatientId}";
    }

    public string[] GetHl7MessageLines(int index)
    {
        if (_hl7Messages == null)
            throw new InvalidOperationException("No HL7 messages loaded.");

        var message = _hl7Messages[index];
        var lines = new List<string>();

        // Standard HL7 segment order
        string[] segmentOrder = { "MSH", "PID", "PV1", "ORC", "OBR", "OBX", "NTE", "ZPD" };

        foreach (var segType in segmentOrder)
        {
            if (message.Segments.TryGetValue(segType, out var segments))
            {
                lines.AddRange(segments);
            }
        }

        // Add remaining segment types not in standard order
        foreach (var kvp in message.Segments)
        {
            if (!segmentOrder.Contains(kvp.Key))
            {
                lines.AddRange(kvp.Value);
            }
        }

        return lines.ToArray();
    }
}
