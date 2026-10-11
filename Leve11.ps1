#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('GUI','Analyze','Plan','Apply','Restore','RemoveApps','Drivers','Malware','Compare')][string]$Mode='GUI',
    [ValidateSet('Auto','8','12','16','32')][string]$Profile='Auto',
    [string[]]$Ids=@(),
    [string]$SessionId,
    [string]$BaselinePath,
    [string[]]$AppNames=@(),
    [switch]$SmokeTest
)
$ErrorActionPreference='Stop'
# Read-only enumeration must not inherit WhatIf: ForEach-Object member access
# and module initialization can otherwise be skipped by Windows PowerShell 5.1.
$requestedWhatIf=[bool]$WhatIfPreference
if ($Mode -eq 'GUI' -and $requestedWhatIf) { throw 'Para simular, use -Mode Apply -Profile 16 -WhatIf. A interface ja oferece revisao antes de aplicar.' }
$WhatIfPreference=$false
. "$PSScriptRoot\src\Engine.ps1"
Assert-LeveWindows
if ($Mode -eq 'GUI') {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Inicie com Iniciar.cmd ou powershell.exe -STA -File Leve11.ps1.' }
    . "$PSScriptRoot\src\UI.ps1"
    Show-LeveWindow -SmokeTest:$SmokeTest
    return
}
switch ($Mode) {
    'Compare' {Get-LeveComparison -BaselinePath $BaselinePath -SessionId $SessionId | ConvertTo-Json -Depth 12}
    'Drivers' {Get-LeveDriverDiagnostic | ConvertTo-Json -Depth 8}
    'Malware' {Get-LeveMalwareDiagnostic | ConvertTo-Json -Depth 8}
    'Analyze' { Get-LeveDiagnostic | ConvertTo-Json -Depth 8 }
    { $_ -in 'Plan','Apply' } {
        if (-not $Ids.Count) {
            if ($Profile -eq 'Auto') { $Profile=(Get-LeveDiagnostic).RecommendedProfile }
            $Ids=@(Get-LeveCatalog | Where-Object { $_.Profiles -contains $Profile } | ForEach-Object { $_.Id })
        }
        if ($Mode -eq 'Plan') { ConvertTo-Json -InputObject @(Get-LevePlan $Ids) -Depth 8 }
        else { Invoke-LeveApply -Ids $Ids -WhatIf:$requestedWhatIf | ConvertTo-Json -Depth 12 }
    }
    'Restore' { Restore-LeveSession -Id $SessionId -WhatIf:$requestedWhatIf | ConvertTo-Json -Depth 12 }
    'RemoveApps' { Remove-LeveApps -Names $AppNames -WhatIf:$requestedWhatIf | ConvertTo-Json -Depth 12 }
}
