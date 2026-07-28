using System.Text;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

/// <summary>
/// Loads and saves HL7 files. Uses Hl7Parser to parse message content.
/// Ported from Import-Hl7File in button-handlers/btnOpen.ps1.
/// </summary>
public class Hl7FileService : IHl7FileService
{
    private readonly IHl7Parser _parser;

    public Hl7FileService(IHl7Parser parser)
    {
        _parser = parser;
    }

    /// <summary>Buffer size for streaming reads; large enough that IO is not the bottleneck.</summary>
    private const int ReadBufferSize = 64 * 1024;

    public List<Hl7Message> LoadHl7File(string filePath)
    {
        // Streamed a line at a time rather than read whole. Buffering the text
        // of a large file costs several copies of it — the string itself, then
        // one per line-ending normalization pass — before parsing even starts.
        // Read as ASCII, matching PS: Get-Content -Encoding ASCII
        return _parser.ParseLines(ReadLines(filePath));
    }

    private static IEnumerable<string> ReadLines(string filePath)
    {
        using var stream = new FileStream(
            filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, ReadBufferSize);
        using var reader = new StreamReader(stream, Encoding.ASCII, false, ReadBufferSize);

        string? line;
        while ((line = reader.ReadLine()) != null)
            yield return line;
    }

    public void SaveHl7File(string filePath, List<Hl7Message> messages)
    {
        var sb = new StringBuilder();
        bool first = true;

        foreach (var message in messages)
        {
            if (!first)
                sb.Append('\n');
            sb.Append(message.RawContent);
            first = false;
        }

        File.WriteAllText(filePath, sb.ToString(), Encoding.ASCII);
    }
}
