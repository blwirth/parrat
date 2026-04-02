using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class ObxServiceTests
{
    private readonly ObxService _service = new();

    #region RepairObxInRawContent

    [Fact]
    public void RepairObxInRawContent_PadsObxWithFewerPipesThanMinFields()
    {
        var content = "MSH|^~\\&|App|Fac\nOBX|1|TX";
        var (modifiedContent, fixedCount) = _service.RepairObxInRawContent(content, 5);

        var lines = modifiedContent.Split('\n');
        var obxLine = lines.First(l => l.StartsWith("OBX|"));
        var pipeCount = obxLine.Count(c => c == '|');
        Assert.True(pipeCount >= 5,
            $"OBX should have been padded to at least 5 pipes, but has {pipeCount}");
        Assert.Equal(1, fixedCount);
    }

    [Fact]
    public void RepairObxInRawContent_DoesNotModifyObxWithEnoughPipes()
    {
        var content = "OBX|1|TX|CODE^Desc|sub|Value|units|ref|flags";
        var (modifiedContent, fixedCount) = _service.RepairObxInRawContent(content, 5);

        Assert.Equal(0, fixedCount);
        Assert.Equal(content, modifiedContent);
    }

    [Fact]
    public void RepairObxInRawContent_LeavesNonObxSegmentsUntouched()
    {
        var content = "MSH|^~\\&\nPID|1|short";
        var (modifiedContent, _) = _service.RepairObxInRawContent(content, 5);

        Assert.Equal(content, modifiedContent);
    }

    [Fact]
    public void RepairObxInRawContent_HandlesMixedPaddingNeeds()
    {
        var content = "OBX|1|TX|CODE^Desc|sub|Value|units|ref|flags\nOBX|2|TX\nOBX|3|TX|CODE|sub|Value|units|ref|flags|extra";
        var (_, fixedCount) = _service.RepairObxInRawContent(content, 5);

        Assert.Equal(1, fixedCount); // Only the second OBX needs fixing
    }

    [Fact]
    public void RepairObxInRawContent_NormalizesCrlfToLf()
    {
        var content = "MSH|^~\\&\r\nOBX|1|TX";
        var (modifiedContent, _) = _service.RepairObxInRawContent(content, 5);

        Assert.DoesNotContain("\r", modifiedContent);
    }

    [Fact]
    public void RepairObxInRawContent_HandlesEmptyContent()
    {
        var (_, fixedCount) = _service.RepairObxInRawContent("", 5);
        Assert.Equal(0, fixedCount);
    }

    [Fact]
    public void RepairObxInRawContent_UsesDefaultMinFields()
    {
        var (_, fixedCount) = _service.RepairObxInRawContent("OBX|1|TX");
        Assert.Equal(1, fixedCount);
    }

    #endregion

    #region RepairObxInMessages

    [Fact]
    public void RepairObxInMessages_FixesObxSegments()
    {
        var messages = new List<Hl7Message>
        {
            new() { RawContent = "MSH|^~\\&\nOBX|1|TX" }
        };
        var (_, fixedCount) = _service.RepairObxInMessages(messages, 5);

        Assert.Equal(1, fixedCount);
    }

    [Fact]
    public void RepairObxInMessages_HandlesMultipleMessages()
    {
        var messages = new List<Hl7Message>
        {
            new() { RawContent = "MSH|^~\\&\nOBX|1|TX" },
            new() { RawContent = "MSH|^~\\&\nOBX|1|TX|CODE|sub|val|u|r|f" }
        };
        var (_, fixedCount) = _service.RepairObxInMessages(messages, 5);

        Assert.Equal(1, fixedCount);
    }

    [Fact]
    public void RepairObxInMessages_HandlesEmptyList()
    {
        var (_, fixedCount) = _service.RepairObxInMessages(new List<Hl7Message>(), 5);
        Assert.Equal(0, fixedCount);
    }

    #endregion

    #region RemoveEmptyObx5FromRawContent

    [Fact]
    public void RemoveEmptyObx5FromRawContent_RemovesEmptyObx5()
    {
        var content = "MSH|^~\\&\nOBX|1|TX|CODE||Value|u|r|f\nOBX|2|TX|CODE|||||\nOBX|3|TX|CODE||More|u|r|f";
        var (modifiedContent, removedCount) = _service.RemoveEmptyObx5FromRawContent(content);

        Assert.Equal(1, removedCount);
        Assert.DoesNotContain("OBX|2", modifiedContent);
        Assert.Contains("OBX|1", modifiedContent);
        Assert.Contains("OBX|3", modifiedContent);
    }

    [Fact]
    public void RemoveEmptyObx5FromRawContent_KeepsNonEmptyObx5()
    {
        var content = "OBX|1|TX|CODE||SomeValue|u|r|f";
        var (modifiedContent, removedCount) = _service.RemoveEmptyObx5FromRawContent(content);

        Assert.Equal(0, removedCount);
        Assert.Contains("SomeValue", modifiedContent);
    }

    [Fact]
    public void RemoveEmptyObx5FromRawContent_TreatsWhitespaceAsEmpty()
    {
        var content = "OBX|1|TX|CODE||   |u|r|f";
        var (_, removedCount) = _service.RemoveEmptyObx5FromRawContent(content);

        Assert.Equal(1, removedCount);
    }

    [Fact]
    public void RemoveEmptyObx5FromRawContent_DoesNotTouchNonObx()
    {
        var content = "MSH|^~\\&|App|Fac\nPID|1||123||Smith^John";
        var (modifiedContent, removedCount) = _service.RemoveEmptyObx5FromRawContent(content);

        Assert.Equal(0, removedCount);
        Assert.Contains("MSH", modifiedContent);
        Assert.Contains("PID", modifiedContent);
    }

    [Fact]
    public void RemoveEmptyObx5FromRawContent_HandlesObxWithFewerThan6Fields()
    {
        var content = "OBX|1|TX|CODE";
        var (_, removedCount) = _service.RemoveEmptyObx5FromRawContent(content);

        Assert.Equal(1, removedCount);
    }

    [Fact]
    public void RemoveEmptyObx5FromRawContent_HandlesEmptyContent()
    {
        var (_, removedCount) = _service.RemoveEmptyObx5FromRawContent("");

        Assert.Equal(0, removedCount);
    }

    [Fact]
    public void RemoveEmptyObx5FromRawContent_NormalizesCrlf()
    {
        var content = "MSH|^~\\&\r\nOBX|1|TX|CODE||Value|u|r|f";
        var (_, removedCount) = _service.RemoveEmptyObx5FromRawContent(content);

        Assert.Equal(0, removedCount);
    }

    #endregion

    #region RemoveEmptyObx5FromMessages

    [Fact]
    public void RemoveEmptyObx5FromMessages_RemovesEmptySegments()
    {
        var messages = new List<Hl7Message>
        {
            new() { RawContent = "MSH|^~\\&\nOBX|1|TX|CODE||Text|u|r|f\nOBX|2|TX|CODE|||||" }
        };
        var (_, removedCount) = _service.RemoveEmptyObx5FromMessages(messages);

        Assert.Equal(1, removedCount);
    }

    [Fact]
    public void RemoveEmptyObx5FromMessages_HandlesMultipleMessages()
    {
        var messages = new List<Hl7Message>
        {
            new() { RawContent = "MSH|^~\\&\nOBX|1|TX|CODE|||||" },
            new() { RawContent = "MSH|^~\\&\nOBX|1|TX|CODE||HasValue|u|r|f" }
        };
        var (_, removedCount) = _service.RemoveEmptyObx5FromMessages(messages);

        Assert.Equal(1, removedCount);
    }

    [Fact]
    public void RemoveEmptyObx5FromMessages_HandlesEmptyList()
    {
        var (_, removedCount) = _service.RemoveEmptyObx5FromMessages(new List<Hl7Message>());

        Assert.Equal(0, removedCount);
    }

    #endregion
}
