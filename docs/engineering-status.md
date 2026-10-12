# Testes publicados e limites

As suites locais de desenvolvimento agora fazem parte do repositorio e do
CI Windows. Nesta revisao: 35 verificacoes do motor, 24 de recuperacao e a
suite CLI passaram. O historico de 73 testes da versao 1.2.0 no README nao
deve ser confundido com a contagem destas suites publicadas.

Engine usa somente uma chave HKCU Software/Leve11.Tests/<GUID> e diretorio
temporario exclusivo. Remocao Appx e simulada. Recovery substitui PnP,
Defender e CIM por doubles: nenhum driver e reinstalado e nenhum scan real
e iniciado. CLI valida Plan e Apply -WhatIf e compara o estado antes/depois.

ALTO: manter restauracao, conflitos e falhas parciais cobertos; MEDIO:
publicar ensaio controlado antes/depois para qualquer alegacao de economia;
BAIXO: ampliar matriz de builds Windows. RAM economizada: NOT_MEASURED.
Testes aprovados nao homologam todas as versoes do Windows.

O runner hospedado do GitHub usa Windows Server. A suite isolada do motor
substitui Assert-LeveWindows somente no processo de teste. A suite CLI
confirma a recusa desse sistema; os cenarios CLI de perfis/WhatIf exigem
Windows 11 e foram executados localmente. O bloqueio de producao permanece.

Para entender esta implementacao: siga plano → backup → aplicacao →
verificacao → restauracao. Estude idempotencia, compensacao e ShouldProcess.
Desafio: injete falha depois de uma escrita e confira se a restauracao
respeita uma alteracao posterior feita pelo usuario.

Referencia: [ShouldProcess](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess).
O mecanismo permite WhatIf/Confirm; testes ainda precisam demonstrar que
todos os efeitos reais estao protegidos.
