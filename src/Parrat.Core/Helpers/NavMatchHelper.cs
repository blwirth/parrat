using System.Data;

namespace Parrat.Core.Helpers;

/// <summary>
/// Narrows the navigation grid to the records that satisfy both the search box
/// and the record filter.
///
/// The mechanism matters at scale. Writing the surviving indices into the row
/// filter — "Index IN (1,2,3,…)" — builds an expression that grows with the
/// result set: a few thousand matches is a multi-tens-of-KB string that DataView
/// re-parses on every keystroke. Instead each row carries a hidden Match column
/// and the row filter is the constant "Match = true", so applying a filter is a
/// single pass over the table no matter how many records match.
/// </summary>
public static class NavMatchHelper
{
    /// <summary>Hidden boolean column the nav tables carry for this purpose.</summary>
    public const string MatchColumn = "Match";

    /// <summary>Constant row filter expression; the work happens in the column.</summary>
    public const string MatchRowFilter = "Match = true";

    /// <summary>Adds the Match column to a nav table, defaulted to visible.</summary>
    public static void AddMatchColumn(DataTable table)
    {
        if (table == null || table.Columns.Contains(MatchColumn))
            return;

        table.Columns.Add(MatchColumn, typeof(bool)).DefaultValue = true;
    }

    /// <summary>
    /// Marks each row matched or not and applies the row filter. Both index sets
    /// are 0-based record indices; a null set means that constraint is not
    /// active, so passing null for both shows everything.
    /// </summary>
    public static void Apply(DataTable? table, IReadOnlyCollection<int>? searchMatches, IReadOnlyCollection<int>? filterMatches)
    {
        if (table == null)
            return;

        AddMatchColumn(table);

        // Dropped before the rows are touched: with the filter live, every
        // changed cell re-evaluates the view, which turns one pass into many.
        table.DefaultView.RowFilter = string.Empty;

        var search = searchMatches == null ? null : new HashSet<int>(searchMatches);
        var filter = filterMatches == null ? null : new HashSet<int>(filterMatches);

        for (int i = 0; i < table.Rows.Count; i++)
        {
            var row = table.Rows[i];

            // The Index column is 1-based in the grid; record indices are not.
            int recordIndex = row["Index"] is int index ? index - 1 : i;

            bool visible = (search == null || search.Contains(recordIndex))
                        && (filter == null || filter.Contains(recordIndex));

            if (!Equals(row[MatchColumn], visible))
                row[MatchColumn] = visible;
        }

        table.DefaultView.RowFilter = MatchRowFilter;
    }
}
