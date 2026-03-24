using Parat.Core.Helpers;
using Parat.Core.Services;
using Xunit;

namespace Parat.Tests.Services;

public class ParatLoggerTests : IDisposable
{
    private readonly string _tempDir;

    public ParatLoggerTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parat_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        Directory.CreateDirectory(Path.Combine(_tempDir, "data"));
        Directory.CreateDirectory(Path.Combine(_tempDir, "config"));
        Directory.CreateDirectory(Path.Combine(_tempDir, "logs"));
        PathHelper.SetRepoRoot(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    [Fact]
    public void Initialize_CreatesLogFile_AndWritesStartupEntry()
    {
        using var logger = new ParatLogger();
        logger.Initialize();

        var logFiles = Directory.GetFiles(Path.Combine(_tempDir, "logs"), "parat_*.log");
        Assert.Single(logFiles);

        var content = File.ReadAllText(logFiles[0]);
        Assert.Contains("[INFO]", content);
        Assert.Contains("[STARTUP]", content);
        Assert.Contains("Session started", content);
    }

    [Fact]
    public void Log_WritesEntryWithTimestampAndLevel()
    {
        using var logger = new ParatLogger();
        logger.Initialize();

        logger.Log("WARN", "Warning message", action: "TEST_ACTION");

        var logFiles = Directory.GetFiles(Path.Combine(_tempDir, "logs"), "parat_*.log");
        var content = File.ReadAllText(logFiles[0]);
        Assert.Contains("[WARN]", content);
        Assert.Contains("[TEST_ACTION]", content);
        Assert.Contains("Warning message", content);
        // Verify timestamp format present
        Assert.Matches(@"\[\d{4}-\d{2}-\d{2}", content);
    }

    [Fact]
    public void Log_IncludesErrorDetailsWhenProvided()
    {
        using var logger = new ParatLogger();
        logger.Initialize();

        logger.Log("ERROR", "Something broke", action: "TEST", errorDetails: "Stack trace here");

        var logFiles = Directory.GetFiles(Path.Combine(_tempDir, "logs"), "parat_*.log");
        var content = File.ReadAllText(logFiles[0]);
        Assert.Contains("[ERROR]", content);
        Assert.Contains("Error: Stack trace here", content);
    }

    [Fact]
    public void Log_DoesNothingWhenNotInitialized()
    {
        using var logger = new ParatLogger();
        // Don't call Initialize

        // Should not throw
        var ex = Record.Exception(() => logger.Log("INFO", "Test", action: "TEST"));
        Assert.Null(ex);
    }

    [Fact]
    public void LogError_SanitizesSsnFromExceptionMessage()
    {
        using var logger = new ParatLogger();
        logger.Initialize();

        var exception = new Exception("Patient 123-45-6789 had an error");
        logger.LogError("Test error", "TEST", exception);

        var logFiles = Directory.GetFiles(Path.Combine(_tempDir, "logs"), "parat_*.log");
        var content = File.ReadAllText(logFiles[0]);
        Assert.Contains("***-**-****", content);
        Assert.DoesNotContain("123-45-6789", content);
    }

    [Fact]
    public void LogError_SanitizesNineDigitNumbersFromExceptionMessage()
    {
        using var logger = new ParatLogger();
        logger.Initialize();

        var exception = new Exception("Error for patient 123456789 in system");
        logger.LogError("Test error", "TEST", exception);

        var logFiles = Directory.GetFiles(Path.Combine(_tempDir, "logs"), "parat_*.log");
        var content = File.ReadAllText(logFiles[0]);
        Assert.Contains("*********", content);
        Assert.DoesNotContain("123456789", content);
    }

    [Fact]
    public void Close_WritesShutdownEntry()
    {
        var logger = new ParatLogger();
        logger.Initialize();
        logger.Close();

        var logFiles = Directory.GetFiles(Path.Combine(_tempDir, "logs"), "parat_*.log");
        var content = File.ReadAllText(logFiles[0]);
        Assert.Contains("[SHUTDOWN]", content);
        Assert.Contains("Session ended", content);
    }
}
