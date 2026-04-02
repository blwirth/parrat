using Parrat.Core.Helpers;
using Xunit;

namespace Parrat.Tests.Helpers;

public class PhiRedactorTests
{
    [Fact]
    public void Redact_ReplacesDashedSsn()
    {
        var result = PhiRedactor.Redact("Patient SSN is 123-45-6789");
        Assert.Contains("***-**-****", result);
        Assert.DoesNotContain("123-45-6789", result);
    }

    [Fact]
    public void Redact_ReplacesNineDigitSsn()
    {
        var result = PhiRedactor.Redact("Patient SSN is 123456789");
        Assert.Contains("*********", result);
        Assert.DoesNotContain("123456789", result);
    }

    [Fact]
    public void Redact_ReplacesMultipleSsnsInSameString()
    {
        var result = PhiRedactor.Redact("Patient 123-45-6789 referred by 987-65-4321");
        Assert.DoesNotContain("123-45-6789", result);
        Assert.DoesNotContain("987-65-4321", result);
        Assert.Equal(2, result.Split("***-**-****").Length - 1);
    }

    [Fact]
    public void Redact_DoesNotRedactShorterNumbers()
    {
        var result = PhiRedactor.Redact("Patient ID 12345678 is valid");
        Assert.Contains("12345678", result);
    }

    [Fact]
    public void Redact_DoesNotRedactLongerNumbers()
    {
        var result = PhiRedactor.Redact("Phone 1234567890 is ten digits");
        Assert.Contains("1234567890", result);
    }

    [Fact]
    public void Redact_ReturnsNullForNull()
    {
        Assert.Null(PhiRedactor.Redact(null!));
    }

    [Fact]
    public void Redact_ReturnsEmptyForEmpty()
    {
        Assert.Equal("", PhiRedactor.Redact(""));
    }

    [Fact]
    public void Redact_PreservesNonSsnText()
    {
        var input = "No sensitive data here";
        Assert.Equal(input, PhiRedactor.Redact(input));
    }

    [Fact]
    public void Redact_HandlesMixedFormats()
    {
        var result = PhiRedactor.Redact("SSN: 123-45-6789 or 987654321");
        Assert.DoesNotContain("123-45-6789", result);
        Assert.DoesNotContain("987654321", result);
    }
}
