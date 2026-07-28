namespace Parrat.Core.Helpers;

/// <summary>
/// Reads one field out of an HL7 segment without splitting the whole segment.
///
/// <c>segment.Split('|')[n]</c> allocates an array and a string for every field
/// in order to read one. On OBX segments — where field 5 carries the report
/// narrative — that repeats the entire text of a file in throwaway strings.
/// </summary>
public static class Hl7FieldHelper
{
    private const char FieldSeparator = '|';

    /// <summary>
    /// Returns the field at <paramref name="fieldIndex"/>, counting the segment
    /// id as field 0. Returns an empty string when the segment is blank or has
    /// no such field — matching <c>Split('|')</c> indexing exactly.
    /// </summary>
    public static string GetField(string? segment, int fieldIndex)
    {
        if (!TryGetFieldBounds(segment, fieldIndex, out var start, out var length))
            return "";

        return length == 0 ? "" : segment!.Substring(start, length);
    }

    /// <summary>
    /// Locates a field within the segment without copying it, so callers that
    /// only need to append or inspect the text can avoid the allocation.
    /// Returns false when the segment is blank or has no such field.
    /// </summary>
    public static bool TryGetFieldBounds(string? segment, int fieldIndex, out int start, out int length)
    {
        start = 0;
        length = 0;

        if (string.IsNullOrWhiteSpace(segment) || fieldIndex < 0)
            return false;

        int fieldStart = 0;
        int current = 0;

        for (int i = 0; i <= segment.Length; i++)
        {
            if (i != segment.Length && segment[i] != FieldSeparator)
                continue;

            if (current == fieldIndex)
            {
                start = fieldStart;
                length = i - fieldStart;
                return true;
            }

            current++;
            fieldStart = i + 1;
        }

        return false;
    }
}
