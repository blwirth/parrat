using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IHl7FileService
{
    List<Hl7Message> LoadHl7File(string filePath);
    void SaveHl7File(string filePath, List<Hl7Message> messages);
}
