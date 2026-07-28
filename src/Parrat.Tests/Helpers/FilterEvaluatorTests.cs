using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Xunit;

namespace Parrat.Tests.Helpers;

public class FilterEvaluatorTests
{
    private static FilterCondition Condition(
        FilterOperator op, string value = "", string value2 = "",
        FieldPart part = FieldPart.Whole, FilterConjunction conjunction = FilterConjunction.And,
        string fieldId = "field") =>
        new()
        {
            FieldId = fieldId,
            Operator = op,
            Value = value,
            Value2 = value2,
            Part = part,
            Conjunction = conjunction
        };

    #region ExtractPart

    [Theory]
    [InlineData("20260315", FieldPart.Whole, "20260315")]
    [InlineData("20260315", FieldPart.Year, "2026")]
    [InlineData("20260315", FieldPart.YearMonth, "202603")]
    [InlineData("20260315", FieldPart.Date, "20260315")]
    [InlineData("20260315143000", FieldPart.Date, "20260315")]
    public void ExtractPart_TakesLeadingCharacters(string value, FieldPart part, string expected)
    {
        Assert.Equal(expected, FilterEvaluator.ExtractPart(value, part));
    }

    [Theory]
    [InlineData("202", FieldPart.Year, "202")]
    [InlineData("2026", FieldPart.YearMonth, "2026")]
    [InlineData("", FieldPart.Year, "")]
    public void ExtractPart_ReturnsShortValuesWhole(string value, FieldPart part, string expected)
    {
        Assert.Equal(expected, FilterEvaluator.ExtractPart(value, part));
    }

    [Fact]
    public void ExtractPart_TreatsNullAsEmpty()
    {
        Assert.Equal("", FilterEvaluator.ExtractPart(null, FieldPart.Year));
    }

    #endregion

    #region Equality and text operators

    [Fact]
    public void Matches_EqualsIsCaseInsensitive()
    {
        Assert.True(FilterEvaluator.Matches("C509", Condition(FilterOperator.Equals, "c509")));
    }

    [Fact]
    public void Matches_EqualsIgnoresSurroundingWhitespace()
    {
        Assert.True(FilterEvaluator.Matches("  C509  ", Condition(FilterOperator.Equals, " C509 ")));
    }

    [Fact]
    public void Matches_NotEqualsIsTheInverseOfEquals()
    {
        Assert.False(FilterEvaluator.Matches("C509", Condition(FilterOperator.NotEquals, "C509")));
        Assert.True(FilterEvaluator.Matches("C502", Condition(FilterOperator.NotEquals, "C509")));
    }

    [Theory]
    [InlineData(FilterOperator.Contains, "50", true)]
    [InlineData(FilterOperator.Contains, "99", false)]
    [InlineData(FilterOperator.NotContains, "99", true)]
    [InlineData(FilterOperator.StartsWith, "C5", true)]
    [InlineData(FilterOperator.StartsWith, "50", false)]
    [InlineData(FilterOperator.EndsWith, "09", true)]
    [InlineData(FilterOperator.EndsWith, "C5", false)]
    public void Matches_TextOperators(FilterOperator op, string target, bool expected)
    {
        Assert.Equal(expected, FilterEvaluator.Matches("C509", Condition(op, target)));
    }

    #endregion

    #region LIKE

    [Theory]
    [InlineData("C50%", "C509", true)]
    [InlineData("C50%", "C449", false)]
    [InlineData("%50%", "C509", true)]
    [InlineData("C___", "C509", true)]
    [InlineData("C__", "C509", false)]
    [InlineData("C50_", "C509", true)]
    [InlineData("C509", "C509", true)]
    [InlineData("c50%", "C509", true)]
    [InlineData("%", "anything", true)]
    public void Matches_LikeHonorsWildcards(string pattern, string value, bool expected)
    {
        Assert.Equal(expected, FilterEvaluator.Matches(value, Condition(FilterOperator.Like, pattern)));
    }

    [Theory]
    [InlineData("C50.9", "C50.9", true)]
    [InlineData("C50.9", "C5029", false)]
    [InlineData("[x]", "[x]", true)]
    [InlineData("(a)", "a", false)]
    [InlineData("a+b", "a+b", true)]
    public void Matches_LikeEscapesRegexMetacharacters(string pattern, string value, bool expected)
    {
        Assert.Equal(expected, FilterEvaluator.Matches(value, Condition(FilterOperator.Like, pattern)));
    }

    [Fact]
    public void Matches_NotLikeIsTheInverseOfLike()
    {
        Assert.False(FilterEvaluator.Matches("C509", Condition(FilterOperator.NotLike, "C50%")));
        Assert.True(FilterEvaluator.Matches("C449", Condition(FilterOperator.NotLike, "C50%")));
    }

    [Fact]
    public void LikeToRegex_ReturnsTheSameCompiledPatternForRepeatedCalls()
    {
        Assert.Same(FilterEvaluator.LikeToRegex("C50%"), FilterEvaluator.LikeToRegex("C50%"));
    }

    #endregion

    #region IN

    [Theory]
    [InlineData("1,2,3", "2", true)]
    [InlineData("1, 2 ,3", "2", true)]
    [InlineData("1,2,3", "4", false)]
    [InlineData("", "2", false)]
    [InlineData("2", "2", true)]
    [InlineData("a,,b", "", false)]
    public void Matches_InTestsCommaSeparatedMembership(string list, string value, bool expected)
    {
        Assert.Equal(expected, FilterEvaluator.Matches(value, Condition(FilterOperator.In, list)));
    }

    #endregion

    #region BETWEEN and ordering

    [Theory]
    [InlineData("20260101", true)]
    [InlineData("20260630", true)]
    [InlineData("20261231", true)]
    [InlineData("20251231", false)]
    [InlineData("20270101", false)]
    public void Matches_BetweenIsInclusiveAtBothEnds(string value, bool expected)
    {
        var condition = Condition(FilterOperator.Between, "20260101", "20261231");
        Assert.Equal(expected, FilterEvaluator.Matches(value, condition));
    }

    [Fact]
    public void Matches_BetweenTreatsAPartialDateAsShorterText()
    {
        // Documents the ordinal-string semantics: "2026" sorts before "20260101"
        // because it is a prefix, so a partial date falls outside a full-date range.
        var condition = Condition(FilterOperator.Between, "20260101", "20261231");
        Assert.False(FilterEvaluator.Matches("2026", condition));

        // Comparing the year part against year bounds is the way to ask that question.
        var yearCondition = Condition(FilterOperator.Between, "2026", "2026", part: FieldPart.Year);
        Assert.True(FilterEvaluator.Matches("20260315", yearCondition));
    }

    [Fact]
    public void Matches_BetweenTreatsABlankBoundAsUnbounded()
    {
        Assert.True(FilterEvaluator.Matches("20991231", Condition(FilterOperator.Between, "20260101", "")));
        Assert.True(FilterEvaluator.Matches("19000101", Condition(FilterOperator.Between, "", "20261231")));
        Assert.False(FilterEvaluator.Matches("20250101", Condition(FilterOperator.Between, "20260101", "")));
    }

    [Theory]
    [InlineData(FilterOperator.GreaterThan, "20260101", true)]
    [InlineData(FilterOperator.GreaterThan, "20260315", false)]
    [InlineData(FilterOperator.GreaterOrEqual, "20260315", true)]
    [InlineData(FilterOperator.LessThan, "20260401", true)]
    [InlineData(FilterOperator.LessThan, "20260315", false)]
    [InlineData(FilterOperator.LessOrEqual, "20260315", true)]
    public void Matches_OrderingOperators(FilterOperator op, string target, bool expected)
    {
        Assert.Equal(expected, FilterEvaluator.Matches("20260315", Condition(op, target)));
    }

    #endregion

    #region Emptiness

    [Theory]
    [InlineData(null, true)]
    [InlineData("", true)]
    [InlineData("   ", true)]
    [InlineData("0", false)]
    public void Matches_IsEmptyTreatsWhitespaceAsEmpty(string? value, bool expected)
    {
        Assert.Equal(expected, FilterEvaluator.Matches(value, Condition(FilterOperator.IsEmpty)));
        Assert.Equal(!expected, FilterEvaluator.Matches(value, Condition(FilterOperator.IsNotEmpty)));
    }

    [Fact]
    public void Matches_MissingValueFailsAValueOperatorRatherThanThrowing()
    {
        Assert.False(FilterEvaluator.Matches(null, Condition(FilterOperator.Equals, "C509")));
        Assert.False(FilterEvaluator.Matches(null, Condition(FilterOperator.Like, "C50%")));
        Assert.True(FilterEvaluator.Matches(null, Condition(FilterOperator.NotEquals, "C509")));
    }

    #endregion

    #region Part applied to the compared value

    [Fact]
    public void Matches_AppliesThePartBeforeComparing()
    {
        var yearIs2026 = Condition(FilterOperator.Equals, "2026", part: FieldPart.Year);

        Assert.True(FilterEvaluator.Matches("20260315", yearIs2026));
        Assert.False(FilterEvaluator.Matches("20250315", yearIs2026));
    }

    [Fact]
    public void Matches_PartStripsTheTimeOffAnHl7Timestamp()
    {
        var condition = Condition(FilterOperator.Equals, "20260315", part: FieldPart.Date);
        Assert.True(FilterEvaluator.Matches("20260315143000", condition));
    }

    #endregion

    #region Chaining

    private static Func<FilterCondition, string?> Values(Dictionary<string, string> values) =>
        condition => values.TryGetValue(condition.FieldId, out var value) ? value : "";

    [Fact]
    public void Evaluate_EmptyConditionListMatchesEverything()
    {
        Assert.True(FilterEvaluator.Evaluate(new List<FilterCondition>(), _ => ""));
        Assert.True(FilterEvaluator.Evaluate(null, _ => ""));
    }

    [Fact]
    public void Evaluate_SingleConditionIgnoresItsConjunction()
    {
        var conditions = new List<FilterCondition>
        {
            Condition(FilterOperator.Equals, "C509", conjunction: FilterConjunction.Or)
        };

        Assert.True(FilterEvaluator.Evaluate(conditions, _ => "C509"));
        Assert.False(FilterEvaluator.Evaluate(conditions, _ => "C449"));
    }

    [Fact]
    public void Evaluate_AndRequiresBothConditions()
    {
        var conditions = new List<FilterCondition>
        {
            Condition(FilterOperator.Equals, "C509", fieldId: "site"),
            Condition(FilterOperator.Equals, "2026", part: FieldPart.Year, fieldId: "dx")
        };

        Assert.True(FilterEvaluator.Evaluate(conditions, Values(new() { ["site"] = "C509", ["dx"] = "20260315" })));
        Assert.False(FilterEvaluator.Evaluate(conditions, Values(new() { ["site"] = "C449", ["dx"] = "20260315" })));
        Assert.False(FilterEvaluator.Evaluate(conditions, Values(new() { ["site"] = "C509", ["dx"] = "20250315" })));
    }

    [Fact]
    public void Evaluate_OrAcceptsEitherCondition()
    {
        var conditions = new List<FilterCondition>
        {
            Condition(FilterOperator.Equals, "C509", fieldId: "site"),
            Condition(FilterOperator.Equals, "C449", fieldId: "site", conjunction: FilterConjunction.Or)
        };

        Assert.True(FilterEvaluator.Evaluate(conditions, Values(new() { ["site"] = "C509" })));
        Assert.True(FilterEvaluator.Evaluate(conditions, Values(new() { ["site"] = "C449" })));
        Assert.False(FilterEvaluator.Evaluate(conditions, Values(new() { ["site"] = "C619" })));
    }

    [Fact]
    public void Evaluate_FoldsLeftToRightWithoutPrecedence()
    {
        // A AND B OR C is (A AND B) OR C, not A AND (B OR C).
        var conditions = new List<FilterCondition>
        {
            Condition(FilterOperator.Equals, "yes", fieldId: "a"),
            Condition(FilterOperator.Equals, "yes", fieldId: "b"),
            Condition(FilterOperator.Equals, "yes", fieldId: "c", conjunction: FilterConjunction.Or)
        };

        // A false, B false, C true -> (false AND false) OR true = true.
        // Under the other reading, A AND (B OR C) would be false.
        Assert.True(FilterEvaluator.Evaluate(conditions,
            Values(new() { ["a"] = "no", ["b"] = "no", ["c"] = "yes" })));

        Assert.False(FilterEvaluator.Evaluate(conditions,
            Values(new() { ["a"] = "yes", ["b"] = "no", ["c"] = "no" })));

        Assert.True(FilterEvaluator.Evaluate(conditions,
            Values(new() { ["a"] = "yes", ["b"] = "yes", ["c"] = "no" })));
    }

    [Fact]
    public void Evaluate_SkipsValueLookupsThatCannotChangeTheResult()
    {
        var conditions = new List<FilterCondition>
        {
            Condition(FilterOperator.Equals, "no", fieldId: "a"),
            Condition(FilterOperator.Equals, "yes", fieldId: "b")
        };

        var read = new List<string>();

        FilterEvaluator.Evaluate(conditions, condition =>
        {
            read.Add(condition.FieldId);
            return "yes";
        });

        // The AND is already settled by the failing first condition.
        Assert.Equal(new[] { "a" }, read);
    }

    #endregion

    #region Describe

    [Fact]
    public void Describe_RendersConditionsAsSqlLikeText()
    {
        var filter = new FilterDefinition { FileType = "xml" };
        filter.Conditions.Add(Condition(FilterOperator.Equals, "2026", part: FieldPart.Year, fieldId: "dateOfDiagnosis"));
        filter.Conditions.Add(Condition(FilterOperator.Like, "C50%", fieldId: "primarySite"));
        filter.Conditions.Add(Condition(FilterOperator.IsEmpty, fieldId: "sex", conjunction: FilterConjunction.Or));

        Assert.Equal(
            "LEFT(dateOfDiagnosis,4) = '2026' AND primarySite LIKE 'C50%' OR sex IS EMPTY",
            filter.Describe());
    }

    [Fact]
    public void Describe_RendersBetweenWithBothBounds()
    {
        var filter = new FilterDefinition();
        filter.Conditions.Add(Condition(FilterOperator.Between, "20260101", "20261231", fieldId: "dateOfDiagnosis"));

        Assert.Equal("dateOfDiagnosis BETWEEN '20260101' AND '20261231'", filter.Describe());
    }

    [Fact]
    public void Describe_UsesTheSuppliedFieldNamer()
    {
        var filter = new FilterDefinition();
        filter.Conditions.Add(Condition(FilterOperator.Equals, "C509", fieldId: "primarySite"));

        Assert.Equal("Primary Site = 'C509'", filter.Describe(_ => "Primary Site"));
    }

    [Fact]
    public void Describe_ReturnsEmptyForAnEmptyFilter()
    {
        Assert.Equal("", new FilterDefinition().Describe());
    }

    #endregion
}
