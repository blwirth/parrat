BeforeAll {
    . "$PSScriptRoot\..\lib\diff.ps1"
}

Describe 'Get-DiffLines' {
    It 'marks identical lines as Unchanged' {
        $linesA = @('line1', 'line2', 'line3')
        $linesB = @('line1', 'line2', 'line3')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $result.Count | Should -Be 3
        $result | ForEach-Object { $_.Status | Should -Be 'Unchanged' }
    }

    It 'detects added lines' {
        $linesA = @('line1', 'line3')
        $linesB = @('line1', 'line2', 'line3')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $added = @($result | Where-Object { $_.Status -eq 'Added' })
        $added.Count | Should -Be 1
        $added[0].ContentB | Should -Be 'line2'
    }

    It 'detects deleted lines' {
        $linesA = @('line1', 'line2', 'line3')
        $linesB = @('line1', 'line3')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $deleted = @($result | Where-Object { $_.Status -eq 'Deleted' })
        $deleted.Count | Should -Be 1
        $deleted[0].ContentA | Should -Be 'line2'
    }

    It 'handles completely different content' {
        $linesA = @('alpha', 'beta')
        $linesB = @('gamma', 'delta')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $deleted = @($result | Where-Object { $_.Status -eq 'Deleted' })
        $added = @($result | Where-Object { $_.Status -eq 'Added' })

        $deleted.Count | Should -Be 2
        $added.Count | Should -Be 2
    }

    It 'handles empty A (all lines are additions)' {
        $linesA = @()
        $linesB = @('new1', 'new2')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $result.Count | Should -Be 2
        $result | ForEach-Object { $_.Status | Should -Be 'Added' }
    }

    It 'handles empty B (all lines are deletions)' {
        $linesA = @('old1', 'old2')
        $linesB = @()
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $result.Count | Should -Be 2
        $result | ForEach-Object { $_.Status | Should -Be 'Deleted' }
    }

    It 'handles both A and B empty' {
        $result = Get-DiffLines -LinesA @() -LinesB @()
        $result.Count | Should -Be 0
    }

    It 'handles null inputs as empty arrays' {
        $result = Get-DiffLines -LinesA $null -LinesB $null
        $result.Count | Should -Be 0
    }

    It 'assigns correct line numbers for unchanged lines' {
        $linesA = @('same1', 'same2')
        $linesB = @('same1', 'same2')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $result[0].LineNumA | Should -Be 1
        $result[0].LineNumB | Should -Be 1
        $result[1].LineNumA | Should -Be 2
        $result[1].LineNumB | Should -Be 2
    }

    It 'sets LineNumA to null for added lines' {
        $linesA = @('same')
        $linesB = @('same', 'added')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $added = $result | Where-Object { $_.Status -eq 'Added' }
        $added.LineNumA | Should -BeNullOrEmpty
        $added.LineNumB | Should -Be 2
    }

    It 'sets LineNumB to null for deleted lines' {
        $linesA = @('same', 'deleted')
        $linesB = @('same')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $deleted = $result | Where-Object { $_.Status -eq 'Deleted' }
        $deleted.LineNumA | Should -Be 2
        $deleted.LineNumB | Should -BeNullOrEmpty
    }

    It 'handles interleaved additions and deletions' {
        $linesA = @('common', 'only-in-a', 'also-common')
        $linesB = @('common', 'only-in-b', 'also-common')
        $result = Get-DiffLines -LinesA $linesA -LinesB $linesB

        $unchanged = @($result | Where-Object { $_.Status -eq 'Unchanged' })
        $unchanged.Count | Should -Be 2
        $unchanged[0].ContentA | Should -Be 'common'
        $unchanged[1].ContentA | Should -Be 'also-common'
    }

    It 'handles single-line inputs' {
        $result = Get-DiffLines -LinesA @('a') -LinesB @('b')
        $result.Count | Should -Be 2

        $deleted = @($result | Where-Object { $_.Status -eq 'Deleted' })
        $added = @($result | Where-Object { $_.Status -eq 'Added' })
        $deleted.Count | Should -Be 1
        $added.Count | Should -Be 1
    }
}
