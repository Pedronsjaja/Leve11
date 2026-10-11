Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Catalog.ps1"
$script:DataRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Leve11'
$script:RunPath = 'Software\Microsoft\Windows\CurrentVersion\Run'
. "$PSScriptRoot\Recovery.ps1"

function Get-LeveIdentity {
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Assert-LeveWindows {
    if (-not [Environment]::Is64BitProcess) { throw 'Use o Windows PowerShell de 64 bits.' }
    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]$os.BuildNumber -lt 22000 -or [int]$os.ProductType -ne 1) {
        throw 'Este programa requer Windows 11 (build 22000 ou superior).'
    }
}

function Get-LeveDiagnostic {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $total = [double]$os.TotalVisibleMemorySize / 1MB
    $available = [double]$os.FreePhysicalMemory / 1MB
    $installed = [double]$cs.TotalPhysicalMemory / 1GB
    try {
        $modules=@(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
        $capacity=($modules | Measure-Object -Property Capacity -Sum).Sum
        if ($capacity -gt 0) { $installed=[double]$capacity / 1GB }
    } catch { } # CIM fallback can report usable RAM; enough for a conservative profile.
    [pscustomobject]@{
        Timestamp=(Get-Date).ToString('o'); Build=$os.BuildNumber
        InstalledGB=[math]::Round($installed,2); UsableGB=[math]::Round($total,2)
        AvailableGB=[math]::Round($available,2); UsedGB=[math]::Round(($total-$available),2)
        UsedPercent=[math]::Round(100*($total-$available)/$total,1)
        RecommendedProfile=(Get-LeveProfile $installed)
        SystemManagedPagefile=[bool]$cs.AutomaticManagedPagefile
        UptimeHours=[math]::Round(((Get-Date)-$os.LastBootUpTime).TotalHours,1)
        Processes=@(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 12 @{n='Name';e={$_.ProcessName}},Id,@{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,1)}})
    }
}

# Registry values are read unexpanded: REG_EXPAND_SZ must round-trip exactly.
function Get-LeveRegistry([string]$Path,[string]$Name) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    try {
        if ($null -eq $key -or $key.GetValueNames() -notcontains $Name) {
            return [pscustomobject]@{ Exists=$false; Kind=''; Value=$null }
        }
        [pscustomobject]@{ Exists=$true; Kind=$key.GetValueKind($Name).ToString(); Value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    } finally { if ($key) { $key.Dispose() } }
}

function Set-LeveRegistry([string]$Path,[string]$Name,$State) {
    if (-not $State.Exists) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path,$true)
        try { if ($key) { $key.DeleteValue($Name,$false) } } finally { if ($key) { $key.Dispose() } }
        return
    }
    $kind = [Microsoft.Win32.RegistryValueKind]::$($State.Kind)
    $value = $State.Value
    switch ($State.Kind) {
        'DWord' { $value = [int]$value }
        'QWord' { $value = [long]$value }
        'Binary' { $value = [byte[]]$value }
        'MultiString' { $value = [string[]]$value }
        'String' { $value = [string]$value }
        'ExpandString' { $value = [string]$value }
        default { throw "Tipo de registro não suportado: $($State.Kind)" }
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
    try { $key.SetValue($Name,$value,$kind) } finally { $key.Dispose() }
}

function Test-LeveEqual($A,$B) {
    if ([bool]$A.Exists -ne [bool]$B.Exists) { return $false }
    if (-not $A.Exists) { return $true }
    return ($A.Kind -eq $B.Kind -and (ConvertTo-Json -InputObject $A.Value -Compress) -ceq (ConvertTo-Json -InputObject $B.Value -Compress))
}

function Save-LeveJson([string]$Path,$Data) {
    $directory = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($directory)
    $temp = Join-Path $directory ([guid]::NewGuid().ToString()+'.tmp')
    try {
        [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject $Data -Depth 20),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Get-LeveStartup {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:RunPath)
    try {
        if ($key) {
            foreach ($name in $key.GetValueNames()) {
                $state = Get-LeveRegistry $script:RunPath $name
                if ($state.Kind -notin @('String','ExpandString')) { continue }
                $protected = ($name+' '+$state.Value) -match '(?i)securityhealth|defender|antivirus|malwarebytes|kaspersky|bitdefender|avast|eset|sophos|crowdstrike|sentinel|forti|vpn|onedrive|dropbox|google.drive|realtek|synaptics|touchpad|nvidia|radeon|intel'
                [pscustomobject]@{ Id=('startup:'+ $name); Title=$name; Command=[string]$state.Value; Protected=$protected; Selected=$false; Note=$(if ($protected) {'Preservado: segurança, driver, VPN ou sincronização. Use as configurações do aplicativo.'} else {'Revisar: remover do login não fecha o app agora. Pode ser recriado pelo próprio aplicativo.'}) }
            }
        }
    } finally { if ($key) { $key.Dispose() } }
}

function Get-LeveInstalledApps {
    $installed = @(Get-AppxPackage -ErrorAction Stop)
    foreach ($app in Get-LeveAppCatalog) {
        $matches = @($installed | Where-Object { $_.Name -eq $app.Name -and -not $_.NonRemovable -and -not $_.IsFramework })
        if ($matches.Count -gt 0) {
            [pscustomobject]@{ Name=$app.Name; Title=$app.Title; Category=$app.Category; Impact=$app.Impact; Store=$app.Store; Selected=$false }
        }
    }
}

function Get-LevePlan([string[]]$Ids) {
    $catalog = @(Get-LeveCatalog)
    $startup = @(Get-LeveStartup)
    foreach ($id in @($Ids | Select-Object -Unique)) {
        $item = $catalog | Where-Object Id -eq $id | Select-Object -First 1
        if ($item) {
            # A machine policy takes precedence over this per-user choice.
            if ($item.Path -like 'Software\Policies\*') {
                $machine = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($item.Path)
                try {
                    if ($machine -and $machine.GetValueNames() -contains $item.Name) {
                        throw "Política de computador existente para $($item.Title). Ajuste não sera sobrescrito."
                    }
                } finally { if ($machine) { $machine.Dispose() } }
            }
            $path=$item.Path; $name=$item.Name; $title=$item.Title
            $desired=[pscustomobject]@{ Exists=$true; Kind=$item.Kind; Value=$item.Value }
        } elseif ($id.StartsWith('startup:')) {
            $entry = $startup | Where-Object Id -eq $id | Select-Object -First 1
            if (-not $entry -or $entry.Protected) { throw "Inicialização ausente ou protegida: $id" }
            $path=$script:RunPath; $name=$entry.Title; $title="Não iniciar no login: $name"
            $desired=[pscustomobject]@{ Exists=$false; Kind=''; Value=$null }
        } else { throw "Ajuste desconhecido: $id" }
        $before = Get-LeveRegistry $path $name
        [pscustomobject]@{ Id=$id; Title=$title; Path=$path; Name=$name; Before=$before; After=$desired; Needed=(-not (Test-LeveEqual $before $desired)); Status='Pending'; Error='' }
    }
}

function Enter-LeveLock {
    [void][IO.Directory]::CreateDirectory($script:DataRoot)
    try { return [IO.File]::Open((Join-Path $script:DataRoot 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw 'Outra operação do Leve11 está em andamento. Feche a outra instancia.' }
}

function Invoke-LeveApply {
    [CmdletBinding(SupportsShouldProcess)]
    param([string[]]$Ids)
    Assert-LeveWindows
    $plan = @(Get-LevePlan $Ids)
    if (-not $PSCmdlet.ShouldProcess("$($plan.Count) ajustes do usuário atual",'Aplicar com backup')) { return $plan }
    $lock=Enter-LeveLock
    try {
        # Re-read under lock; never keep a stale snapshot from the preview.
        $plan=@(Get-LevePlan $Ids | Where-Object Needed)
        if ($plan.Count -eq 0) { return [pscustomobject]@{ Id=''; Status='NoChanges'; Operations=@(); Message='Os ajustes selecionados já estão configurados.' } }
        $id=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
        $path=Join-Path $script:DataRoot ('history\'+$id+'.json')
        $session=[pscustomobject]@{ Schema=1; Id=$id; UserSid=(Get-LeveIdentity); Computer=$env:COMPUTERNAME; Created=(Get-Date).ToString('o'); Type='Settings'; Status='Applying'; Operations=$plan }
        Save-LeveJson $path $session
        foreach ($op in $plan) {
            try {
                if (-not (Test-LeveEqual (Get-LeveRegistry $op.Path $op.Name) $op.Before)) { throw 'O valor mudou depois do backup. Atualize a análise.' }
                # Journal flushed BEFORE mutation: recoverable if the process terminates.
                $op.Status='Applying'; Save-LeveJson $path $session
                Set-LeveRegistry $op.Path $op.Name $op.After
                if (-not (Test-LeveEqual (Get-LeveRegistry $op.Path $op.Name) $op.After)) { throw 'A verificação do valor gravado falhou.' }
                $op.Status='Applied'
            } catch { $op.Status='Failed'; $op.Error=$_.Exception.Message }
            Save-LeveJson $path $session
        }
        $session.Status=if (@($plan | Where-Object Status -eq 'Failed').Count) {'Partial'} else {'Applied'}
        Save-LeveJson $path $session
        return $session
    } finally { $lock.Dispose() }
}

function Get-LeveHistory {
    $folder=Join-Path $script:DataRoot 'history'
    if (-not (Test-Path -LiteralPath $folder)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.json' | Sort-Object Name -Descending) {
        try { Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json }
        catch { Write-Warning "Histórico ilegível: $($file.Name). Preserve o arquivo para análise." }
    }
}

function Assert-LeveOperation($Op) {
    $item=Get-LeveCatalog | Where-Object Id -eq $Op.Id | Select-Object -First 1
    if ($item) {
        $expected=[pscustomobject]@{Exists=$true;Kind=$item.Kind;Value=$item.Value}
        if ($Op.Path -cne $item.Path -or $Op.Name -cne $item.Name -or -not (Test-LeveEqual $Op.After $expected)) { throw 'Backup contem destino inesperado.' }
    } elseif ($Op.Id -ceq ('startup:'+$Op.Name) -and $Op.Path -ceq $script:RunPath -and -not $Op.After.Exists -and $Op.Before.Kind -in @('String','ExpandString')) {
        # Only restores inert registry data; never executes a backed-up command.
    } else { throw 'Operação desconhecida no backup.' }
}

function Restore-LeveSession {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)
    Assert-LeveWindows
    if ($Id -notmatch '^\d{8}-\d{6}-\d{3}-[a-f0-9]{8}$') { throw 'ID de histórico inválido.' }
    if (-not $PSCmdlet.ShouldProcess($Id,'Restaurar ajustes do usuário')) { return }
    $lock=Enter-LeveLock
    try {
        $sessions=@(Get-LeveHistory)
        $session=$sessions | Where-Object Id -eq $Id | Select-Object -First 1
        if (-not $session -or $session.Type -ne 'Settings' -or $session.Schema -ne 1) { throw 'Backup de ajustes não encontrado ou incompatível.' }
        if ($session.UserSid -ne (Get-LeveIdentity) -or $session.Computer -ne $env:COMPUTERNAME) { throw 'O backup pertence a outro usuário ou computador.' }
        $latest=$sessions | Where-Object { $_.Type -eq 'Settings' -and $_.Status -ne 'Restored' } | Select-Object -First 1
        if ($latest -and $latest.Id -ne $Id) { throw 'Restaure primeiro a sessão de ajustes mais recente.' }
        foreach ($op in $session.Operations) { Assert-LeveOperation $op }
        $path=Join-Path $script:DataRoot ('history\'+$Id+'.json')
        $ops=@($session.Operations); [array]::Reverse($ops)
        foreach ($op in $ops) {
            if ($op.Status -eq 'Restored') { continue }
            try {
                $current=Get-LeveRegistry $op.Path $op.Name
                if (Test-LeveEqual $current $op.Before) { $op.Status='Restored'; $op.Error='' }
                elseif (Test-LeveEqual $current $op.After) {
                    Set-LeveRegistry $op.Path $op.Name $op.Before
                    if (-not (Test-LeveEqual (Get-LeveRegistry $op.Path $op.Name) $op.Before)) { throw 'Verificação da restauração falhou.' }
                    $op.Status='Restored'; $op.Error=''
                } else { $op.Status='Conflict'; $op.Error='Alterado fora do Leve11. Preservado para não sobrescrever sua nova preferência.' }
            } catch { $op.Status='RestoreFailed'; $op.Error=$_.Exception.Message }
            Save-LeveJson $path $session
        }
        $session.Status=if (@($ops | Where-Object Status -ne 'Restored').Count) {'RestorePartial'} else {'Restored'}
        Save-LeveJson $path $session
        $session
    } finally { $lock.Dispose() }
}

function Remove-LeveApps {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Names)
    Assert-LeveWindows
    $catalog=@(Get-LeveAppCatalog)
    foreach ($name in $Names) { if ($catalog.Name -notcontains $name) { throw "Pacote fora do catálogo permitido: $name" } }
    if (-not $PSCmdlet.ShouldProcess(($Names -join ', '),'Desinstalar para este usuário; dados locais podem ser perdidos')) { return }
    $lock=Enter-LeveLock
    try {
        $id=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
        $path=Join-Path $script:DataRoot ('history\'+$id+'.json')
        $ops=@(foreach ($name in ($Names | Select-Object -Unique)) {
            $app=$catalog | Where-Object Name -eq $name | Select-Object -First 1
            [pscustomobject]@{ Name=$name; Title=$app.Title; Store=$app.Store; Status='Pending'; Error='' }
        })
        $session=[pscustomobject]@{Schema=1; Id=$id; UserSid=(Get-LeveIdentity); Computer=$env:COMPUTERNAME; Created=(Get-Date).ToString('o'); Type='Apps'; Status='Removing'; Operations=$ops}
        Save-LeveJson $path $session
        foreach ($op in $ops) {
            try {
                $packages=@(Get-AppxPackage -Name $op.Name -ErrorAction Stop | Where-Object { $_.Name -eq $op.Name })
                if (@($packages | Where-Object { $_.NonRemovable -or $_.IsFramework }).Count) { throw 'Pacote protegido pelo Windows.' }
                $op.Status='Removing'; Save-LeveJson $path $session
                foreach ($pkg in $packages) { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop }
                if (@(Get-AppxPackage -Name $op.Name -ErrorAction Stop).Count) { throw 'O pacote continua registrado. Consulte o Windows.' }
                $op.Status='Removed'
            } catch { $op.Status='Failed'; $op.Error=$_.Exception.Message }
            Save-LeveJson $path $session
        }
        $session.Status=if (@($ops | Where-Object Status -eq 'Failed').Count) {'Partial'} else {'Removed'}
        Save-LeveJson $path $session
        $session
    } finally { $lock.Dispose() }
}
