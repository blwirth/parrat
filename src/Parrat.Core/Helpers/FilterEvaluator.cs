using System.Collections.Concurrent;
using System.Text;
using System.Text.RegularExpressions;
using Parrat.Core.Models;

namespace Parrat.Core.Helpers;

/// <summary>
/// Evaluates filter conditions against plain strings. Every value in a NAACCR
/// XML or HL7 file is a string — dates included — so all comparisons here are
/// string comparisons and nothing is parsed into a DateTime or a number.
///
/// That is not a shortcut. NAACCR dates are zero-padded CCYYMMDD, which orders
/// identically as text and as a date, so BETWEEN '20260101' AND '20261231'
/// means what the user expects without a single conversion. Coded fields are
/// fixed-width for the same reason.
///
/// This class knows nothing about XML or HL7; the caller supplies the values.
/// </summary>
public static class FilterEvaluator
{
    private const StringComparison Ci = StringComparison.OrdinalIgnoreCase;

    /// <summary>
    /// Translated LIKE patterns, kept so a scan over thousands of records
    /// compiles each pattern once rather than once per record.
    /// </summary>
    private static readonly ConcurrentDictionary<string, Regex> LikeCache = new(StringComparer.Ordinal);

    /// <summary>
    /// The leading slice of a value a condition compares. Values shorter than
    /// the requested part are returned whole rather than throwing, so a blank
    /// or truncated date simply fails to match instead of aborting the scan.
    /// </summary>
    public static string ExtractPart(string? value, FieldPart part)
    {
        if (string.IsNullOrEmpty(value) || part == FieldPart.Whole)
            return value ?? string.Empty;

        int length = part switch
        {
            FieldPart.Year => 4,
            FieldPart.YearMonth => 6,
            FieldPart.Date => 8,
            _ => value.Length
        };

        return value.Length <= length ? value : value.Substring(0, length);
    }

    /// <summary>
    /// Tests one condition against one field value. Matching is
    /// case-insensitive throughout; the ordering operators compare ordinally so
    /// fixed-width coded values sort predictably regardless of locale.
    /// </summary>
    public static bool Matches(string? fieldValue, FilterCondition condition)
    {
        if (condition == null)
            return true;

        string value = ExtractPart(fieldValue, condition.Part).Trim();

        switch (condition.Operator)
        {
            case FilterOperator.IsEmpty:
                return value.Length == 0;
            case FilterOperator.IsNotEmpty:
                return value.Length != 0;
        }

        string target = condition.Value?.Trim() ?? string.Empty;

        return condition.Operator switch
        {
            FilterOperator.Equals => string.Equals(value, target, Ci),
            FilterOperator.NotEquals => !string.Equals(value, target, Ci),
            FilterOperator.Contains => value.Contains(target, Ci),
            FilterOperator.NotContains => !value.Contains(target, Ci),
            FilterOperator.StartsWith => value.StartsWith(target, Ci),
            FilterOperator.EndsWith => value.EndsWith(target, Ci),
            FilterOperator.Like => LikeToRegex(target).IsMatch(value),
            FilterOperator.NotLike => !LikeToRegex(target).IsMatch(value),
            FilterOperator.In => MatchesAnyOf(value, target),
            FilterOperator.Between => IsBetween(value, target, condition.Value2?.Trim() ?? string.Empty),
            FilterOperator.GreaterThan => Compare(value, target) > 0,
            FilterOperator.GreaterOrEqual => Compare(value, target) >= 0,
            FilterOperator.LessThan => Compare(value, target) < 0,
            FilterOperator.LessOrEqual => Compare(value, target) <= 0,
            _ => false
        };
    }

    /// <summary>
    /// Folds the conditions left to right with their own AND/OR, so
    /// "A AND B OR C" is "(A AND B) OR C". No precedence, no grouping — what
    /// the dialog shows top to bottom is the order it is evaluated in.
    /// An empty condition list matches everything.
    /// </summary>
    public static bool Evaluate(IReadOnlyList<FilterCondition>? conditions, Func<FilterCondition, string?> valueOf)
    {
        if (conditions == null || conditions.Count == 0)
            return true;

        bool result = Matches(valueOf(conditions[0]), conditions[0]);

        for (int i = 1; i < conditions.Count; i++)
        {
            var condition = conditions[i];

            // Short-circuit only where the outcome is already settled. AND with
            // a false accumulator and OR with a true one cannot change, and
            // skipping the value lookup is what makes a wide filter over
            // thousands of records cheap.
            if (condition.Conjunction == FilterConjunction.And)
            {
                if (!result) continue;
                result = Matches(valueOf(condition), condition);
            }
            else
            {
                if (result) continue;
                result = Matches(valueOf(condition), condition);
            }
        }

        return result;
    }

    /// <summary>
    /// Compiles a SQL LIKE pattern: % matches any run of characters, _ matches
    /// exactly one, and everything else is literal — regex metacharacters in a
    /// value such as "C50.9" or "[see note]" are escaped, not honoured.
    /// </summary>
    public static Regex LikeToRegex(string pattern)
    {
        return LikeCache.GetOrAdd(pattern ?? string.Empty, static p =>
        {
            var expression = new StringBuilder(p.Length * 2 + 2);
            expression.Append('^');

            foreach (char c in p)
            {
                switch (c)
                {
                    case '%': expression.Append(".*"); break;
                    case '_': expression.Append('.'); break;
                    default: expression.Append(Regex.Escape(c.ToString())); break;
                }
            }

            expression.Append('$');

            return new Regex(
                expression.ToString(),
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Singleline);
        });
    }

    /// <summary>
    /// Comma-separated list membership. Entries are trimmed, so "1, 2 ,3"
    /// behaves the same as "1,2,3", and empty entries are ignored.
    /// </summary>
    private static bool MatchesAnyOf(string value, string list)
    {
        if (list.Length == 0)
            return false;

        foreach (var entry in list.Split(','))
        {
            var trimmed = entry.Trim();
            if (trimmed.Length > 0 && string.Equals(value, trimmed, Ci))
                return true;
        }

        return false;
    }

    /// <summary>
    /// Inclusive at both ends. A blank bound is treated as unbounded on that
    /// side, so a half-filled range still does something useful.
    /// </summary>
    private static bool IsBetween(string value, string low, string high)
    {
        if (low.Length > 0 && Compare(value, low) < 0)
            return false;

        if (high.Length > 0 && Compare(value, high) > 0)
            return false;

        return true;
    }

    private static int Compare(string left, string right) =>
        string.Compare(left, right, StringComparison.OrdinalIgnoreCase);
}
