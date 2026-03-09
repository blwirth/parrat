BeforeAll {
    . "$PSScriptRoot\..\lib\fix-obx.ps1"
}

Describe 'Fix-ObxInRawContent' {
    It 'pads OBX segments with fewer pipes than MinFields' {
        $content = "MSH|^~\&|App|Fac`nOBX|1|TX"
        $result = Fix-ObxInRawContent -RawContent $content -MinFields 5

        $lines = $result.ModifiedContent -split "`n"
        $obxLine = $lines | Where-Object { $_.StartsWith('OBX|') }
        ($obxLine -split '\|').Count - 1 | Should -BeGreaterOrEqual 5
        $result.FixedCount | Should -Be 1
        $result.TotalObxCount | Should -Be 1
    }

    It 'does not modify OBX segments with enough pipes' {
        $content = "OBX|1|TX|CODE^Desc|sub|Value|units|ref|flags"
        $result = Fix-ObxInRawContent -RawContent $content -MinFields 5

        $result.FixedCount | Should -Be 0
        $result.TotalObxCount | Should -Be 1
        $result.ModifiedContent | Should -Be $content
    }

    It 'leaves non-OBX segments untouched' {
        $content = "MSH|^~\&`nPID|1|short"
        $result = Fix-ObxInRawContent -RawContent $content -MinFields 5

        $result.ModifiedContent | Should -Be $content
        $result.TotalObxCount | Should -Be 0
        $result.FixedCount | Should -Be 0
    }

    It 'handles multiple OBX segments with mixed padding needs' {
        $content = "OBX|1|TX|CODE^Desc|sub|Value|units|ref|flags`nOBX|2|TX`nOBX|3|TX|CODE|sub|Value|units|ref|flags|extra"
        $result = Fix-ObxInRawContent -RawContent $content -MinFields 5

        $result.TotalObxCount | Should -Be 3
        $result.FixedCount | Should -Be 1  # Only the second OBX needs fixing
    }

    It 'normalizes CRLF to LF' {
        $content = "MSH|^~\&`r`nOBX|1|TX"
        $result = Fix-ObxInRawContent -RawContent $content -MinFields 5

        $result.ModifiedContent | Should -Not -Match "`r"
    }

    It 'handles empty content' {
        $result = Fix-ObxInRawContent -RawContent '' -MinFields 5

        $result.FixedCount | Should -Be 0
        $result.TotalObxCount | Should -Be 0
    }

    It 'uses default MinFields of 5' {
        $content = "OBX|1|TX"
        $result = Fix-ObxInRawContent -RawContent $content

        $result.FixedCount | Should -Be 1
    }
}

Describe 'Fix-ObxInMessages' {
    It 'fixes OBX segments in message objects' {
        $messages = @(
            [PSCustomObject]@{ RawContent = "MSH|^~\&`nOBX|1|TX" }
        )
        $result = Fix-ObxInMessages -Hl7Messages $messages -MinFields 5

        $result.FixedCount | Should -Be 1
        $result.TotalObxCount | Should -Be 1
        $result.ModifiedContent | Should -Match 'OBX\|1\|TX\|'
    }

    It 'handles multiple messages' {
        $messages = @(
            [PSCustomObject]@{ RawContent = "MSH|^~\&`nOBX|1|TX" },
            [PSCustomObject]@{ RawContent = "MSH|^~\&`nOBX|1|TX|CODE|sub|val|u|r|f" }
        )
        $result = Fix-ObxInMessages -Hl7Messages $messages -MinFields 5

        $result.TotalObxCount | Should -Be 2
        $result.FixedCount | Should -Be 1
    }

    It 'handles empty messages array' {
        $result = Fix-ObxInMessages -Hl7Messages @() -MinFields 5

        $result.FixedCount | Should -Be 0
        $result.TotalObxCount | Should -Be 0
    }
}
