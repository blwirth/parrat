using Parat.Core.Models;
using Parat.Core.Services;
using Xunit;

namespace Parat.Tests.Services;

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
}
