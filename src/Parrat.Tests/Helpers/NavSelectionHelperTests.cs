using System.Data;
using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class NavSelectionHelperTests
{
    /// <summary>Mirrors the nav grid tables: checkbox plus a 1-based Index column.</summary>
    private static DataTable BuildNavTable(int recordCount)
    {
        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("nameLast", typeof(string));
        NavMatchHelper.AddMatchColumn(table);

        for (int i = 0; i < recordCount; i++)
            table.Rows.Add(false, i + 1, $"Patient{i}");

        return table;
    }

    private static void Check(DataTable table, params int[] recordIndices)
    {
        foreach (var index in recordIndices)
            table.Rows[index]["Selected"] = true;
    }

    #region GetCheckedIndices

    [Fact]
    public void GetCheckedIndices_ReturnsNothingWhenNothingIsChecked()
    {
        Assert.Empty(NavSelectionHelper.GetCheckedIndices(BuildNavTable(5)));
    }

    [Fact]
    public void GetCheckedIndices_ReturnsZeroBasedIndicesInLoadOrder()
    {
        var table = BuildNavTable(5);
        Check(table, 3, 0, 2);

        Assert.Equal(new[] { 0, 2, 3 }, NavSelectionHelper.GetCheckedIndices(table));
    }

    [Fact]
    public void GetCheckedIndices_IncludesRecordsTheFilterIsHiding()
    {
        // The case that made this a helper: five checked, a filter showing two
        // of them. An export must still act on all five.
        var table = BuildNavTable(10);
        Check(table, 0, 1, 2, 3, 4);
        NavMatchHelper.Apply(table, null, new[] { 3, 4 });

        Assert.Equal(2, table.DefaultView.Count);
        Assert.Equal(new[] { 0, 1, 2, 3, 4 }, NavSelectionHelper.GetCheckedIndices(table));
    }

    [Fact]
    public void GetCheckedIndices_IsUnaffectedByAFilterThatHidesEverything()
    {
        var table = BuildNavTable(4);
        Check(table, 1);
        NavMatchHelper.Apply(table, System.Array.Empty<int>(), null);

        Assert.Equal(0, table.DefaultView.Count);
        Assert.Equal(new[] { 1 }, NavSelectionHelper.GetCheckedIndices(table));
    }

    [Fact]
    public void GetCheckedIndices_HandlesANullTable()
    {
        Assert.Empty(NavSelectionHelper.GetCheckedIndices(null));
    }

    [Fact]
    public void GetCheckedIndices_HandlesATableWithoutASelectedColumn()
    {
        var table = new DataTable();
        table.Columns.Add("Index", typeof(int));
        table.Rows.Add(1);

        Assert.Empty(NavSelectionHelper.GetCheckedIndices(table));
    }

    [Fact]
    public void GetCheckedIndices_SkipsRowsWithNoIndexValue()
    {
        var table = BuildNavTable(3);
        Check(table, 0, 1);
        table.Rows[1]["Index"] = DBNull.Value;

        Assert.Equal(new[] { 0 }, NavSelectionHelper.GetCheckedIndices(table));
    }

    #endregion

    #region GetCheckedCount

    [Fact]
    public void GetCheckedCount_CountsEveryCheckedRecordRegardlessOfTheFilter()
    {
        var table = BuildNavTable(10);
        Check(table, 0, 1, 2, 3, 4);
        NavMatchHelper.Apply(table, null, new[] { 3, 4 });

        Assert.Equal(5, NavSelectionHelper.GetCheckedCount(table));
    }

    [Fact]
    public void GetCheckedCount_AgreesWithGetCheckedIndices()
    {
        var table = BuildNavTable(20);
        Check(table, 2, 7, 11, 19);
        NavMatchHelper.Apply(table, new[] { 7, 11 }, null);

        Assert.Equal(
            NavSelectionHelper.GetCheckedIndices(table).Length,
            NavSelectionHelper.GetCheckedCount(table));
    }

    [Fact]
    public void GetCheckedCount_HandlesANullTable()
    {
        Assert.Equal(0, NavSelectionHelper.GetCheckedCount(null));
    }

    #endregion

    #region GetCheckedHiddenCount

    [Fact]
    public void GetCheckedHiddenCount_IsZeroWithNoFilter()
    {
        var table = BuildNavTable(5);
        Check(table, 0, 4);

        Assert.Equal(0, NavSelectionHelper.GetCheckedHiddenCount(table));
    }

    [Fact]
    public void GetCheckedHiddenCount_CountsCheckedRecordsTheViewIsHiding()
    {
        var table = BuildNavTable(10);
        Check(table, 0, 1, 2, 3, 4);
        NavMatchHelper.Apply(table, null, new[] { 3, 4 });

        Assert.Equal(3, NavSelectionHelper.GetCheckedHiddenCount(table));
    }

    [Fact]
    public void GetCheckedHiddenCount_CountsAllOfThemWhenTheViewIsEmpty()
    {
        var table = BuildNavTable(6);
        Check(table, 0, 5);
        NavMatchHelper.Apply(table, System.Array.Empty<int>(), null);

        Assert.Equal(2, NavSelectionHelper.GetCheckedHiddenCount(table));
    }

    #endregion
}
