namespace Parrat.Core.Helpers;

/// <summary>
/// Formats counted nouns for display. Writing "1 file" and "2 files" rather
/// than "1 file(s)" costs nothing and reads as though a person wrote it.
/// </summary>
public static class PluralHelper
{
    /// <summary>
    /// The singular or plural form for a count. The plural defaults to the
    /// singular with "s" appended; pass one explicitly for irregular nouns.
    /// </summary>
    public static string Noun(int count, string singular, string? plural = null)
        => count == 1 ? singular : plural ?? singular + "s";

    /// <summary>
    /// A count followed by its noun, with thousands separators — "1 file",
    /// "2 files", "1,204 messages".
    /// </summary>
    public static string Count(int count, string singular, string? plural = null)
        => $"{count:N0} {Noun(count, singular, plural)}";
}
