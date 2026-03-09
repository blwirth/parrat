BeforeAll {
    . "$PSScriptRoot\..\lib\hl7-helpers.ps1"
}

Describe 'Get-Hl7Field' {
    It 'returns the field at the given index' {
        $segment = 'MSH|^~\&|SendApp|SendFac|RecvApp|RecvFac|20240101120000'
        Get-Hl7Field -Segment $segment -FieldIndex 2 | Should -Be 'SendApp'
    }

    It 'returns empty string for out-of-range index' {
        $segment = 'PID|1|123'
        Get-Hl7Field -Segment $segment -FieldIndex 99 | Should -Be ''
    }

    It 'returns empty string for null segment' {
        Get-Hl7Field -Segment $null -FieldIndex 0 | Should -Be ''
    }

    It 'returns empty string for whitespace segment' {
        Get-Hl7Field -Segment '   ' -FieldIndex 0 | Should -Be ''
    }

    It 'returns first field (segment name) at index 0' {
        Get-Hl7Field -Segment 'OBX|1|TX|CODE^Text' -FieldIndex 0 | Should -Be 'OBX'
    }
}

Describe 'Get-Hl7Component' {
    It 'returns the component at the given index' {
        Get-Hl7Component -Field 'Smith^John^M' -ComponentIndex 1 | Should -Be 'John'
    }

    It 'returns empty string for out-of-range index' {
        Get-Hl7Component -Field 'Smith^John' -ComponentIndex 5 | Should -Be ''
    }

    It 'returns empty string for null field' {
        Get-Hl7Component -Field $null -ComponentIndex 0 | Should -Be ''
    }

    It 'returns the first component at index 0' {
        Get-Hl7Component -Field 'CODE^Description^System' -ComponentIndex 0 | Should -Be 'CODE'
    }

    It 'handles single-component fields' {
        Get-Hl7Component -Field 'OnlyValue' -ComponentIndex 0 | Should -Be 'OnlyValue'
    }
}

Describe 'ConvertFrom-MshSegment' {
    It 'parses a full MSH segment' {
        $msh = 'MSH|^~\&|SendApp|SendFac|RecvApp|RecvFac|20240115143022||ORU^R01|MSG001|P|2.5'
        $result = ConvertFrom-MshSegment -MshSegment $msh

        $result.SendingApplication | Should -Be 'SendApp'
        $result.SendingFacility | Should -Be 'SendFac'
        $result.MessageDateTime | Should -Be '20240115143022'
        $result.MessageType | Should -Be 'ORU^R01'
        $result.MessageControlId | Should -Be 'MSG001'
    }

    It 'handles minimal MSH with few fields' {
        $msh = 'MSH|^~\&'
        $result = ConvertFrom-MshSegment -MshSegment $msh

        $result.SendingApplication | Should -Be ''
        $result.SendingFacility | Should -Be ''
    }

    It 'handles empty string' {
        $result = ConvertFrom-MshSegment -MshSegment ''
        $result.SendingApplication | Should -Be ''
    }
}

Describe 'ConvertFrom-PidSegment' {
    It 'parses patient name with first, last, and middle' {
        $pidSeg = 'PID|1||12345||Smith^John^M||19800215|M'
        $result = ConvertFrom-PidSegment -PidSegment $pidSeg

        $result.PatientId | Should -Be '12345'
        $result.LastName | Should -Be 'Smith'
        $result.FirstName | Should -Be 'John'
        $result.MiddleName | Should -Be 'M'
        $result.PatientName | Should -Be 'Smith, John M'
        $result.DateOfBirth | Should -Be '19800215'
        $result.Sex | Should -Be 'M'
    }

    It 'parses patient name without middle name' {
        $pidSeg = 'PID|1||12345||Doe^Jane||19900101|F'
        $result = ConvertFrom-PidSegment -PidSegment $pidSeg

        $result.PatientName | Should -Be 'Doe, Jane'
        $result.MiddleName | Should -Be ''
    }

    It 'handles empty PID segment' {
        $result = ConvertFrom-PidSegment -PidSegment ''
        $result.PatientId | Should -Be ''
        $result.LastName | Should -Be ''
        $result.FirstName | Should -Be ''
    }

    It 'handles PID with missing name field' {
        $pidSeg = 'PID|1||99999'
        $result = ConvertFrom-PidSegment -PidSegment $pidSeg

        $result.PatientId | Should -Be '99999'
        $result.LastName | Should -Be ''
    }
}

Describe 'ConvertFrom-ObrSegment' {
    It 'parses ordering provider with ID' {
        # OBR: 0=OBR|1=SetID|2=Placer|3=Filler|4=UnivSvcID|5=Priority|6=ReqDT|7=ObsDT|8|9|10|11|12|13|14|15|16=OrderingProvider
        #       0     1       2        3        4            5         6       7       8 9 10 11 12 13 14 15 16
        $obr = 'OBR|1|ORD001|FILL001|PROC001||20240101|20240102|||||||||1234^Jones^Mary'
        $result = ConvertFrom-ObrSegment -ObrSegment $obr

        $result.OrderDateTime | Should -Be '20240102'
        $result.OrderingProvider | Should -Match 'Jones'
        $result.OrderingProvider | Should -Match 'Mary'
        $result.OrderingProvider | Should -Match '1234'
    }

    It 'handles empty OBR segment' {
        $result = ConvertFrom-ObrSegment -ObrSegment ''
        $result.OrderDateTime | Should -Be ''
    }

    It 'handles OBR with few fields' {
        $obr = 'OBR|1'
        $result = ConvertFrom-ObrSegment -ObrSegment $obr
        $result.OrderDateTime | Should -Be ''
    }
}

Describe 'ConvertFrom-ObxSegments' {
    It 'parses multiple OBX segments' {
        $obxSegments = @(
            'OBX|1|TX|CODE1^Description1||Value1|units1|ref1|N',
            'OBX|2|NM|CODE2^Description2||42|mg/dL|10-50|'
        )
        $result = ConvertFrom-ObxSegments -ObxSegments $obxSegments

        $result.Count | Should -Be 2
        $result[0].SetId | Should -Be '1'
        $result[0].ValueType | Should -Be 'TX'
        $result[0].ObservationId | Should -Be 'CODE1^Description1'
        $result[0].ObservationValue | Should -Be 'Value1'
        $result[0].Units | Should -Be 'units1'
        $result[1].ObservationValue | Should -Be '42'
        $result[1].Units | Should -Be 'mg/dL'
    }

    It 'handles empty OBX segments array' {
        $result = ConvertFrom-ObxSegments -ObxSegments @()
        $result.Count | Should -Be 0
    }
}

Describe 'Format-Hl7DateTime' {
    It 'formats YYYYMMDDHHMMSS to readable date-time' {
        Format-Hl7DateTime -Hl7DateTime '20240115143022' | Should -Be '2024-01-15 14:30:22'
    }

    It 'formats YYYYMMDD to readable date' {
        Format-Hl7DateTime -Hl7DateTime '20240115' | Should -Be '2024-01-15'
    }

    It 'returns empty string for null input' {
        Format-Hl7DateTime -Hl7DateTime $null | Should -Be ''
    }

    It 'returns empty string for whitespace input' {
        Format-Hl7DateTime -Hl7DateTime '   ' | Should -Be ''
    }

    It 'returns original value for short strings' {
        Format-Hl7DateTime -Hl7DateTime '2024' | Should -Be '2024'
    }
}

Describe 'Get-ObxTextContent' {
    It 'combines OBX-5 values with CRLF' {
        $obxSegments = @(
            'OBX|1|TX|RPT||Line one|||',
            'OBX|2|TX|RPT||Line two|||'
        )
        $result = Get-ObxTextContent -ObxSegments $obxSegments
        $result | Should -Be "Line one`r`nLine two"
    }

    It 'skips OBX segments with empty OBX-5' {
        $obxSegments = @(
            'OBX|1|TX|RPT||Text here|||',
            'OBX|2|TX|RPT|||||',
            'OBX|3|TX|RPT||More text|||'
        )
        $result = Get-ObxTextContent -ObxSegments $obxSegments
        $result | Should -Be "Text here`r`nMore text"
    }

    It 'returns empty string for null input' {
        Get-ObxTextContent -ObxSegments $null | Should -Be ''
    }

    It 'returns empty string for empty array' {
        Get-ObxTextContent -ObxSegments @() | Should -Be ''
    }

    It 'handles HL7 escape sequences' {
        $obxSegments = @(
            'OBX|1|TX|RPT||Text\F\with\S\escapes|||'
        )
        $result = Get-ObxTextContent -ObxSegments $obxSegments
        $result | Should -Be 'Text|with^escapes'
    }

    It 'handles \E\ escape for backslash' {
        $obxSegments = @(
            'OBX|1|TX|RPT||path\E\file|||'
        )
        $result = Get-ObxTextContent -ObxSegments $obxSegments
        $result | Should -Be 'path\file'
    }

    It 'handles \T\ escape for ampersand' {
        $obxSegments = @(
            'OBX|1|TX|RPT||A\T\B|||'
        )
        $result = Get-ObxTextContent -ObxSegments $obxSegments
        $result | Should -Be 'A&B'
    }

    It 'handles \R\ escape for tilde' {
        $obxSegments = @(
            'OBX|1|TX|RPT||A\R\B|||'
        )
        $result = Get-ObxTextContent -ObxSegments $obxSegments
        $result | Should -Be 'A~B'
    }
}

Describe 'Get-Obx3Component1' {
    It 'extracts the first component of OBX-3' {
        Get-Obx3Component1 -ObxSegment 'OBX|1|TX|PATHREPORT^Pathology Report||text|||' | Should -Be 'PATHREPORT'
    }

    It 'returns empty for null input' {
        Get-Obx3Component1 -ObxSegment $null | Should -Be ''
    }

    It 'returns empty for whitespace input' {
        Get-Obx3Component1 -ObxSegment '   ' | Should -Be ''
    }

    It 'returns empty when OBX has fewer than 4 fields' {
        Get-Obx3Component1 -ObxSegment 'OBX|1|TX' | Should -Be ''
    }

    It 'returns empty when OBX-3 is empty' {
        Get-Obx3Component1 -ObxSegment 'OBX|1|TX||sub|value' | Should -Be ''
    }

    It 'handles OBX-3 with no components (no caret)' {
        Get-Obx3Component1 -ObxSegment 'OBX|1|TX|SIMPLECODE||value|||' | Should -Be 'SIMPLECODE'
    }
}

Describe 'Select-ObxSegments' {
    It 'filters out segments matching skip codes' {
        $segments = @(
            'OBX|1|TX|KEEP^Text||val1|||',
            'OBX|2|TX|SKIP^Text||val2|||',
            'OBX|3|TX|KEEP2^Text||val3|||'
        )
        $result = Select-ObxSegments -ObxSegments $segments -SkipCodes @('SKIP')

        $result.Count | Should -Be 2
        $result[0] | Should -Match 'KEEP'
        $result[1] | Should -Match 'KEEP2'
    }

    It 'is case-insensitive' {
        $segments = @(
            'OBX|1|TX|MyCode^Text||val|||'
        )
        $result = Select-ObxSegments -ObxSegments $segments -SkipCodes @('mycode')
        $result.Count | Should -Be 0
    }

    It 'returns all segments when skip codes is empty' {
        $segments = @(
            'OBX|1|TX|CODE1^Text||val|||',
            'OBX|2|TX|CODE2^Text||val|||'
        )
        $result = Select-ObxSegments -ObxSegments $segments -SkipCodes @()
        $result.Count | Should -Be 2
    }

    It 'returns empty array for null input' {
        $result = Select-ObxSegments -ObxSegments $null -SkipCodes @('CODE')
        $result.Count | Should -Be 0
    }

    It 'returns all segments when skip codes is null' {
        $segments = @(
            'OBX|1|TX|CODE^Text||val|||'
        )
        $result = Select-ObxSegments -ObxSegments $segments -SkipCodes $null
        $result.Count | Should -Be 1
    }
}

Describe 'Get-FilteredObxTextContent' {
    It 'combines filtering and text extraction' {
        $segments = @(
            'OBX|1|TX|RPT^Report||Report text|||',
            'OBX|2|TX|HEADER^Header||Header text|||',
            'OBX|3|TX|RPT^Report||More report|||'
        )
        $result = Get-FilteredObxTextContent -ObxSegments $segments -SkipCodes @('HEADER')
        $result | Should -Be "Report text`r`nMore report"
    }
}

Describe 'ConvertFrom-Hl7Content' {
    It 'parses a single HL7 message' {
        $content = @"
MSH|^~\&|SendApp|SendFac|||20240115143022||ORU^R01|MSG001|P|2.5
PID|1||12345||Smith^John^M||19800215|M
OBR|1|ORD001|FILL001|PROC001
OBX|1|TX|RPT^Report||Test result|||
"@
        $messages = ConvertFrom-Hl7Content -Content $content

        $messages.Count | Should -Be 1
        $messages[0].PatientId | Should -Be '12345'
        $messages[0].PatientLastName | Should -Be 'Smith'
        $messages[0].PatientFirstName | Should -Be 'John'
        $messages[0].MessageType | Should -Be 'ORU^R01'
        $messages[0].SendingApplication | Should -Be 'SendApp'
        $messages[0].SendingFacility | Should -Be 'SendFac'
    }

    It 'parses multiple HL7 messages' {
        $content = @"
MSH|^~\&|App1|Fac1|||20240101||ORU^R01|M1|P|2.5
PID|1||111||Alpha^First||19900101|F

MSH|^~\&|App2|Fac2|||20240102||ORU^R01|M2|P|2.5
PID|1||222||Beta^Second||19850601|M
"@
        $messages = ConvertFrom-Hl7Content -Content $content

        $messages.Count | Should -Be 2
        $messages[0].PatientLastName | Should -Be 'Alpha'
        $messages[1].PatientLastName | Should -Be 'Beta'
    }

    It 'handles messages with CRLF line endings' {
        $content = "MSH|^~\&|App|Fac|||20240101||ORU^R01|M1|P|2.5`r`nPID|1||123||Test^Patient||19900101|M"
        $messages = ConvertFrom-Hl7Content -Content $content

        $messages.Count | Should -Be 1
        $messages[0].PatientLastName | Should -Be 'Test'
    }

    It 'skips blank lines between segments' {
        $content = @"
MSH|^~\&|App|Fac|||20240101||ORU^R01|M1|P|2.5

PID|1||123||Test^Patient||19900101|M

OBR|1|ORD1||PROC1
"@
        $messages = ConvertFrom-Hl7Content -Content $content
        $messages.Count | Should -Be 1
        $messages[0].Segments.ContainsKey('PID') | Should -BeTrue
        $messages[0].Segments.ContainsKey('OBR') | Should -BeTrue
    }

    It 'returns empty for empty content' {
        $messages = ConvertFrom-Hl7Content -Content ''
        $messages.Count | Should -Be 0
    }

    It 'assigns sequential Index values starting at 0' {
        $content = @"
MSH|^~\&|A|B|||20240101||ORU^R01|1|P|2.5
PID|1||1||A^B||19900101|M
MSH|^~\&|A|B|||20240102||ORU^R01|2|P|2.5
PID|1||2||C^D||19900101|F
"@
        $messages = ConvertFrom-Hl7Content -Content $content
        $messages[0].Index | Should -Be 0
        $messages[1].Index | Should -Be 1
    }
}
