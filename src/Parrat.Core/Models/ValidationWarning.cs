namespace Parrat.Core.Models;

public class ValidationWarning
{
    public string NaaccrId { get; set; } = string.Empty;
    public string CsvHeader { get; set; } = string.Empty;
    public int RowIndex { get; set; }
    public string Value { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}
