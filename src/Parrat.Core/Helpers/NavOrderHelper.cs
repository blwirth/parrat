using System.Data;

namespace Parrat.Core.Helpers;

/// <summary>
/// Steps through records in the order the navigation grid is showing them.
///
/// Record indices are load order, but the grid is a view over them: the user
/// can sort by any column, and a filter or search can hide rows. Walking the
/// indices means Previous and Next disagree with what is on screen — sort by
/// diagnosis date and Next jumps somewhere arbitrary, apply a filter and it
/// steps onto records that are not displayed at all. Walking the view keeps
/// the buttons and the grid telling the same story.
/// </summary>
public static class NavOrderHelper
{
    /// <summary>1-based record number column, which the grid displays.</summary>
    public const string IndexColumn = "Index";

    /// <summary>
    /// The record to move to from <paramref name="currentIndex"/>, stepping
    /// <paramref name="step"/> rows through the view's current order, or -1
    /// when there is nowhere to go.
    ///
    /// When the current record is not in the view — a filter has just hidden
    /// it — this returns the view's first or last record according to the
    /// direction, so navigation lands somewhere visible rather than stalling.
    /// </summary>
    public static int NextVisibleIndex(DataView? view, int currentIndex, int step)
    {
        if (view == null || view.Count == 0 || step == 0)
            return -1;

        int position = PositionOf(view, currentIndex);

        if (position < 0)
            return RecordIndexAt(view, step > 0 ? 0 : view.Count - 1);

        int target = position + step;
        if (target < 0 || target >= view.Count)
            return -1;

        return RecordIndexAt(view, target);
    }

    /// <summary>
    /// Where <paramref name="recordIndex"/> sits in the view's current order, or
    /// -1 when the view is not showing it.
    /// </summary>
    public static int PositionOf(DataView? view, int recordIndex)
    {
        if (view == null || recordIndex < 0)
            return -1;

        for (int i = 0; i < view.Count; i++)
        {
            if (RecordIndexAt(view, i) == recordIndex)
                return i;
        }

        return -1;
    }

    /// <summary>The 0-based record index of the row at a view position, or -1.</summary>
    public static int RecordIndexAt(DataView? view, int position)
    {
        if (view == null || position < 0 || position >= view.Count)
            return -1;

        var value = view[position][IndexColumn];
        if (value == null || value == DBNull.Value)
            return -1;

        try
        {
            // The column is 1-based for display; callers work in 0-based indices.
            return Convert.ToInt32(value) - 1;
        }
        catch (Exception ex) when (ex is FormatException or InvalidCastException or OverflowException)
        {
            return -1;
        }
    }
}
