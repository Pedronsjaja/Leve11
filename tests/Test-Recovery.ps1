#requires -Version 5.1
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\src\Engine.ps1"
$script:Pass=0
function Assert($Condition,[string]$Message) {if (-not $Condition) {throw "FALHOU: $Message"};$script:Pass++;"OK: $Message"}
function Throws([scriptblock]$Action,[string]$Message) {$failed=$false;try {& $Action | Out-Null} catch {$failed=$true};Assert $failed $Message}
$testId=[guid]::NewGuid().ToString('N');$script:DataRoot=Join-Path $env:TEMP ('Leve11.Recovery.Tests-'+$testId)
$script:Admin=$true;$script:PnpCalls=0;$script:ScanCalls=0;$script:Version='1.0';$script:PnpExit=0
function Test-LeveAdmin {return $script:Admin}
function Get-LeveMachineId {return 'fixture-machine'}
function Get-CimInstance {
    param($ClassName)
    switch ($ClassName) {
        'Win32_PnPSignedDriver' {[pscustomobject]@{DeviceID='FIXTURE';DeviceName='Test device';DriverVersion=$script:Version;DriverProviderName='Test vendor';InfName='oem42.inf'}}
        'Win32_PnPEntity' {[pscustomobject]@{DeviceID='FIXTURE';Name='Test device';ConfigManagerErrorCode=43}}
        default {throw 'Unexpected CIM class'}
    }
}
function Get-WinEvent {param($FilterHashtable,$MaxEvents,$ErrorAction);throw 'Mock event log inaccessible'}
function Invoke-LevePnp {
    param([string[]]$Arguments)
    $script:PnpCalls++;$script:LastArguments=$Arguments
    if ($Arguments[0] -eq '/export-driver') {
        [IO.File]::WriteAllText((Join-Path $Arguments[2] 'test.inf'),'Fixture INF - not a real driver')
        [IO.File]::WriteAllText((Join-Path $Arguments[2] 'test.sys'),'Fixture SYS - not executable')
    }
    [pscustomobject]@{ExitCode=$script:PnpExit;Output='Mock PnP output'}
}
$script:Mp=[pscustomobject]@{AMRunningMode='Normal';AntivirusEnabled=$true;RealTimeProtectionEnabled=$true;AntivirusSignatureLastUpdated=(Get-Date);AntivirusSignatureAge=0;QuickScanStartTime=$null;QuickScanEndTime=$null;FullScanStartTime=$null;FullScanEndTime=$null}
$script:Threats=@();$script:MpFail=$false;$script:ThreatFail=$false;$script:ScanFail=$false;$script:ScanNoEnd=$false
function Get-MpComputerStatus {param($ErrorAction);if ($script:MpFail) {throw 'Mock unavailable'}; $script:Mp.PSObject.Copy()}
function Get-MpThreat {param($ErrorAction);if ($script:ThreatFail) {throw 'Mock denied'}; $script:Threats}
function Start-MpScan {
    param($ScanType,$ErrorAction)
    $script:ScanCalls++
    if ($script:ScanFail) {throw 'Mock cancelled'}
    if (-not $script:ScanNoEnd) {if ($ScanType -eq 'QuickScan') {$script:Mp.QuickScanEndTime=Get-Date} else {$script:Mp.FullScanEndTime=Get-Date}}
}
try {
    $diag=Get-LeveDriverDiagnostic
    Assert ($diag.Devices[0].Code -eq 43 -and $diag.Warnings.Count -eq 1 -and $script:PnpCalls -eq 0) 'Diagnostico PnP nao executa reparo; erro de eventos visivel'
    Assert ((Get-LeveDriverAdvice 45) -match 'desconectado') 'Dispositivo desconectado nao tratado como driver defeituoso'
    Export-LeveDriver 'FIXTURE' -WhatIf | Out-Null
    Assert ($script:PnpCalls -eq 0 -and -not (Test-Path -LiteralPath $script:DataRoot)) 'Backup WhatIf sem escrita ou PnP'
    $script:Admin=$false
    Throws {Export-LeveDriver 'FIXTURE' -Confirm:$false} 'Backup exige privilegios'
    $script:Admin=$true
    $export=Export-LeveDriver 'FIXTURE' -Confirm:$false
    $backup=Read-LeveDriverBackup $export.Path
    Assert ($backup.Manifest.Version -eq '1.0' -and $backup.Manifest.Files.Count -eq 2) 'Backup simulado inclui manifesto e hashes'
    Restore-LeveDriver $export.Path -WhatIf | Out-Null
    Assert ($script:PnpCalls -eq 1) 'Restauracao WhatIf nao instala'
    $script:Version='2.0'
    $restore=Restore-LeveDriver $export.Path -Confirm:$false
    Assert ($script:LastArguments[0] -eq '/add-driver' -and $script:LastArguments -notcontains '/reboot' -and $script:LastArguments -notcontains '/delete-driver') 'Reinstalacao sem remover driver ou reiniciar'
    Assert ($restore.Message -match '2.0' -and $restore.Message -match 'não confirma') 'Versao nao trocada nao apresentada como rollback bem-sucedido'
    $script:PnpExit=3010
    Assert ((Restore-LeveDriver $export.Path -Confirm:$false).ExitCode -eq 3010) 'Retorno de reinicializacao necessaria preservado'
    $script:PnpExit=5
    Throws {Restore-LeveDriver $export.Path -Confirm:$false} 'Falha nativa nao reportada como sucesso'
    $script:PnpExit=0
    $manifest=Get-Content -LiteralPath $export.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.MachineId='other';Save-LeveJson $export.Path $manifest
    Throws {Read-LeveDriverBackup $export.Path} 'Backup de outra maquina bloqueado'
    $manifest.MachineId='fixture-machine';$goodInf=$manifest.Inf;$manifest.Inf='..\escape.inf';Save-LeveJson $export.Path $manifest
    Throws {Read-LeveDriverBackup $export.Path} 'INF fora do manifesto bloqueado'
    $manifest.Inf=$goodInf;Save-LeveJson $export.Path $manifest
    [IO.File]::WriteAllText($backup.InfPath,'Tampered fixture')
    Throws {Read-LeveDriverBackup $export.Path} 'Hash adulterado bloqueado'

    $malware=Get-LeveMalwareDiagnostic
    Assert ($malware.Summary -match 'não é uma varredura' -and $script:ScanCalls -eq 0) 'Consulta sem ameacas nao declara sistema limpo nem inicia scan'
    $script:Threats=@([pscustomobject]@{ThreatID=1;ThreatName='Test historical';IsActive=$false;DidThreatExecute=$false;SeverityID=2})
    Assert ((Get-LeveMalwareDiagnostic).Summary -match 'Nenhuma ameaça ativa') 'Registro historico separado de ameaca ativa'
    $script:Threats[0].IsActive=$true
    Assert ((Get-LeveMalwareDiagnostic).Summary -match '1 ameaça') 'Ameaca ativa reportada'
    $script:ThreatFail=$true
    Assert ((Get-LeveMalwareDiagnostic).Summary -match 'incompleta') 'Falha na leitura nao significa ausencia de ameacas'
    $script:ThreatFail=$false;$script:Threats=@();$script:Mp.AMRunningMode='Passive'
    Assert ((Get-LeveMalwareDiagnostic).Summary -match 'passivo') 'Modo passivo identificado'
    Throws {Invoke-LeveMalwareScan -Confirm:$false} 'Scan bloqueado com Defender passivo'
    $script:Mp.AMRunningMode='Normal';$script:MpFail=$true
    Assert ((Get-LeveMalwareDiagnostic).Status -eq $null) 'Defender indisponivel explicitado'
    $script:MpFail=$false
    Invoke-LeveMalwareScan -WhatIf | Out-Null
    Assert ($script:ScanCalls -eq 0) 'WhatIf nao inicia scan'
    $scan=Invoke-LeveMalwareScan -Confirm:$false
    $receipt=Get-Content -LiteralPath $scan.Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($receipt.Status -eq 'CompletionReported') 'Conclusao exige timestamp atualizado pelo Defender'
    $script:ScanNoEnd=$true
    $scan=Invoke-LeveMalwareScan -Confirm:$false
    Assert ((Get-Content -LiteralPath $scan.Path -Raw -Encoding UTF8 | ConvertFrom-Json).Status -eq 'CompletionNotConfirmed') 'Sem timestamp novo nao inventa conclusao'
    $script:ScanFail=$true
    Throws {Invoke-LeveMalwareScan -Confirm:$false} 'Scan cancelado ou com erro nao retorna sucesso'
    'TOTAL: '+$script:Pass+' testes de recuperacao passaram.'
} finally {
    $resolved=[IO.Path]::GetFullPath($script:DataRoot)
    $expected=[IO.Path]::GetFullPath((Join-Path $env:TEMP ('Leve11.Recovery.Tests-'+$testId)))
    if ($resolved -ceq $expected -and (Split-Path -Leaf $resolved) -eq ('Leve11.Recovery.Tests-'+$testId) -and (Test-Path -LiteralPath $resolved)) {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
