namespace Parrat.Core.Models;

/// <summary>What the restore plan decided for one tumor and field.</summary>
public enum RestoreStatus
{
    /// <summary>The original holds a different value; it will be restored.</summary>
    Restore,

    /// <summary>Current and original values already agree; nothing to do.</summary>
    AlreadyCorrect,

    /// <summary>The key was not found in the original file; left alone.</summary>
    NoMatch,

    /// <summary>The record carries no key value to match on; left alone.</summary>
    MissingKey,

    /// <summary>
    /// The key matches several original records whose values disagree, so no
    /// single value can be called "the" original; left alone. Duplicates that
    /// agree are not ambiguous and restore normally.
    /// </summary>
    Ambiguous,

    /// <summary>
    /// The original record matched but holds no value for this field.
    /// Restoring would blank the field rather than rescue it, so it is left
    /// alone and reported.
    /// </summary>
    OriginalEmpty
}

/// <summary>One tumor/field pairing in a restore plan.</summary>
public sealed class FieldRestoreRow
{
    /// <summary>0-based index of the tumor in the loaded (damaged) file.</summary>
    public int TumorIndex { get; init; }

    public string KeyValue { get; init; } = "";

    public string FieldId { get; init; } = "";

    /// <summary>The value the loaded file currently holds.</summary>
    public string CurrentValue { get; init; } = "";

    /// <summary>The original file's value; empty when no match was found.</summary>
    public string OriginalValue { get; init; } = "";

    public RestoreStatus Status { get; init; }
}

/// <summary>
/// The full change plan, computed before anything is written so every record's
/// fate is visible first. Only <see cref="RestoreStatus.Restore"/> rows alter
/// the repaired document.
/// </summary>
public sealed class FieldRestorePlan
{
    public IReadOnlyList<FieldRestoreRow> Rows { get; init; } = Array.Empty<FieldRestoreRow>();

    public int RestoreCount => Count(RestoreStatus.Restore);
    public int AlreadyCorrectCount => Count(RestoreStatus.AlreadyCorrect);
    public int NoMatchCount => Count(RestoreStatus.NoMatch);
    public int MissingKeyCount => Count(RestoreStatus.MissingKey);
    public int AmbiguousCount => Count(RestoreStatus.Ambiguous);
    public int OriginalEmptyCount => Count(RestoreStatus.OriginalEmpty);

    private int Count(RestoreStatus status) => Rows.Count(r => r.Status == status);
}
