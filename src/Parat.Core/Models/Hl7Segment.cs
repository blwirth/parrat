namespace Parat.Core.Models;

public class MshSegment
{
    public string SendingApplication { get; set; } = string.Empty;
    public string SendingFacility { get; set; } = string.Empty;
    public string MessageDateTime { get; set; } = string.Empty;
    public string MessageType { get; set; } = string.Empty;
    public string MessageControlId { get; set; } = string.Empty;
}

public class PidSegment
{
    public string PatientId { get; set; } = string.Empty;
    public string PatientName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
    public string FirstName { get; set; } = string.Empty;
    public string MiddleName { get; set; } = string.Empty;
    public string DateOfBirth { get; set; } = string.Empty;
    public string Sex { get; set; } = string.Empty;
}

public class ObrSegment
{
    public string AccessionNumber { get; set; } = string.Empty;
    public string OrderDateTime { get; set; } = string.Empty;
    public string OrderingProvider { get; set; } = string.Empty;
}

public class ObxSegment
{
    public string SetId { get; set; } = string.Empty;
    public string ValueType { get; set; } = string.Empty;
    public string ObservationId { get; set; } = string.Empty;
    public string ObservationValue { get; set; } = string.Empty;
    public string Units { get; set; } = string.Empty;
    public string ReferenceRange { get; set; } = string.Empty;
    public string AbnormalFlag { get; set; } = string.Empty;
}
