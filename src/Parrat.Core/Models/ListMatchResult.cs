namespace Parrat.Core.Models;

/// <summary>
/// Outcome of matching a list of key values against the loaded tumors.
/// </summary>
public sealed class ListMatchResult
{
    /// <summary>0-based indices of every tumor whose key field matched a listed value, in load order.</summary>
    public int[] MatchedIndices { get; init; } = Array.Empty<int>();

    /// <summary>Listed values that matched no tumor at all, in the order given.</summary>
    public IReadOnlyList<string> UnmatchedValues { get; init; } = Array.Empty<string>();

    /// <summary>
    /// Listed values that matched more than one tumor. A patient-level key
    /// (an MRN, say) legitimately hits every tumor of that patient — including
    /// tumors filed under a second Patient element for the same person — so
    /// this is surfaced as a heads-up rather than treated as an error.
    /// </summary>
    public IReadOnlyList<string> MultiMatchValues { get; init; } = Array.Empty<string>();

    /// <summary>How many distinct values were searched for.</summary>
    public int ValueCount { get; init; }
}
