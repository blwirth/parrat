using System.Data;
using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class NavMatchHelperTests
{
    /// <summary>Mirrors the shape of the nav grid tables: 1-based Index column.</summary>
    private static DataTable BuildNavTable(int recordCount)
    {
        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("nameLast", typeof(string));

        for (int i = 0; i < recordCount; i++)
            table.Rows.Add(false, i + 1, $"Patient{i}");

        return table;
    }

    private static int[] VisibleRecordIndices(DataTable table) =>
        table.DefaultView.Cast<DataRowView>().Select(r => (int)r["Index"] - 1).ToArray();

    [Fact]
    public void AddMatchColumn_AddsTheColumnDefaultedToVisible()
    {
        var table = BuildNavTable(3);
        NavMatchHelper.AddMatchColumn(table);

        Assert.True(table.Columns.Contains(NavMatchHelper.MatchColumn));
        Assert.True((bool)table.Columns[NavMatchHelper.MatchColumn]!.DefaultValue);
    }

    [Fact]
    public void AddMatchColumn_IsSafeToCallTwice()
    {
        var table = BuildNavTable(3);
        NavMatchHelper.AddMatchColumn(table);
        NavMatchHelper.AddMatchColumn(table);

        Assert.Equal(4, table.Columns.Count);
    }

    [Fact]
    public void Apply_WithNoConstraintsShowsEveryRecord()
    {
        var table = BuildNavTable(5);
        NavMatchHelper.Apply(table, null, null);

        Assert.Equal(new[] { 0, 1, 2, 3, 4 }, VisibleRecordIndices(table));
    }

    [Fact]
    public void Apply_WithSearchOnlyShowsTheSearchMatches()
    {
        var table = BuildNavTable(5);
        NavMatchHelper.Apply(table, new[] { 1, 3 }, null);

        Assert.Equal(new[] { 1, 3 }, VisibleRecordIndices(table));
    }

    [Fact]
    public void Apply_WithFilterOnlyShowsTheFilterMatches()
    {
        var table = BuildNavTable(5);
        NavMatchHelper.Apply(table, null, new[] { 0, 4 });

        Assert.Equal(new[] { 0, 4 }, VisibleRecordIndices(table));
    }

    [Fact]
    public void Apply_WithBothShowsTheIntersection()
    {
        var table = BuildNavTable(6);
        NavMatchHelper.Apply(table, new[] { 1, 2, 3, 4 }, new[] { 3, 4, 5 });

        Assert.Equal(new[] { 3, 4 }, VisibleRecordIndices(table));
    }

    [Fact]
    public void Apply_WithDisjointSetsShowsNothing()
    {
        var table = BuildNavTable(6);
        NavMatchHelper.Apply(table, new[] { 0, 1 }, new[] { 4, 5 });

        Assert.Empty(VisibleRecordIndices(table));
    }

    [Fact]
    public void Apply_WithAnEmptyMatchSetShowsNothing()
    {
        // Empty is "nothing matched", which is not the same as null's "no constraint".
        var table = BuildNavTable(3);
        NavMatchHelper.Apply(table, Array.Empty<int>(), null);

        Assert.Empty(VisibleRecordIndices(table));
    }

    [Fact]
    public void Apply_ReplacesThePreviousResultRatherThanNarrowingIt()
    {
        var table = BuildNavTable(5);

        NavMatchHelper.Apply(table, new[] { 0 }, null);
        NavMatchHelper.Apply(table, new[] { 3, 4 }, null);

        Assert.Equal(new[] { 3, 4 }, VisibleRecordIndices(table));
    }

    [Fact]
    public void Apply_UsesAConstantSizeRowFilterRegardlessOfMatchCount()
    {
        var small = BuildNavTable(10);
        var large = BuildNavTable(5000);

        NavMatchHelper.Apply(small, Enumerable.Range(0, 10).ToArray(), null);
        NavMatchHelper.Apply(large, Enumerable.Range(0, 5000).ToArray(), null);

        Assert.Equal(small.DefaultView.RowFilter, large.DefaultView.RowFilter);
        Assert.Equal(NavMatchHelper.MatchRowFilter, large.DefaultView.RowFilter);
        Assert.Equal(5000, large.DefaultView.Count);
    }

    [Fact]
    public void Apply_LeavesOtherColumnsUntouched()
    {
        var table = BuildNavTable(3);
        table.Rows[1]["Selected"] = true;

        NavMatchHelper.Apply(table, new[] { 0 }, null);

        Assert.True((bool)table.Rows[1]["Selected"]);
        Assert.Equal("Patient1", table.Rows[1]["nameLast"]);
    }

    [Fact]
    public void Apply_IgnoresANullTable()
    {
        NavMatchHelper.Apply(null, new[] { 1 }, null);
    }
}
