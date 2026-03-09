BeforeAll {
    . "$PSScriptRoot\..\lib\hl7-helpers.ps1"
    . "$PSScriptRoot\..\lib\split-file.ps1"
}

Describe 'Get-AlphabetRanges' {
    It 'returns 2 ranges for split count 2' {
        $ranges = Get-AlphabetRanges -SplitCount 2

        $ranges.Count | Should -Be 2
        $ranges[0].StartLetter | Should -Be 'A'
        $ranges[0].EndLetter | Should -Be 'M'
        $ranges[0].Label | Should -Be 'A-M'
        $ranges[1].StartLetter | Should -Be 'N'
        $ranges[1].EndLetter | Should -Be 'Z'
        $ranges[1].Label | Should -Be 'N-Z'
    }

    It 'returns 3 ranges for split count 3' {
        $ranges = Get-AlphabetRanges -SplitCount 3

        $ranges.Count | Should -Be 3
        $ranges[0].Label | Should -Be 'A-I'
        $ranges[1].Label | Should -Be 'J-R'
        $ranges[2].Label | Should -Be 'S-Z'
    }

    It 'returns 4 ranges for split count 4' {
        $ranges = Get-AlphabetRanges -SplitCount 4

        $ranges.Count | Should -Be 4
        $ranges[0].Label | Should -Be 'A-F'
        $ranges[1].Label | Should -Be 'G-L'
        $ranges[2].Label | Should -Be 'M-R'
        $ranges[3].Label | Should -Be 'S-Z'
    }

    It 'returns 5 ranges for split count 5' {
        $ranges = Get-AlphabetRanges -SplitCount 5

        $ranges.Count | Should -Be 5
        $ranges[0].Label | Should -Be 'A-E'
        $ranges[4].Label | Should -Be 'U-Z'
    }

    It 'covers the full alphabet without gaps for all split counts' {
        foreach ($count in 2..5) {
            $ranges = Get-AlphabetRanges -SplitCount $count
            $ranges[0].StartLetter | Should -Be 'A'
            $ranges[-1].EndLetter | Should -Be 'Z'

            # Verify no gaps between ranges
            for ($i = 1; $i -lt $ranges.Count; $i++) {
                $prevEnd = [char]$ranges[$i - 1].EndLetter
                $currStart = [char]$ranges[$i].StartLetter
                ($currStart - $prevEnd) | Should -Be 1
            }
        }
    }
}

Describe 'Get-FileSplitBucket' {
    Context 'with split count 2' {
        It 'puts "Anderson" in bucket 0 (A-M)' {
            Get-FileSplitBucket -LastName 'Anderson' -SplitCount 2 | Should -Be 0
        }

        It 'puts "Miller" in bucket 0 (A-M)' {
            Get-FileSplitBucket -LastName 'Miller' -SplitCount 2 | Should -Be 0
        }

        It 'puts "Nelson" in bucket 1 (N-Z)' {
            Get-FileSplitBucket -LastName 'Nelson' -SplitCount 2 | Should -Be 1
        }

        It 'puts "Zimmerman" in bucket 1 (N-Z)' {
            Get-FileSplitBucket -LastName 'Zimmerman' -SplitCount 2 | Should -Be 1
        }
    }

    Context 'case insensitivity' {
        It 'treats lowercase names the same as uppercase' {
            $upper = Get-FileSplitBucket -LastName 'SMITH' -SplitCount 2
            $lower = Get-FileSplitBucket -LastName 'smith' -SplitCount 2
            $mixed = Get-FileSplitBucket -LastName 'Smith' -SplitCount 2

            $upper | Should -Be $lower
            $lower | Should -Be $mixed
        }
    }

    Context 'edge cases' {
        It 'puts empty string in the last bucket' {
            Get-FileSplitBucket -LastName '' -SplitCount 3 | Should -Be 2
        }

        It 'puts null in the last bucket' {
            Get-FileSplitBucket -LastName $null -SplitCount 3 | Should -Be 2
        }

        It 'puts whitespace-only in the last bucket' {
            Get-FileSplitBucket -LastName '   ' -SplitCount 4 | Should -Be 3
        }

        It 'puts numeric-starting names in the last bucket' {
            Get-FileSplitBucket -LastName '123Test' -SplitCount 2 | Should -Be 1
        }

        It 'puts special-char-starting names in the last bucket' {
            Get-FileSplitBucket -LastName '#Special' -SplitCount 2 | Should -Be 1
        }

        It 'handles leading whitespace by trimming' {
            Get-FileSplitBucket -LastName '  Adams' -SplitCount 2 | Should -Be 0
        }
    }

    Context 'boundary letters' {
        It 'puts "A" names at the start of the first bucket' {
            Get-FileSplitBucket -LastName 'A' -SplitCount 2 | Should -Be 0
        }

        It 'puts "Z" names at the end of the last bucket' {
            Get-FileSplitBucket -LastName 'Z' -SplitCount 2 | Should -Be 1
        }

        It 'puts "M" in bucket 0 and "N" in bucket 1 for split 2' {
            Get-FileSplitBucket -LastName 'M' -SplitCount 2 | Should -Be 0
            Get-FileSplitBucket -LastName 'N' -SplitCount 2 | Should -Be 1
        }
    }
}

Describe 'Get-Hl7LastName' {
    It 'extracts last name from a message with PID segment' {
        $msgText = "MSH|^~\&|App|Fac|||20240101||ORU^R01|1|P|2.5`nPID|1||123||Smith^John^M||19900101|M"
        Get-Hl7LastName -MessageText $msgText | Should -Be 'Smith'
    }

    It 'returns empty string when no PID segment' {
        $msgText = "MSH|^~\&|App|Fac|||20240101||ORU^R01|1|P|2.5`nOBR|1||FILL|PROC"
        Get-Hl7LastName -MessageText $msgText | Should -Be ''
    }

    It 'returns empty string for null input' {
        Get-Hl7LastName -MessageText $null | Should -Be ''
    }

    It 'returns empty string for empty input' {
        Get-Hl7LastName -MessageText '' | Should -Be ''
    }

    It 'handles PID with empty name field' {
        $msgText = "MSH|^~\&|App|Fac|||20240101||ORU^R01|1|P|2.5`nPID|1||123||||19900101|M"
        Get-Hl7LastName -MessageText $msgText | Should -Be ''
    }
}

Describe 'Get-SplitDistribution' {
    It 'distributes names across buckets correctly' {
        $names = @('Adams', 'Baker', 'Clark', 'Nelson', 'Owens', 'Smith', 'Wilson')
        $result = Get-SplitDistribution -LastNames $names -SplitCount 2

        $result[0] | Should -BeGreaterThan 0  # A-M bucket
        $result[1] | Should -BeGreaterThan 0  # N-Z bucket
        ($result[0] + $result[1]) | Should -Be 7
    }

    It 'handles empty name array' {
        $result = Get-SplitDistribution -LastNames @() -SplitCount 2
        $result[0] | Should -Be 0
        $result[1] | Should -Be 0
    }

    It 'places all A names in first bucket' {
        $names = @('Adams', 'Allen', 'Anderson')
        $result = Get-SplitDistribution -LastNames $names -SplitCount 2

        $result[0] | Should -Be 3
        $result[1] | Should -Be 0
    }

    It 'places empty names in last bucket' {
        $names = @('', $null, '   ')
        $result = Get-SplitDistribution -LastNames $names -SplitCount 3

        $result[2] | Should -Be 3
    }
}
