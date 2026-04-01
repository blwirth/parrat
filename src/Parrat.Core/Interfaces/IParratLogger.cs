namespace Parrat.Core.Interfaces;

public interface IParratLogger : IDisposable
{
    void Initialize();
    void Log(string level, string message, string? action = null, string? errorDetails = null);
    void LogError(string message, string action, Exception? exception = null);
    void Close();
}
