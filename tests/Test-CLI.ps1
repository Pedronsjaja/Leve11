#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. "$root\src\Engine.ps1"
$entry=Join-Path $root 'Leve11.ps1'
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
