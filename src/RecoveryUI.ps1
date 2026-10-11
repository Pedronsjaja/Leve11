function Update-LeveDriverView($Result) {
    $script:DriverDiagnostic=$Result
    $script:Controls.DriverGrid.ItemsSource=@($Result.Devices)
    $issues=@($Result.Devices | Where-Object {$_.Code -notin @(0,45)}).Count
    $script:Controls.DriverHint.Text="$issues dispositivo(s) com código diferente de 0/45. Selecione uma linha para criar backup. Código 45 indica desconexão; eventos e códigos não provam a causa do bug. "+($Result.Warnings -join ' ')
}
function Update-LeveMalwareView($Result) {
    $script:Controls.MalwareHint.Text=$Result.Summary
    $script:Controls.ThreatGrid.ItemsSource=@($Result.Threats)
    $lines=@('Consulta: '+$Result.Timestamp)
    if ($Result.Status) {
        $s=$Result.Status
        $lines+="Modo: $($s.AMRunningMode) | Antivírus ativo: $($s.AntivirusEnabled) | Tempo real: $($s.RealTimeProtectionEnabled)"
        $lines+="Definições: $($s.AntivirusSignatureLastUpdated) | Idade reportada (dias): $($s.AntivirusSignatureAge)"
        $lines+="Última rápida concluída: $($s.QuickScanEndTime) | Última completa concluída: $($s.FullScanEndTime)"
    }
    $lines+=@($Result.Warnings)
    $script:Controls.DefenderDetails.Text=$lines -join "`r`n"
}
function Start-LeveScanUI([string]$ScanType) {
    $kind=if ($ScanType -eq 'FullScan') {'completa (pode levar horas)'} else {'rápida'}
    $body="Executar verificação $kind?`r`n`r`nO Defender poderá colocar arquivos em quarentena conforme suas configurações. O Leve11 não muda exclusões nem desativa proteções.`r`n`r`nMantenha o Leve11 aberto durante a operação. Você pode acompanhar e cancelar pela Segurança do Windows, usando o botão no rodapé. A verificação usa CPU/disco enquanto executa. Atualize as definições antes se necessário."
    if (Show-LeveDialog 'Verificação de malware' $body 'Iniciar verificação' -Cancel) {
        Start-LeveWork 'Scan' $ScanType {param($r)
            Update-LeveMalwareView $r.Diagnostic
            [void](Show-LeveDialog 'Resultado da verificação' $r.Message)
        }
        $script:Controls.StatusText.Text='Defender em execução. Acompanhe ou cancele na Segurança do Windows pelo botão ao lado.'
    }
}
function Initialize-LeveRecoveryUI {
    foreach ($name in @('DriverHint','DriverGrid','DriverAnalyzeButton','DriverBackupButton','DriverRestoreButton','DriverRollbackButton','DriverEventsButton','MalwareHint','DefenderDetails','ThreatGrid','MalwareAnalyzeButton','SignatureButton','QuickScanButton','FullScanButton','OfflineScanButton','SecurityShortcutButton')) {
        $script:Controls[$name]=$script:Window.FindName($name)
        if (-not $script:Controls[$name]) {throw "Controle ausente: $name"}
    }
    $script:DriverDiagnostic=$null
    $script:Controls.DriverAnalyzeButton.Add_Click({Start-LeveWork 'Drivers' $null {param($r) Update-LeveDriverView $r}})
    $script:Controls.DriverBackupButton.Add_Click({
        $device=$script:Controls.DriverGrid.SelectedItem
        if (-not $device) {[void](Show-LeveDialog 'Selecione um dispositivo' 'Execute Diagnosticar e escolha o dispositivo cujo pacote deseja guardar.');return}
        if (Show-LeveDialog 'Backup de driver' "Dispositivo: $($device.Title)`r`nVersão atual: $($device.Version)`r`nPacote: $($device.InfName)`r`n`r`nExportar este pacote para a pasta local do Leve11? Backup do driver atual não cria uma versão anterior ao bug. Pacotes nativos do Windows não são exportáveis por esta opção." 'Criar backup' -Cancel) {
            Start-LeveWork 'DriverBackup' $device.DeviceId {param($r) [void](Show-LeveDialog 'Backup do driver' $r.Message)}
        }
    })
    $script:Controls.DriverRestoreButton.Add_Click({
        $open=New-Object Microsoft.Win32.OpenFileDialog; $open.Filter='Backup de driver|driver-backup.json'
        $folder=Join-Path $script:DataRoot 'drivers'; if (Test-Path -LiteralPath $folder) {$open.InitialDirectory=$folder}
        if ($open.ShowDialog($script:Window)) {
            try {
                $backup=Read-LeveDriverBackup $open.FileName
                $body="Dispositivo do backup: $($backup.Manifest.Title)`r`nVersão salva: $($backup.Manifest.Version)`r`nData: $($backup.Manifest.Created)`r`n`r`nO Windows aplicará o pacote somente se ele for compatível e escolhido pela sua classificação de drivers. Isso pode afetar todos os dispositivos compatíveis com esse pacote e não força uma versão mais antiga.`r`n`r`nPode haver interrupção temporária do dispositivo. Salve o trabalho antes. Não haverá reinicialização automática. Para voltar à versão anterior de um dispositivo, prefira Reverter driver no Gerenciador."
                if (Show-LeveDialog 'Reinstalar pacote do backup' $body 'Reinstalar pacote' -Cancel) {
                    Start-LeveWork 'DriverRestore' $open.FileName {param($r) [void](Show-LeveDialog 'Resultado da reinstalação' $r.Message)}
                }
            } catch {[void](Show-LeveDialog 'Backup não aceito' $_.Exception.Message)}
        }
    })
    $script:Controls.DriverRollbackButton.Add_Click({
        $device=$script:Controls.DriverGrid.SelectedItem
        $title=if ($device) {$device.Title} else {'o dispositivo com problema'}
        if (Show-LeveDialog 'Reverter para a versão anterior' "No Gerenciador de Dispositivos:`r`n1. Localize $title.`r`n2. Abra Propriedades > Driver > Reverter Driver.`r`n3. Confirme o motivo e siga as instruções do Windows.`r`n`r`nSe o botão estiver indisponível, o Windows pode não ter uma versão anterior guardada. Use um backup anterior ao problema ou um pacote oficial do fabricante. O Leve11 não remove drivers à força para contornar isso." 'Abrir Gerenciador' -Cancel) {Start-Process "$env:SystemRoot\System32\devmgmt.msc"}
    })
    $script:Controls.DriverEventsButton.Add_Click({
        if (-not $script:DriverDiagnostic) {[void](Show-LeveDialog 'Diagnóstico necessário' 'Clique em Diagnosticar para consultar os eventos dos últimos sete dias.');return}
        $body="Até 25 eventos críticos/erros de Sistema dos últimos sete dias. Podem ter causas diferentes de drivers. Nenhum evento isolado justifica uma restauração automática.`r`n`r`n"+($script:DriverDiagnostic.Events | Format-List | Out-String -Width 120)
        [void](Show-LeveDialog 'Eventos recentes do Windows' $body)
    })
    $script:Controls.MalwareAnalyzeButton.Add_Click({Start-LeveWork 'Malware' $null {param($r) Update-LeveMalwareView $r}})
    $script:Controls.SignatureButton.Add_Click({
        if (Show-LeveDialog 'Atualizar definições' 'Baixar as definições pelo mecanismo de atualização do Microsoft Defender? Esta ação requer internet e administrador.' 'Atualizar' -Cancel) {Start-LeveWork 'Signatures' $null {param($r) Update-LeveMalwareView $r}}
    })
    $script:Controls.QuickScanButton.Add_Click({Start-LeveScanUI 'QuickScan'})
    $script:Controls.FullScanButton.Add_Click({Start-LeveScanUI 'FullScan'})
    $script:Controls.SecurityShortcutButton.Add_Click({Start-Process 'windowsdefender://threat'})
    $script:Controls.OfflineScanButton.Add_Click({
        if (Show-LeveDialog 'Verificação offline pelo Windows' "A verificação offline reinicia o computador. Salve o trabalho e confira se tem acesso à chave de recuperação caso o BitLocker a solicite.`r`n`r`nNa Segurança do Windows, abra Proteção contra vírus e ameaças > Opções de verificação > Microsoft Defender Antivírus (verificação offline). Inicie e confirme pelo próprio Windows.`r`n`r`nO botão abaixo apenas abre a tela; não inicia verificação nem reinicia." 'Abrir Segurança do Windows' -Cancel) {Start-Process 'windowsdefender://threat'}
    })
}
