using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Xunit;

namespace Parrat.Tests.Helpers;

public class ListSelectionHelperTests
{
    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var xmlDoc = new XmlDocument { XmlResolver = null };
        xmlDoc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(xmlDoc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var tumors = xmlDoc.SelectNodes("//n:Tumor", nsMgr)!;
        return (tumors, nsMgr);
    }

    private static string BuildThreePatientXml()
    {
        // Patient 1000 has two tumors under one Patient element; patient 3000
        // is the same person filed twice as separate Patient elements — the
        // shape the parser meets in real folder merges.
        return NaaccrXmlTestHelper.BuildNaaccrXml(patients: new[]
        {
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Smith", PatientIdNumber = "1000",
                Tumors = new[]
                {
                    new NaaccrXmlTestHelper.TumorData { PathReportNumber1 = "S24-0001" },
                    new NaaccrXmlTestHelper.TumorData { PathReportNumber1 = "S24-0002" }
                }
            },
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Jones", PatientIdNumber = "2000",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PathReportNumber1 = "S24-0003" } }
            },
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Lee", PatientIdNumber = "3000",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PathReportNumber1 = "S24-0004" } }
            },
            new NaaccrXmlTestHelper.PatientData
            {
                NameLast = "Lee", PatientIdNumber = "3000",
                Tumors = new[] { new NaaccrXmlTestHelper.TumorData { PathReportNumber1 = "S24-0005" } }
            }
        });
    }

    // ── ParseValues ──────────────────────────────────────────────────────

    [Fact]
    public void ParseValues_SplitsLinesAndSeparators_TrimsAndDedupes()
    {
        var values = ListSelectionHelper.ParseValues(" A1 \r\nB2, C3;\tD4\n\n a1 ");

        Assert.Equal(new[] { "A1", "B2", "C3", "D4" }, values);
    }

    [Fact]
    public void ParseValues_EmptyOrNull_ReturnsEmpty()
    {
        Assert.Empty(ListSelectionHelper.ParseValues(null));
        Assert.Empty(ListSelectionHelper.ParseValues("  \r\n , ; "));
    }

    // ── CSV extraction ───────────────────────────────────────────────────

    private static CsvParseResult BuildWorklistCsv() => new()
    {
        Headers = new[] { "mrn", "name", "status" },
        Rows = new List<string[]>
        {
            new[] { "1000", "Smith", "A" },
            new[] { "2000", "Jones", "B" },
            new[] { "3000", "Lee", "a" },
            new[] { "4000", "Kim", "C" },
            new[] { "1000", "Smith", "A" },
            new[] { "", "NoKey", "A" }
        }
    };

    [Fact]
    public void ExtractKeyValues_NoFilter_ReturnsDistinctNonEmptyKeys()
    {
        var values = ListSelectionHelper.ExtractKeyValues(BuildWorklistCsv(), keyColumnIndex: 0);

        Assert.Equal(new[] { "1000", "2000", "3000", "4000" }, values);
    }

    [Fact]
    public void ExtractKeyValues_FilterColumn_KeepsOnlyIncludedRows()
    {
        // The "col x has A, B, C — export only A" scenario; the include list
        // is case-insensitive so "a" rows count as "A".
        var values = ListSelectionHelper.ExtractKeyValues(
            BuildWorklistCsv(), keyColumnIndex: 0, filterColumnIndex: 2,
            includedFilterValues: new[] { "A" });

        Assert.Equal(new[] { "1000", "3000" }, values);
    }

    [Fact]
    public void ExtractKeyValues_NothingIncluded_ReturnsEmpty()
    {
        var values = ListSelectionHelper.ExtractKeyValues(
            BuildWorklistCsv(), keyColumnIndex: 0, filterColumnIndex: 2,
            includedFilterValues: Array.Empty<string>());

        Assert.Empty(values);
    }

    [Fact]
    public void ExtractKeyValues_BadColumnIndex_ReturnsEmpty()
    {
        Assert.Empty(ListSelectionHelper.ExtractKeyValues(BuildWorklistCsv(), keyColumnIndex: 9));
        Assert.Empty(ListSelectionHelper.ExtractKeyValues(BuildWorklistCsv(), keyColumnIndex: -1));
    }

    [Fact]
    public void DistinctColumnValues_ReturnsFirstSeenSpellings()
    {
        var values = ListSelectionHelper.DistinctColumnValues(BuildWorklistCsv(), 2);

        Assert.Equal(new[] { "A", "B", "C" }, values);
    }

    // ── MatchTumors ──────────────────────────────────────────────────────

    [Fact]
    public void MatchTumors_TumorLevelKey_SelectsSingleRows()
    {
        var (tumors, nsMgr) = LoadTumors(BuildThreePatientXml());

        var result = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "pathReportNumber1", new[] { "S24-0002", "S24-0003" });

        Assert.Equal(new[] { 1, 2 }, result.MatchedIndices);
        Assert.Empty(result.UnmatchedValues);
        Assert.Empty(result.MultiMatchValues);
    }

    [Fact]
    public void MatchTumors_PatientLevelKey_SelectsEveryTumorOfThePatient()
    {
        var (tumors, nsMgr) = LoadTumors(BuildThreePatientXml());

        var result = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "patientIdNumber", new[] { "1000" });

        Assert.Equal(new[] { 0, 1 }, result.MatchedIndices);
        Assert.Equal(new[] { "1000" }, result.MultiMatchValues);
    }

    [Fact]
    public void MatchTumors_PatientSplitAcrossPatientElements_MatchesBoth()
    {
        var (tumors, nsMgr) = LoadTumors(BuildThreePatientXml());

        var result = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "patientIdNumber", new[] { "3000" });

        Assert.Equal(new[] { 3, 4 }, result.MatchedIndices);
        Assert.Equal(new[] { "3000" }, result.MultiMatchValues);
    }

    [Fact]
    public void MatchTumors_ReportsUnmatchedValues()
    {
        var (tumors, nsMgr) = LoadTumors(BuildThreePatientXml());

        var result = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "pathReportNumber1", new[] { "S24-0001", "S99-9999" });

        Assert.Equal(new[] { 0 }, result.MatchedIndices);
        Assert.Equal(new[] { "S99-9999" }, result.UnmatchedValues);
        Assert.Equal(2, result.ValueCount);
    }

    [Fact]
    public void MatchTumors_CaseSensitivityHonorsFlag()
    {
        var (tumors, nsMgr) = LoadTumors(BuildThreePatientXml());

        var insensitive = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "pathReportNumber1", new[] { "s24-0001" }, caseInsensitive: true);
        Assert.Equal(new[] { 0 }, insensitive.MatchedIndices);

        var sensitive = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "pathReportNumber1", new[] { "s24-0001" }, caseInsensitive: false);
        Assert.Empty(sensitive.MatchedIndices);
        Assert.Equal(new[] { "s24-0001" }, sensitive.UnmatchedValues);
    }

    [Fact]
    public void MatchTumors_DuplicateAndBlankValues_CollapseIntoDistinctList()
    {
        var (tumors, nsMgr) = LoadTumors(BuildThreePatientXml());

        var result = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "pathReportNumber1", new[] { "S24-0001", " s24-0001 ", "", "  " });

        Assert.Equal(1, result.ValueCount);
        Assert.Equal(new[] { 0 }, result.MatchedIndices);
        Assert.Empty(result.MultiMatchValues);
    }

    [Fact]
    public void MatchTumors_FieldAbsentEverywhere_MatchesNothing()
    {
        var (tumors, nsMgr) = LoadTumors(BuildThreePatientXml());

        var result = ListSelectionHelper.MatchTumors(
            tumors, nsMgr, "medicalRecordNumber", new[] { "1000" });

        Assert.Empty(result.MatchedIndices);
        Assert.Equal(new[] { "1000" }, result.UnmatchedValues);
    }
}
