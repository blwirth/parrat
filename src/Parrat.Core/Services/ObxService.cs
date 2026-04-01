using System.Text;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

/// <summary>
/// Repairs truncated OBX segments and removes OBX segments with empty OBX-5 values.
/// Ported from lib/fix-obx.ps1 and lib/remove-empty-obx5.ps1.
/// </summary>
public class ObxService : IObxService
{
    public (List<Hl7Message> Messages, int RepairedCount) RepairObxInMessages(List<Hl7Message> messages, int minFields = 5)
    {
        int fixedCount = 0;
        var sb = new StringBuilder();
        bool isFirst = true;

        foreach (var message in messages)
        {
            var rawContent = message.RawContent;
            var lines = rawContent.Split('\n');
            var modifiedLines = new List<string>(lines.Length);

            foreach (var line in lines)
            {
                var trimmedLine = line.TrimEnd('\r');

                if (trimmedLine.Length >= 4 && trimmedLine[..4] == "OBX|")
                {
                    int pipeCount = 0;
                    int idx = -1;
                    while ((idx = trimmedLine.IndexOf('|', idx + 1)) != -1)
                        pipeCount++;

                    if (pipeCount < minFields)
                    {
                        trimmedLine += new string('|', minFields - pipeCount);
                        fixedCount++;
                    }
                }

                modifiedLines.Add(trimmedLine);
            }

            if (!isFirst)
                sb.Append('\n');
            sb.Append(string.Join("\n", modifiedLines));
            isFirst = false;
        }

        // Re-parse from modified content
        var parser = new Hl7Parser();
        var repairedMessages = parser.Parse(sb.ToString());

        return (repairedMessages, fixedCount);
    }

    public (string Content, int RepairedCount) RepairObxInRawContent(string rawContent, int minFields = 5)
    {
        int fixedCount = 0;

        // Normalize line endings
        rawContent = rawContent.Replace("\r\n", "\n").Replace("\r", "\n");

        var lines = rawContent.Split('\n');
        var result = new string[lines.Length];

        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i];

            if (line.Length >= 4 && line[..4] == "OBX|")
            {
                int pipeCount = 0;
                int idx = -1;
                while ((idx = line.IndexOf('|', idx + 1)) != -1)
                    pipeCount++;

                if (pipeCount < minFields)
                {
                    line += new string('|', minFields - pipeCount);
                    fixedCount++;
                }
            }

            result[i] = line;
        }

        return (string.Join("\n", result), fixedCount);
    }

    public (List<Hl7Message> Messages, int RemovedCount) RemoveEmptyObx5FromMessages(List<Hl7Message> messages)
    {
        int removedCount = 0;
        var sb = new StringBuilder();
        bool isFirst = true;

        foreach (var message in messages)
        {
            var rawContent = message.RawContent;
            var lines = rawContent.Split('\n');
            var modifiedLines = new List<string>(lines.Length);

            foreach (var line in lines)
            {
                var trimmedLine = line.TrimEnd('\r');

                if (trimmedLine.Length >= 4 && trimmedLine[..4] == "OBX|")
                {
                    var fields = trimmedLine.Split('|', 7);
                    var obx5Value = fields.Length > 5 ? fields[5] : "";

                    if (string.IsNullOrWhiteSpace(obx5Value))
                    {
                        removedCount++;
                        continue;
                    }
                }

                modifiedLines.Add(trimmedLine);
            }

            if (!isFirst)
                sb.Append('\n');
            sb.Append(string.Join("\n", modifiedLines));
            isFirst = false;
        }

        var parser = new Hl7Parser();
        var resultMessages = parser.Parse(sb.ToString());

        return (resultMessages, removedCount);
    }

    public (string Content, int RemovedCount) RemoveEmptyObx5FromRawContent(string rawContent)
    {
        int removedCount = 0;

        // Normalize line endings
        rawContent = rawContent.Replace("\r\n", "\n").Replace("\r", "\n");

        var lines = rawContent.Split('\n');
        var result = new List<string>(lines.Length);

        foreach (var line in lines)
        {
            if (line.Length >= 4 && line[..4] == "OBX|")
            {
                var fields = line.Split('|', 7);
                var obx5Value = fields.Length > 5 ? fields[5] : "";

                if (string.IsNullOrWhiteSpace(obx5Value))
                {
                    removedCount++;
                    continue;
                }
            }

            result.Add(line);
        }

        return (string.Join("\n", result), removedCount);
    }
}
