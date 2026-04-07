namespace Parrat.Core.Models;

public class CsvImportMapping
{
    public int CsvColumnIndex { get; set; }
    public string CsvHeader { get; set; } = string.Empty;
    public string? MappedNaaccrId { get; set; }
    public bool IsAutoMatched { get; set; }
    public bool IsSkipped => MappedNaaccrId == null;
}
