using System.Text;
using Parrat.Core.Helpers;

namespace Parrat.Core.Services;

/// <summary>The file formats PARRAT can open, as identified from content.</summary>
public enum DetectedFileFormat
{
    /// <summary>Content did not match any supported format.</summary>
    Unknown,
    Hl7,
    NaaccrXml,
    EpathDat,
    /// <summary>
    /// Readable text that is not a supported record format — typically a raw
    /// pathology narrative destined for Convert TXT to HL7.
    /// </summary>
    PlainText
}

/// <summary>
/// Identifies a file's format from its content rather than its extension.
/// Extensions are unreliable in practice: HL7 arrives as .txt as often as .hl7,
/// and .txt is also used for raw pathology narrative, so only the content can
/// distinguish them.
/// </summary>
public static class FileFormatDetector
{
    /// <summary>Bytes inspected when detecting from a file. Ample for any header.</summary>
    private const int DetectionByteLimit = 64 * 1024;

    /// <summary>Minimum pipe-delimited field count for ePath, matching the .dat validator.</summary>
    private const int MinEpathFieldCount = 20;

    /// <summary>Identifies the format of already-loaded content.</summary>
    public static DetectedFileFormat Detect(string? content)
    {
        if (string.IsNullOrWhiteSpace(content))
            return DetectedFileFormat.Unknown;

        var lines = content.Replace("\r\n", "\n").Replace("\r", "\n")
            .Split('\n', StringSplitOptions.RemoveEmptyEntries);

        var firstLine = lines.Select(l => l.Trim())
            .FirstOrDefault(l => l.Length > 0);

        if (firstLine == null)
            return DetectedFileFormat.Unknown;

        // HL7: a message header, or a batch envelope wrapping one.
        if (firstLine.StartsWith("MSH|", StringComparison.Ordinal) ||
            Hl7BatchHelper.IsEnvelopeSegment(firstLine))
        {
            return DetectedFileFormat.Hl7;
        }

        // XML: check the root element rather than assuming, so non-NAACCR XML
        // is reported as unsupported instead of failing deeper in the loader.
        if (firstLine.StartsWith("<", StringComparison.Ordinal))
        {
            return content.Contains("<NaaccrData", StringComparison.Ordinal) ||
                   content.Contains(":NaaccrData", StringComparison.Ordinal)
                ? DetectedFileFormat.NaaccrXml
                : DetectedFileFormat.Unknown;
        }

        // Some senders prepend blank or comment lines before the first MSH.
        if (lines.Any(l => l.TrimStart().StartsWith("MSH|", StringComparison.Ordinal)))
            return DetectedFileFormat.Hl7;

        // ePath: pipe-delimited flat records with a large fixed field count.
        if (firstLine.Contains('|') &&
            EpathParserService.SplitEpathLine(firstLine).Length >= MinEpathFieldCount)
        {
            return DetectedFileFormat.EpathDat;
        }

        return DetectedFileFormat.PlainText;
    }

    /// <summary>
    /// Identifies a file's format by inspecting its leading content. Returns
    /// <see cref="DetectedFileFormat.Unknown"/> if the file cannot be read.
    /// </summary>
    public static DetectedFileFormat DetectFile(string filePath)
    {
        try
        {
            return Detect(ReadHead(filePath));
        }
        catch (IOException)
        {
            return DetectedFileFormat.Unknown;
        }
        catch (UnauthorizedAccessException)
        {
            return DetectedFileFormat.Unknown;
        }
    }

    /// <summary>Reads at most <see cref="DetectionByteLimit"/> bytes of text from a file.</summary>
    private static string ReadHead(string filePath)
    {
        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);

        var buffer = new char[DetectionByteLimit];
        var read = reader.Read(buffer, 0, buffer.Length);

        return new string(buffer, 0, read);
    }

    /// <summary>
    /// A human-readable name for the detected format, for use in messages.
    /// </summary>
    public static string DescribeFormat(DetectedFileFormat format) => format switch
    {
        DetectedFileFormat.Hl7 => "HL7",
        DetectedFileFormat.NaaccrXml => "NAACCR XML",
        DetectedFileFormat.EpathDat => "ePath .dat",
        DetectedFileFormat.PlainText => "plain text",
        _ => "unrecognized"
    };
}
