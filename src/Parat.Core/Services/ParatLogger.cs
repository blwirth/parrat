using Parat.Core.Helpers;
using Parat.Core.Interfaces;

namespace Parat.Core.Services;

public class ParatLogger : IParatLogger
{
    private string? _logPath;
    private Mutex? _logMutex;
    private bool _disposed;

    public void Initialize()
    {
        var logDir = PathHelper.LogsDir;
        PathHelper.EnsureDirectoryExists(logDir);

        var date = DateTime.Now.ToString("yyyyMMdd");
        _logPath = Path.Combine(logDir, $"parat_{date}.log");

        try
        {
            _logMutex = new Mutex(false, @"Local\ParatLogMutex");
        }
        catch
        {
            _logMutex = new Mutex(false);
        }

        Log("INFO", "Session started", action: "STARTUP");
    }

    public void Log(string level, string message, string? action = null, string? errorDetails = null)
    {
        if (_logPath == null) return;

        var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
        var userInfo = $"{Environment.MachineName}\\{Environment.UserName}";
        var entry = $"[{timestamp}] [{userInfo}] [{level}] [{action}] {message}";

        if (!string.IsNullOrEmpty(errorDetails))
        {
            entry += $"\n  Error: {errorDetails}";
        }

        var acquired = false;
        try
        {
            acquired = _logMutex?.WaitOne(100) ?? false;
            if (acquired)
            {
                File.AppendAllText(_logPath, entry + Environment.NewLine);
            }
            else
            {
                // Mutex busy - write to local fallback
                var fallback = Path.Combine(Path.GetTempPath(), "parat_log_fallback.txt");
                try
                {
                    File.AppendAllText(fallback, entry + Environment.NewLine);
                }
                catch
                {
                    // Silent fail
                }
            }
        }
        catch
        {
            // Silent fail - don't crash app for logging failure
        }
        finally
        {
            if (acquired)
            {
                _logMutex?.ReleaseMutex();
            }
        }
    }

    public void LogError(string message, string action, Exception? exception = null)
    {
        var sanitizedError = exception?.Message ?? string.Empty;
        sanitizedError = PhiRedactor.Redact(sanitizedError);

        Log("ERROR", message, action, sanitizedError);
    }

    public void Close()
    {
        Log("INFO", "Session ended", action: "SHUTDOWN");
        _logMutex?.Dispose();
        _logMutex = null;
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            Close();
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }
}
