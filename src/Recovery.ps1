# Windows tools only; diagnostics never install drivers or initiate scans.
function Test-LeveAdmin {
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Assert-LeveAdmin {
    if (-not (Test-LeveAdmin)) { throw 'Esta ação exige administrador. Feche o Leve11 e abra Iniciar.cmd com Executar como administrador, usando a mesma conta.' }
}
function Get-LeveMachineId {
    (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
}
function Get-LeveDriverAdvice([int]$Code) {
    switch ($Code) {
        0 {'Sem erro PnP informado; isso não exclui bugs.'}
        10 {'Não iniciou. Verifique conexão e mudanças recentes antes de reverter.'}
        22 {'Dispositivo desativado; pode ser intencional. Revise no Gerenciador.'}
        28 {'Driver não instalado. Use Windows Update, fabricante ou backup compatível.'}
        31 {'Windows não conseguiu carregar o driver. Revise o erro no Gerenciador.'}
        43 {'Dispositivo relatou falha. Pode ser hardware, conexão, firmware ou driver.'}
        45 {'Dispositivo desconectado; não significa driver defeituoso.'}
        default {'Consulte o código no Gerenciador de Dispositivos; não prova causa por driver.'}
    }
}
function Get-LeveDriverDiagnostic {
    $signed=@(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)
    $map=@{}
    foreach ($d in $signed) { if ($d.DeviceID) { $map[$d.DeviceID]=$d } }
    $rows=@(foreach ($device in Get-CimInstance Win32_PnPEntity -ErrorAction Stop) {
        $driver=$map[$device.DeviceID]
        $code=if ($null -ne $device.ConfigManagerErrorCode) {[int]$device.ConfigManagerErrorCode} else {-1}
        [pscustomobject]@{
            DeviceId=$device.DeviceID; Title=$device.Name; Code=$code
            Version=$(if ($driver) {$driver.DriverVersion} else {''})
            Provider=$(if ($driver) {$driver.DriverProviderName} else {''})
            InfName=$(if ($driver) {$driver.InfName} else {''})
            Advice=(Get-LeveDriverAdvice $code)
        }
    })
    $warnings=@(); $events=@()
    try {
        $events=@(Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date).AddDays(-7);Level=@(1,2)} -MaxEvents 25 -ErrorAction Stop |
            Select-Object TimeCreated,Id,ProviderName,Message)
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { $warnings+='Não foi possível ler os eventos: '+$_.Exception.Message }
    }
    [pscustomobject]@{Timestamp=(Get-Date).ToString('o');Devices=@($rows | Sort-Object @{e={if ($_.Code -notin @(0,45)) {0} else {1}}},Title);Events=$events;Warnings=$warnings}
}
function Invoke-LevePnp([string[]]$Arguments) {
    # Arguments are passed directly to a fixed Windows binary, never to a shell.
    $output=& "$env:SystemRoot\System32\pnputil.exe" @Arguments 2>&1 | Out-String
    $code=$LASTEXITCODE
    [pscustomobject]@{ExitCode=$code;Output=$output}
}
function Assert-LeveRegularPath([string]$Path) {
    $current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while ($null -ne $current) {
        if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links e pontos de redirecionamento não são aceitos no backup.' }
        $parent=Split-Path -Parent $current.FullName
        if (-not $parent -or $parent -eq $current.FullName) { break }
        $current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
    }
}
function Get-LeveBackupFiles([string]$Folder) {
    $base=[IO.Path]::GetFullPath($Folder).TrimEnd('\')
    Assert-LeveRegularPath $base
    # Reject reparse directories before descending; never traverse their target.
    $queue=[Collections.Generic.Queue[string]]::new(); $queue.Enqueue($base)
    while ($queue.Count) {
        foreach ($file in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Backup contém link ou redirecionamento.' }
            if ($file.PSIsContainer) { $queue.Enqueue($file.FullName); continue }
            [pscustomobject]@{Path=$file.FullName.Substring($base.Length+1);Hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
        }
    }
}
function Export-LeveDriver {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$DeviceId)
    $driver=Get-CimInstance Win32_PnPSignedDriver | Where-Object {$_.DeviceID -eq $DeviceId} | Select-Object -First 1
    if (-not $driver -or $driver.InfName -notmatch '^oem\d+\.inf$') { throw 'Somente pacotes de terceiros (oemNN.inf) podem ser exportados. Drivers nativos são recuperados pelo Windows.' }
    if (-not $PSCmdlet.ShouldProcess($driver.DeviceName,'Criar backup do pacote de driver atual')) { return }
    Assert-LeveAdmin
    $lock=Enter-LeveLock
    try {
        $folder=Join-Path $script:DataRoot ('drivers\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $packages=Join-Path $folder 'package'; [void][IO.Directory]::CreateDirectory($packages)
        $result=Invoke-LevePnp @('/export-driver',$driver.InfName,$packages)
        [IO.File]::WriteAllText((Join-Path $folder 'export.log'),$result.Output)
        if ($result.ExitCode -ne 0) { throw "Exportação falhou (código $($result.ExitCode)). Log: $folder" }
        $files=@(Get-LeveBackupFiles $packages)
        $infs=@($files | Where-Object {$_.Path -match '\.inf$'})
        if ($infs.Count -ne 1) { throw 'Exportação sem um INF único. Backup não liberado para restauração automática.' }
        $manifest=[pscustomobject]@{Schema=1;Type='DriverBackup';MachineId=(Get-LeveMachineId);Created=(Get-Date).ToString('o');DeviceId=$DeviceId;Title=$driver.DeviceName;Version=$driver.DriverVersion;Inf=$infs[0].Path;Files=$files}
        $path=Join-Path $folder 'driver-backup.json'; Save-LeveJson $path $manifest
        [pscustomobject]@{Message="Backup criado: $path`r`nVersão: $($driver.DriverVersion). Este é o driver atual, não uma versão anterior.";Path=$path;ExitCode=0}
    } finally {$lock.Dispose()}
}
function Read-LeveDriverBackup([string]$ManifestPath) {
    $resolved=[IO.Path]::GetFullPath($ManifestPath)
    Assert-LeveRegularPath $resolved
    $manifest=Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.Schema -ne 1 -or $manifest.Type -ne 'DriverBackup' -or $manifest.MachineId -ne (Get-LeveMachineId)) { throw 'Backup incompatível ou pertencente a outra instalação do Windows.' }
    $folder=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $resolved) 'package'))
    $actual=@(Get-LeveBackupFiles $folder)
    if ($actual.Count -eq 0 -or $actual.Count -ne @($manifest.Files).Count) { throw 'Arquivos do backup ausentes ou adicionais.' }
    $seen=@{}
    foreach ($file in $manifest.Files) {
        if ($file.Path -notmatch '^[^:]+$' -or [IO.Path]::IsPathRooted($file.Path) -or ($file.Path -split '[\\/]') -contains '..' -or $seen.ContainsKey($file.Path)) { throw 'Caminho inválido ou duplicado no manifesto.' }
        $seen[$file.Path]=$true
        $match=@($actual | Where-Object {$_.Path -ceq $file.Path -and $_.Hash -ceq $file.Hash})
        if ($match.Count -ne 1) { throw "Integridade do backup falhou: $($file.Path)" }
    }
    if ($manifest.Inf -notmatch '\.inf$' -or -not $seen.ContainsKey($manifest.Inf)) { throw 'INF não pertence ao manifesto.' }
    [pscustomobject]@{Manifest=$manifest;InfPath=(Join-Path $folder $manifest.Inf);Folder=(Split-Path -Parent $resolved)}
}
function Restore-LeveDriver {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$ManifestPath)
    $backup=Read-LeveDriverBackup $ManifestPath
    if (-not $PSCmdlet.ShouldProcess(($backup.Manifest.Title+' / '+$backup.Manifest.Version),'Reinstalar pacote do backup; Windows decide a versão aplicável')) { return }
    Assert-LeveAdmin
    $lock=Enter-LeveLock
    try {
        $backup=Read-LeveDriverBackup $ManifestPath
        $log=Join-Path $backup.Folder ('restore-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json')
        $record=[pscustomobject]@{Timestamp=(Get-Date).ToString('o');Status='Requested';ExitCode=$null;Output='';After=@();Warning=''}
        Save-LeveJson $log $record
        $result=Invoke-LevePnp @('/add-driver',$backup.InfPath,'/install')
        $record.ExitCode=$result.ExitCode;$record.Output=$result.Output;$record.Status='CommandReturned'
        Save-LeveJson $log $record
        $after=@()
        try {$after=@(Get-CimInstance Win32_PnPSignedDriver | Where-Object {$_.DeviceID -eq $backup.Manifest.DeviceId} | Select-Object DeviceName,DriverVersion,InfName)}
        catch {$record.Warning='Não foi possível consultar a versão após a operação: '+$_.Exception.Message}
        $record.After=$after;Save-LeveJson $log $record
        if ($result.ExitCode -notin @(0,3010)) { throw "Windows recusou a reinstalação (código $($result.ExitCode)). Consulte $log" }
        $versions=(@($after | ForEach-Object {$_.DriverVersion}) -join ', ')
        if (-not $versions) {$versions='não disponível; confira no Gerenciador de Dispositivos'}
        [pscustomobject]@{ExitCode=$result.ExitCode;Path=$log;Message="Pacote processado pelo Windows. Isso não confirma que a versão ativa foi trocada ou que o bug foi resolvido.`r`nVersão observada após a operação: $versions`r`n$($record.Warning)`r`nReinicialização indicada pelo comando: $($result.ExitCode -eq 3010). Reinicie manualmente quando conveniente.`r`nLog: $log`r`n`r`n$($result.Output)"}
    } finally {$lock.Dispose()}
}
function Get-LeveMalwareDiagnostic {
    $warnings=@(); $status=$null; $threats=@(); $threatsReadable=$false
    try {$status=Get-MpComputerStatus -ErrorAction Stop} catch {$warnings+='Estado do Defender indisponível: '+$_.Exception.Message}
    if ($status) {
        try {
            $threats=@(Get-MpThreat -ErrorAction Stop | Select-Object ThreatID,ThreatName,IsActive,DidThreatExecute,SeverityID)
            $threatsReadable=$true
        } catch {$warnings+='Não foi possível consultar ameaças: '+$_.Exception.Message}
    }
    $active=@($threats | Where-Object IsActive).Count
    $summary=if (-not $status -or -not $threatsReadable) {'Avaliação incompleta; consulte a Segurança do Windows.'}
        elseif ($active -gt 0) {"Defender informa $active ameaça(s) ativa(s). Abra o histórico de proteção."}
        elseif (-not $status.AntivirusEnabled -or $status.AMRunningMode -ne 'Normal') {'Defender desativado/passivo. Use o antivírus responsável; não há conclusão de ausência de malware.'}
        else {'Nenhuma ameaça ativa reportada nesta consulta. Isso não é uma varredura nem garante ausência de malware.'}
    if ($status -and -not $status.RealTimeProtectionEnabled) {$warnings+='Proteção em tempo real do Defender não está ativa.'}
    [pscustomobject]@{Timestamp=(Get-Date).ToString('o');Summary=$summary;Threats=$threats;Warnings=$warnings;Status=$(if ($status) {$status | Select-Object AMRunningMode,AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated,AntivirusSignatureAge,QuickScanStartTime,QuickScanEndTime,FullScanStartTime,FullScanEndTime} else {$null})}
}
function Invoke-LeveMalwareScan {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('QuickScan','FullScan')][string]$ScanType='QuickScan')
    if (-not $PSCmdlet.ShouldProcess($ScanType,'Executar varredura; Defender pode colocar ameaças em quarentena conforme suas políticas')) {return}
    Assert-LeveAdmin
    $before=Get-MpComputerStatus -ErrorAction Stop
    if (-not $before.AntivirusEnabled -or $before.AMRunningMode -ne 'Normal') {throw 'Defender não está no modo ativo. Use o antivírus responsável na Segurança do Windows.'}
    $lock=Enter-LeveLock
    try {
        $started=Get-Date
        $log=Join-Path $script:DataRoot ('security\scan-'+$started.ToString('yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json')
        $record=[pscustomobject]@{Type=$ScanType;Started=$started.ToString('o');Status='Requested';Finished='';Error=''}
        Save-LeveJson $log $record
        try {
            Start-MpScan -ScanType $ScanType -ErrorAction Stop
            $after=Get-MpComputerStatus -ErrorAction Stop
            $end=if ($ScanType -eq 'QuickScan') {$after.QuickScanEndTime} else {$after.FullScanEndTime}
            $previous=if ($ScanType -eq 'QuickScan') {$before.QuickScanEndTime} else {$before.FullScanEndTime}
            $confirmed=$null -ne $end -and [datetime]$end -ge $started.AddSeconds(-2) -and ($null -eq $previous -or [datetime]$end -gt [datetime]$previous)
            $record.Status=if ($confirmed) {'CompletionReported'} else {'CompletionNotConfirmed'}
            $record.Finished=(Get-Date).ToString('o'); Save-LeveJson $log $record
        } catch {
            $record.Status='FailedOrCancelled';$record.Error=$_.Exception.Message;Save-LeveJson $log $record
            throw "Varredura falhou ou foi cancelada. Log: $log. $($_.Exception.Message)"
        }
        [pscustomobject]@{Message="Comando de varredura retornou. Conclusão recente reportada pelo Defender: $confirmed.`r`nConsulte o diagnóstico atualizado e o histórico de proteção; nenhum resultado garante ausência de malware.`r`nLog: $log";Path=$log;Diagnostic=(Get-LeveMalwareDiagnostic)}
    } finally {$lock.Dispose()}
}
function Update-LeveDefender {
    [CmdletBinding(SupportsShouldProcess)]param()
    if (-not $PSCmdlet.ShouldProcess('Microsoft Defender','Baixar atualização de definições')) {return}
    Assert-LeveAdmin
    Update-MpSignature -ErrorAction Stop
    Get-LeveMalwareDiagnostic
}
