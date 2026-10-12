#requires -Version 5.1
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\src\Engine.ps1"
$script:Passed=0
function Assert($Condition,[string]$Message) {
    if (-not $Condition) { throw "FALHOU: $Message" }
    $script:Passed++; Write-Output "OK: $Message"
}
function Assert-Throws([scriptblock]$Action,[string]$Message) {
    $thrown=$false
    try { & $Action | Out-Null } catch { $thrown=$true }
    Assert $thrown $Message
}

# Real Windows registry IO, but exclusively inside a unique test key.
# No production tuning, startup command or app package is modified.
$testId=[guid]::NewGuid().ToString('N')
$script:FixturePath='Software\Leve11.Tests\'+$testId
$script:DataRoot=Join-Path $env:TEMP ('Leve11.Tests-'+$testId)
$script:RunPath=$script:FixturePath+'\Run'
function Get-LeveCatalog {
    @(
        [pscustomobject]@{ Id='test-a'; Title='A'; Path=$script:FixturePath; Name='A'; Value=0; Kind='DWord' }
        [pscustomobject]@{ Id='test-b'; Title='B'; Path=$script:FixturePath; Name='B'; Value=0; Kind='DWord' }
    )
}
try {
    Assert ((Get-LeveProfile 7.7) -eq '8') 'Perfil 8 GB'
    Assert ((Get-LeveProfile 11.5) -eq '12') 'Perfil 12 GB'
    Assert ((Get-LeveProfile 15.3) -eq '16') 'Perfil 16 GB'
    Assert ((Get-LeveProfile 24) -eq '32' -and (Get-LeveProfile 64) -eq '32') 'Acima de 16 GB: sob demanda'
    $original=[pscustomobject]@{Exists=$true;Kind='DWord';Value=1}
    Set-LeveRegistry $script:FixturePath 'A' $original
    Assert (Test-LeveEqual (Get-LeveRegistry $script:FixturePath 'A') $original) 'Leitura/gravação DWORD real em chave isolada'
    $plan=@(Invoke-LeveApply -Ids @('test-a','test-b') -WhatIf)
    Assert ($plan.Count -eq 2 -and -not (Test-Path -LiteralPath $script:DataRoot)) 'WhatIf sem histórico ou mutacao'
    Assert (Test-LeveEqual (Get-LeveRegistry $script:FixturePath 'A') $original) 'WhatIf preserva valor'
    Assert-Throws {Get-LevePlan @('unknown')} 'IDs desconhecidos bloqueados'
    $session=Invoke-LeveApply @('test-a','test-b') -Confirm:$false
    Assert ($session.Status -eq 'Applied') 'Aplicacao verificada'
    $history=@(Get-LeveHistory)
    Assert ($history.Count -eq 1 -and $history[0].Operations[0].Before.Value -eq 1) 'Backup preserva valor original'
    $again=Invoke-LeveApply @('test-a','test-b') -Confirm:$false
    Assert ($again.Status -eq 'NoChanges' -and @(Get-LeveHistory).Count -eq 1) 'Idempotência: não sobrescreve backup'
    $restored=Restore-LeveSession $session.Id -Confirm:$false
    Assert ($restored.Status -eq 'Restored') 'Restaura sessão'
    Assert (Test-LeveEqual (Get-LeveRegistry $script:FixturePath 'A') $original) 'Restaura valor existente'
    Assert (-not (Get-LeveRegistry $script:FixturePath 'B').Exists) 'Remove valor originalmente ausente'

    $s1=Invoke-LeveApply @('test-a') -Confirm:$false
    $s2=Invoke-LeveApply @('test-b') -Confirm:$false
    Assert-Throws {Restore-LeveSession $s1.Id -Confirm:$false} 'Restaura somente em ordem inversa'
    Restore-LeveSession $s2.Id -Confirm:$false | Out-Null
    Set-LeveRegistry $script:FixturePath 'A' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=9})
    $conflict=Restore-LeveSession $s1.Id -Confirm:$false
    Assert ($conflict.Status -eq 'RestorePartial' -and (Get-LeveRegistry $script:FixturePath 'A').Value -eq 9) 'Conflito preserva preferência externa'
    Set-LeveRegistry $script:FixturePath 'A' ([pscustomobject]@{Exists=$true;Kind='DWord';Value=0})
    Assert ((Restore-LeveSession $s1.Id -Confirm:$false).Status -eq 'Restored') 'Nova tentativa resolve conflito'

    $command=[pscustomobject]@{Exists=$true;Kind='ExpandString';Value='"%LOCALAPPDATA%\TestApp\app.exe" --background'}
    Set-LeveRegistry $script:RunPath 'FixtureApp' $command
    Set-LeveRegistry $script:RunPath 'OneDrive' $command
    $startup=@(Get-LeveStartup)
    Assert (@($startup | Where-Object { $_.Title -eq 'OneDrive' -and $_.Protected }).Count -eq 1) 'Sincronização reconhecida protegida'
    Assert-Throws {Get-LevePlan @('startup:OneDrive')} 'Proteção também no motor'
    $startupSession=Invoke-LeveApply @('startup:FixtureApp') -Confirm:$false
    Assert (-not (Get-LeveRegistry $script:RunPath 'FixtureApp').Exists) 'Remove entrada de login isolada'
    Restore-LeveSession $startupSession.Id -Confirm:$false | Out-Null
    Assert (Test-LeveEqual (Get-LeveRegistry $script:RunPath 'FixtureApp') $command) 'REG_EXPAND_SZ restaurado sem expandir variáveis'

    # Simulate a crash after mutation but before final journal status.
    $crash=Invoke-LeveApply @('test-a') -Confirm:$false
    $crash.Status='Applying'; $crash.Operations[0].Status='Applying'
    Save-LeveJson (Join-Path $script:DataRoot ('history\'+$crash.Id+'.json')) $crash
    Assert ((Restore-LeveSession $crash.Id -Confirm:$false).Status -eq 'Restored') 'Recuperação de sessão interrompida'
    Assert-Throws {Restore-LeveSession '..\escape' -Confirm:$false} 'Caminho de restauração validado'
    Assert-Throws {Remove-LeveApps @('Microsoft.WindowsStore') -Confirm:$false} 'Store fora do catálogo de remoção'
    $lock=Enter-LeveLock
    try { Assert-Throws {Enter-LeveLock} 'Concorrência bloqueada' } finally { $lock.Dispose() }
    $tampered=[pscustomobject]@{Id='test-a';Path='Software\Other';Name='A';After=$original}
    Assert-Throws {Assert-LeveOperation $tampered} 'Backup com destino adulterado rejeitado'

    # Inject write failure: another operation may succeed and must remain undoable.
    $script:RealSetter=${function:Set-LeveRegistry}
    function Set-LeveRegistry([string]$Path,[string]$Name,$State) {
        if ($Name -eq 'B' -and $State.Exists) { throw 'Falha injetada de gravação' }
        & $script:RealSetter $Path $Name $State
    }
    $partial=Invoke-LeveApply @('test-a','test-b') -Confirm:$false
    Assert ($partial.Status -eq 'Partial' -and @($partial.Operations | Where-Object Status -eq 'Failed').Count -eq 1) 'Falha parcial registrada sem falso sucesso'
    Assert ((Restore-LeveSession $partial.Id -Confirm:$false).Status -eq 'Restored') 'Falha parcial permite restauração'

    # Replace Appx commands in this process. No real package can be uninstalled here.
    $script:FakeRemoved=$false; $script:FakeRemoveCalls=0; $script:FakeRemoveFails=$false
    function Get-AppxPackage {
        param($Name,$ErrorAction)
        if (-not $script:FakeRemoved -and $Name -eq 'Clipchamp.Clipchamp') {
            [pscustomobject]@{Name='Clipchamp.Clipchamp';PackageFullName='FixturePackage_1';NonRemovable=$false;IsFramework=$false}
        }
    }
    function Remove-AppxPackage {
        param($Package,$ErrorAction)
        $script:FakeRemoveCalls++
        if ($script:FakeRemoveFails) { throw 'Falha Appx simulada' }
        $script:FakeRemoved=$true
    }
    $countBefore=@(Get-LeveHistory).Count
    Remove-LeveApps @('Clipchamp.Clipchamp') -WhatIf | Out-Null
    Assert ($script:FakeRemoveCalls -eq 0 -and @(Get-LeveHistory).Count -eq $countBefore) 'WhatIf de Appx sem remocao ou historico'
    $removed=Remove-LeveApps @('Clipchamp.Clipchamp') -Confirm:$false
    Assert ($removed.Status -eq 'Removed' -and $script:FakeRemoveCalls -eq 1) 'Remocao Appx simulada verificada'
    Assert ($removed.Operations[0].Store -eq '9P1J8S7CCWWT') 'Recibo inclui identificador para reinstalacao'
    $script:FakeRemoved=$false; $script:FakeRemoveFails=$true
    $removeFailed=Remove-LeveApps @('Clipchamp.Clipchamp') -Confirm:$false
    Assert ($removeFailed.Status -eq 'Partial' -and $removeFailed.Operations[0].Error -match 'simulada') 'Erro Appx registrado sem falso sucesso'

    foreach ($fixture in @(
        [pscustomobject]@{Exists=$true;Kind='Binary';Value=[byte[]]@(0,127,255)},
        [pscustomobject]@{Exists=$true;Kind='MultiString';Value=[string[]]@('first','second')},
        [pscustomobject]@{Exists=$true;Kind='QWord';Value=[long]9000000000}
    )) {
        $serialized=$fixture | ConvertTo-Json -Depth 4 | ConvertFrom-Json
        & $script:RealSetter $script:FixturePath 'Typed' $serialized
        Assert (Test-LeveEqual (Get-LeveRegistry $script:FixturePath 'Typed') $fixture) ('Round-trip JSON/registro: '+$fixture.Kind)
    }
    Write-Output "TOTAL: $script:Passed testes passaram."
} finally {
    # Fixed registry subtree and verified absolute temp path, never a user directory.
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:FixturePath,$false)
    $resolved=[IO.Path]::GetFullPath($script:DataRoot)
    $expected=[IO.Path]::GetFullPath((Join-Path $env:TEMP ('Leve11.Tests-'+$testId)))
    if ($resolved -ceq $expected -and (Split-Path -Leaf $resolved) -eq ('Leve11.Tests-'+$testId) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
