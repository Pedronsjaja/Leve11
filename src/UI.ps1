Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:EngineFile=Join-Path $PSScriptRoot 'Engine.ps1'
$script:XamlFile=Join-Path $PSScriptRoot 'MainWindow.xaml'
. "$PSScriptRoot\RecoveryUI.ps1"

function Get-LeveLabel([string]$Value) {
    $labels=@{Applied='Aplicado';Applying='Em aplicação';Partial='Concluído com falhas';NoChanges='Já configurado';Pending='Pendente';Restored='Restaurado';RestorePartial='Restauração incompleta';RestoreFailed='Falha ao restaurar';Conflict='Conflito preservado';Failed='Falha';Removing='Em desinstalação';Removed='Desinstalado';Settings='Ajustes';Apps='Aplicativos'}
    if ($labels.ContainsKey($Value)) { return $labels[$Value] }
    return $Value
}

function Show-LeveDialog([string]$Title,[string]$Body,[string]$Accept='Entendi',[switch]$Cancel) {
    $dialog=New-Object Windows.Window
    $dialog.Title=$Title; $dialog.Width=760; $dialog.Height=520
    $dialog.Owner=$script:Window; $dialog.WindowStartupLocation='CenterOwner'
    $dialog.Background='#F3F5F7'; $dialog.FontFamily='Segoe UI'
    $grid=New-Object Windows.Controls.Grid; $grid.Margin='24'
    $row1=New-Object Windows.Controls.RowDefinition; $row1.Height='*'; [void]$grid.RowDefinitions.Add($row1)
    $row2=New-Object Windows.Controls.RowDefinition; $row2.Height='Auto'; [void]$grid.RowDefinitions.Add($row2)
    $text=New-Object Windows.Controls.TextBox
    $text.Text=$Body; $text.IsReadOnly=$true; $text.TextWrapping='Wrap'; $text.VerticalScrollBarVisibility='Auto'
    $text.FontSize=14; $text.Padding='14'; $text.BorderThickness=0
    [void]$grid.Children.Add($text)
    $buttons=New-Object Windows.Controls.StackPanel; $buttons.Orientation='Horizontal'; $buttons.HorizontalAlignment='Right'; $buttons.Margin='0,18,0,0'
    [Windows.Controls.Grid]::SetRow($buttons,1)
    $yes=New-Object Windows.Controls.Button; $yes.Content=$Accept; $yes.Padding='20,10'; $yes.Margin='8,0,0,0'
    $yes.Add_Click({$this.Tag.DialogResult=$true}); $yes.Tag=$dialog
    [void]$buttons.Children.Add($yes)
    if ($Cancel) {
        $no=New-Object Windows.Controls.Button; $no.Content='Cancelar'; $no.Padding='20,10'; $no.Margin='8,0,0,0'; $no.IsCancel=$true
        [void]$buttons.Children.Add($no)
    }
    [void]$grid.Children.Add($buttons); $dialog.Content=$grid
    return $dialog.ShowDialog()
}

function Set-LeveBusy([bool]$Busy,[string]$Text) {
    $script:Controls.Tabs.IsEnabled=-not $Busy
    $script:Controls.RefreshButton.IsEnabled=-not $Busy
    $script:Controls.BusyBar.Visibility=if ($Busy) {'Visible'} else {'Collapsed'}
    $script:Controls.StatusText.Text=$Text
}

# All CIM/Appx/registry operations run outside the WPF dispatcher.
function Start-LeveWork([string]$Operation,$Payload,[scriptblock]$Done) {
    if ($script:Worker) { throw 'Uma operação já está em andamento.' }
    Set-LeveBusy $true 'Processando localmente... aguarde a verificação.'
    $ps=[PowerShell]::Create()
    [void]$ps.AddScript({
        param($engine,$operation,$payload)
        . $engine
        switch ($operation) {
            'Analyze' {
                $warnings=@(); $apps=@()
                try { $apps=@(Get-LeveInstalledApps) } catch { $warnings+="Não foi possivel listar apps: $($_.Exception.Message)" }
                [pscustomobject]@{ Diagnostic=(Get-LeveDiagnostic); Startup=@(Get-LeveStartup); Apps=$apps; History=@(Get-LeveHistory); Warnings=$warnings }
            }
            'Apply' { Invoke-LeveApply -Ids @($payload) -Confirm:$false }
            'Restore' { Restore-LeveSession -Id $payload -Confirm:$false }
            'Remove' { Remove-LeveApps -Names @($payload) -Confirm:$false }
            'Drivers' { Get-LeveDriverDiagnostic }
            'DriverBackup' { Export-LeveDriver -DeviceId $payload -Confirm:$false }
            'DriverRestore' { Restore-LeveDriver -ManifestPath $payload -Confirm:$false }
            'Malware' { Get-LeveMalwareDiagnostic }
            'Scan' { Invoke-LeveMalwareScan -ScanType $payload -Confirm:$false }
            'Signatures' { Update-LeveDefender -Confirm:$false }
            default { throw 'Operação desconhecida.' }
        }
    }).AddArgument($script:EngineFile).AddArgument($Operation).AddArgument($Payload)
    $script:Worker=[pscustomobject]@{PS=$ps; Handle=$ps.BeginInvoke(); Done=$Done; Operation=$Operation}
    $script:Timer.Start()
}

function Update-LeveProfile {
    $profile=[string]$script:Controls.ProfileCombo.SelectedItem.Tag
    foreach ($item in Get-LeveCatalog) { $script:Checks[$item.Id].IsChecked=($item.Profiles -contains $profile) }
    $hints=@{
        '8'='Essencial: pré-carga do navegador, captura histórica e transparência. Revise especialmente os apps que abrem no login.'
        '12'='Equilibrado: sugere reduzir tarefas do navegador e captura histórica. Mantem os efeitos visuais.'
        '16'='Conforto: sugere somente limitar o Edge fora de uso. Aplicativos de trabalho e jogos continuam por sua escolha.'
        '32'='Sob demanda (inclui 24, 32, 48 e 64 GB): nenhum ajuste pre-selecionado. Priorize processos pesados e inicialização.'
    }
    $script:Controls.ProfileHint.Text=$hints[$profile]+' O perfil apenas seleciona opções; não desfaz ajustes anteriores.'
}

function Update-LeveView($Result) {
    $script:Diagnostic=$Result.Diagnostic
    $d=$script:Diagnostic
    $script:Controls.UsedText.Text=('{0} GB / {1}%' -f $d.UsedGB,$d.UsedPercent)
    $script:Controls.MemoryDetail.Text=('{0} GB utilizáveis / {1} GB detectados' -f $d.UsableGB,$d.InstalledGB)
    $script:Controls.AvailableText.Text=('{0} GB' -f $d.AvailableGB)
    $script:Controls.ProfileText.Text=if ($d.RecommendedProfile -eq '32') {'32 GB+ / sob demanda'} else {$d.RecommendedProfile+' GB'}
    $script:Controls.StartupGrid.ItemsSource=@($Result.Startup)
    $script:Controls.AppsGrid.ItemsSource=@($Result.Apps)
    $script:Controls.ProcessGrid.ItemsSource=@($d.Processes)
    foreach ($session in @($Result.History)) {
        $session | Add-Member -NotePropertyName DisplayType -NotePropertyValue (Get-LeveLabel $session.Type) -Force
        $session | Add-Member -NotePropertyName DisplayStatus -NotePropertyValue (Get-LeveLabel $session.Status) -Force
    }
    $script:Controls.HistoryGrid.ItemsSource=@($Result.History)
    $script:Controls.DiagnosticHint.Text=('Build {0} | Ligado há {1} h | Arquivo de paginação automático: {2}. Working set inclui memória compartilhada; não some os processos.' -f $d.Build,$d.UptimeHours,$d.SystemManagedPagefile)
    if (-not $script:ProfileInitialized) {
        $script:Controls.ProfileCombo.SelectedIndex=@('8','12','16','32').IndexOf([string]$d.RecommendedProfile)
        $script:ProfileInitialized=$true
        Update-LeveProfile
    }
    $script:Controls.StatusText.Text=if (@($Result.Warnings).Count) {$Result.Warnings -join ' | '} else {'Análise atualizada. Nenhuma alteração é feita ao analisar. A seleção de apps e inicialização foi limpa.'}
}

function Show-LeveResult($Result) {
    $lines=@("Resultado: $(Get-LeveLabel $Result.Status)")
    if ($Result.Id) { $lines+="Sessão: $($Result.Id)" }
    foreach ($op in @($Result.Operations)) {
        $lines+="`r`n$($op.Title): $(Get-LeveLabel $op.Status)"
        if ($op.Error) { $lines+=$op.Error }
    }
    $lines+="`r`nFeche o programa e reinicie quando for conveniente para comparar o uso. Nenhum aplicativo foi encerrado à força."
    [void](Show-LeveDialog 'Resultado da operação' ($lines -join "`r`n"))
    Start-LeveWork 'Analyze' $null {param($r) Update-LeveView $r}
}

function Show-LevePlan([string[]]$Ids) {
    if (-not $Ids.Count) { [void](Show-LeveDialog 'Seleção vazia' 'Selecione ao menos um ajuste ou uma entrada de inicialização.'); return }
    try {
        $plan=@(Get-LevePlan $Ids)
        $lines=@('Estas mudanças valem apenas para o usuário atual. Os valores originais serão salvos antes de aplicar.','')
        foreach ($op in $plan) {
            $before=if ($op.Before.Exists) { ConvertTo-Json -InputObject $op.Before.Value -Compress } else {'não configurado'}
            $after=if ($op.After.Exists) { ConvertTo-Json -InputObject $op.After.Value -Compress } else {'remover entrada de inicialização'}
            $lines+="$($op.Title)`r`n  Atual: $before`r`n  Proposto: $after`r`n  Alteração necessária: $($op.Needed)`r`n"
        }
        if (Show-LeveDialog 'Revisão dos ajustes' ($lines -join "`r`n") 'Aplicar com backup' -Cancel) {
            Start-LeveWork 'Apply' $Ids {param($r) Show-LeveResult $r}
        }
    } catch { [void](Show-LeveDialog 'Não foi possivel preparar' $_.Exception.Message) }
}

function Show-LeveWindow([switch]$SmokeTest) {
    $script:SmokeMode=[bool]$SmokeTest
    $script:SmokeError=$null
    $reader=New-Object Xml.XmlNodeReader ([xml](Get-Content -LiteralPath $script:XamlFile -Raw))
    $script:Window=[Windows.Markup.XamlReader]::Load($reader)
    $script:Controls=@{}
    foreach ($name in @('UsedText','MemoryDetail','AvailableText','ProfileText','RefreshButton','Tabs','ProfileCombo','ProfileHint','TweaksPanel','PreviewButton','StartupGrid','StartupApplyButton','StartupSettingsButton','StartupFolderButton','AppsGrid','RemoveAppsButton','InstalledSettingsButton','DiagnosticHint','ProcessGrid','ExportButton','CompareButton','EffectsButton','HistoryGrid','RestoreButton','DetailsButton','StoreButton','StatusText','BusyBar')) {
        $script:Controls[$name]=$script:Window.FindName($name)
        if ($null -eq $script:Controls[$name]) { throw "Controle ausente: $name" }
    }
    $script:Checks=@{}; $script:Worker=$null; $script:Diagnostic=$null; $script:ProfileInitialized=$false
    Initialize-LeveRecoveryUI
    foreach ($item in Get-LeveCatalog) {
        $border=New-Object Windows.Controls.Border; $border.Padding='14,12'; $border.Margin='0,0,0,8'; $border.Background='#F3F6F9'; $border.CornerRadius=6
        $stack=New-Object Windows.Controls.StackPanel
        $check=New-Object Windows.Controls.CheckBox; $check.Content=$item.Title; $check.FontSize=14; $check.FontWeight='SemiBold'
        $check.ToolTip=$item.Category; $script:Checks[$item.Id]=$check
        $description=New-Object Windows.Controls.TextBlock; $description.Text=$item.Category+' / '+$item.Description
        $description.TextWrapping='Wrap'; $description.Foreground='#607285'; $description.Margin='22,7,0,0'
        [void]$stack.Children.Add($check); [void]$stack.Children.Add($description); $border.Child=$stack
        [void]$script:Controls.TweaksPanel.Children.Add($border)
    }
    $script:Timer=New-Object Windows.Threading.DispatcherTimer; $script:Timer.Interval=[timespan]::FromMilliseconds(150)
    $script:Timer.Add_Tick({
        if ($script:Worker -and $script:Worker.Handle.IsCompleted) {
            $script:Timer.Stop(); $worker=$script:Worker; $script:Worker=$null
            try {
                $results=$worker.PS.EndInvoke($worker.Handle)
                if ($worker.PS.HadErrors) { throw ($worker.PS.Streams.Error | Out-String) }
                Set-LeveBusy $false 'Operação concluida.'
                & $worker.Done ($results | Select-Object -Last 1)
            } catch {
                Set-LeveBusy $false 'Operação não concluida. Consulte os detalhes e o histórico.'
                if ($script:SmokeMode) { $script:SmokeError=$_.Exception.Message }
                else { [void](Show-LeveDialog 'Detalhes do erro' $_.Exception.Message) }
            } finally { $worker.PS.Dispose() }
        }
    })
    $script:Controls.ProfileCombo.Add_SelectionChanged({Update-LeveProfile})
    $script:Controls.RefreshButton.Add_Click({Start-LeveWork 'Analyze' $null {param($r) Update-LeveView $r}})
    $script:Controls.PreviewButton.Add_Click({Show-LevePlan @($script:Checks.Keys | Where-Object {$script:Checks[$_].IsChecked})})
    $script:Controls.StartupApplyButton.Add_Click({Show-LevePlan @($script:Controls.StartupGrid.ItemsSource | Where-Object { $_.Selected -and -not $_.Protected } | ForEach-Object Id)})
    $script:Controls.StartupSettingsButton.Add_Click({Start-Process 'ms-settings:startupapps'})
    $script:Controls.StartupFolderButton.Add_Click({Start-Process explorer.exe -ArgumentList 'shell:startup'})
    $script:Controls.InstalledSettingsButton.Add_Click({Start-Process 'ms-settings:appsfeatures'})
    $script:Controls.EffectsButton.Add_Click({Start-Process 'ms-settings:easeofaccess-visualeffects'})
    $script:Controls.RemoveAppsButton.Add_Click({
        $selected=@($script:Controls.AppsGrid.ItemsSource | Where-Object Selected)
        if (-not $selected.Count) { [void](Show-LeveDialog 'Seleção vazia' 'Marque os aplicativos que você não usa.'); return }
        $body="A desinstalação pode apagar dados locais. Exporte projetos e dados antes de continuar.`r`n`r`n"+ (($selected | ForEach-Object {"$($_.Title): $($_.Impact)"}) -join "`r`n`r`n")+"`r`n`r`nO histórico guarda nomes e links para reinstalar, mas NÃO guarda os dados dos apps. A disponibilidade futura na Store depende da Microsoft."
        if (Show-LeveDialog 'Confirmar desinstalação' $body 'Desinstalar os selecionados' -Cancel) { Start-LeveWork 'Remove' @($selected | ForEach-Object Name) {param($r) Show-LeveResult $r} }
    })
    $script:Controls.ExportButton.Add_Click({
        if (-not $script:Diagnostic) { return }
        $save=New-Object Microsoft.Win32.SaveFileDialog; $save.Filter='Medição JSON|*.json'; $save.FileName='Leve11-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json'
        if ($save.ShowDialog($script:Window)) {
            try { Save-LeveJson $save.FileName $script:Diagnostic; $script:Controls.StatusText.Text='Medição salva: '+$save.FileName }
            catch { [void](Show-LeveDialog 'Erro ao salvar' $_.Exception.Message) }
        }
    })
    $script:Controls.CompareButton.Add_Click({
        if (-not $script:Diagnostic) { return }
        $open=New-Object Microsoft.Win32.OpenFileDialog; $open.Filter='Medição JSON|*.json'
        if ($open.ShowDialog($script:Window)) {
            try {
                $old=Get-Content -LiteralPath $open.FileName -Raw | ConvertFrom-Json
                if (-not ($old.PSObject.Properties.Name -contains 'UsedGB') -or -not ($old.PSObject.Properties.Name -contains 'Timestamp')) { throw 'Arquivo não é uma medição do Leve11.' }
                $delta=[math]::Round(($script:Diagnostic.UsedGB-[double]$old.UsedGB),2)
                [void](Show-LeveDialog 'Comparação de medições' "Anterior ($($old.Timestamp)): $($old.UsedGB) GB em uso.`r`nAtual ($($script:Diagnostic.Timestamp)): $($script:Diagnostic.UsedGB) GB em uso.`r`nVariação: $delta GB (negativo significa menos uso).`r`n`r`nEsta diferença não prova ganho causado pelos ajustes. Compare após reiniciar, com o mesmo conjunto de apps e tempo de espera. Cache, atualizações e o próprio Leve11 influenciam a leitura.")
            } catch { [void](Show-LeveDialog 'Erro ao comparar' $_.Exception.Message) }
        }
    })
    $script:Controls.RestoreButton.Add_Click({
        $session=$script:Controls.HistoryGrid.SelectedItem
        if (-not $session -or $session.Type -ne 'Settings') { [void](Show-LeveDialog 'Selecione uma sessão de ajustes' 'A restauração automática vale para ajustes. Para aplicativos, use Reinstalar apps pela Store.'); return }
        if (Show-LeveDialog 'Restaurar ajustes' "Restaurar os valores anteriores da sessão $($session.Id)?`r`n`r`nEntradas de inicialização restauradas voltam a abrir no próximo login. A sessão deve ser a mais recente ainda não restaurada." 'Restaurar' -Cancel) { Start-LeveWork 'Restore' $session.Id {param($r) Show-LeveResult $r} }
    })
    $script:Controls.DetailsButton.Add_Click({
        $session=$script:Controls.HistoryGrid.SelectedItem
        if ($session) { [void](Show-LeveDialog 'Registro da sessão' ($session | ConvertTo-Json -Depth 12)) }
    })
    $script:Controls.StoreButton.Add_Click({
        $session=$script:Controls.HistoryGrid.SelectedItem
        if (-not $session -or $session.Type -ne 'Apps') { [void](Show-LeveDialog 'Selecione uma sessão de aplicativos' 'O histórico de desinstalação contem os links dos apps removidos.'); return }
        # Copyable links, one Store window per explicit selection; no automatic installs.
        $body=(@($session.Operations | ForEach-Object {"$($_.Title)`r`nhttps://apps.microsoft.com/detail/$($_.Store)`r`n"}) -join "`r`n")+"`r`nCopie o link do app desejado no navegador para reinstalar. Dados locais não são recuperados pelo Leve11."
        [void](Show-LeveDialog 'Links para reinstalar' $body)
    })
    $script:Window.Add_Closing({
        if ($script:Worker) { $_.Cancel=$true; $script:Controls.StatusText.Text='Aguarde a operação terminar antes de fechar.' }
    })
    Update-LeveProfile
    if ($SmokeTest) {
        # Exercise the real async read-only worker and dispatcher without showing a window.
        Start-LeveWork 'Analyze' $null {param($r) Update-LeveView $r}
        function Wait-LeveSmokeWorker {
            $deadline=(Get-Date).AddSeconds(40)
            while ($script:Worker -and (Get-Date) -lt $deadline) {
                $frame=New-Object Windows.Threading.DispatcherFrame
                $pulse=New-Object Windows.Threading.DispatcherTimer
                $pulse.Interval=[timespan]::FromMilliseconds(100)
                $pulse.Tag=$frame
                $pulse.Add_Tick({$this.Tag.Continue=$false; $this.Stop()})
                $pulse.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
            }
            if ($script:Worker) { throw 'Timeout no worker da interface.' }
            if ($script:SmokeError) { throw $script:SmokeError }
        }
        Wait-LeveSmokeWorker
        if (-not $script:Diagnostic -or $script:Controls.ProcessGrid.Items.Count -eq 0) { throw 'Diagnóstico não chegou a interface.' }
        Start-LeveWork 'Drivers' $null {param($r) Update-LeveDriverView $r}
        Wait-LeveSmokeWorker
        Start-LeveWork 'Malware' $null {param($r) Update-LeveMalwareView $r}
        Wait-LeveSmokeWorker
        # Deterministic, non-personal values for the distributable preview.
        $script:Controls.UsedText.Text='5,2 GB / 33%'; $script:Controls.AvailableText.Text='10,5 GB'
        $script:Controls.MemoryDetail.Text='15,7 GB utilizáveis / 16 GB detectados'
        $script:Controls.ProfileText.Text='16 GB'; $script:Controls.ProfileCombo.SelectedIndex=2
        $script:Controls.StatusText.Text='Prévia ilustrativa. Abra o Leve11 para analisar o seu computador.'
        $script:Controls.DriverGrid.ItemsSource=@([pscustomobject]@{Title='Dispositivo de exemplo';Code=43;Version='1.2.3';InfName='oem42.inf';Advice=(Get-LeveDriverAdvice 43)})
        $script:Controls.DriverHint.Text='Exemplo ilustrativo: um código de falha é um indício. Selecione o dispositivo para criar backup ou use Reverter driver para orientação.'
        $script:Controls.MalwareHint.Text='Exemplo ilustrativo. Consultar o estado não executa varredura nem comprova ausência de malware.'
        $script:Controls.ThreatGrid.ItemsSource=@()
        $script:Controls.DefenderDetails.Text='Dados de exemplo: Defender em modo normal. Consulte o estado no seu computador para ver proteção e datas das verificações.'
        $root=$script:Window.Content
        foreach ($preview in @(@(0,'preview.png'),@(5,'preview-drivers.png'),@(6,'preview-malware.png'))) {
            $script:Controls.Tabs.SelectedIndex=$preview[0]
            $root.Measure([Windows.Size]::new(1120,780)); $root.Arrange([Windows.Rect]::new(0,0,1120,780)); $root.UpdateLayout()
            # Let deferred DataGrid column/binding layout run before the offscreen render.
            $script:Window.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
            $root.UpdateLayout()
            $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap 1120,780,96,96,([Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($root)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $out=Join-Path (Split-Path -Parent $script:EngineFile) ('..\docs\'+$preview[1])
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $out))
            $stream=[IO.File]::Create($out)
            try { $encoder.Save($stream) } finally { $stream.Dispose() }
        }
        'WPF carregado: '+$script:Controls.Count+' controles; '+$script:Checks.Count+' ajustes.'
        'Worker de análise e bindings verificados; preview ilustrativa salva em docs/preview.png.'
        $script:Window.Close()
        return
    }
    $script:Window.Add_Loaded({Start-LeveWork 'Analyze' $null {param($r) Update-LeveView $r}})
    [void]$script:Window.ShowDialog()
    $script:Timer.Stop()
}
