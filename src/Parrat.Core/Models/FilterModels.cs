using System.Text;

namespace Parrat.Core.Models;

/// <summary>
/// How a condition joins to the one before it. Conditions are folded strictly
/// left to right — there is no precedence and no grouping — so "A AND B OR C"
/// reads as "(A AND B) OR C".
/// </summary>
public enum FilterConjunction
{
    And,
    Or
}

/// <summary>
/// Which part of a value a condition compares. The stand-in for SQL's LEFT():
/// NAACCR and HL7 dates are zero-padded CCYYMMDD strings, so "diagnosed in 2026"
/// is a comparison against the first four characters and nothing more.
/// </summary>
public enum FieldPart
{
    /// <summary>The whole value.</summary>
    Whole,

    /// <summary>First 4 characters — LEFT(value, 4).</summary>
    Year,

    /// <summary>First 6 characters — LEFT(value, 6).</summary>
    YearMonth,

    /// <summary>First 8 characters, which drops the time off an HL7 timestamp.</summary>
    Date
}

public enum FilterOperator
{
    Equals,
    NotEquals,
    Contains,
    NotContains,
    StartsWith,
    EndsWith,

    /// <summary>SQL LIKE: % matches any run of characters, _ matches exactly one.</summary>
    Like,
    NotLike,

    /// <summary>Value holds a comma-separated list; matches if any entry is equal.</summary>
    In,

    /// <summary>Inclusive on both ends, comparing <see cref="FilterCondition.Value"/> to <see cref="FilterCondition.Value2"/>.</summary>
    Between,

    GreaterThan,
    GreaterOrEqual,
    LessThan,
    LessOrEqual,

    /// <summary>Missing, empty, or whitespace only.</summary>
    IsEmpty,
    IsNotEmpty
}

public sealed class FilterCondition
{
    /// <summary>Ignored on the first condition, which has nothing to join to.</summary>
    public FilterConjunction Conjunction { get; set; } = FilterConjunction.And;

    /// <summary>A NAACCR naaccrId for XML, or an <see cref="Hl7FilterFields"/> key for HL7.</summary>
    public string FieldId { get; set; } = string.Empty;

    public FieldPart Part { get; set; } = FieldPart.Whole;

    public FilterOperator Operator { get; set; } = FilterOperator.Equals;

    public string Value { get; set; } = string.Empty;

    /// <summary>The upper bound, used by <see cref="FilterOperator.Between"/> only.</summary>
    public string Value2 { get; set; } = string.Empty;

    public FilterCondition Clone() => new()
    {
        Conjunction = Conjunction,
        FieldId = FieldId,
        Part = Part,
        Operator = Operator,
        Value = Value,
        Value2 = Value2
    };
}

public sealed class FilterDefinition
{
    /// <summary>"xml" or "hl7", matching AppState.FileType, so a filter is not
    /// carried across a load into a file whose field ids mean nothing.</summary>
    public string FileType { get; set; } = string.Empty;

    public List<FilterCondition> Conditions { get; } = new();

    public bool IsEmpty => Conditions.Count == 0;

    /// <summary>
    /// A one-line, SQL-flavoured rendering of the conditions for the filter
    /// banner and its tooltip. Field ids are shown as given; the caller
    /// substitutes friendly names where it has them.
    /// </summary>
    public string Describe(Func<string, string>? fieldNamer = null)
    {
        if (IsEmpty)
            return string.Empty;

        var text = new StringBuilder();

        for (int i = 0; i < Conditions.Count; i++)
        {
            var condition = Conditions[i];

            if (i > 0)
                text.Append(condition.Conjunction == FilterConjunction.Or ? " OR " : " AND ");

            string field = fieldNamer?.Invoke(condition.FieldId) ?? condition.FieldId;

            text.Append(condition.Part switch
            {
                FieldPart.Year => $"LEFT({field},4)",
                FieldPart.YearMonth => $"LEFT({field},6)",
                FieldPart.Date => $"LEFT({field},8)",
                _ => field
            });

            text.Append(' ').Append(DescribeOperator(condition.Operator));

            switch (condition.Operator)
            {
                case FilterOperator.IsEmpty:
                case FilterOperator.IsNotEmpty:
                    break;
                case FilterOperator.Between:
                    text.Append($" '{condition.Value}' AND '{condition.Value2}'");
                    break;
                default:
                    text.Append($" '{condition.Value}'");
                    break;
            }
        }

        return text.ToString();
    }

    private static string DescribeOperator(FilterOperator op) => op switch
    {
        FilterOperator.Equals => "=",
        FilterOperator.NotEquals => "<>",
        FilterOperator.Contains => "CONTAINS",
        FilterOperator.NotContains => "NOT CONTAINS",
        FilterOperator.StartsWith => "STARTS WITH",
        FilterOperator.EndsWith => "ENDS WITH",
        FilterOperator.Like => "LIKE",
        FilterOperator.NotLike => "NOT LIKE",
        FilterOperator.In => "IN",
        FilterOperator.Between => "BETWEEN",
        FilterOperator.GreaterThan => ">",
        FilterOperator.GreaterOrEqual => ">=",
        FilterOperator.LessThan => "<",
        FilterOperator.LessOrEqual => "<=",
        FilterOperator.IsEmpty => "IS EMPTY",
        FilterOperator.IsNotEmpty => "IS NOT EMPTY",
        _ => op.ToString()
    };
}
