Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'WT-10Pane-Layout Build-WtArgs' {
    BeforeAll {
        $env:WT_LAYOUT_IMPORT = '1'
        . "$PSScriptRoot/../Modules/WT-10Pane-Layout.ps1"
    }

    It 'builds args with repo, fullscreen and window target' {
        $repo = 'C:\\Users\\Richard Wilks\\CLI_RESTART'
        $args = Build-WtArgs -Repo $repo -UseExistingWindow -Fullscreen
        ($args -join ' ') | Should -Match '--fullscreen' -Because 'Fullscreen should be requested on supported builds.'
        ($args -join ' ') | Should -Match "-w last" -Because 'UseExistingWindow should direct actions to the last WT window.'
        # -d quoting is asserted in a dedicated test below
    }

    It 'has exactly 10 pane titles and 1 new-tab + 9 split-pane' {
        $repo = 'C:\\Users\\Richard Wilks\\CLI_RESTART'
        $args = Build-WtArgs -Repo $repo -Fullscreen

        $ntCount = @($args | Where-Object { $_ -eq 'new-tab' }).Count
        $spCount = @($args | Where-Object { $_ -eq 'split-pane' }).Count
        $ntCount | Should -Be 1 -Because 'Exactly one new-tab should initialize the first pane.'
        $spCount | Should -Be 9 -Because 'There must be nine splits to reach 10 panes total.'

        $titleIdx = for($i=0;$i -lt $args.Count;$i++){ if($args[$i] -eq '--title'){ $i } }
        $foundTitles = @()
        foreach($i in $titleIdx){ $foundTitles += $args[$i+1] }
        $foundTitles.Count | Should -Be 10 -Because 'Every pane must have a stable title to avoid confusion.'

        $expected = @(
            'Claude','Codex-1','Codex-2','Codex-3',
            'aider-file_mod-1','aider-file_mod-2','aider-file_mod-3',
            'aider-error_fix-1','aider-error_fix-2','aider-error_fix-3'
        )
        foreach($t in $expected){
            @($foundTitles | Where-Object { $_ -eq $t }).Count | Should -Be 1 -Because "Missing or duplicate title '$t' would break predictable navigation."
        }
    }

    

    It 'uses one vertical split and eight horizontal splits for a 2x5 grid' {
        $repo = 'C:\\Users\\Richard Wilks\\CLI_RESTART'
        $args = Build-WtArgs -Repo $repo -Fullscreen
        $flags = @()
        for($i=0;$i -lt $args.Count;$i++){
            if ($args[$i] -eq 'split-pane'){
                $flags += $args[$i+1]
            }
        }
        @($flags | Where-Object { $_ -eq '-V' }).Count | Should -Be 1 -Because 'Exactly one vertical split to create two columns.'
        @($flags | Where-Object { $_ -eq '-H' }).Count | Should -Be 8 -Because 'Four horizontal splits per column to reach five rows each.'
    }

    It 'applies the expected move-focus sequence for stable splitting' {
        $repo = 'C:\\Users\\Richard Wilks\\CLI_RESTART'
        $args = Build-WtArgs -Repo $repo -Fullscreen
        $moves = @()
        for($i=0;$i -lt $args.Count;$i++){
            if ($args[$i] -eq 'move-focus'){
                $moves += $args[$i+1]
            }
        }
        $moves.Count | Should -Be 8 -Because 'One left after column split, three ups for left column splits, one right to switch, three ups for right column splits.'
        $expectedMoves = @('left','up','up','up','right','up','up','up')
        $moves -join ',' | Should -Be ($expectedMoves -join ',') -Because 'The exact focus choreography ensures even fractional splits apply to the intended pane.'
    }

    It 'includes expected launch commands for claude/codex/aider with pwsh -NoExit -Command' {
        $repo = 'C:\\Users\\Richard Wilks\\CLI_RESTART'
        $args = Build-WtArgs -Repo $repo -Fullscreen
        $joined = ($args -join ' ')
        $joined | Should -Match "pwsh -NoExit -Command claude" -Because 'Claude pane should launch the claude CLI via pwsh.'
        ($joined | Select-String -Pattern "pwsh -NoExit -Command codex" -AllMatches).Matches.Count | Should -Be 3 -Because 'Codex should run in three panes (Codex-1..3).'
        ($joined | Select-String -Pattern "pwsh -NoExit -Command aider" -AllMatches).Matches.Count | Should -Be 6 -Because 'Six aider panes per requested layout.'
    }

    It 'passes -d for each pane/split (11 total) and each is quoted' {
        $repo = 'C:\\Users\\Richard Wilks\\CLI_RESTART'
        $args = Build-WtArgs -Repo $repo -Fullscreen
        $dIdx = for($i=0;$i -lt $args.Count;$i++){ if($args[$i] -eq '-d'){ $i } }
        $dIdx.Count | Should -Be 11 -Because 'One base -d and one per new-tab/split-pane to ensure all panes start in repo.'
        foreach($i in $dIdx){
            $args[$i+1] | Should -Be '"C:\\Users\\Richard Wilks\\CLI_RESTART"' -Because 'Quoted path prevents 0x80070002 errors on spaces.'
        }
    }

    It 'sets --suppressApplicationTitle for every titled pane (10 total)' {
        $repo = 'C:\\Users\\Richard Wilks\\CLI_RESTART'
        $args = Build-WtArgs -Repo $repo -Fullscreen
        $titleCount = ($args | Where-Object { $_ -eq '--title' }).Count
        $suppressCount = ($args | Where-Object { $_ -eq '--suppressApplicationTitle' }).Count
        $titleCount | Should -Be 10 -Because 'All panes must be titled for predictable navigation.'
        $suppressCount | Should -Be 10 -Because 'Titles should not be overridden by app prompts.'
    }

    Context 'Tool presence diagnostics' {
        BeforeAll {
            Set-Variable -Scope Script -Name LogFile -Value $null -Force
        }
        It 'returns $false when a tool is missing' {
            Mock -CommandName Get-Command -MockWith {
                param($Name)
                switch ($Name) {
                    'codex' { return $null }
                    'claude' { return [pscustomobject]@{ Source='claude.exe' } }
                    'aider' { return [pscustomobject]@{ Source='aider.exe' } }
                    Default { return $null }
                }
            } | Out-Null
            (Test-Tool -Name 'claude') | Should -BeTrue -Because 'Present tool should return $true.'
            (Test-Tool -Name 'codex')  | Should -BeFalse -Because 'Missing tool should return $false.'
            (Test-Tool -Name 'aider')  | Should -BeTrue -Because 'Present tool should return $true.'
        }
    }
}
