using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IObxService
{
    (List<Hl7Message> Messages, int RepairedCount) RepairObxInMessages(List<Hl7Message> messages, int minFields = 5);
    (string Content, int RepairedCount) RepairObxInRawContent(string rawContent, int minFields = 5);
    (List<Hl7Message> Messages, int RemovedCount) RemoveEmptyObx5FromMessages(List<Hl7Message> messages);
    (string Content, int RemovedCount) RemoveEmptyObx5FromRawContent(string rawContent);
}
