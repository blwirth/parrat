using System.Xml;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class FolderLoadServiceTests : IDisposable
{
    private readonly string _folder;
    private readonly FolderLoadService _service;

    public FolderLoadServiceTests()
    {
        _folder = Path.Combine(Path.GetTempPath(), $"parrat-folder-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_folder);

        _service = new FolderLoadService(
            new Hl7FileService(new Hl7Parser()),
            new EpathParserService(),
            new XmlFileService());
    }

    public void Dispose()
    {
        if (Directory.Exists(_folder))
            Directory.Delete(_folder, recursive: true);
    }

    // ── Scanning ─────────────────────────────────────────────────────────

    [Fact]
    public void ScanFolder_ClassifiesFilesByContentNotExtension()
    {
        WriteHl7("report-a.hl7", messageCount: 1);
        WriteHl7("report-b.txt", messageCount: 1);   // HL7 wearing a .txt extension
        WriteFile("notes.txt", "Just some narrative text about a specimen.\n");

        var scan = _service.ScanFolder(_folder);

        var hl7 = scan.FilesOfFormat(DetectedFileFormat.Hl7);
        Assert.Equal(2, hl7.Count);
        Assert.Contains(hl7, f => f.FileName == "report-b.txt");
        Assert.Contains(scan.SkippedFiles, f => f.FileName == "notes.txt");
    }

    [Fact]
    public void ScanFolder_IgnoresSubfolders()
    {
        WriteHl7("top.hl7", messageCount: 1);

        var nested = Path.Combine(_folder, "nested");
        Directory.CreateDirectory(nested);
        File.WriteAllText(Path.Combine(nested, "deep.hl7"), BuildHl7(1, "NESTED"));

        var scan = _service.ScanFolder(_folder);

        var hl7 = scan.FilesOfFormat(DetectedFileFormat.Hl7);
        Assert.Single(hl7);
        Assert.Equal("top.hl7", hl7[0].FileName);
    }

    [Fact]
    public void ScanFolder_EmptyFolder_ReportsNothingLoadable()
    {
        var scan = _service.ScanFolder(_folder);

        Assert.False(scan.HasLoadableFiles);
        Assert.Empty(scan.AvailableFormats);
    }

    [Fact]
    public void ScanFolder_UnsupportedFilesOnly_ReportsThemAsSkipped()
    {
        WriteFile("readme.txt", "A folder of reports.\n");

        var scan = _service.ScanFolder(_folder);

        Assert.False(scan.HasLoadableFiles);
        Assert.Single(scan.SkippedFiles);
    }

    [Fact]
    public void ScanFolder_MissingFolder_Throws()
    {
        var missing = Path.Combine(_folder, "does-not-exist");

        Assert.Throws<DirectoryNotFoundException>(() => _service.ScanFolder(missing));
    }

    [Fact]
    public void ScanFolder_ReturnsFilesInNameOrder()
    {
        WriteHl7("c.hl7", messageCount: 1);
        WriteHl7("a.hl7", messageCount: 1);
        WriteHl7("b.hl7", messageCount: 1);

        var scan = _service.ScanFolder(_folder);

        Assert.Equal(
            new[] { "a.hl7", "b.hl7", "c.hl7" },
            scan.FilesOfFormat(DetectedFileFormat.Hl7).Select(f => f.FileName));
    }

    // ── Loading ──────────────────────────────────────────────────────────

    [Fact]
    public void LoadHl7Files_MergesMessagesAndStampsSourceFile()
    {
        var first = WriteHl7("first.hl7", messageCount: 2);
        var second = WriteHl7("second.hl7", messageCount: 3);

        var result = _service.LoadHl7Files(new[] { first, second });

        Assert.Equal(5, result.Records.Count);
        Assert.Equal(2, result.FileCount);
        Assert.Empty(result.Failures);
        Assert.Equal(2, result.Records.Count(m => m.SourceFile == first));
        Assert.Equal(3, result.Records.Count(m => m.SourceFile == second));
    }

    [Fact]
    public void LoadHl7Files_RenumbersIndexesAcrossTheWholeSet()
    {
        var first = WriteHl7("first.hl7", messageCount: 2);
        var second = WriteHl7("second.hl7", messageCount: 2);

        var result = _service.LoadHl7Files(new[] { first, second });

        Assert.Equal(new[] { 0, 1, 2, 3 }, result.Records.Select(m => m.Index));
    }

    [Fact]
    public void LoadHl7Files_BatchWrappedFile_ExcludesEnvelopeSegments()
    {
        var path = Path.Combine(_folder, "batch.hl7");
        File.WriteAllText(path,
            "FHS|^~\\&|App|Fac\n" +
            "BHS|^~\\&|App|Fac\n" +
            BuildHl7(1, "BATCH") +
            "BTS|1\n" +
            "FTS|1\n");

        var result = _service.LoadHl7Files(new[] { path });

        Assert.Single(result.Records);
        Assert.DoesNotContain("BTS|", result.Records[0].RawContent);
        Assert.DoesNotContain("FTS|", result.Records[0].RawContent);
    }

    [Fact]
    public void LoadHl7Files_UnreadableFile_RecordsFailureAndKeepsGoing()
    {
        var good = WriteHl7("good.hl7", messageCount: 2);
        var empty = WriteFile("empty.hl7", "");

        var result = _service.LoadHl7Files(new[] { empty, good });

        Assert.Equal(2, result.Records.Count);
        Assert.Single(result.LoadedFiles);
        Assert.Single(result.Failures);
        Assert.Equal("empty.hl7", result.Failures[0].FileName);
        // The surviving file still gets a contiguous index range.
        Assert.Equal(new[] { 0, 1 }, result.Records.Select(m => m.Index));
    }

    [Fact]
    public void LoadHl7Files_MissingFile_RecordsFailure()
    {
        var missing = Path.Combine(_folder, "gone.hl7");

        var result = _service.LoadHl7Files(new[] { missing });

        Assert.Empty(result.Records);
        Assert.Single(result.Failures);
    }

    [Fact]
    public void LoadHl7Files_NoFiles_ReturnsEmptyResult()
    {
        var result = _service.LoadHl7Files(Array.Empty<string>());

        Assert.Empty(result.Records);
        Assert.Empty(result.Failures);
        Assert.Equal(0, result.FileCount);
    }

    [Fact]
    public void LoadHl7Files_PreservesFileOrderInMergedSet()
    {
        var first = WriteHl7("first.hl7", messageCount: 1, patientPrefix: "AAA");
        var second = WriteHl7("second.hl7", messageCount: 1, patientPrefix: "BBB");

        var result = _service.LoadHl7Files(new[] { first, second });

        Assert.Equal("AAA0", result.Records[0].PatientLastName);
        Assert.Equal("BBB0", result.Records[1].PatientLastName);
    }

    // ── NAACCR XML merging ───────────────────────────────────────────────

    [Fact]
    public void LoadXmlFiles_MergesTumorsAcrossFilesAndTracksSources()
    {
        var first = WriteXml("first.xml", patients: 2, tumorsPerPatient: 1);
        var second = WriteXml("second.xml", patients: 1, tumorsPerPatient: 3);

        var result = _service.LoadXmlFiles(new[] { first, second });

        Assert.Equal(5, result.TumorCount);
        Assert.Equal(2, result.FileCount);
        Assert.Empty(result.Failures);
        Assert.Equal(2, result.TumorSourceFiles.Count(s => s == first));
        Assert.Equal(3, result.TumorSourceFiles.Count(s => s == second));
        // Source attribution must line up with document order.
        Assert.Equal(new[] { first, first, second, second, second }, result.TumorSourceFiles);
    }

    [Fact]
    public void LoadXmlFiles_MergedDocumentIsQueryableLikeASingleFile()
    {
        var first = WriteXml("first.xml", patients: 1, tumorsPerPatient: 1);
        var second = WriteXml("second.xml", patients: 1, tumorsPerPatient: 1);

        var result = _service.LoadXmlFiles(new[] { first, second });

        Assert.NotNull(result.Document);
        Assert.NotNull(result.NsMgr);

        // Every tumor resolves its patient, proving the imported subtrees are
        // properly parented in the merged document.
        var svc = new XmlFileService();
        for (int i = 0; i < result.Tumors!.Count; i++)
            Assert.NotNull(svc.GetPatientForTumor(result.Tumors[i]!));
    }

    [Fact]
    public void LoadXmlFiles_MergedDocumentSurvivesSerializationRoundTrip()
    {
        // Merged patients are read straight into the target document rather
        // than cloned, so verify namespaces and structure came out intact by
        // writing the result and reading it back.
        var first = WriteXml("first.xml", patients: 2, tumorsPerPatient: 1);
        var second = WriteXml("second.xml", patients: 2, tumorsPerPatient: 2);

        var result = _service.LoadXmlFiles(new[] { first, second });
        Assert.Equal(6, result.TumorCount);

        var roundTripPath = Path.Combine(_folder, "merged-output.xml");
        result.Document!.Save(roundTripPath);

        var reloaded = new XmlDocument { XmlResolver = null };
        reloaded.Load(roundTripPath);
        var nsMgr = new XmlNamespaceManager(reloaded.NameTable);
        nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml");

        Assert.Equal("NaaccrData", reloaded.DocumentElement!.LocalName);
        Assert.Equal("http://naaccr.org/naaccrxml", reloaded.DocumentElement.NamespaceURI);
        Assert.Equal(6, reloaded.SelectNodes("//n:Tumor", nsMgr)!.Count);
        Assert.Equal(4, reloaded.SelectNodes("//n:Patient", nsMgr)!.Count);

        // Namespaced item lookups still resolve, which is what the grid and
        // export rely on.
        Assert.Equal(6, reloaded.SelectNodes("//n:Tumor/n:Item[@naaccrId='primarySite']", nsMgr)!.Count);
    }

    [Fact]
    public void LoadXmlFiles_MergedTumorsResolveItemsThroughXmlFileService()
    {
        var first = WriteXml("first.xml", patients: 1, tumorsPerPatient: 1);
        var second = WriteXml("second.xml", patients: 1, tumorsPerPatient: 1);

        var result = _service.LoadXmlFiles(new[] { first, second });
        var svc = new XmlFileService();

        for (int i = 0; i < result.Tumors!.Count; i++)
        {
            var tumor = result.Tumors[i]!;
            Assert.Equal("C500", svc.GetItemValue(tumor, "primarySite", result.NsMgr!));

            var patient = svc.GetPatientForTumor(tumor);
            Assert.NotNull(patient);
            Assert.NotEmpty(svc.GetItemValue(patient!, "patientIdNumber", result.NsMgr!));
        }
    }

    [Fact]
    public void LoadXmlFiles_IncompatibleRecordType_IsRejectedNotMerged()
    {
        var first = WriteXml("first.xml", patients: 1, tumorsPerPatient: 1);
        var other = WriteXml("other.xml", patients: 1, tumorsPerPatient: 1, recordType: "I");

        var result = _service.LoadXmlFiles(new[] { first, other });

        Assert.Equal(1, result.TumorCount);
        Assert.Single(result.Failures);
        Assert.Contains("recordType", result.Failures[0].Reason);
    }

    [Fact]
    public void LoadXmlFiles_IncompatibleDictionary_IsRejectedNotMerged()
    {
        var first = WriteXml("first.xml", patients: 1, tumorsPerPatient: 1);
        var other = WriteXml("other.xml", patients: 1, tumorsPerPatient: 1,
            dictionaryUri: "http://naaccr.org/naaccrxml/naaccr-dictionary-210.xml");

        var result = _service.LoadXmlFiles(new[] { first, other });

        Assert.Equal(1, result.TumorCount);
        Assert.Single(result.Failures);
        Assert.Contains("baseDictionaryUri", result.Failures[0].Reason);
    }

    [Fact]
    public void LoadXmlFiles_DisagreeingFileLevelItems_AreWarnedAboutNotSilent()
    {
        var first = WriteXml("first.xml", patients: 1, tumorsPerPatient: 1, registryId: "0000000001");
        var second = WriteXml("second.xml", patients: 1, tumorsPerPatient: 1, registryId: "0000000099");

        var result = _service.LoadXmlFiles(new[] { first, second });

        Assert.Equal(2, result.TumorCount);
        Assert.Single(result.Warnings);
        Assert.Contains("registryId", result.Warnings[0]);
    }

    [Fact]
    public void LoadXmlFiles_MatchingFileLevelItems_ProduceNoWarning()
    {
        var first = WriteXml("first.xml", patients: 1, tumorsPerPatient: 1, registryId: "0000000001");
        var second = WriteXml("second.xml", patients: 1, tumorsPerPatient: 1, registryId: "0000000001");

        var result = _service.LoadXmlFiles(new[] { first, second });

        Assert.Empty(result.Warnings);
    }

    [Fact]
    public void LoadXmlFiles_FileWithNoTumors_IsReportedAndSkipped()
    {
        var good = WriteXml("good.xml", patients: 1, tumorsPerPatient: 2);
        var empty = WriteXml("empty.xml", patients: 1, tumorsPerPatient: 0);

        var result = _service.LoadXmlFiles(new[] { empty, good });

        Assert.Equal(2, result.TumorCount);
        Assert.Single(result.LoadedFiles);
        Assert.Single(result.Failures);
        Assert.Contains("No tumors", result.Failures[0].Reason);
    }

    [Fact]
    public void LoadXmlFiles_MalformedFile_IsReportedAndOthersStillLoad()
    {
        var good = WriteXml("good.xml", patients: 1, tumorsPerPatient: 1);
        var bad = WriteFile("bad.xml", "<NaaccrData><Patient>truncated");

        var result = _service.LoadXmlFiles(new[] { bad, good });

        Assert.Equal(1, result.TumorCount);
        Assert.Single(result.Failures);
        Assert.Equal("bad.xml", result.Failures[0].FileName);
    }

    [Fact]
    public void LoadXmlFiles_NoUsableFiles_ReturnsEmptyResult()
    {
        var result = _service.LoadXmlFiles(Array.Empty<string>());

        Assert.Null(result.Document);
        Assert.Equal(0, result.TumorCount);
    }

    [Fact]
    public void ScanFolder_ClassifiesXmlAsLoadable()
    {
        WriteXml("cases.xml", patients: 1, tumorsPerPatient: 1);

        var scan = _service.ScanFolder(_folder);

        Assert.Single(scan.FilesOfFormat(DetectedFileFormat.NaaccrXml));
    }

    // ── Record counts ────────────────────────────────────────────────────

    [Fact]
    public void CountRecords_Hl7_CountsMessagesAcrossFiles()
    {
        var first = WriteHl7("first.hl7", messageCount: 2);
        var second = WriteHl7("second.hl7", messageCount: 3);

        Assert.Equal(5, _service.CountRecords(DetectedFileFormat.Hl7, new[] { first, second }));
    }

    [Fact]
    public void CountRecords_Hl7_IgnoresBatchEnvelope()
    {
        var path = Path.Combine(_folder, "batch.hl7");
        File.WriteAllText(path,
            "FHS|^~\\&|App|Fac\nBHS|^~\\&|App|Fac\n" + BuildHl7(3) + "BTS|3\nFTS|1\n");

        Assert.Equal(3, _service.CountRecords(DetectedFileFormat.Hl7, new[] { path }));
    }

    [Fact]
    public void CountRecords_Hl7_MatchesWhatLoadingProduces()
    {
        var first = WriteHl7("first.hl7", messageCount: 4);
        var second = WriteHl7("second.hl7", messageCount: 7);
        var files = new[] { first, second };

        Assert.Equal(
            _service.LoadHl7Files(files).Records.Count,
            _service.CountRecords(DetectedFileFormat.Hl7, files));
    }

    [Fact]
    public void CountRecords_Xml_CountsTumorsNotPatients()
    {
        // A patient may carry several tumors, so the two counts differ.
        var path = WriteXml("cases.xml", patients: 3, tumorsPerPatient: 2);

        Assert.Equal(6, _service.CountRecords(DetectedFileFormat.NaaccrXml, new[] { path }));
    }

    [Fact]
    public void CountRecords_Xml_MatchesWhatMergingProduces()
    {
        var first = WriteXml("first.xml", patients: 2, tumorsPerPatient: 3);
        var second = WriteXml("second.xml", patients: 1, tumorsPerPatient: 4);
        var files = new[] { first, second };

        Assert.Equal(
            _service.LoadXmlFiles(files).TumorCount,
            _service.CountRecords(DetectedFileFormat.NaaccrXml, files));
    }

    [Fact]
    public void CountRecords_UnreadableFile_ContributesNothingAndDoesNotThrow()
    {
        var good = WriteHl7("good.hl7", messageCount: 2);
        var missing = Path.Combine(_folder, "gone.hl7");

        Assert.Equal(2, _service.CountRecords(DetectedFileFormat.Hl7, new[] { good, missing }));
    }

    [Fact]
    public void CountRecords_MalformedXml_ContributesNothingAndDoesNotThrow()
    {
        var good = WriteXml("good.xml", patients: 1, tumorsPerPatient: 2);
        var bad = WriteFile("bad.xml", "<NaaccrData><Patient>truncated");

        Assert.Equal(2, _service.CountRecords(DetectedFileFormat.NaaccrXml, new[] { good, bad }));
    }

    [Fact]
    public void CountRecords_NoFiles_ReturnsZero()
    {
        Assert.Equal(0, _service.CountRecords(DetectedFileFormat.Hl7, Array.Empty<string>()));
    }

    [Fact]
    public void TotalBytes_SumsExistingFilesAndIgnoresMissing()
    {
        var path = WriteFile("a.hl7", new string('x', 100));
        var missing = Path.Combine(_folder, "missing.hl7");

        Assert.Equal(100, _service.TotalBytes(new[] { path, missing }));
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private string WriteXml(
        string fileName,
        int patients,
        int tumorsPerPatient,
        string recordType = "A",
        string dictionaryUri = "http://naaccr.org/naaccrxml/naaccr-dictionary-240.xml",
        string? registryId = null)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine(@"<?xml version=""1.0""?>");
        sb.AppendLine($@"<NaaccrData baseDictionaryUri=""{dictionaryUri}"" recordType=""{recordType}"" " +
                      @"xmlns=""http://naaccr.org/naaccrxml"">");

        if (registryId != null)
            sb.AppendLine($@"  <Item naaccrId=""registryId"">{registryId}</Item>");

        for (int p = 0; p < patients; p++)
        {
            sb.AppendLine("  <Patient>");
            sb.AppendLine($@"    <Item naaccrId=""patientIdNumber"">{fileName}-{p:D4}</Item>");
            for (int t = 0; t < tumorsPerPatient; t++)
            {
                sb.AppendLine("    <Tumor>");
                sb.AppendLine($@"      <Item naaccrId=""primarySite"">C50{t}</Item>");
                sb.AppendLine("    </Tumor>");
            }
            sb.AppendLine("  </Patient>");
        }

        sb.AppendLine("</NaaccrData>");
        return WriteFile(fileName, sb.ToString());
    }

    private string WriteHl7(string fileName, int messageCount, string patientPrefix = "Patient")
        => WriteFile(fileName, BuildHl7(messageCount, patientPrefix));

    private string WriteFile(string fileName, string content)
    {
        var path = Path.Combine(_folder, fileName);
        File.WriteAllText(path, content);
        return path;
    }

    private static string BuildHl7(int messageCount, string patientPrefix = "Patient")
    {
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < messageCount; i++)
        {
            sb.Append($"MSH|^~\\&|App|Fac|||2024010{i + 1}||ORU^R01|{i + 1}|P|2.5.1\n");
            sb.Append($"PID|1||MRN{i:D3}||{patientPrefix}{i}^Test||19850315|F\n");
            sb.Append($"OBR|1||SP-{i:D3}|PATH^Pathology Report\n");
            sb.Append("OBX|1|TX|PATH_DX^Diagnosis||Carcinoma||||||F\n");
        }
        return sb.ToString();
    }
}
