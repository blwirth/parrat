namespace Parrat.Core.Models;

public class CsvParseResult
{
    public string[] Headers { get; set; } = Array.Empty<string>();
    public List<string[]> Rows { get; set; } = new();
    public int ColumnCount => Headers.Length;
    public int RowCount => Rows.Count;
}
