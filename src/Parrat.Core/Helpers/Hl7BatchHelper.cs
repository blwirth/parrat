namespace Parrat.Core.Helpers;

/// <summary>
/// Recognizes the HL7 v2 batch protocol envelope segments that may wrap a file
/// of messages (HL7 v2.5.1 chapter 2.10):
///
///   FHS  file header      — at most one, first line of the file
///   BHS  batch header     — one per batch; a file may contain several batches
///   BTS  batch trailer    — closes a BHS
///   FTS  file trailer     — closes the FHS, last line of the file
///
/// PARRAT works at the message level and does not use batch metadata, but the
/// segments must still be recognized so they are never mistaken for part of a
/// message. Without this, trailers land inside whatever message precedes them.
/// </summary>
public static class Hl7BatchHelper
{
    private static readonly HashSet<string> EnvelopeIds =
        new(StringComparer.Ordinal) { "FHS", "BHS", "BTS", "FTS" };

    /// <summary>The segment identifiers treated as batch envelope, not message content.</summary>
    public static IReadOnlyCollection<string> EnvelopeSegmentIds => EnvelopeIds;

    /// <summary>
    /// True if the line is a batch envelope segment (FHS, BHS, BTS or FTS).
    /// The line is matched on its segment identifier followed by a field
    /// separator, so narrative text merely beginning with those letters is not
    /// mistaken for an envelope segment.
    /// </summary>
    public static bool IsEnvelopeSegment(string? line)
    {
        if (line == null) return false;

        var trimmed = line.Trim();
        if (trimmed.Length < 4) return false;
        if (trimmed[3] != '|') return false;

        return EnvelopeIds.Contains(trimmed[..3]);
    }

    /// <summary>
    /// Removes batch envelope segments from HL7 content, leaving only message
    /// lines. Line endings are preserved as they appear in the input.
    /// </summary>
    public static string StripEnvelopeSegments(string? content)
    {
        if (string.IsNullOrEmpty(content))
            return content ?? string.Empty;

        // Nothing to do for the common case of a file with no batch wrapper.
        if (!ContainsEnvelopeSegment(content))
            return content;

        var normalized = content.Replace("\r\n", "\n").Replace("\r", "\n");
        var kept = normalized.Split('\n').Where(line => !IsEnvelopeSegment(line));

        return string.Join("\n", kept);
    }

    /// <summary>True if the content contains at least one batch envelope segment.</summary>
    public static bool ContainsEnvelopeSegment(string? content)
    {
        if (string.IsNullOrEmpty(content))
            return false;

        var normalized = content.Replace("\r\n", "\n").Replace("\r", "\n");
        return normalized.Split('\n').Any(IsEnvelopeSegment);
    }
}
