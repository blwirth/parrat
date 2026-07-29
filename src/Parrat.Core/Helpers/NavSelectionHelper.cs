using System.Data;

namespace Parrat.Core.Helpers;

/// <summary>
/// Reads the checkbox selection out of a navigation table.
///
/// Selection and filtering are separate ideas: the checkbox says which records
/// an operation acts on, the filter says which records are on screen. Reading
/// the selection from the grid's visible rows conflates the two — check ten
/// records, apply a filter that hides five of them, and an export would
/// silently write five while the record label still said ten. Reading the
/// table means a checked record stays checked whether or not it is showing.
/// </summary>
public static class NavSelectionHelper
{
    /// <summary>Checkbox column carried by every navigation table.</summary>
    public const string SelectedColumn = "Selected";

    /// <summary>1-based record number column, which the grid displays.</summary>
    public const string IndexColumn = "Index";

    /// <summary>
    /// The 0-based indices of every checked record, in load order, whether or
    /// not the record is currently visible.
    /// </summary>
    public static int[] GetCheckedIndices(DataTable? table)
    {
        if (table == null || !table.Columns.Contains(SelectedColumn))
            return Array.Empty<int>();

        var indices = new List<int>();

        foreach (DataRow row in table.Rows)
        {
            if (row.RowState == DataRowState.Deleted)
                continue;

            if (row[SelectedColumn] is not bool selected || !selected)
                continue;

            if (TryGetRecordIndex(row[IndexColumn], out var recordIndex))
                indices.Add(recordIndex);
        }

        indices.Sort();
        return indices.ToArray();
    }

    /// <summary>How many records are checked, visible or not.</summary>
    public static int GetCheckedCount(DataTable? table)
    {
        if (table == null || !table.Columns.Contains(SelectedColumn))
            return 0;

        int count = 0;

        foreach (DataRow row in table.Rows)
        {
            if (row.RowState != DataRowState.Deleted && row[SelectedColumn] is bool selected && selected)
                count++;
        }

        return count;
    }

    /// <summary>
    /// How many checked records the current view is hiding. The number an
    /// operation should mention before acting on records the user cannot see.
    /// </summary>
    public static int GetCheckedHiddenCount(DataTable? table)
    {
        if (table == null || !table.Columns.Contains(SelectedColumn))
            return 0;

        int visible = 0;

        foreach (DataRowView row in table.DefaultView)
        {
            if (row[SelectedColumn] is bool selected && selected)
                visible++;
        }

        return Math.Max(0, GetCheckedCount(table) - visible);
    }

    private static bool TryGetRecordIndex(object? indexValue, out int recordIndex)
    {
        recordIndex = -1;

        if (indexValue == null || indexValue == DBNull.Value)
            return false;

        try
        {
            // The column is 1-based for display; callers work in 0-based indices.
            recordIndex = Convert.ToInt32(indexValue) - 1;
        }
        catch (Exception ex) when (ex is FormatException or InvalidCastException or OverflowException)
        {
            return false;
        }

        return recordIndex >= 0;
    }
}
