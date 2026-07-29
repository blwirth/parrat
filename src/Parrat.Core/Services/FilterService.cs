using System.Diagnostics;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

/// <summary>
/// Runs a <see cref="FilterDefinition"/> over a record set and reports which
/// records match. All the intelligence lives in <see cref="FilterEvaluator"/>
/// and the supplied <see cref="IFilterFieldSource"/>; this is the scan loop and
/// the logging around it.
/// </summary>
public class FilterService : IFilterService
{
    private readonly IParratLogger _logger;

    public FilterService() : this(NullParratLogger.Instance) { }

    public FilterService(IParratLogger logger)
    {
        _logger = logger;
    }

    public int[] GetMatchingIndices(FilterDefinition? filter, IFilterFieldSource source)
    {
        if (source == null)
            return Array.Empty<int>();

        int count = source.RecordCount;

        if (filter == null || filter.IsEmpty)
            return Enumerable.Range(0, count).ToArray();

        var conditions = filter.Conditions;
        var matches = new List<int>();
        var stopwatch = Stopwatch.StartNew();

        for (int i = 0; i < count; i++)
        {
            // Captured per record so the evaluator can short-circuit: a
            // condition whose outcome cannot change the result is never read.
            int recordIndex = i;

            if (FilterEvaluator.Evaluate(conditions, c => source.GetValue(recordIndex, c.FieldId)))
                matches.Add(i);
        }

        stopwatch.Stop();
        _logger.Log("INFO",
            $"Filter matched {matches.Count} of {count} records in {stopwatch.ElapsedMilliseconds} ms",
            "FILTER_APPLY");

        return matches.ToArray();
    }

    public IReadOnlyList<string> GetReferencedFields(FilterDefinition? filter)
    {
        if (filter == null || filter.IsEmpty)
            return Array.Empty<string>();

        return filter.Conditions
            .Select(c => c.FieldId)
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .ToList();
    }
}
