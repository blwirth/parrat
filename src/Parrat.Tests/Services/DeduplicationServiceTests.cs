using System.Xml;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class DeduplicationServiceTests
{
    private readonly DeduplicationService _service = new();

    private static (XmlDocument Doc, XmlNamespaceManager NsMgr) CreateTestDoc(params string[] patientFragments)
    {
        string innerXml = string.Join("\n", patientFragments);
        string xmlString = $@"<?xml version=""1.0"" encoding=""UTF-8""?>
<NaaccrData xmlns=""http://naaccr.org/naaccrxml"">
{innerXml}
</NaaccrData>";

        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xmlString);

        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml");

        return (doc, nsMgr);
    }

    private static string PatientFragment(string nameLast, string nameFirst, string dob,
        params (string Key, string Value)[][] tumors)
    {
        string patientItems = $@"    <Item naaccrId=""nameLast"">{nameLast}</Item>
    <Item naaccrId=""nameFirst"">{nameFirst}</Item>
    <Item naaccrId=""dateOfBirth"">{dob}</Item>";

        var tumorFragments = new List<string>();
        foreach (var t in tumors)
        {
            var items = t.Select(kv => $"      <Item naaccrId=\"{kv.Key}\">{kv.Value}</Item>");
            tumorFragments.Add($"    <Tumor>\n{string.Join("\n", items)}\n    </Tumor>");
        }

        return $"  <Patient>\n{patientItems}\n{string.Join("\n", tumorFragments)}\n  </Patient>";
    }

    [Fact]
    public void GetTumorFingerprint_ProducesConsistentFingerprintForIdenticalTumors()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("dateOfDiagnosis", "20240101") },
                new[] { ("primarySite", "C501"), ("dateOfDiagnosis", "20240101") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var patient = doc.SelectNodes("//n:Patient", nsMgr)![0]!;

        string fp1 = _service.GetTumorFingerprint(tumors[0]!, patient, nsMgr);
        string fp2 = _service.GetTumorFingerprint(tumors[1]!, patient, nsMgr);

        Assert.Equal(fp1, fp2);
    }

    [Fact]
    public void GetTumorFingerprint_ProducesDifferentFingerprintForDifferentTumors()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("dateOfDiagnosis", "20240101") },
                new[] { ("primarySite", "C502"), ("dateOfDiagnosis", "20240201") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var patient = doc.SelectNodes("//n:Patient", nsMgr)![0]!;

        string fp1 = _service.GetTumorFingerprint(tumors[0]!, patient, nsMgr);
        string fp2 = _service.GetTumorFingerprint(tumors[1]!, patient, nsMgr);

        Assert.NotEqual(fp1, fp2);
    }

    [Fact]
    public void GetTumorFingerprint_IgnoresDateCaseReportReceived()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("dateCaseReportReceived", "20240101") },
                new[] { ("primarySite", "C501"), ("dateCaseReportReceived", "20240601") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var patient = doc.SelectNodes("//n:Patient", nsMgr)![0]!;

        string fp1 = _service.GetTumorFingerprint(tumors[0]!, patient, nsMgr);
        string fp2 = _service.GetTumorFingerprint(tumors[1]!, patient, nsMgr);

        Assert.Equal(fp1, fp2);
    }

    [Fact]
    public void GetTumorFingerprint_IgnoresDateCaseReportLoaded()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("dateCaseReportLoaded", "20240101") },
                new[] { ("primarySite", "C501"), ("dateCaseReportLoaded", "20240601") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var patient = doc.SelectNodes("//n:Patient", nsMgr)![0]!;

        string fp1 = _service.GetTumorFingerprint(tumors[0]!, patient, nsMgr);
        string fp2 = _service.GetTumorFingerprint(tumors[1]!, patient, nsMgr);

        Assert.Equal(fp1, fp2);
    }

    [Fact]
    public void GetTumorFingerprint_IgnoresPhysician3()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("physician3", "DrA") },
                new[] { ("primarySite", "C501"), ("physician3", "DrB") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var patient = doc.SelectNodes("//n:Patient", nsMgr)![0]!;

        string fp1 = _service.GetTumorFingerprint(tumors[0]!, patient, nsMgr);
        string fp2 = _service.GetTumorFingerprint(tumors[1]!, patient, nsMgr);

        Assert.Equal(fp1, fp2);
    }

    [Fact]
    public void GetTumorFingerprint_IncludesPatientItemsWithPPrefix()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501") }));

        var tumor = doc.SelectNodes("//n:Tumor", nsMgr)![0]!;
        var patient = doc.SelectNodes("//n:Patient", nsMgr)![0]!;

        string fp = _service.GetTumorFingerprint(tumor, patient, nsMgr);

        Assert.Contains("P|nameLast|Smith", fp);
        Assert.Contains("P|nameFirst|John", fp);
    }

    [Fact]
    public void GetTumorFingerprint_IncludesTumorItemsWithTPrefix()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501") }));

        var tumor = doc.SelectNodes("//n:Tumor", nsMgr)![0]!;
        var patient = doc.SelectNodes("//n:Patient", nsMgr)![0]!;

        string fp = _service.GetTumorFingerprint(tumor, patient, nsMgr);

        Assert.Contains("T|primarySite|C501", fp);
    }

    [Fact]
    public void GetPatientTumorGroups_GroupsTumorsByPatientKey()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001") },
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C502"), ("pathReportNumber1", "P001") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var groups = _service.GetPatientTumorGroups(tumors, nsMgr);

        Assert.Single(groups);
        Assert.Equal(2, groups.Values.First().Count);
    }

    [Fact]
    public void GetPatientTumorGroups_SeparatesTumorsWithDifferentDiagnosisDates()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001") },
                new[] { ("dateOfDiagnosis", "20240601"), ("primarySite", "C501"), ("pathReportNumber1", "P001") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var groups = _service.GetPatientTumorGroups(tumors, nsMgr);

        Assert.Equal(2, groups.Count);
    }

    [Fact]
    public void GetPatientTumorGroups_SeparatesDifferentPatients()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("pathReportNumber1", "P001") }),
            PatientFragment("Jones", "Mary", "19900202",
                new[] { ("dateOfDiagnosis", "20240101"), ("pathReportNumber1", "P002") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var groups = _service.GetPatientTumorGroups(tumors, nsMgr);

        Assert.Equal(2, groups.Count);
    }

    [Fact]
    public void GetPatientTumorGroups_StoresCorrectTumorIndex()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001") },
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C502"), ("pathReportNumber1", "P001") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var groups = _service.GetPatientTumorGroups(tumors, nsMgr);

        var group = groups.Values.First();
        Assert.Equal(0, group[0].Index);
        Assert.Equal(1, group[1].Index);
    }

    [Fact]
    public void GetDuplicates_KeepsAllUniqueTumors()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001") }),
            PatientFragment("Jones", "Mary", "19900202",
                new[] { ("dateOfDiagnosis", "20240201"), ("primarySite", "C502"), ("pathReportNumber1", "P002") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicates(tumors, nsMgr);

        Assert.Equal(2, result.IndicesToKeep.Count);
        Assert.Empty(result.Report);
    }

    [Fact]
    public void GetDuplicates_RemovesTrueDuplicates()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240101") },
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240601") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicates(tumors, nsMgr);

        Assert.Single(result.IndicesToKeep);
        Assert.Single(result.Report);
    }

    [Fact]
    public void GetDuplicates_KeepsTumorsWithDifferentFingerprintsInSameGroup()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001") },
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C502"), ("pathReportNumber1", "P001") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicates(tumors, nsMgr);

        Assert.Equal(2, result.IndicesToKeep.Count);
        Assert.Empty(result.Report);
    }

    [Fact]
    public void GetDuplicates_ReportIncludesPatientKeyAndReason()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240101") },
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240601") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicates(tumors, nsMgr);

        Assert.Contains("Smith", result.Report[0].PatientKey);
        Assert.False(string.IsNullOrEmpty(result.Report[0].Reason));
    }

    [Fact]
    public void GetDuplicates_HandlesSingleTumor()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("dateOfDiagnosis", "20240101"), ("primarySite", "C501"), ("pathReportNumber1", "P001") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicates(tumors, nsMgr);

        Assert.Single(result.IndicesToKeep);
        Assert.Contains(0, result.IndicesToKeep);
        Assert.Empty(result.Report);
    }

    [Fact]
    public void GetDuplicatesByPrimaryKey_KeepsUniqueTumors()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("laterality", "1") },
                new[] { ("primarySite", "C502"), ("laterality", "2") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicatesByPrimaryKey(tumors, nsMgr);

        Assert.Equal(2, result.IndicesToKeep.Count);
        Assert.Empty(result.Report);
    }

    [Fact]
    public void GetDuplicatesByPrimaryKey_DeduplicatesTumorsWithSamePrimaryKey()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("laterality", "1"), ("dateCaseReportReceived", "20240101") },
                new[] { ("primarySite", "C501"), ("laterality", "1"), ("dateCaseReportReceived", "20240601") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicatesByPrimaryKey(tumors, nsMgr);

        Assert.Single(result.IndicesToKeep);
        Assert.Single(result.Report);
        Assert.Contains("PrimaryKey:", result.Report[0].PatientKey);
    }

    [Fact]
    public void GetDuplicatesByPrimaryKey_KeepsEarliestDateCaseReportReceived()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("laterality", "1"), ("dateCaseReportReceived", "20240601") },
                new[] { ("primarySite", "C501"), ("laterality", "1"), ("dateCaseReportReceived", "20240101") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicatesByPrimaryKey(tumors, nsMgr);

        Assert.Contains(1, result.IndicesToKeep);
        Assert.DoesNotContain(0, result.IndicesToKeep);
    }

    [Fact]
    public void GetDuplicatesByPathReport_KeepsUniquePathReports()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("pathReportNumber1", "P001"), ("primarySite", "C501") },
                new[] { ("pathReportNumber1", "P002"), ("primarySite", "C502") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicatesByPathReport(tumors, nsMgr);

        Assert.Equal(2, result.IndicesToKeep.Count);
        Assert.Empty(result.Report);
    }

    [Fact]
    public void GetDuplicatesByPathReport_DeduplicatesSamePathReport()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240101") },
                new[] { ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240601") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicatesByPathReport(tumors, nsMgr);

        Assert.Single(result.IndicesToKeep);
        Assert.Single(result.Report);
        Assert.Contains("pathReportNumber1: P001", result.Report[0].PatientKey);
    }

    [Fact]
    public void GetDuplicatesByPathReport_KeepsTumorsWithoutPathReport()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501") },
                new[] { ("primarySite", "C502") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicatesByPathReport(tumors, nsMgr);

        Assert.Equal(2, result.IndicesToKeep.Count);
    }

    [Fact]
    public void GetDuplicatesByPathReport_KeepsEarliestDateReceived()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240601") },
                new[] { ("pathReportNumber1", "P001"), ("dateCaseReportReceived", "20240101") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var result = _service.GetDuplicatesByPathReport(tumors, nsMgr);

        Assert.Contains(1, result.IndicesToKeep);
        Assert.DoesNotContain(0, result.IndicesToKeep);
    }

    [Fact]
    public void WriteDedupedXml_WritesOnlyKeptTumors()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501"), ("dateOfDiagnosis", "20240101") },
                new[] { ("primarySite", "C502"), ("dateOfDiagnosis", "20240201") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var indicesToKeep = new HashSet<int> { 0 };
        string outputPath = Path.Combine(Path.GetTempPath(), $"deduped_{Guid.NewGuid()}.xml");

        try
        {
            _service.WriteDedupedXml(doc, tumors, indicesToKeep, outputPath);

            Assert.True(File.Exists(outputPath));

            var resultDoc = new XmlDocument();
            resultDoc.Load(outputPath);
            var resultNsMgr = new XmlNamespaceManager(resultDoc.NameTable);
            resultNsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml");
            var resultTumors = resultDoc.SelectNodes("//n:Tumor", resultNsMgr)!;

            Assert.Equal(1, resultTumors.Count);
            var site = resultTumors[0]!.SelectSingleNode("./n:Item[@naaccrId='primarySite']", resultNsMgr);
            Assert.Equal("C501", site!.InnerText);
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    [Fact]
    public void WriteDedupedXml_DropsPatientWhenAllTumorsRemoved()
    {
        var (doc, nsMgr) = CreateTestDoc(
            PatientFragment("Smith", "John", "19800101",
                new[] { ("primarySite", "C501") }),
            PatientFragment("Jones", "Mary", "19900202",
                new[] { ("primarySite", "C502") }));

        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        var indicesToKeep = new HashSet<int> { 1 }; // Keep only Jones
        string outputPath = Path.Combine(Path.GetTempPath(), $"deduped_{Guid.NewGuid()}.xml");

        try
        {
            _service.WriteDedupedXml(doc, tumors, indicesToKeep, outputPath);

            var resultDoc = new XmlDocument();
            resultDoc.Load(outputPath);
            var resultNsMgr = new XmlNamespaceManager(resultDoc.NameTable);
            resultNsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml");
            var patients = resultDoc.SelectNodes("//n:Patient", resultNsMgr)!;

            Assert.Equal(1, patients.Count);
            var nameNode = patients[0]!.SelectSingleNode("./n:Item[@naaccrId='nameLast']", resultNsMgr);
            Assert.Equal("Jones", nameNode!.InnerText);
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }
}
