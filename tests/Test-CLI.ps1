#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. "$root\src\Engine.ps1"
$entry=Join-Path $root 'Leve11.ps1'
$os=Get-CimInstance Win32_OperatingSystem
if ([int]$os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 22000) {
    $previous=$ErrorActionPreference
    $ErrorActionPreference='Continue'
    $result=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry -Mode Plan -Profile 8 2>&1 | Out-String)
    $code=$LASTEXITCODE
    $ErrorActionPreference=$previous
    if ($code -eq 0 -or $result -notmatch 'Windows 11') { throw 'CLI deve recusar Windows nao suportado.' }
    # The nonzero child exit was the expected assertion, not a test failure.
    $global:LASTEXITCODE=0
    'OK: CLI recusa Windows Server; perfis/WhatIf exigem Windows 11 e foram testados localmente.'
    return
}
$before=@(Get-LeveCatalog | ForEach-Object {Get-LeveRegistry $_.Path $_.Name}) | ConvertTo-Json -Depth 8
$historyBefore=@(Get-LeveHistory).Count
$plan8=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry -Mode Plan -Profile 8 | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or @($plan8).Count -ne 4) { throw 'Plano de 8 GB incorreto.' }
$plan32=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry -Mode Plan -Profile 32 | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or @($plan32).Count -ne 0) { throw 'Plano sob demanda deve produzir array JSON vazio.' }
$dryRun=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entry -Mode Apply -Profile 16 -WhatIf | Out-String
if ($LASTEXITCODE -ne 0) { throw 'WhatIf falhou.' }
$jsonStart=$dryRun.IndexOf('[')
if ($jsonStart -lt 0) { throw 'WhatIf nao retornou plano.' }
$parsed=$dryRun.Substring($jsonStart) | ConvertFrom-Json
if (@($parsed).Count -ne 2 -or $parsed[0].Id -ne 'edge-boost') { throw 'WhatIf perdeu os IDs durante a enumeracao do perfil.' }
$after=@(Get-LeveCatalog | ForEach-Object {Get-LeveRegistry $_.Path $_.Name}) | ConvertTo-Json -Depth 8
if ($before -cne $after -or @(Get-LeveHistory).Count -ne $historyBefore) { throw 'Comando de leitura/simulacao alterou estado.' }
'OK: CLI - perfis 8/32, WhatIf de 16 GB e preservacao de estado.'
