using System.Data;
using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class NavOrderHelperTests
{
    /// <summary>Mirrors the nav grid tables: 1-based Index plus a sortable column.</summary>
    private static DataTable BuildNavTable(params string[] dates)
    {
        var table = new DataTable();
        table.Columns.Add("Selected", typeof(bool));
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("dateOfDiagnosis", typeof(string));
        NavMatchHelper.AddMatchColumn(table);

        for (int i = 0; i < dates.Length; i++)
            table.Rows.Add(false, i + 1, dates[i]);

        return table;
    }

    private static DataTable FiveRecords() =>
        BuildNavTable("20240501", "20220101", "20260301", "20230715", "20250210");

    #region Unfiltered, unsorted

    [Fact]
    public void NextVisibleIndex_StepsForwardThroughLoadOrder()
    {
        var view = FiveRecords().DefaultView;

        Assert.Equal(1, NavOrderHelper.NextVisibleIndex(view, 0, 1));
        Assert.Equal(2, NavOrderHelper.NextVisibleIndex(view, 1, 1));
    }

    [Fact]
    public void NextVisibleIndex_StepsBackward()
    {
        var view = FiveRecords().DefaultView;

        Assert.Equal(2, NavOrderHelper.NextVisibleIndex(view, 3, -1));
    }

    [Fact]
    public void NextVisibleIndex_StopsAtBothEnds()
    {
        var view = FiveRecords().DefaultView;

        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(view, 4, 1));
        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(view, 0, -1));
    }

    #endregion

    #region Sorting

    [Fact]
    public void NextVisibleIndex_FollowsTheSortRatherThanLoadOrder()
    {
        var table = FiveRecords();
        var view = table.DefaultView;
        view.Sort = "dateOfDiagnosis ASC";

        // Sorted: 2022(rec 1), 2023(rec 3), 2024(rec 0), 2025(rec 4), 2026(rec 2).
        Assert.Equal(3, NavOrderHelper.NextVisibleIndex(view, 1, 1));
        Assert.Equal(0, NavOrderHelper.NextVisibleIndex(view, 3, 1));
        Assert.Equal(4, NavOrderHelper.NextVisibleIndex(view, 0, 1));
        Assert.Equal(2, NavOrderHelper.NextVisibleIndex(view, 4, 1));
        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(view, 2, 1));
    }

    [Fact]
    public void NextVisibleIndex_StepsBackwardThroughTheSort()
    {
        var table = FiveRecords();
        var view = table.DefaultView;
        view.Sort = "dateOfDiagnosis ASC";

        Assert.Equal(0, NavOrderHelper.NextVisibleIndex(view, 4, -1));
        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(view, 1, -1));
    }

    #endregion

    #region Filtering

    [Fact]
    public void NextVisibleIndex_SkipsRecordsTheFilterIsHiding()
    {
        var table = FiveRecords();
        NavMatchHelper.Apply(table, null, new[] { 0, 2, 4 });

        Assert.Equal(2, NavOrderHelper.NextVisibleIndex(table.DefaultView, 0, 1));
        Assert.Equal(4, NavOrderHelper.NextVisibleIndex(table.DefaultView, 2, 1));
        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(table.DefaultView, 4, 1));
    }

    [Fact]
    public void NextVisibleIndex_LandsOnAVisibleRecordWhenTheCurrentOneIsHidden()
    {
        // Applying a filter can hide the record on screen. Navigation should
        // move somewhere visible rather than stall.
        var table = FiveRecords();
        NavMatchHelper.Apply(table, null, new[] { 1, 3 });

        Assert.Equal(1, NavOrderHelper.NextVisibleIndex(table.DefaultView, 0, 1));
        Assert.Equal(3, NavOrderHelper.NextVisibleIndex(table.DefaultView, 0, -1));
    }

    [Fact]
    public void NextVisibleIndex_ReturnsNothingWhenTheFilterHidesEverything()
    {
        var table = FiveRecords();
        NavMatchHelper.Apply(table, System.Array.Empty<int>(), null);

        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(table.DefaultView, 0, 1));
    }

    [Fact]
    public void NextVisibleIndex_CombinesSortingAndFiltering()
    {
        var table = FiveRecords();
        NavMatchHelper.Apply(table, null, new[] { 0, 2, 4 });
        table.DefaultView.Sort = "dateOfDiagnosis DESC";

        // Visible, newest first: 2026(rec 2), 2025(rec 4), 2024(rec 0).
        Assert.Equal(4, NavOrderHelper.NextVisibleIndex(table.DefaultView, 2, 1));
        Assert.Equal(0, NavOrderHelper.NextVisibleIndex(table.DefaultView, 4, 1));
        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(table.DefaultView, 0, 1));
    }

    #endregion

    #region Degenerate input

    [Fact]
    public void NextVisibleIndex_HandlesANullView()
    {
        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(null, 0, 1));
    }

    [Fact]
    public void NextVisibleIndex_HandlesAZeroStep()
    {
        Assert.Equal(-1, NavOrderHelper.NextVisibleIndex(FiveRecords().DefaultView, 0, 0));
    }

    [Fact]
    public void NextVisibleIndex_HandlesAnUnknownCurrentRecord()
    {
        var view = FiveRecords().DefaultView;

        Assert.Equal(0, NavOrderHelper.NextVisibleIndex(view, 99, 1));
        Assert.Equal(4, NavOrderHelper.NextVisibleIndex(view, -1, -1));
    }

    #endregion

    #region PositionOf and RecordIndexAt

    [Fact]
    public void PositionOf_ReportsTheRowsPlaceInTheCurrentOrder()
    {
        var table = FiveRecords();
        table.DefaultView.Sort = "dateOfDiagnosis ASC";

        Assert.Equal(0, NavOrderHelper.PositionOf(table.DefaultView, 1));
        Assert.Equal(4, NavOrderHelper.PositionOf(table.DefaultView, 2));
    }

    [Fact]
    public void PositionOf_ReturnsMinusOneForARecordTheViewIsHiding()
    {
        var table = FiveRecords();
        NavMatchHelper.Apply(table, null, new[] { 0 });

        Assert.Equal(-1, NavOrderHelper.PositionOf(table.DefaultView, 3));
    }

    [Fact]
    public void RecordIndexAt_ConvertsTheOneBasedColumnToARecordIndex()
    {
        var view = FiveRecords().DefaultView;

        Assert.Equal(0, NavOrderHelper.RecordIndexAt(view, 0));
        Assert.Equal(4, NavOrderHelper.RecordIndexAt(view, 4));
        Assert.Equal(-1, NavOrderHelper.RecordIndexAt(view, 99));
    }

    #endregion
}
