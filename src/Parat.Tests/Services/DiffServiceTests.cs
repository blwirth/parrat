using Parat.Core.Models;
using Parat.Core.Services;
using Xunit;

namespace Parat.Tests.Services;

public class DiffServiceTests
{
    private readonly DiffService _service = new();

    [Fact]
    public void GetDiffLines_IdenticalLines_AllUnchanged()
    {
        string[] linesA = { "line1", "line2", "line3" };
        string[] linesB = { "line1", "line2", "line3" };

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(3, result.Count);
        Assert.All(result, line => Assert.Equal(DiffStatus.Unchanged, line.Status));
    }

    [Fact]
    public void GetDiffLines_DetectsAddedLines()
    {
        string[] linesA = { "line1", "line3" };
        string[] linesB = { "line1", "line2", "line3" };

        var result = _service.GetDiffLines(linesA, linesB);

        var added = result.Where(r => r.Status == DiffStatus.Added).ToList();
        Assert.Single(added);
        Assert.Equal("line2", added[0].ContentB);
    }

    [Fact]
    public void GetDiffLines_DetectsDeletedLines()
    {
        string[] linesA = { "line1", "line2", "line3" };
        string[] linesB = { "line1", "line3" };

        var result = _service.GetDiffLines(linesA, linesB);

        var deleted = result.Where(r => r.Status == DiffStatus.Deleted).ToList();
        Assert.Single(deleted);
        Assert.Equal("line2", deleted[0].ContentA);
    }

    [Fact]
    public void GetDiffLines_CompletelyDifferentContent()
    {
        string[] linesA = { "alpha", "beta" };
        string[] linesB = { "gamma", "delta" };

        var result = _service.GetDiffLines(linesA, linesB);

        var deleted = result.Where(r => r.Status == DiffStatus.Deleted).ToList();
        var added = result.Where(r => r.Status == DiffStatus.Added).ToList();

        Assert.Equal(2, deleted.Count);
        Assert.Equal(2, added.Count);
    }

    [Fact]
    public void GetDiffLines_EmptyA_AllAdditions()
    {
        string[] linesA = Array.Empty<string>();
        string[] linesB = { "new1", "new2" };

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(2, result.Count);
        Assert.All(result, line => Assert.Equal(DiffStatus.Added, line.Status));
    }

    [Fact]
    public void GetDiffLines_EmptyB_AllDeletions()
    {
        string[] linesA = { "old1", "old2" };
        string[] linesB = Array.Empty<string>();

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(2, result.Count);
        Assert.All(result, line => Assert.Equal(DiffStatus.Deleted, line.Status));
    }

    [Fact]
    public void GetDiffLines_BothEmpty_ReturnsEmpty()
    {
        var result = _service.GetDiffLines(Array.Empty<string>(), Array.Empty<string>());
        Assert.Empty(result);
    }

    [Fact]
    public void GetDiffLines_NullInputs_TreatedAsEmpty()
    {
        var result = _service.GetDiffLines(null!, null!);
        Assert.Empty(result);
    }

    [Fact]
    public void GetDiffLines_CorrectLineNumbersForUnchanged()
    {
        string[] linesA = { "same1", "same2" };
        string[] linesB = { "same1", "same2" };

        var result = _service.GetDiffLines(linesA, linesB);

        Assert.Equal(1, result[0].LineNumA);
        Assert.Equal(1, result[0].LineNumB);
        Assert.Equal(2, result[1].LineNumA);
        Assert.Equal(2, result[1].LineNumB);
    }

    [Fact]
    public void GetDiffLines_AddedLines_LineNumAIsNull()
    {
        string[] linesA = { "same" };
        string[] linesB = { "same", "added" };

        var result = _service.GetDiffLines(linesA, linesB);

        var added = result.First(r => r.Status == DiffStatus.Added);
        Assert.Null(added.LineNumA);
        Assert.Equal(2, added.LineNumB);
    }

    [Fact]
    public void GetDiffLines_DeletedLines_LineNumBIsNull()
    {
        string[] linesA = { "same", "deleted" };
        string[] linesB = { "same" };

        var result = _service.GetDiffLines(linesA, linesB);

        var deleted = result.First(r => r.Status == DiffStatus.Deleted);
        Assert.Equal(2, deleted.LineNumA);
        Assert.Null(deleted.LineNumB);
    }

    [Fact]
    public void GetDiffLines_InterleavedChanges()
    {
        string[] linesA = { "common", "only-in-a", "also-common" };
        string[] linesB = { "common", "only-in-b", "also-common" };

        var result = _service.GetDiffLines(linesA, linesB);

        var unchanged = result.Where(r => r.Status == DiffStatus.Unchanged).ToList();
        Assert.Equal(2, unchanged.Count);
        Assert.Equal("common", unchanged[0].ContentA);
        Assert.Equal("also-common", unchanged[1].ContentA);
    }

    [Fact]
    public void GetDiffLines_SingleLineInputs()
    {
        var result = _service.GetDiffLines(new[] { "a" }, new[] { "b" });

        Assert.Equal(2, result.Count);
        Assert.Single(result.Where(r => r.Status == DiffStatus.Deleted));
        Assert.Single(result.Where(r => r.Status == DiffStatus.Added));
    }
}
