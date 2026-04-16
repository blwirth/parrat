using System.Text.RegularExpressions;

namespace Parrat.Core.Helpers;

/// <summary>
/// Handles HL7 escape sequence replacement in observation values.
/// Supports: \F\ (|), \S\ (^), \R\ (~), \E\ (\), \T\ (&), \X0D\ (CR), \X0A\ (LF), \.br\ (CRLF)
/// </summary>
public static class Hl7EscapeHelper
{
    private static readonly Regex EscapeRegex = new(
        @"\\(X0D|X0A|E|F|S|T|R|\.br)\\",
        RegexOptions.Compiled);

    private static readonly Dictionary<string, string> EscapeMap = new()
    {
        ["X0D"] = "\r",
        ["X0A"] = "\n",
        ["E"] = @"\",
        ["F"] = "|",
        ["S"] = "^",
        ["T"] = "&",
        ["R"] = "~",
        [".br"] = "\r\n"
    };

    /// <summary>
    /// Replaces HL7 escape sequences in a string with their actual characters.
    /// </summary>
    public static string Unescape(string value)
    {
        if (string.IsNullOrEmpty(value))
            return value;

        return EscapeRegex.Replace(value, match =>
        {
            var key = match.Groups[1].Value;
            return EscapeMap.TryGetValue(key, out var replacement) ? replacement : match.Value;
        });
    }

    /// <summary>
    /// Escapes special HL7 characters in text for safe inclusion in a field value.
    /// </summary>
    public static string Escape(string value)
    {
        if (string.IsNullOrEmpty(value))
            return value;

        return value
            .Replace(@"\", @"\E\")
            .Replace("|", @"\F\")
            .Replace("^", @"\S\")
            .Replace("&", @"\T\")
            .Replace("~", @"\R\")
            .Replace("\r\n", @"\.br\")
            .Replace("\r", @"\.br\")
            .Replace("\n", @"\.br\");
    }

    /// <summary>
    /// Normalizes segment separators to \r for HL7 v2.x standard compliance.
    /// </summary>
    public static string NormalizeSegmentSeparators(string hl7Message)
    {
        if (string.IsNullOrEmpty(hl7Message))
            return hl7Message;

        return hl7Message.Replace("\r\n", "\r").Replace("\n", "\r");
    }
}
