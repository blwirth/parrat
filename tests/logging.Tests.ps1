BeforeAll {
    . "$PSScriptRoot\..\lib\logging.ps1"
}

Describe 'Write-ParatError' {
    It 'sanitizes SSN patterns from error messages' {
        $testLogDir = Join-Path $TestDrive 'logs'
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        $script:LogPath = Join-Path $testLogDir 'test.log'
        $script:LogMutex = New-Object System.Threading.Mutex($false)

        # Create a mock ErrorRecord with SSN-like content
        try { throw "Patient 123-45-6789 had an error" } catch { $errorRecord = $_ }

        Write-ParatError -Message "Test error" -Action "TEST" -ErrorRecord $errorRecord

        $logContent = Get-Content -Path $script:LogPath -Raw
        $logContent | Should -Match '\[SSN\]'
        $logContent | Should -Not -Match '123-45-6789'

        $script:LogMutex.Dispose()
        $script:LogMutex = $null
    }

    It 'sanitizes MRN patterns (9-digit numbers) from error messages' {
        $testLogDir = Join-Path $TestDrive 'logs'
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        $script:LogPath = Join-Path $testLogDir 'test.log'
        $script:LogMutex = New-Object System.Threading.Mutex($false)

        try { throw "Error for patient 123456789 in system" } catch { $errorRecord = $_ }

        Write-ParatError -Message "Test error" -Action "TEST" -ErrorRecord $errorRecord

        $logContent = Get-Content -Path $script:LogPath -Raw
        $logContent | Should -Match '\[MRN\]'
        $logContent | Should -Not -Match '123456789'

        $script:LogMutex.Dispose()
        $script:LogMutex = $null
    }
}

Describe 'Write-ParatLog' {
    It 'writes a log entry to the log file' {
        $testLogDir = Join-Path $TestDrive 'logs'
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        $script:LogPath = Join-Path $testLogDir 'test.log'
        $script:LogMutex = New-Object System.Threading.Mutex($false)

        Write-ParatLog -Level INFO -Message "Test message" -Action "TEST_ACTION"

        $logContent = Get-Content -Path $script:LogPath -Raw
        $logContent | Should -Match '\[INFO\]'
        $logContent | Should -Match '\[TEST_ACTION\]'
        $logContent | Should -Match 'Test message'

        $script:LogMutex.Dispose()
        $script:LogMutex = $null
    }

    It 'includes error details when provided' {
        $testLogDir = Join-Path $TestDrive 'logs'
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        $script:LogPath = Join-Path $testLogDir 'test.log'
        $script:LogMutex = New-Object System.Threading.Mutex($false)

        Write-ParatLog -Level ERROR -Message "Something broke" -Action "TEST" -ErrorDetails "Stack trace here"

        $logContent = Get-Content -Path $script:LogPath -Raw
        $logContent | Should -Match '\[ERROR\]'
        $logContent | Should -Match 'Error: Stack trace here'

        $script:LogMutex.Dispose()
        $script:LogMutex = $null
    }

    It 'does nothing when LogPath is not set' {
        $originalLogPath = $script:LogPath
        $script:LogPath = $null

        # Should not throw
        { Write-ParatLog -Level INFO -Message "Test" -Action "TEST" } | Should -Not -Throw

        $script:LogPath = $originalLogPath
    }

    It 'includes timestamp and user info in log entry' {
        $testLogDir = Join-Path $TestDrive 'logs'
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        $script:LogPath = Join-Path $testLogDir 'test.log'
        $script:LogMutex = New-Object System.Threading.Mutex($false)

        Write-ParatLog -Level WARN -Message "Warning" -Action "TEST"

        $logContent = Get-Content -Path $script:LogPath -Raw
        $logContent | Should -Match '\[\d{4}-\d{2}-\d{2}'
        $logContent | Should -Match '\[WARN\]'

        $script:LogMutex.Dispose()
        $script:LogMutex = $null
    }
}

Describe 'Close-ParatLogging' {
    It 'disposes the mutex and sets it to null' {
        $script:LogPath = Join-Path $TestDrive 'test.log'
        $script:LogMutex = New-Object System.Threading.Mutex($false)

        Close-ParatLogging

        $script:LogMutex | Should -BeNullOrEmpty
    }
}
