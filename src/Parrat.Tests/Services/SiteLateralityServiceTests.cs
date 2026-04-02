using System.Xml;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class SiteLateralityServiceTests
{
    private readonly SiteLateralityService _svc = new();

    // =====================================================================
    //  GetLaterality
    // =====================================================================

    #region GetLaterality

    [Fact]
    public void GetLaterality_ReturnsNull_WhenNoSidePresent()
    {
        Assert.Null(_svc.GetLaterality("adenocarcinoma of the lung"));
    }

    [Fact]
    public void GetLaterality_Returns1_WhenRightOnly()
    {
        Assert.Equal("1", _svc.GetLaterality("right breast mass"));
    }

    [Fact]
    public void GetLaterality_Returns2_WhenLeftOnly()
    {
        Assert.Equal("2", _svc.GetLaterality("left axillary lymph node"));
    }

    [Fact]
    public void GetLaterality_Returns9_WhenBothSidesPresent()
    {
        Assert.Equal("9", _svc.GetLaterality("left and right ovaries involved"));
    }

    [Fact]
    public void GetLaterality_IsCaseInsensitive()
    {
        Assert.Equal("1", _svc.GetLaterality("RIGHT UPPER OUTER QUADRANT"));
        Assert.Equal("2", _svc.GetLaterality("LEFT LOWER LOBE"));
    }

    [Fact]
    public void GetLaterality_DoesNotMatchPartialWords()
    {
        // "righteous" and "leftover" should not count
        Assert.Null(_svc.GetLaterality("righteous pathology leftover tissue"));
    }

    [Fact]
    public void GetLaterality_Returns1_WhenRightAppearsInSentence()
    {
        Assert.Equal("1", _svc.GetLaterality("excision of right lower extremity lesion"));
    }

    #endregion

    // =====================================================================
    //  GetBestCode
    // =====================================================================

    #region GetBestCode

    [Fact]
    public void GetBestCode_ReturnsNull_WhenMapIsEmpty()
    {
        var result = _svc.GetBestCode(new List<TopographyEntry>(), "breast cancer");
        Assert.Null(result.PrimarySite);
    }

    [Fact]
    public void GetBestCode_ReturnsNull_WhenNoMatchInText()
    {
        var map = new List<TopographyEntry>
        {
            new() { Code = "C50.9", SearchPhrase = "breast" }
        };
        var result = _svc.GetBestCode(map, "lung adenocarcinoma");
        Assert.Null(result.PrimarySite);
    }

    [Fact]
    public void GetBestCode_ReturnsCode_WhenPhraseMatchesInText()
    {
        var map = new List<TopographyEntry>
        {
            new() { Code = "C50.9", SearchPhrase = "breast" }
        };
        var result = _svc.GetBestCode(map, "right breast mass, invasive ductal carcinoma");
        Assert.Equal("C50.9", result.PrimarySite);
    }

    [Fact]
    public void GetBestCode_ReturnsEarliestMatch_WhenMultiplePhraseMatch()
    {
        var map = new List<TopographyEntry>
        {
            new() { Code = "C50.9", SearchPhrase = "breast" },
            new() { Code = "C34.1", SearchPhrase = "lung" }
        };
        // "lung" appears before "breast" in the text
        var result = _svc.GetBestCode(map, "lung and breast tissue submitted");
        Assert.Equal("C34.1", result.PrimarySite);
    }

    [Fact]
    public void GetBestCode_DoesNotMatchPartialWord()
    {
        var map = new List<TopographyEntry>
        {
            new() { Code = "C50.9", SearchPhrase = "breast" }
        };
        // "breastbone" should not match "breast" as a word boundary
        var result = _svc.GetBestCode(map, "breastbone lesion");
        Assert.Null(result.PrimarySite);
    }

    #endregion

    // =====================================================================
    //  TestSiteCodingRule — term type
    // =====================================================================

    #region TestSiteCodingRule — term

    [Fact]
    public void TestSiteCodingRule_Term_Matches_WhenTermPresentInText()
    {
        var rule = new SiteCodingRule
        {
            Code = "C34.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "term", Value = "non-small cell" }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "diagnosis: non-small cell lung cancer");
        Assert.True(result.Matched);
        Assert.Equal("non-small cell", result.MatchedTerm);
    }

    [Fact]
    public void TestSiteCodingRule_Term_NoMatch_WhenTermAbsent()
    {
        var rule = new SiteCodingRule
        {
            Code = "C34.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "term", Value = "non-small cell" }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "small cell carcinoma of the lung");
        Assert.False(result.Matched);
    }

    [Fact]
    public void TestSiteCodingRule_Term_DoesNotMatchPartialWord()
    {
        var rule = new SiteCodingRule
        {
            Code = "C50.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "term", Value = "breast" }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "breastbone resection");
        Assert.False(result.Matched);
    }

    #endregion

    // =====================================================================
    //  TestSiteCodingRule — group type (OR logic)
    // =====================================================================

    #region TestSiteCodingRule — group OR

    [Fact]
    public void TestSiteCodingRule_GroupOr_Matches_WhenAnyTermPresent()
    {
        var rule = new SiteCodingRule
        {
            Code = "C34.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "group", Logic = "OR", Terms = new List<string> { "nsclc", "squamous cell carcinoma" } }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "pathology: squamous cell carcinoma");
        Assert.True(result.Matched);
    }

    [Fact]
    public void TestSiteCodingRule_GroupOr_NoMatch_WhenNoTermsPresent()
    {
        var rule = new SiteCodingRule
        {
            Code = "C34.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "group", Logic = "OR", Terms = new List<string> { "nsclc", "squamous cell carcinoma" } }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "adenocarcinoma of the colon");
        Assert.False(result.Matched);
    }

    #endregion

    // =====================================================================
    //  TestSiteCodingRule — group type (AND logic)
    // =====================================================================

    #region TestSiteCodingRule — group AND

    [Fact]
    public void TestSiteCodingRule_GroupAnd_Matches_WhenAllTermsPresent()
    {
        var rule = new SiteCodingRule
        {
            Code = "C50.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "group", Logic = "AND", Terms = new List<string> { "ductal", "carcinoma" } }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "invasive ductal carcinoma of the breast");
        Assert.True(result.Matched);
    }

    [Fact]
    public void TestSiteCodingRule_GroupAnd_NoMatch_WhenOnlyOneTermPresent()
    {
        var rule = new SiteCodingRule
        {
            Code = "C50.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "group", Logic = "AND", Terms = new List<string> { "ductal", "carcinoma" } }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "ductal tissue without malignancy");
        Assert.False(result.Matched);
    }

    #endregion

    // =====================================================================
    //  TestSiteCodingRule — top-level AND/OR across multiple expression items
    // =====================================================================

    #region TestSiteCodingRule — top-level logic

    [Fact]
    public void TestSiteCodingRule_TopLevelAnd_Matches_WhenAllItemsMatch()
    {
        var rule = new SiteCodingRule
        {
            Code = "C34.9",
            Logic = "AND",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "term", Value = "lung" },
                new() { Type = "term", Value = "adenocarcinoma" }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "lung adenocarcinoma, stage iiia");
        Assert.True(result.Matched);
    }

    [Fact]
    public void TestSiteCodingRule_TopLevelAnd_NoMatch_WhenOneItemMissing()
    {
        var rule = new SiteCodingRule
        {
            Code = "C34.9",
            Logic = "AND",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "term", Value = "lung" },
                new() { Type = "term", Value = "adenocarcinoma" }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "lung squamous cell carcinoma");
        Assert.False(result.Matched);
    }

    [Fact]
    public void TestSiteCodingRule_TopLevelOr_Matches_WhenAnyItemMatches()
    {
        var rule = new SiteCodingRule
        {
            Code = "C34.9",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "term", Value = "nsclc" },
                new() { Type = "term", Value = "non-small cell" }
            }
        };
        var result = _svc.TestSiteCodingRule(rule, "nsclc, right upper lobe");
        Assert.True(result.Matched);
        Assert.Equal("nsclc", result.MatchedTerm);
    }

    #endregion

    // =====================================================================
    //  TestSiteCodingRule — topo-template type
    // =====================================================================

    #region TestSiteCodingRule — topo-template

    [Fact]
    public void TestSiteCodingRule_TopoTemplate_Matches_WhenTemplateExpandsToTextMatch()
    {
        var rule = new SiteCodingRule
        {
            Code = "{topo}",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "topo-template", Template = "carcinoma of the {topo}" }
            }
        };
        var topoMap = new List<TopographyEntry>
        {
            new() { Code = "C50.9", SearchPhrase = "breast" },
            new() { Code = "C34.1", SearchPhrase = "lung" }
        };
        var result = _svc.TestSiteCodingRule(rule, "carcinoma of the breast, right side", topoMap);
        Assert.True(result.Matched);
        Assert.Equal("C50.9", result.TopoCode);
    }

    [Fact]
    public void TestSiteCodingRule_TopoTemplate_NoMatch_WhenNoTopoEntryFitsTemplate()
    {
        var rule = new SiteCodingRule
        {
            Code = "{topo}",
            Logic = "OR",
            Expression = new List<ExpressionItem>
            {
                new() { Type = "topo-template", Template = "carcinoma of the {topo}" }
            }
        };
        var topoMap = new List<TopographyEntry>
        {
            new() { Code = "C50.9", SearchPhrase = "breast" }
        };
        var result = _svc.TestSiteCodingRule(rule, "adenocarcinoma of the colon", topoMap);
        Assert.False(result.Matched);
    }

    #endregion

    // =====================================================================
    //  ReadTopographyJson
    // =====================================================================

    #region ReadTopographyJson

    [Fact]
    public void ReadTopographyJson_ParsesJsonlFile()
    {
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllLines(tempFile, new[]
            {
                """{"Code":"C509","SearchPhrase":"breast"}""",
                """{"Code":"C189","SearchPhrase":"colon"}""",
            });

            var result = _svc.ReadTopographyJson(tempFile);
            Assert.Equal(2, result.Count);
            Assert.Equal("C509", result[0].Code);
            Assert.Equal("breast", result[0].SearchPhrase);
        }
        finally { File.Delete(tempFile); }
    }

    [Fact]
    public void ReadTopographyJson_SkipsMalformedLines()
    {
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllLines(tempFile, new[]
            {
                """{"Code":"C509","SearchPhrase":"breast"}""",
                "not valid json",
                """{"Code":"C189","SearchPhrase":"colon"}""",
            });

            var result = _svc.ReadTopographyJson(tempFile);
            Assert.Equal(2, result.Count);
        }
        finally { File.Delete(tempFile); }
    }

    [Fact]
    public void ReadTopographyJson_ThrowsForMissingFile()
    {
        Assert.Throws<FileNotFoundException>(() => _svc.ReadTopographyJson("/nonexistent/path.jsonl"));
    }

    #endregion

    // =====================================================================
    //  ReadLateralityJson
    // =====================================================================

    #region ReadLateralityJson

    [Fact]
    public void ReadLateralityJson_ParsesJsonArray()
    {
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, """["C509","C501","C502"]""");

            var result = _svc.ReadLateralityJson(tempFile);
            Assert.Equal(3, result.Count);
            Assert.True(result.ContainsKey("C509"));
            Assert.True(result.ContainsKey("C501"));
        }
        finally { File.Delete(tempFile); }
    }

    [Fact]
    public void ReadLateralityJson_ThrowsForMissingFile()
    {
        Assert.Throws<FileNotFoundException>(() => _svc.ReadLateralityJson("/nonexistent/path.json"));
    }

    #endregion

    // =====================================================================
    //  ReadSiteCodingRules
    // =====================================================================

    #region ReadSiteCodingRules

    [Fact]
    public void ReadSiteCodingRules_ParsesAndSortsByPriority()
    {
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllLines(tempFile, new[]
            {
                """{"Code":"C509","Priority":2,"Enabled":true,"Expression":[{"Type":"term","Value":"breast"}]}""",
                """{"Code":"C189","Priority":1,"Enabled":true,"Expression":[{"Type":"term","Value":"colon"}]}""",
            });

            var result = _svc.ReadSiteCodingRules(tempFile);
            Assert.Equal(2, result.Count);
            Assert.Equal("C189", result[0].Code); // Priority 1 first
            Assert.Equal("C509", result[1].Code); // Priority 2 second
        }
        finally { File.Delete(tempFile); }
    }

    [Fact]
    public void ReadSiteCodingRules_SkipsDisabledRules()
    {
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllLines(tempFile, new[]
            {
                """{"Code":"C509","Priority":1,"Enabled":true,"Expression":[{"Type":"term","Value":"breast"}]}""",
                """{"Code":"C189","Priority":2,"Enabled":false,"Expression":[{"Type":"term","Value":"colon"}]}""",
            });

            var result = _svc.ReadSiteCodingRules(tempFile);
            Assert.Single(result);
            Assert.Equal("C509", result[0].Code);
        }
        finally { File.Delete(tempFile); }
    }

    [Fact]
    public void ReadSiteCodingRules_ReturnsEmptyForMissingFile()
    {
        var result = _svc.ReadSiteCodingRules("/nonexistent/path.jsonl");
        Assert.Empty(result);
    }

    #endregion

    // =====================================================================
    //  WriteAssignedXml
    // =====================================================================

    #region WriteAssignedXml

    [Fact]
    public void WriteAssignedXml_WritesSiteAndLateralityToOutput()
    {
        var xml = $@"<?xml version=""1.0""?>
<NaaccrData xmlns=""{NaaccrXmlTestHelper.NaaccrNamespace}"">
  <Patient>
    <Item naaccrId=""nameLast"">Smith</Item>
    <Tumor>
      <Item naaccrId=""dateOfDiagnosis"">20240101</Item>
    </Tumor>
  </Patient>
</NaaccrData>";

        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        var tumors = doc.SelectNodes("//n:Tumor", nsMgr)!;

        var assignments = new Dictionary<int, SiteAssignment>
        {
            [0] = new SiteAssignment { PrimarySite = "C509", Laterality = "2" }
        };

        var outputPath = Path.Combine(Path.GetTempPath(), $"parrat_site_test_{Guid.NewGuid():N}.xml");
        try
        {
            _svc.WriteAssignedXml(doc, tumors, assignments, nsMgr, outputPath);

            var outDoc = new XmlDocument();
            outDoc.Load(outputPath);
            var outNsMgr = new XmlNamespaceManager(outDoc.NameTable);
            outNsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);

            var siteNode = outDoc.SelectSingleNode("//n:Tumor/n:Item[@naaccrId='primarySite']", outNsMgr);
            Assert.NotNull(siteNode);
            Assert.Equal("C509", siteNode!.InnerText);

            var latNode = outDoc.SelectSingleNode("//n:Tumor/n:Item[@naaccrId='laterality']", outNsMgr);
            Assert.NotNull(latNode);
            Assert.Equal("2", latNode!.InnerText);

            // Verify patient data preserved
            var nameNode = outDoc.SelectSingleNode("//n:Patient/n:Item[@naaccrId='nameLast']", outNsMgr);
            Assert.Equal("Smith", nameNode!.InnerText);
        }
        finally { if (File.Exists(outputPath)) File.Delete(outputPath); }
    }

    #endregion
}
