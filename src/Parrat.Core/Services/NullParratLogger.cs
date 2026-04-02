using Parrat.Core.Interfaces;

namespace Parrat.Core.Services;

/// <summary>
/// A no-op logger implementation used as a default when no logger is provided.
/// This allows services to be constructed without a logger (e.g., in tests)
/// while still having all catch blocks wired to a valid IParratLogger instance.
/// </summary>
internal sealed class NullParratLogger : IParratLogger
{
    public static readonly NullParratLogger Instance = new();

    public void Initialize() { }
    public void Log(string level, string message, string? action = null, string? errorDetails = null) { }
    public void LogError(string message, string action, Exception? exception = null) { }
    public void Close() { }
    public void Dispose() { }
}
