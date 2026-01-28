function Get-SearchTextChangedHandler {
    param(
        [hashtable]$Controls,
        [hashtable]$ScriptVars
    )

    return {
        # Debounce using a 200ms timer
        if ($null -eq $script:SearchTimer) {
            $script:SearchTimer = New-Object System.Windows.Forms.Timer
            $script:SearchTimer.Interval = 200
            $script:SearchTimer.Add_Tick({
                $script:SearchTimer.Stop()

                $searchText = $Controls['txtSearch'].Text
                $navTable = $ScriptVars['NavTable']
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

                # Re-highlight the currently displayed record panels
                Invoke-SearchHighlight -RichTextBox $Controls['rtbPath'] -SearchText $searchText
                Invoke-SearchHighlight -RichTextBox $Controls['rtbItems'] -SearchText $searchText
            })
        }

        # Reset the timer on each keystroke
        $script:SearchTimer.Stop()
        $script:SearchTimer.Start()
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
