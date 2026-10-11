# Catálogo fechado: nenhuma configuração ou comando vem da internet.
function Get-LeveCatalog {
    @(
        [pscustomobject]@{ Id='edge-boost'; Category='Segundo plano'; Title='Edge: iniciar somente quando você abrir'; Description='Desliga a pré-carga do Edge no login. A primeira abertura pode demorar mais. A política aparece como gerenciada no navegador.'; Profiles=@('8','12','16'); Path='Software\Policies\Microsoft\Edge'; Name='StartupBoostEnabled'; Value=0; Kind='DWord' }
        [pscustomobject]@{ Id='edge-background'; Category='Segundo plano'; Title='Edge: encerrar tarefas ao fechar'; Description='Desliga o modo em segundo plano. Extensoes e apps web podem deixar de enviar avisos quando o Edge estiver fechado.'; Profiles=@('8','12','16'); Path='Software\Policies\Microsoft\Edge'; Name='BackgroundModeEnabled'; Value=0; Kind='DWord' }
        [pscustomobject]@{ Id='capture-background'; Category='Captura de jogos'; Title='Desativar gravação de jogos em segundo plano'; Description='Desliga a captura histórica do Game DVR. Deixe desmarcado se usa a funcao de gravar o que aconteceu. Não remove Xbox ou Game Bar.'; Profiles=@('8','12'); Path='Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name='HistoricalCaptureEnabled'; Value=0; Kind='DWord' }
        [pscustomobject]@{ Id='transparency'; Category='Aparência'; Title='Reduzir efeitos de transparência'; Description='Janelas e barra ficam opacas. Prioriza simplicidade visual; a economia de RAM pode ser pequena.'; Profiles=@('8'); Path='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Value=0; Kind='DWord' }
        [pscustomobject]@{ Id='suggestions'; Category='Conforto'; Title='Reduzir sugestões de conteúdo do Windows'; Description='Desativa uma preferência de sugestões do sistema. Ajuste de conforto, sem promessa de economia de RAM; pode variar por build.'; Profiles=@(); Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name='SubscribedContent-338388Enabled'; Value=0; Kind='DWord' }
    )
}

function Get-LeveAppCatalog {
    @(
        [pscustomobject]@{ Name='Clipchamp.Clipchamp'; Title='Clipchamp'; Category='Criação'; Impact='Editor de vídeo. Exporte seus projetos antes de remover.'; Store='9P1J8S7CCWWT' }
        [pscustomobject]@{ Name='Microsoft.BingNews'; Title='Notícias'; Category='Conteúdo'; Impact='Leitor de notícias da Microsoft.'; Store='9WZDNCRFHVFW' }
        [pscustomobject]@{ Name='Microsoft.BingWeather'; Title='Clima'; Category='Conteúdo'; Impact='Previsão do tempo; não desinstala o painel Widgets.'; Store='9WZDNCRFJ3Q2' }
        [pscustomobject]@{ Name='Microsoft.MicrosoftSolitaireCollection'; Title='Solitaire Collection'; Category='Jogos casuais'; Impact='Jogos de cartas e dados locais associados.'; Store='9WZDNCRFHWD2' }
        [pscustomobject]@{ Name='Microsoft.GetHelp'; Title='Obter Ajuda'; Category='Suporte'; Impact='Interface de suporte da Microsoft.'; Store='9PKDZBMV1H3T' }
        [pscustomobject]@{ Name='Microsoft.Getstarted'; Title='Dicas'; Category='Suporte'; Impact='Tutoriais do Windows, quando presentes.'; Store='9WZDNCRDTBJJ' }
        [pscustomobject]@{ Name='Microsoft.YourPhone'; Title='Vincular ao Celular'; Category='Conectividade'; Impact='Interrompe integração, chamadas e notificações do celular neste usuário.'; Store='9NMPJ99VJBWV' }
        [pscustomobject]@{ Name='MSTeams'; Title='Microsoft Teams'; Category='Comunicação'; Impact='Remove este pacote do Teams. Preserve se usa para trabalho ou reuniões.'; Store='XP8BT8DW290MPQ' }
        [pscustomobject]@{ Name='Microsoft.Copilot'; Title='Microsoft Copilot'; Category='Assistente'; Impact='Remove o aplicativo separado; não desativa recursos de IA de outros produtos.'; Store='9NHT9RB2F4HD' }
    )
}

function Get-LeveProfile([double]$MemoryGB) {
    if ($MemoryGB -le 8.5) { return '8' }
    if ($MemoryGB -le 12.5) { return '12' }
    if ($MemoryGB -le 16.5) { return '16' }
    return '32'
}
