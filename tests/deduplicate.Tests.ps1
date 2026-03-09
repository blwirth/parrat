BeforeAll {
    . "$PSScriptRoot\..\lib\deduplicate.ps1"

    # Helper: build a minimal NAACCR XML document with patients/tumors
    function New-TestNaaccrXml {
        param([string[]]$PatientXmlFragments)

        $innerXml = $PatientXmlFragments -join "`n"
        $xmlString = @"
<?xml version="1.0" encoding="UTF-8"?>
<NaaccrData xmlns="http://naaccr.org/naaccrxml">
$innerXml
</NaaccrData>
"@
        $doc = New-Object System.Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.LoadXml($xmlString)
        return $doc
    }

    # Helper: create namespace manager for a given XmlDocument
    function New-TestNsMgr {
        param([System.Xml.XmlDocument]$Doc)
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($Doc.NameTable)
        [void]$nsMgr.AddNamespace("n", "http://naaccr.org/naaccrxml")
        return ,$nsMgr
    }

    # Helper: build a Patient XML fragment with Items and Tumors
    function New-PatientFragment {
        param(
            [string]$NameLast,
            [string]$NameFirst,
            [string]$DateOfBirth,
            [hashtable[]]$Tumors
        )

        $patientItems = @"
    <Item naaccrId="nameLast">$NameLast</Item>
    <Item naaccrId="nameFirst">$NameFirst</Item>
    <Item naaccrId="dateOfBirth">$DateOfBirth</Item>
"@
        $tumorFragments = foreach ($t in $Tumors) {
            $items = foreach ($key in $t.Keys) {
                "      <Item naaccrId=`"$key`">$($t[$key])</Item>"
            }
            "    <Tumor>`n$($items -join "`n")`n    </Tumor>"
        }

        return @"
  <Patient>
$patientItems
$($tumorFragments -join "`n")
  </Patient>
"@
    }
}

Describe 'Get-TiebreakerValue' {
    It 'returns field value when present' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateCaseReportReceived = '20240101'; primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumor = $doc.SelectNodes("//n:Tumor", $nsMgr)[0]

        $result = Get-TiebreakerValue -Tumor $tumor -NsMgr $nsMgr -FieldId 'dateCaseReportReceived'
        $result | Should -Be '20240101'
    }

    It 'returns empty string when field is absent' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumor = $doc.SelectNodes("//n:Tumor", $nsMgr)[0]

        $result = Get-TiebreakerValue -Tumor $tumor -NsMgr $nsMgr -FieldId 'dateCaseReportReceived'
        $result | Should -Be ''
    }
}

Describe 'Get-TumorFingerprint' {
    It 'produces consistent fingerprint for identical tumors' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateOfDiagnosis = '20240101' }
                @{ primarySite = 'C501'; dateOfDiagnosis = '20240101' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $fp1 = Get-TumorFingerprint -Tumor $tumors[0] -Patient $patient -NsMgr $nsMgr
        $fp2 = Get-TumorFingerprint -Tumor $tumors[1] -Patient $patient -NsMgr $nsMgr

        $fp1 | Should -Be $fp2
    }

    It 'produces different fingerprint for different tumors' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateOfDiagnosis = '20240101' }
                @{ primarySite = 'C502'; dateOfDiagnosis = '20240201' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $fp1 = Get-TumorFingerprint -Tumor $tumors[0] -Patient $patient -NsMgr $nsMgr
        $fp2 = Get-TumorFingerprint -Tumor $tumors[1] -Patient $patient -NsMgr $nsMgr

        $fp1 | Should -Not -Be $fp2
    }

    It 'ignores dateCaseReportReceived in fingerprint' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateCaseReportReceived = '20240101' }
                @{ primarySite = 'C501'; dateCaseReportReceived = '20240601' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $fp1 = Get-TumorFingerprint -Tumor $tumors[0] -Patient $patient -NsMgr $nsMgr
        $fp2 = Get-TumorFingerprint -Tumor $tumors[1] -Patient $patient -NsMgr $nsMgr

        $fp1 | Should -Be $fp2
    }

    It 'ignores dateCaseReportLoaded in fingerprint' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateCaseReportLoaded = '20240101' }
                @{ primarySite = 'C501'; dateCaseReportLoaded = '20240601' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $fp1 = Get-TumorFingerprint -Tumor $tumors[0] -Patient $patient -NsMgr $nsMgr
        $fp2 = Get-TumorFingerprint -Tumor $tumors[1] -Patient $patient -NsMgr $nsMgr

        $fp1 | Should -Be $fp2
    }

    It 'ignores physician3 in fingerprint' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; physician3 = 'DrA' }
                @{ primarySite = 'C501'; physician3 = 'DrB' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $fp1 = Get-TumorFingerprint -Tumor $tumors[0] -Patient $patient -NsMgr $nsMgr
        $fp2 = Get-TumorFingerprint -Tumor $tumors[1] -Patient $patient -NsMgr $nsMgr

        $fp1 | Should -Be $fp2
    }

    It 'includes patient-level items prefixed with P|' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumor = $doc.SelectNodes("//n:Tumor", $nsMgr)[0]
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $fp = Get-TumorFingerprint -Tumor $tumor -Patient $patient -NsMgr $nsMgr

        $fp | Should -Match 'P\|nameLast\|Smith'
        $fp | Should -Match 'P\|nameFirst\|John'
    }

    It 'includes tumor-level items prefixed with T|' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumor = $doc.SelectNodes("//n:Tumor", $nsMgr)[0]
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $fp = Get-TumorFingerprint -Tumor $tumor -Patient $patient -NsMgr $nsMgr

        $fp | Should -Match 'T\|primarySite\|C501'
    }
}

Describe 'Get-PatientTumorGroups' {
    It 'groups tumors by patient key' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001' }
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C502'; pathReportNumber1 = 'P001' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $groups = Get-PatientTumorGroups -Tumors $tumors -NsMgr $nsMgr

        # Both tumors share same patient key (nameLast|nameFirst|dob|dateOfDiagnosis|pathReportNumber1)
        $groups.Count | Should -Be 1
        $key = ($groups.Keys | Select-Object -First 1)
        $groups[$key].Count | Should -Be 2
    }

    It 'separates tumors with different diagnosis dates' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001' }
                @{ dateOfDiagnosis = '20240601'; primarySite = 'C501'; pathReportNumber1 = 'P001' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $groups = Get-PatientTumorGroups -Tumors $tumors -NsMgr $nsMgr

        $groups.Count | Should -Be 2
    }

    It 'separates tumors from different patients' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; pathReportNumber1 = 'P001' }
            )),
            (New-PatientFragment -NameLast 'Jones' -NameFirst 'Mary' -DateOfBirth '19900202' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; pathReportNumber1 = 'P002' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $groups = Get-PatientTumorGroups -Tumors $tumors -NsMgr $nsMgr

        $groups.Count | Should -Be 2
    }

    It 'stores correct tumor index' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001' }
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C502'; pathReportNumber1 = 'P001' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $groups = Get-PatientTumorGroups -Tumors $tumors -NsMgr $nsMgr

        $key = ($groups.Keys | Select-Object -First 1)
        $groups[$key][0].Index | Should -Be 0
        $groups[$key][1].Index | Should -Be 1
    }
}

Describe 'Apply-TiebreakerRules' {
    BeforeEach {
        # Build a doc with 3 duplicate tumors using different tiebreaker fields
        $script:testDoc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateCaseReportLoaded = '20240301'; dateCaseReportReceived = '20240201' }
                @{ primarySite = 'C501'; dateCaseReportLoaded = '20240101'; dateCaseReportReceived = '20240301'; physician3 = 'DrJones' }
                @{ primarySite = 'C501'; dateCaseReportReceived = '20240101' }
            ))
        )
        $script:testNsMgr = New-TestNsMgr -Doc $script:testDoc
        $script:testTumors = $script:testDoc.SelectNodes("//n:Tumor", $script:testNsMgr)
        $script:testPatient = $script:testDoc.SelectNodes("//n:Patient", $script:testNsMgr)[0]
    }

    It 'returns single item unchanged' {
        $group = @(
            @{ Index = 0; Tumor = $script:testTumors[0]; Patient = $script:testPatient }
        )

        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $script:testNsMgr

        $winner.Index | Should -Be 0
    }

    It 'Rule 1: keeps tumor with earliest dateCaseReportLoaded' {
        $group = @(
            @{ Index = 0; Tumor = $script:testTumors[0]; Patient = $script:testPatient }
            @{ Index = 1; Tumor = $script:testTumors[1]; Patient = $script:testPatient }
        )

        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $script:testNsMgr

        # Tumor 1 has dateCaseReportLoaded = 20240101 (earlier than 20240301)
        $winner.Index | Should -Be 1
    }

    It 'Rule 2: falls back to earliest dateCaseReportReceived when no dateCaseReportLoaded' {
        # Build tumors without dateCaseReportLoaded
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateCaseReportReceived = '20240301' }
                @{ primarySite = 'C501'; dateCaseReportReceived = '20240101' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $group = @(
            @{ Index = 0; Tumor = $tumors[0]; Patient = $patient }
            @{ Index = 1; Tumor = $tumors[1]; Patient = $patient }
        )

        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $nsMgr

        $winner.Index | Should -Be 1
    }

    It 'Rule 3: prefers non-empty physician3 when dates tie' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateCaseReportReceived = '20240101' }
                @{ primarySite = 'C501'; dateCaseReportReceived = '20240101'; physician3 = 'DrJones' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $group = @(
            @{ Index = 0; Tumor = $tumors[0]; Patient = $patient }
            @{ Index = 1; Tumor = $tumors[1]; Patient = $patient }
        )

        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $nsMgr

        $winner.Index | Should -Be 1
    }

    It 'Rule 4: falls back to first occurrence when no tiebreaker fields' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
                @{ primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $group = @(
            @{ Index = 0; Tumor = $tumors[0]; Patient = $patient }
            @{ Index = 1; Tumor = $tumors[1]; Patient = $patient }
        )

        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $nsMgr

        $winner.Index | Should -Be 0
    }

    It 'Rule 3 without dates: prefers physician3 over no physician3' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
                @{ primarySite = 'C501'; physician3 = 'DrSmith' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $patient = $doc.SelectNodes("//n:Patient", $nsMgr)[0]

        $group = @(
            @{ Index = 0; Tumor = $tumors[0]; Patient = $patient }
            @{ Index = 1; Tumor = $tumors[1]; Patient = $patient }
        )

        $winner = Apply-TiebreakerRules -DuplicateGroup $group -NsMgr $nsMgr

        $winner.Index | Should -Be 1
    }
}

Describe 'Get-Duplicates' {
    It 'keeps all unique tumors' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001' }
            )),
            (New-PatientFragment -NameLast 'Jones' -NameFirst 'Mary' -DateOfBirth '19900202' -Tumors @(
                @{ dateOfDiagnosis = '20240201'; primarySite = 'C502'; pathReportNumber1 = 'P002' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-Duplicates -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 2
        $result.Report.Count | Should -Be 0
    }

    It 'removes true duplicates (identical fingerprints)' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240101' }
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240601' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-Duplicates -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 1
        $result.Report.Count | Should -Be 1
    }

    It 'keeps tumors with different fingerprints in same patient group' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001' }
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C502'; pathReportNumber1 = 'P001' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-Duplicates -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 2
        $result.Report.Count | Should -Be 0
    }

    It 'report includes patient key and reason' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240101' }
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240601' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-Duplicates -Tumors $tumors -NsMgr $nsMgr

        $result.Report[0].PatientKey | Should -Match 'Smith'
        $result.Report[0].Reason | Should -Not -BeNullOrEmpty
    }

    It 'handles single tumor (no duplicates possible)' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ dateOfDiagnosis = '20240101'; primarySite = 'C501'; pathReportNumber1 = 'P001' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-Duplicates -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 1
        $result.IndicesToKeep.ContainsKey(0) | Should -Be $true
        $result.Report.Count | Should -Be 0
    }
}

Describe 'Get-DuplicatesByPrimaryKey' {
    It 'keeps unique tumors by primary key' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; laterality = '1' }
                @{ primarySite = 'C502'; laterality = '2' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPrimaryKey -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 2
        $result.Report.Count | Should -Be 0
    }

    It 'deduplicates tumors with same primary key' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; laterality = '1'; dateCaseReportReceived = '20240101' }
                @{ primarySite = 'C501'; laterality = '1'; dateCaseReportReceived = '20240601' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPrimaryKey -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 1
        $result.Report.Count | Should -Be 1
        $result.Report[0].PatientKey | Should -Match 'PrimaryKey:'
    }

    It 'keeps tumor with earliest dateCaseReportReceived' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; laterality = '1'; dateCaseReportReceived = '20240601' }
                @{ primarySite = 'C501'; laterality = '1'; dateCaseReportReceived = '20240101' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPrimaryKey -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.ContainsKey(1) | Should -Be $true
        $result.IndicesToKeep.ContainsKey(0) | Should -Be $false
    }

    It 'handles different patients with same site/laterality' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; laterality = '1' }
            )),
            (New-PatientFragment -NameLast 'Jones' -NameFirst 'Mary' -DateOfBirth '19900202' -Tumors @(
                @{ primarySite = 'C501'; laterality = '1' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPrimaryKey -Tumors $tumors -NsMgr $nsMgr

        # Different patients = different primary keys, both kept
        $result.IndicesToKeep.Count | Should -Be 2
    }
}

Describe 'Get-DuplicatesByPathReport' {
    It 'keeps tumors with unique pathReportNumber1' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ pathReportNumber1 = 'P001'; primarySite = 'C501' }
                @{ pathReportNumber1 = 'P002'; primarySite = 'C502' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPathReport -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 2
        $result.Report.Count | Should -Be 0
    }

    It 'deduplicates tumors with same pathReportNumber1' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240101' }
                @{ pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240601' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPathReport -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.Count | Should -Be 1
        $result.Report.Count | Should -Be 1
        $result.Report[0].PatientKey | Should -Match 'pathReportNumber1: P001'
    }

    It 'keeps tumors without pathReportNumber1 (does not deduplicate them)' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
                @{ primarySite = 'C502' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPathReport -Tumors $tumors -NsMgr $nsMgr

        # Both kept because neither has pathReportNumber1
        $result.IndicesToKeep.Count | Should -Be 2
    }

    It 'keeps tumor with earliest dateCaseReportReceived among duplicates' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240601' }
                @{ pathReportNumber1 = 'P001'; dateCaseReportReceived = '20240101' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        $result = Get-DuplicatesByPathReport -Tumors $tumors -NsMgr $nsMgr

        $result.IndicesToKeep.ContainsKey(1) | Should -Be $true
        $result.IndicesToKeep.ContainsKey(0) | Should -Be $false
    }
}

Describe 'Write-DedupedXml' {
    It 'writes XML with only kept tumors' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501'; dateOfDiagnosis = '20240101' }
                @{ primarySite = 'C502'; dateOfDiagnosis = '20240201' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        # Keep only first tumor
        $indicesToKeep = @{ 0 = $true }
        $outputPath = Join-Path $TestDrive 'deduped.xml'

        Write-DedupedXml -XmlDoc $doc -Tumors $tumors -IndicesToKeep $indicesToKeep -OutputPath $outputPath

        Test-Path $outputPath | Should -Be $true

        $resultDoc = New-Object System.Xml.XmlDocument
        $resultDoc.Load($outputPath)
        $resultNsMgr = New-TestNsMgr -Doc $resultDoc
        $resultTumors = $resultDoc.SelectNodes("//n:Tumor", $resultNsMgr)

        $resultTumors.Count | Should -Be 1

        $site = $resultTumors[0].SelectSingleNode("./n:Item[@naaccrId='primarySite']", $resultNsMgr)
        $site.InnerText | Should -Be 'C501'
    }

    It 'preserves XML declaration' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $indicesToKeep = @{ 0 = $true }
        $outputPath = Join-Path $TestDrive 'deduped-decl.xml'

        Write-DedupedXml -XmlDoc $doc -Tumors $tumors -IndicesToKeep $indicesToKeep -OutputPath $outputPath

        $content = Get-Content -Path $outputPath -Raw
        $content | Should -Match 'xml version'
        $content | Should -Match 'UTF-8'
    }

    It 'preserves namespace on root element' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $indicesToKeep = @{ 0 = $true }
        $outputPath = Join-Path $TestDrive 'deduped-ns.xml'

        Write-DedupedXml -XmlDoc $doc -Tumors $tumors -IndicesToKeep $indicesToKeep -OutputPath $outputPath

        $content = Get-Content -Path $outputPath -Raw
        $content | Should -Match 'naaccr.org/naaccrxml'
    }

    It 'drops patient node when all its tumors are removed' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
            )),
            (New-PatientFragment -NameLast 'Jones' -NameFirst 'Mary' -DateOfBirth '19900202' -Tumors @(
                @{ primarySite = 'C502' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)

        # Keep only second tumor (Jones)
        $indicesToKeep = @{ 1 = $true }
        $outputPath = Join-Path $TestDrive 'deduped-drop.xml'

        Write-DedupedXml -XmlDoc $doc -Tumors $tumors -IndicesToKeep $indicesToKeep -OutputPath $outputPath

        $resultDoc = New-Object System.Xml.XmlDocument
        $resultDoc.Load($outputPath)
        $resultNsMgr = New-TestNsMgr -Doc $resultDoc
        $patients = $resultDoc.SelectNodes("//n:Patient", $resultNsMgr)

        $patients.Count | Should -Be 1
        $nameNode = $patients[0].SelectSingleNode("./n:Item[@naaccrId='nameLast']", $resultNsMgr)
        $nameNode.InnerText | Should -Be 'Jones'
    }

    It 'preserves patient-level items on kept patients' {
        $doc = New-TestNaaccrXml @(
            (New-PatientFragment -NameLast 'Smith' -NameFirst 'John' -DateOfBirth '19800101' -Tumors @(
                @{ primarySite = 'C501' }
            ))
        )
        $nsMgr = New-TestNsMgr -Doc $doc
        $tumors = $doc.SelectNodes("//n:Tumor", $nsMgr)
        $indicesToKeep = @{ 0 = $true }
        $outputPath = Join-Path $TestDrive 'deduped-items.xml'

        Write-DedupedXml -XmlDoc $doc -Tumors $tumors -IndicesToKeep $indicesToKeep -OutputPath $outputPath

        $resultDoc = New-Object System.Xml.XmlDocument
        $resultDoc.Load($outputPath)
        $resultNsMgr = New-TestNsMgr -Doc $resultDoc
        $patient = $resultDoc.SelectNodes("//n:Patient", $resultNsMgr)[0]

        $lastName = $patient.SelectSingleNode("./n:Item[@naaccrId='nameLast']", $resultNsMgr)
        $firstName = $patient.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", $resultNsMgr)
        $dob = $patient.SelectSingleNode("./n:Item[@naaccrId='dateOfBirth']", $resultNsMgr)

        $lastName.InnerText | Should -Be 'Smith'
        $firstName.InnerText | Should -Be 'John'
        $dob.InnerText | Should -Be '19800101'
    }
}
