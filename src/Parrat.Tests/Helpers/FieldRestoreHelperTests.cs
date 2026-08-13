using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Xunit;

namespace Parrat.Tests.Helpers;

public class FieldRestoreHelperTests
{
    private static (XmlDocument doc, XmlNodeList tumors, XmlNamespaceManager nsMgr) Load(string xml)
    {
        var doc = new XmlDocument { XmlResolver = null };
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;
        return (doc, tumors, nsMgr);
    }

    private static NaaccrXmlTestHelper.PatientData Patient(
        string nameLast, params NaaccrXmlTestHelper.TumorData[] tumors) =>
        new() { NameLast = nameLast, Tumors = tumors };

    private static NaaccrXmlTestHelper.TumorData Tumor(string pathReport, string? facility) =>
        new()
        {
            PathReportNumber1 = pathReport,
            Items = facility == null
                ? null
                : new Dictionary<string, string> { ["reportingFacility"] = facility }
        };

    /// <summary>Damaged file: every record blanket-set to facility 9999999999.</summary>
    private static string BuildDamagedXml() => NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
    {
        Patient("Smith", Tumor("S24-0001", "9999999999")),
        Patient("Jones", Tumor("S24-0002", "9999999999")),
        Patient("Lee", Tumor("S24-0003", "9999999999"))
    });

    /// <summary>Original file with the distinct per-record facilities.</summary>
    private static string BuildOriginalXml() => NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
    {
        Patient("Smith", Tumor("S24-0001", "1111111111")),
        Patient("Jones", Tumor("S24-0002", "2222222222")),
        Patient("Lee", Tumor("S24-0003", "9999999999"))
    });

    private static FieldRestorePlan BuildFacilityPlan(string damagedXml, string originalXml)
    {
        var (_, damagedTumors, damagedNs) = Load(damagedXml);
        var (_, originalTumors, originalNs) = Load(originalXml);

        return FieldRestoreHelper.BuildPlan(
            damagedTumors, damagedNs, originalTumors, originalNs,
            "pathReportNumber1", new[] { "reportingFacility" });
    }

    // ── BuildPlan ────────────────────────────────────────────────────────

    [Fact]
    public void BuildPlan_RestoresDifferingValues_AndKeepsAgreeingOnes()
    {
        var plan = BuildFacilityPlan(BuildDamagedXml(), BuildOriginalXml());

        Assert.Equal(3, plan.Rows.Count);
        Assert.Equal(2, plan.RestoreCount);
        Assert.Equal(1, plan.AlreadyCorrectCount);

        var first = plan.Rows[0];
        Assert.Equal(RestoreStatus.Restore, first.Status);
        Assert.Equal("S24-0001", first.KeyValue);
        Assert.Equal("9999999999", first.CurrentValue);
        Assert.Equal("1111111111", first.OriginalValue);

        Assert.Equal(RestoreStatus.AlreadyCorrect, plan.Rows[2].Status);
    }

    [Fact]
    public void BuildPlan_KeyNotInOriginal_ReportsNoMatch()
    {
        var original = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("S24-0001", "1111111111")));

        var plan = BuildFacilityPlan(BuildDamagedXml(), original);

        Assert.Equal(1, plan.RestoreCount);
        Assert.Equal(2, plan.NoMatchCount);
        Assert.All(plan.Rows.Where(r => r.Status == RestoreStatus.NoMatch),
            r => Assert.Equal("", r.OriginalValue));
    }

    [Fact]
    public void BuildPlan_RecordWithoutKey_ReportsMissingKey()
    {
        var damaged = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("", "9999999999")));

        var plan = BuildFacilityPlan(damaged, BuildOriginalXml());

        Assert.Equal(1, plan.MissingKeyCount);
        Assert.Equal(0, plan.RestoreCount);
    }

    [Fact]
    public void BuildPlan_ConflictingOriginalDuplicates_ReportsAmbiguous()
    {
        var original = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            Patient("Smith", Tumor("S24-0001", "1111111111")),
            Patient("Smith", Tumor("S24-0001", "3333333333"))
        });
        var damaged = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("S24-0001", "9999999999")));

        var plan = BuildFacilityPlan(damaged, original);

        Assert.Equal(1, plan.AmbiguousCount);
        Assert.Equal(0, plan.RestoreCount);
    }

    [Fact]
    public void BuildPlan_AgreeingOriginalDuplicates_RestoreNormally()
    {
        var original = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            Patient("Smith", Tumor("S24-0001", "1111111111")),
            Patient("Smith", Tumor("S24-0001", "1111111111")),
            Patient("Smith", Tumor("S24-0001", null))
        });
        var damaged = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("S24-0001", "9999999999")));

        var plan = BuildFacilityPlan(damaged, original);

        // An empty duplicate carries no information and never causes a conflict.
        Assert.Equal(1, plan.RestoreCount);
        Assert.Equal("1111111111", plan.Rows[0].OriginalValue);
    }

    [Fact]
    public void BuildPlan_OriginalHoldsNoValue_SkipsRatherThanBlanks()
    {
        var original = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("S24-0001", null)));
        var damaged = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("S24-0001", "9999999999")));

        var plan = BuildFacilityPlan(damaged, original);

        Assert.Equal(1, plan.OriginalEmptyCount);
        Assert.Equal(0, plan.RestoreCount);
    }

    [Fact]
    public void BuildPlan_KeyMatchingIgnoresCaseByDefault()
    {
        var original = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("s24-0001", "1111111111")));
        var damaged = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("S24-0001", "9999999999")));

        var (_, damagedTumors, damagedNs) = Load(damaged);
        var (_, originalTumors, originalNs) = Load(original);

        var insensitive = FieldRestoreHelper.BuildPlan(
            damagedTumors, damagedNs, originalTumors, originalNs,
            "pathReportNumber1", new[] { "reportingFacility" });
        Assert.Equal(1, insensitive.RestoreCount);

        var sensitive = FieldRestoreHelper.BuildPlan(
            damagedTumors, damagedNs, originalTumors, originalNs,
            "pathReportNumber1", new[] { "reportingFacility" }, caseInsensitiveKeys: false);
        Assert.Equal(1, sensitive.NoMatchCount);
    }

    [Fact]
    public void BuildPlan_MultipleFields_PlansEachIndependently()
    {
        var original = NaaccrXmlTestHelper.BuildNaaccrXml(patients: Patient("Smith",
            new NaaccrXmlTestHelper.TumorData
            {
                PathReportNumber1 = "S24-0001",
                Items = new Dictionary<string, string>
                {
                    ["reportingFacility"] = "1111111111",
                    ["npiReportingFacility"] = "1234567890"
                }
            }));
        var damaged = NaaccrXmlTestHelper.BuildNaaccrXml(patients: Patient("Smith",
            new NaaccrXmlTestHelper.TumorData
            {
                PathReportNumber1 = "S24-0001",
                Items = new Dictionary<string, string>
                {
                    ["reportingFacility"] = "9999999999",
                    ["npiReportingFacility"] = "1234567890"
                }
            }));

        var (_, damagedTumors, damagedNs) = Load(damaged);
        var (_, originalTumors, originalNs) = Load(original);

        var plan = FieldRestoreHelper.BuildPlan(
            damagedTumors, damagedNs, originalTumors, originalNs,
            "pathReportNumber1", new[] { "reportingFacility", "npiReportingFacility" });

        Assert.Equal(2, plan.Rows.Count);
        Assert.Equal(1, plan.RestoreCount);
        Assert.Equal(1, plan.AlreadyCorrectCount);
        Assert.Equal("reportingFacility", plan.Rows.Single(r => r.Status == RestoreStatus.Restore).FieldId);
    }

    // ── BuildRepairedDocument ────────────────────────────────────────────

    [Fact]
    public void BuildRepairedDocument_WritesPlannedValues_AndLeavesSourceUntouched()
    {
        var (damagedDoc, damagedTumors, damagedNs) = Load(BuildDamagedXml());
        var (_, originalTumors, originalNs) = Load(BuildOriginalXml());

        var plan = FieldRestoreHelper.BuildPlan(
            damagedTumors, damagedNs, originalTumors, originalNs,
            "pathReportNumber1", new[] { "reportingFacility" });

        var repaired = FieldRestoreHelper.BuildRepairedDocument(damagedDoc, damagedNs, plan);

        var repairedNs = new XmlNamespaceManager(repaired.NameTable);
        repairedNs.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var repairedTumors = repaired.SelectNodes("//n:Tumor", repairedNs)!;

        Assert.Equal("1111111111", TumorFieldReader.ReadValueAnyLevel(repairedTumors[0]!, "reportingFacility", repairedNs));
        Assert.Equal("2222222222", TumorFieldReader.ReadValueAnyLevel(repairedTumors[1]!, "reportingFacility", repairedNs));
        Assert.Equal("9999999999", TumorFieldReader.ReadValueAnyLevel(repairedTumors[2]!, "reportingFacility", repairedNs));

        // The loaded document is never touched — the repair is a new document.
        foreach (XmlNode tumor in damagedTumors)
            Assert.Equal("9999999999", TumorFieldReader.ReadValueAnyLevel(tumor, "reportingFacility", damagedNs));
    }

    [Fact]
    public void BuildRepairedDocument_CreatesItemWhenDamagedRecordLacksIt()
    {
        var damaged = NaaccrXmlTestHelper.BuildNaaccrXml(
            patients: Patient("Smith", Tumor("S24-0001", null)));
        var (damagedDoc, damagedTumors, damagedNs) = Load(damaged);
        var (_, originalTumors, originalNs) = Load(BuildOriginalXml());

        var plan = FieldRestoreHelper.BuildPlan(
            damagedTumors, damagedNs, originalTumors, originalNs,
            "pathReportNumber1", new[] { "reportingFacility" });
        Assert.Equal(1, plan.RestoreCount);

        var repaired = FieldRestoreHelper.BuildRepairedDocument(damagedDoc, damagedNs, plan);

        var repairedNs = new XmlNamespaceManager(repaired.NameTable);
        repairedNs.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var tumor = repaired.SelectNodes("//n:Tumor", repairedNs)![0]!;

        var item = tumor.SelectSingleNode("./n:Item[@naaccrId='reportingFacility']", repairedNs);
        Assert.NotNull(item);
        Assert.Equal("1111111111", item!.InnerText);
        Assert.Equal(NaaccrXmlTestHelper.NaaccrNamespace, item.NamespaceURI);
    }

    [Fact]
    public void BuildRepairedDocument_PreservesEverythingElse()
    {
        var (damagedDoc, damagedTumors, damagedNs) = Load(BuildDamagedXml());
        var (_, originalTumors, originalNs) = Load(BuildOriginalXml());

        var plan = FieldRestoreHelper.BuildPlan(
            damagedTumors, damagedNs, originalTumors, originalNs,
            "pathReportNumber1", new[] { "reportingFacility" });

        var repaired = FieldRestoreHelper.BuildRepairedDocument(damagedDoc, damagedNs, plan);

        var repairedNs = new XmlNamespaceManager(repaired.NameTable);
        repairedNs.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);

        Assert.Equal(3, repaired.SelectNodes("//n:Patient", repairedNs)!.Count);
        Assert.Equal("Smith", repaired.SelectSingleNode("//n:Patient[1]/n:Item[@naaccrId='nameLast']", repairedNs)?.InnerText);
        Assert.Equal("S24-0002", repaired.SelectNodes("//n:Tumor", repairedNs)![1]!
            .SelectSingleNode("./n:Item[@naaccrId='pathReportNumber1']", repairedNs)?.InnerText);
        Assert.Equal(damagedDoc.DocumentElement!.GetAttribute("baseDictionaryUri"),
            repaired.DocumentElement!.GetAttribute("baseDictionaryUri"));
    }
}
