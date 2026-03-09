BeforeAll {
    . "$PSScriptRoot\..\lib\remove-empty-obx5.ps1"
}

Describe 'Remove-EmptyObx5FromRawContent' {
    It 'removes OBX segments with empty OBX-5' {
        $content = "MSH|^~\&`nOBX|1|TX|CODE||Value|u|r|f`nOBX|2|TX|CODE|||||`nOBX|3|TX|CODE||More|u|r|f"
        $result = Remove-EmptyObx5FromRawContent -RawContent $content

        $result.RemovedCount | Should -Be 1
        $result.TotalObxCount | Should -Be 3
        $result.ModifiedContent | Should -Not -Match 'OBX\|2'
        $result.ModifiedContent | Should -Match 'OBX\|1'
        $result.ModifiedContent | Should -Match 'OBX\|3'
    }

    It 'keeps OBX segments with non-empty OBX-5' {
        $content = "OBX|1|TX|CODE||SomeValue|u|r|f"
        $result = Remove-EmptyObx5FromRawContent -RawContent $content

        $result.RemovedCount | Should -Be 0
        $result.TotalObxCount | Should -Be 1
        $result.ModifiedContent | Should -Match 'SomeValue'
    }

    It 'treats whitespace-only OBX-5 as empty' {
        $content = "OBX|1|TX|CODE||   |u|r|f"
        $result = Remove-EmptyObx5FromRawContent -RawContent $content

        $result.RemovedCount | Should -Be 1
    }

    It 'does not touch non-OBX segments' {
        $content = "MSH|^~\&|App|Fac`nPID|1||123||Smith^John"
        $result = Remove-EmptyObx5FromRawContent -RawContent $content

        $result.TotalObxCount | Should -Be 0
        $result.RemovedCount | Should -Be 0
        $result.ModifiedContent | Should -Match 'MSH'
        $result.ModifiedContent | Should -Match 'PID'
    }

    It 'handles OBX with fewer than 6 fields as empty OBX-5' {
        $content = "OBX|1|TX|CODE"
        $result = Remove-EmptyObx5FromRawContent -RawContent $content

        $result.RemovedCount | Should -Be 1
    }

    It 'handles empty content' {
        $result = Remove-EmptyObx5FromRawContent -RawContent ''

        $result.RemovedCount | Should -Be 0
        $result.TotalObxCount | Should -Be 0
    }

    It 'normalizes CRLF line endings' {
        $content = "MSH|^~\&`r`nOBX|1|TX|CODE||Value|u|r|f"
        $result = Remove-EmptyObx5FromRawContent -RawContent $content

        $result.TotalObxCount | Should -Be 1
        $result.RemovedCount | Should -Be 0
    }
}

Describe 'Remove-EmptyObx5FromMessages' {
    It 'removes empty OBX-5 segments from message objects' {
        $messages = @(
            [PSCustomObject]@{ RawContent = "MSH|^~\&`nOBX|1|TX|CODE||Text|u|r|f`nOBX|2|TX|CODE|||||" }
        )
        $result = Remove-EmptyObx5FromMessages -Hl7Messages $messages

        $result.RemovedCount | Should -Be 1
        $result.TotalObxCount | Should -Be 2
        $result.ModifiedContent | Should -Match 'OBX\|1'
        $result.ModifiedContent | Should -Not -Match 'OBX\|2'
    }

    It 'handles multiple messages' {
        $messages = @(
            [PSCustomObject]@{ RawContent = "MSH|^~\&`nOBX|1|TX|CODE|||||" },
            [PSCustomObject]@{ RawContent = "MSH|^~\&`nOBX|1|TX|CODE||HasValue|u|r|f" }
        )
        $result = Remove-EmptyObx5FromMessages -Hl7Messages $messages

        $result.RemovedCount | Should -Be 1
        $result.TotalObxCount | Should -Be 2
    }

    It 'handles empty messages array' {
        $result = Remove-EmptyObx5FromMessages -Hl7Messages @()

        $result.RemovedCount | Should -Be 0
        $result.TotalObxCount | Should -Be 0
    }
}
