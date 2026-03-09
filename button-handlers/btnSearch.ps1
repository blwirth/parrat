function Get-SearchTextChangedHandler {
    param(
        [hashtable]$Controls
    )

    return {
        try {
            # 200ms debounce
            if ($null -eq $script:SearchTimer) {
                $script:SearchTimer = New-Object System.Windows.Forms.Timer
                $script:SearchTimer.Interval = 200
                $script:SearchTimer.Add_Tick({
                    try {
                        $script:SearchTimer.Stop()

                        $searchText = $Controls['txtSearch'].Text
                        $navTable = $script:NavTable
                        $searchIndex = $script:SearchIndex

                        if ($null -eq $navTable) { return }

                        $matchCount = Invoke-SearchFilter -SearchText $searchText -NavTable $navTable -SearchIndex $searchIndex
                        $totalCount = if ($null -ne $searchIndex) { $searchIndex.Count } else { 0 }

                        if ([string]::IsNullOrWhiteSpace($searchText)) {
                            $Controls['lblSearchCount'].Text = ""
                        }
                        else {
                            $Controls['lblSearchCount'].Text = "$matchCount / $totalCount"
                        }

                        # Re-highlight current record panels
                        Invoke-SearchHighlight -RichTextBox $Controls['rtbPath'] -SearchText $searchText
                        Invoke-SearchHighlight -RichTextBox $Controls['rtbItems'] -SearchText $searchText
                    }
                    catch {
                        Write-ParatError -Message "Search filter failed" -Action "SEARCH" -ErrorRecord $_
                    }
                })
            }

            # Reset timer on each keystroke
            $script:SearchTimer.Stop()
            $script:SearchTimer.Start()
        }
        catch {
            Write-ParatError -Message "Search handler failed" -Action "SEARCH" -ErrorRecord $_
            [System.Windows.Forms.MessageBox]::Show(
                "Error during search: $($_.Exception.Message)",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
}

function Get-SearchClearHandler {
    param(
        [hashtable]$Controls
    )

    return {
        $Controls['txtSearch'].Text = ""
    }
}
