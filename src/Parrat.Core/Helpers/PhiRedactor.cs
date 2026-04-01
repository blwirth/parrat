using System.Text.RegularExpressions;

namespace Parrat.Core.Helpers;

public static partial class PhiRedactor
{
    [GeneratedRegex(@"\b\d{3}-\d{2}-\d{4}\b")]
    private static partial Regex SsnPattern();

    [GeneratedRegex(@"\b\d{9}\b")]
    private static partial Regex SsnNoDelimPattern();

    [GeneratedRegex(@"\b\d{2}/\d{2}/\d{4}\b")]
    private static partial Regex DatePattern();

    public static string Redact(string input)
    {
        if (string.IsNullOrEmpty(input)) return input;

        var result = SsnPattern().Replace(input, "***-**-****");
        result = SsnNoDelimPattern().Replace(result, "*********");
        return result;
    }
}
