using System.Text;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class CsvParserService : ICsvParserService
{
    public CsvParseResult Parse(string filePath)
    {
        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Parse(stream);
    }

    public CsvParseResult Parse(Stream stream)
    {
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        var content = reader.ReadToEnd();

        var rows = ParseRows(content);

        if (rows.Count == 0)
            return new CsvParseResult();

        var headers = rows[0];
        rows.RemoveAt(0);

        return new CsvParseResult
        {
            Headers = headers,
            Rows = rows
        };
    }

    private static List<string[]> ParseRows(string content)
    {
        var rows = new List<string[]>();
        var fields = new List<string>();
        var field = new StringBuilder();
        bool inQuotes = false;
        int i = 0;

        while (i < content.Length)
        {
            char c = content[i];

            if (inQuotes)
            {
                if (c == '"')
                {
                    // Peek ahead: doubled quote or end of quoted field
                    if (i + 1 < content.Length && content[i + 1] == '"')
                    {
                        field.Append('"');
                        i += 2;
                    }
                    else
                    {
                        inQuotes = false;
                        i++;
                    }
                }
                else
                {
                    field.Append(c);
                    i++;
                }
            }
            else
            {
                if (c == '"' && field.Length == 0)
                {
                    inQuotes = true;
                    i++;
                }
                else if (c == ',')
                {
                    fields.Add(field.ToString());
                    field.Clear();
                    i++;
                }
                else if (c == '\r')
                {
                    // Handle \r\n or bare \r
                    fields.Add(field.ToString());
                    field.Clear();
                    rows.Add(fields.ToArray());
                    fields.Clear();
                    i++;
                    if (i < content.Length && content[i] == '\n')
                        i++;
                }
                else if (c == '\n')
                {
                    fields.Add(field.ToString());
                    field.Clear();
                    rows.Add(fields.ToArray());
                    fields.Clear();
                    i++;
                }
                else
                {
                    field.Append(c);
                    i++;
                }
            }
        }

        // Flush last field/row if there's content remaining
        if (field.Length > 0 || fields.Count > 0)
        {
            fields.Add(field.ToString());
            rows.Add(fields.ToArray());
        }

        return rows;
    }
}
