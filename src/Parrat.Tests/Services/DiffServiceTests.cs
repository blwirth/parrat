using System.Xml;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class DiffServiceTests
{
    private readonly DiffService _service = new();

    [Fact]
    public void GetDiffLines_IdenticalLines_AllUnchanged()
    {
        string[] linesA = { "line1", "line2", "line3" };
        string[] linesB = { "line1", "line2", "line3" };

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(3, result.Count);
        Assert.All(result, line => Assert.Equal(DiffStatus.Unchanged, line.Status));
    }

    [Fact]
    public void GetDiffLines_DetectsAddedLines()
    {
        string[] linesA = { "line1", "line3" };
        string[] linesB = { "line1", "line2", "line3" };

        var result = _service.GetDiffLines(linesA, linesB);

        var added = result.Where(r => r.Status == DiffStatus.Added).ToList();
        Assert.Single(added);
        Assert.Equal("line2", added[0].ContentB);
    }

    [Fact]
    public void GetDiffLines_DetectsDeletedLines()
    {
        string[] linesA = { "line1", "line2", "line3" };
        string[] linesB = { "line1", "line3" };

        var result = _service.GetDiffLines(linesA, linesB);

        var deleted = result.Where(r => r.Status == DiffStatus.Deleted).ToList();
        Assert.Single(deleted);
        Assert.Equal("line2", deleted[0].ContentA);
    }

    [Fact]
    public void GetDiffLines_CompletelyDifferentContent()
    {
        string[] linesA = { "alpha", "beta" };
        string[] linesB = { "gamma", "delta" };

        var result = _service.GetDiffLines(linesA, linesB);

        var deleted = result.Where(r => r.Status == DiffStatus.Deleted).ToList();
        var added = result.Where(r => r.Status == DiffStatus.Added).ToList();

        Assert.Equal(2, deleted.Count);
        Assert.Equal(2, added.Count);
    }

    [Fact]
    public void GetDiffLines_EmptyA_AllAdditions()
    {
        string[] linesA = Array.Empty<string>();
        string[] linesB = { "new1", "new2" };

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(2, result.Count);
        Assert.All(result, line => Assert.Equal(DiffStatus.Added, line.Status));
    }

    [Fact]
    public void GetDiffLines_EmptyB_AllDeletions()
    {
        string[] linesA = { "old1", "old2" };
        string[] linesB = Array.Empty<string>();

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(2, result.Count);
        Assert.All(result, line => Assert.Equal(DiffStatus.Deleted, line.Status));
    }

    [Fact]
    public void GetDiffLines_BothEmpty_ReturnsEmpty()
    {
        var result = _service.GetDiffLines(Array.Empty<string>(), Array.Empty<string>());
        Assert.Empty(result);
    }

    [Fact]
    public void GetDiffLines_NullInputs_TreatedAsEmpty()
    {
        var result = _service.GetDiffLines(null!, null!);
        Assert.Empty(result);
    }

    [Fact]
    public void GetDiffLines_CorrectLineNumbersForUnchanged()
    {
        string[] linesA = { "same1", "same2" };
        string[] linesB = { "same1", "same2" };

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(1, result[0].LineNumA);
        Assert.Equal(1, result[0].LineNumB);
        Assert.Equal(2, result[1].LineNumA);
        Assert.Equal(2, result[1].LineNumB);
    }

    [Fact]
    public void GetDiffLines_AddedLines_LineNumAIsNull()
    {
        string[] linesA = { "same" };
        string[] linesB = { "same", "added" };

        var result = _service.GetDiffLines(linesA, linesB);

        var added = result.First(r => r.Status == DiffStatus.Added);
        Assert.Null(added.LineNumA);
        Assert.Equal(2, added.LineNumB);
    }

    [Fact]
    public void GetDiffLines_DeletedLines_LineNumBIsNull()
    {
        string[] linesA = { "same", "deleted" };
        string[] linesB = { "same" };

        var result = _service.GetDiffLines(linesA, linesB);

        var deleted = result.First(r => r.Status == DiffStatus.Deleted);
        Assert.Equal(2, deleted.LineNumA);
        Assert.Null(deleted.LineNumB);
    }

    [Fact]
    public void GetDiffLines_InterleavedChanges()
    {
        string[] linesA = { "common", "only-in-a", "also-common" };
        string[] linesB = { "common", "only-in-b", "also-common" };

        var result = _service.GetDiffLines(linesA, linesB);

        var unchanged = result.Where(r => r.Status == DiffStatus.Unchanged).ToList();
        Assert.Equal(2, unchanged.Count);
        Assert.Equal("common", unchanged[0].ContentA);
        Assert.Equal("also-common", unchanged[1].ContentA);
    }

    [Fact]
    public void GetDiffLines_SingleLineInputs()
    {
        var result = _service.GetDiffLines(new[] { "a" }, new[] { "b" });

        Assert.Equal(2, result.Count);
        Assert.Single(result.Where(r => r.Status == DiffStatus.Deleted));
        Assert.Single(result.Where(r => r.Status == DiffStatus.Added));
    }

    // =====================================================================
    //  GetTumorLabel
    // =====================================================================

    [Fact]
    public void GetTumorLabel_ReturnsFormattedLabel()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Smith",
            NameFirst = "John",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData
                {
                    DateOfDiagnosis = "20240101",
                    PathReportNumber1 = "P001"
                }
            }
        });

        var (tumors, nsMgr) = LoadTumors(xml);
        var service = new DiffService(tumors, nsMgr);

        var label = service.GetTumorLabel(0);
        Assert.Contains("Smith", label);
        Assert.Contains("John", label);
        Assert.Contains("20240101", label);
        Assert.Contains("P001", label);
        Assert.Contains("Idx 1", label);
    }

    [Fact]
    public void GetTumorLabel_ThrowsForInvalidIndex()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);
        var service = new DiffService(tumors, nsMgr);

        Assert.Throws<ArgumentOutOfRangeException>(() => service.GetTumorLabel(5));
    }

    [Fact]
    public void GetTumorLabel_ThrowsWhenNoTumorsLoaded()
    {
        var service = new DiffService();
        Assert.Throws<InvalidOperationException>(() => service.GetTumorLabel(0));
    }

    // =====================================================================
    //  GetFormattedTumorXml
    // =====================================================================

    [Fact]
    public void GetFormattedTumorXml_ReturnsIndentedXmlLines()
    {
        var xml = NaaccrXmlTestHelper.BuildSimpleNaaccrXml();
        var (tumors, nsMgr) = LoadTumors(xml);
        var service = new DiffService(tumors, nsMgr);

        var lines = service.GetFormattedTumorXml(0);
        Assert.True(lines.Length > 1, "Should have multiple formatted lines");
        Assert.Contains(lines, l => l.Contains("Patient"));
    }

    // =====================================================================
    //  GetHl7MessageLabel
    // =====================================================================

    [Fact]
    public void GetHl7MessageLabel_ReturnsFormattedLabel()
    {
        var messages = new List<Hl7Message>
        {
            new()
            {
                PatientName = "Smith, John",
                MessageType = "ORU^R01",
                PatientId = "12345"
            }
        };
        var service = new DiffService(null, null, messages);

        var label = service.GetHl7MessageLabel(0);
        Assert.Contains("Smith, John", label);
        Assert.Contains("ORU^R01", label);
        Assert.Contains("12345", label);
        Assert.Contains("Idx 1", label);
    }

    [Fact]
    public void GetHl7MessageLabel_ThrowsWhenNoMessagesLoaded()
    {
        var service = new DiffService();
        Assert.Throws<InvalidOperationException>(() => service.GetHl7MessageLabel(0));
    }

    // =====================================================================
    //  GetHl7MessageLines
    // =====================================================================

    [Fact]
    public void GetHl7MessageLines_ReturnsSegmentsInStandardOrder()
    {
        var messages = new List<Hl7Message>
        {
            new()
            {
                Segments = new Dictionary<string, List<string>>
                {
                    ["OBR"] = new() { "OBR|1|ORD1||PROC1" },
                    ["MSH"] = new() { "MSH|^~\\&|App|Fac" },
                    ["PID"] = new() { "PID|1||123" },
                }
            }
        };
        var service = new DiffService(null, null, messages);

        var lines = service.GetHl7MessageLines(0);
        Assert.Equal(3, lines.Length);
        // MSH should come first, then PID, then OBR
        Assert.StartsWith("MSH", lines[0]);
        Assert.StartsWith("PID", lines[1]);
        Assert.StartsWith("OBR", lines[2]);
    }

    [Fact]
    public void GetHl7MessageLines_IncludesNonStandardSegments()
    {
        var messages = new List<Hl7Message>
        {
            new()
            {
                Segments = new Dictionary<string, List<string>>
                {
                    ["MSH"] = new() { "MSH|^~\\&|App|Fac" },
                    ["ZCS"] = new() { "ZCS|custom" },
                }
            }
        };
        var service = new DiffService(null, null, messages);

        var lines = service.GetHl7MessageLines(0);
        Assert.Equal(2, lines.Length);
        Assert.StartsWith("MSH", lines[0]);
        Assert.StartsWith("ZCS", lines[1]);
    }

    // =====================================================================
    //  Helpers
    // =====================================================================

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        return (tumors, nsMgr);
    }
}
