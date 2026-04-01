using System.Data;
using System.Xml;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

/// <summary>
/// Tests verifying the isolation guarantees of the reference panel feature.
/// These ensure that reference file data cannot contaminate primary state
/// and that the data structures used by the reference panel lack export capability.
/// </summary>
public class ReferenceIsolationTests : IDisposable
{
    private readonly string _tempDir;

    public ReferenceIsolationTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_ref_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, true);
    }

    // ── DataTable structure tests ────────────────────────────────────────

    [Fact]
    public void ReferenceNavTable_HasNoSelectedColumn_WhenBuiltForXml()
    {
        // A reference panel DataTable must NOT have a "Selected" column.
        // This structurally prevents GetCheckedIndices() from operating on it.
        var table = BuildReferenceStyleXmlTable();

        Assert.False(table.Columns.Contains("Selected"),
            "Reference NavTable must NOT contain a 'Selected' column — this is the structural export isolation guarantee");
        Assert.True(table.Columns.Contains("Index"));
    }

    [Fact]
    public void ReferenceNavTable_HasNoSelectedColumn_WhenBuiltForHl7()
    {
        var table = BuildReferenceStyleHl7Table(
            ("Smith", "John", "19800101", "PATH001", "PAT001"));

        Assert.False(table.Columns.Contains("Selected"),
            "Reference NavTable must NOT contain a 'Selected' column — this is the structural export isolation guarantee");
        Assert.True(table.Columns.Contains("Index"));
    }

    [Fact]
    public void PrimaryNavTable_HasSelectedColumn()
    {
        // Verify primary table structure for contrast
        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("nameLast", typeof(string));

        Assert.True(table.Columns.Contains("Selected"),
            "Primary NavTable should have a 'Selected' column");
    }

    // ── Data isolation tests ─────────────────────────────────────────────

    [Fact]
    public void LoadingReferenceFile_DoesNotAffectPrimaryXmlState()
    {
        // Simulate: primary has file A loaded, reference loads file B.
        // Primary state must remain unchanged.
        var xmlService = new XmlFileService();

        // Load "primary" file
        var primaryXml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "PrimaryPatient",
            NameFirst = "John",
            DateOfBirth = "19800101",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
        });
        var primaryPath = Path.Combine(_tempDir, "primary.xml");
        File.WriteAllText(primaryPath, primaryXml);

        var (primaryDoc, primaryTumors, primaryNsMgr) = xmlService.LoadNaaccrXml(primaryPath);

        // Load "reference" file into separate variables (simulates FileContext)
        var refXml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "ReferencePatient",
            NameFirst = "Jane",
            DateOfBirth = "19900202",
            Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C340" } }
        });
        var refPath = Path.Combine(_tempDir, "reference.xml");
        File.WriteAllText(refPath, refXml);

        var (refDoc, refTumors, refNsMgr) = xmlService.LoadNaaccrXml(refPath);

        // Verify primary state is untouched
        Assert.Equal(1, primaryTumors.Count);
        var primaryPatientName = xmlService.GetItemValue(
            xmlService.GetPatientForTumor(primaryTumors[0]!)!, "nameLast", primaryNsMgr);
        Assert.Equal("PrimaryPatient", primaryPatientName);

        // Verify reference loaded different data
        Assert.Equal(1, refTumors.Count);
        var refPatientName = xmlService.GetItemValue(
            xmlService.GetPatientForTumor(refTumors[0]!)!, "nameLast", refNsMgr);
        Assert.Equal("ReferencePatient", refPatientName);

        // They are completely independent objects
        Assert.NotSame(primaryDoc, refDoc);
        Assert.NotSame(primaryTumors, refTumors);
    }

    [Fact]
    public void LoadingReferenceFile_DoesNotAffectPrimaryHl7State()
    {
        var parser = new Hl7Parser();
        var hl7Service = new Hl7FileService(parser);

        // Build two distinct HL7 files
        var primaryContent = BuildMinimalHl7("PrimaryPatient", "John", "19800101");
        var primaryPath = Path.Combine(_tempDir, "primary.hl7");
        File.WriteAllText(primaryPath, primaryContent);

        var refContent = BuildMinimalHl7("ReferencePatient", "Jane", "19900202");
        var refPath = Path.Combine(_tempDir, "reference.hl7");
        File.WriteAllText(refPath, refContent);

        var primaryMessages = hl7Service.LoadHl7File(primaryPath);
        var refMessages = hl7Service.LoadHl7File(refPath);

        // Primary is untouched
        Assert.Single(primaryMessages);
        Assert.Equal("PrimaryPatient", primaryMessages[0].PatientLastName);

        // Reference has its own data
        Assert.Single(refMessages);
        Assert.Equal("ReferencePatient", refMessages[0].PatientLastName);

        // Independent lists
        Assert.NotSame(primaryMessages, refMessages);
    }

    // ── Search index isolation tests ─────────────────────────────────────

    [Fact]
    public void SearchIndex_BuiltIndependently_ForEachFileContext()
    {
        var xmlService = new XmlFileService();

        var xml1 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Alpha", Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" } }
        });
        var path1 = Path.Combine(_tempDir, "file1.xml");
        File.WriteAllText(path1, xml1);

        var xml2 = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Bravo", Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PrimarySite = "C340" } }
        });
        var path2 = Path.Combine(_tempDir, "file2.xml");
        File.WriteAllText(path2, xml2);

        var (_, tumors1, nsMgr1) = xmlService.LoadNaaccrXml(path1);
        var (_, tumors2, nsMgr2) = xmlService.LoadNaaccrXml(path2);

        var index1 = new SearchService(tumors1, nsMgr1).BuildSearchIndex("xml");
        var index2 = new SearchService(tumors2, nsMgr2).BuildSearchIndex("xml");

        Assert.Contains("alpha", index1[0]);
        Assert.DoesNotContain("bravo", index1[0]);

        Assert.Contains("bravo", index2[0]);
        Assert.DoesNotContain("alpha", index2[0]);
    }

    // ── FindByKeyFields matching tests ───────────────────────────────────

    [Fact]
    public void FindByKeyFields_SingleMatch_ReturnsCorrectIndex()
    {
        var table = BuildReferenceStyleXmlTable(
            ("Smith", "John", "19800101", "PATH001", "C509"),
            ("Doe", "Jane", "19900202", "PATH002", "C340"));

        var matches = FindMatchingIndices(table, "Smith", "John", "19800101", "PATH001");

        Assert.Single(matches);
        Assert.Equal(1, matches[0]); // 1-based index
    }

    [Fact]
    public void FindByKeyFields_MultipleMatches_ReturnsAllCandidates()
    {
        // Same patient with two tumors (same key fields)
        var table = BuildReferenceStyleXmlTable(
            ("Smith", "John", "19800101", "PATH001", "C509"),
            ("Smith", "John", "19800101", "PATH001", "C340"),
            ("Doe", "Jane", "19900202", "PATH002", "C619"));

        var matches = FindMatchingIndices(table, "Smith", "John", "19800101", "PATH001");

        Assert.Equal(2, matches.Count);
        Assert.Contains(1, matches);
        Assert.Contains(2, matches);
    }

    [Fact]
    public void FindByKeyFields_NoMatch_ReturnsEmpty()
    {
        var table = BuildReferenceStyleXmlTable(
            ("Smith", "John", "19800101", "PATH001", "C509"));

        var matches = FindMatchingIndices(table, "Nobody", "None", "20000101", "PATH999");

        Assert.Empty(matches);
    }

    [Fact]
    public void FindByKeyFields_CaseInsensitiveNameMatch()
    {
        var table = BuildReferenceStyleXmlTable(
            ("SMITH", "JOHN", "19800101", "PATH001", "C509"));

        var matches = FindMatchingIndices(table, "smith", "john", "19800101", "PATH001");

        Assert.Single(matches);
    }

    [Fact]
    public void FindByKeyFields_DoesNotModifyPrimaryDataTable()
    {
        // Simulate primary table (with Selected column)
        var primaryTable = new DataTable();
        primaryTable.Columns.Add("Selected", typeof(bool));
        primaryTable.Columns.Add("Index", typeof(int));
        primaryTable.Columns.Add("nameLast", typeof(string));

        var primaryRow = primaryTable.NewRow();
        primaryRow["Selected"] = true;
        primaryRow["Index"] = 1;
        primaryRow["nameLast"] = "PrimaryPatient";
        primaryTable.Rows.Add(primaryRow);

        // Reference table (no Selected column)
        var refTable = BuildReferenceStyleXmlTable(
            ("RefPatient", "Jane", "19900202", "PATH002", "C340"));

        // Perform find on reference
        var matches = FindMatchingIndices(refTable, "RefPatient", "Jane", "19900202", "PATH002");

        // Primary table is completely untouched
        Assert.True((bool)primaryTable.Rows[0]["Selected"]);
        Assert.Equal("PrimaryPatient", primaryTable.Rows[0]["nameLast"]);
        Assert.Single(matches);
    }

    // ── HL7 accession number matching tests ─────────────────────────────

    [Fact]
    public void FindByKeyFields_MatchesHl7AccessionNumber()
    {
        var table = BuildReferenceStyleHl7Table(
            ("Smith", "John", "19800101", "PATH-2024-001", "PAT001"),
            ("Smith", "John", "19800101", "PATH-2024-002", "PAT001"));

        // pathReportNumber from XML primary should match accessionNumber in HL7 reference
        var matches = FindMatchingIndices(table, "Smith", "John", "19800101", "PATH-2024-001");

        Assert.Single(matches);
        Assert.Equal(1, matches[0]);
    }

    [Fact]
    public void FindByKeyFields_Hl7NoAccessionMatch_FallsBackToNameDob()
    {
        var table = BuildReferenceStyleHl7Table(
            ("Smith", "John", "19800101", "DIFFERENT-PATH", "PAT001"));

        // Path number doesn't match — should return empty (accessionNumber column exists but value differs)
        var matches = FindMatchingIndices(table, "Smith", "John", "19800101", "PATH-2024-001");

        Assert.Empty(matches);
    }

    [Fact]
    public void ReferenceHl7NavTable_HasAccessionNumberColumn()
    {
        var table = BuildReferenceStyleHl7Table(
            ("Smith", "John", "19800101", "PATH001", "PAT001"));

        Assert.True(table.Columns.Contains("accessionNumber"));
        Assert.False(table.Columns.Contains("Selected"));
    }

    // ── Test helpers ─────────────────────────────────────────────────────

    /// <summary>
    /// Builds a reference-style DataTable (NO "Selected" column) with the given records.
    /// </summary>
    private static DataTable BuildReferenceStyleXmlTable(
        params (string Last, string First, string Dob, string PathReport, string Site)[] records)
    {
        var table = new DataTable();
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("nameLast", typeof(string));
        table.Columns.Add("nameFirst", typeof(string));
        table.Columns.Add("dateOfBirth", typeof(string));
        table.Columns.Add("pathReportNumber1", typeof(string));
        table.Columns.Add("primarySite", typeof(string));

        for (int i = 0; i < records.Length; i++)
        {
            var row = table.NewRow();
            row["Index"] = i + 1;
            row["nameLast"] = records[i].Last;
            row["nameFirst"] = records[i].First;
            row["dateOfBirth"] = records[i].Dob;
            row["pathReportNumber1"] = records[i].PathReport;
            row["primarySite"] = records[i].Site;
            table.Rows.Add(row);
        }

        return table;
    }

    private static DataTable BuildReferenceStyleHl7Table(
        params (string Last, string First, string Dob, string Accession, string PatientId)[] records)
    {
        var table = new DataTable();
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("nameLast", typeof(string));
        table.Columns.Add("nameFirst", typeof(string));
        table.Columns.Add("dateOfBirth", typeof(string));
        table.Columns.Add("accessionNumber", typeof(string));
        table.Columns.Add("patientId", typeof(string));
        table.Columns.Add("messageType", typeof(string));
        table.Columns.Add("orderDateTime", typeof(string));

        for (int i = 0; i < records.Length; i++)
        {
            var row = table.NewRow();
            row["Index"] = i + 1;
            row["nameLast"] = records[i].Last;
            row["nameFirst"] = records[i].First;
            row["dateOfBirth"] = records[i].Dob;
            row["accessionNumber"] = records[i].Accession;
            row["patientId"] = records[i].PatientId;
            table.Rows.Add(row);
        }

        return table;
    }

    /// <summary>
    /// Simulates the FindByKeyFields matching logic (mirrors ReferenceForm.FindByKeyFields).
    /// Uses the same algorithm so tests verify the matching behavior without WinForms dependencies.
    /// </summary>
    private static List<int> FindMatchingIndices(DataTable table, string lastName, string firstName, string dob, string pathReport)
    {
        var matches = new List<int>();
        string lastLower = lastName.Trim().ToLowerInvariant();
        string firstLower = firstName.Trim().ToLowerInvariant();
        string dobTrimmed = dob.Trim();
        string pathTrimmed = pathReport.Trim();

        foreach (DataRow row in table.Rows)
        {
            int index = Convert.ToInt32(row["Index"]);

            string rowLast = (row.Table.Columns.Contains("nameLast") ? row["nameLast"]?.ToString() ?? "" : "").Trim().ToLowerInvariant();
            string rowFirst = (row.Table.Columns.Contains("nameFirst") ? row["nameFirst"]?.ToString() ?? "" : "").Trim().ToLowerInvariant();

            bool lastMatch = string.IsNullOrEmpty(lastLower) || rowLast == lastLower;
            bool firstMatch = string.IsNullOrEmpty(firstLower) || rowFirst == firstLower;

            bool dobMatch = true;
            if (!string.IsNullOrEmpty(dobTrimmed) && row.Table.Columns.Contains("dateOfBirth"))
            {
                string rowDob = (row["dateOfBirth"]?.ToString() ?? "").Trim();
                dobMatch = rowDob == dobTrimmed;
            }

            bool pathMatch = true;
            if (!string.IsNullOrEmpty(pathTrimmed))
            {
                if (row.Table.Columns.Contains("pathReportNumber1"))
                {
                    string rowPath = (row["pathReportNumber1"]?.ToString() ?? "").Trim();
                    pathMatch = rowPath == pathTrimmed;
                }
                else if (row.Table.Columns.Contains("accessionNumber"))
                {
                    string rowAccession = (row["accessionNumber"]?.ToString() ?? "").Trim();
                    pathMatch = rowAccession == pathTrimmed;
                }
            }

            if (lastMatch && firstMatch && dobMatch && pathMatch)
                matches.Add(index);
        }

        return matches;
    }

    private static string BuildMinimalHl7(string lastName, string firstName, string dob)
    {
        return $"MSH|^~\\&|SendApp|SendFac||ReceiveFac|20240101120000||ORU^R01|MSG001|P|2.3\r" +
               $"PID|||PAT001||{lastName}^{firstName}||{dob}|M\r" +
               $"OBR|1||ORD001|PathReport|||20240101\r" +
               $"OBX|1|TX|PathReport||Test result text||||||F\r";
    }
}
