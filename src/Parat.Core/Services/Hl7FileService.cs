using System.Text;
using Parat.Core.Interfaces;
using Parat.Core.Models;

namespace Parat.Core.Services;

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

    public List<Hl7Message> LoadHl7File(string filePath)
    {
        // Read as ASCII, matching PS: Get-Content -Encoding ASCII
        var content = File.ReadAllText(filePath, Encoding.ASCII);

        if (string.IsNullOrWhiteSpace(content))
            return new List<Hl7Message>();

        return _parser.Parse(content);
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
