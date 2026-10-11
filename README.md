# Leve11

Otimizador portátil para Windows 11, em português, com perfis de RAM, controle de inicialização, recuperação de drivers e verificações pelo Microsoft Defender.

**[Baixar o Leve11 pronto para usar](https://github.com/Pedronsjaja/Leve11/releases/latest)**

## Como usar

1. Baixe o arquivo `Leve11-1.1.0.zip` na página de versões.
2. Extraia a pasta inteira. Não execute de dentro do ZIP.
3. Abra **Iniciar.cmd** com dois cliques.
4. Revise as opções sugeridas e confirme as alterações desejadas.

Para backup/reinstalação de drivers e verificações do Defender, clique com o botão direito em `Iniciar.cmd` e escolha **Executar como administrador**, usando a mesma conta.

Requer Windows 11 e Windows PowerShell 5.1 de 64 bits, incluído no sistema. Mantenha `Leve11.ps1` e a pasta `src` junto do iniciador: são os arquivos necessários ao funcionamento. Não é necessário instalar Python, Node.js ou outro programa. O iniciador permite a execução de scripts somente no processo atual, sem alterar a política permanente do Windows.

## O que você pode fazer

| Área | Funções |
|---|---|
| Ajustes | Perfis sugeridos para 8, 12, 16 e mais de 16 GB de RAM; revisão antes de aplicar |
| Inicialização | Desativação reversível de entradas Run do usuário; acesso à lista completa do Windows |
| Aplicativos | Remoção seletiva de aplicativos opcionais instalados |
| Diagnóstico | Uso de RAM, processos e comparação de medições |
| Histórico | Restauração dos valores originais dos ajustes |
| Drivers | Códigos de problema, eventos recentes, backup e reinstalação de pacote; orientação para reverter pelo Windows |
| Malware | Estado e ameaças reportadas pelo Defender, atualização de definições, verificações rápida/completa e orientação para verificação offline |

Nenhum aplicativo é removido automaticamente por um perfil. Acima de 16 GB, as opções começam desmarcadas. Escolha conforme seu uso; não há promessa de liberar uma quantidade fixa de RAM.

## Precisa executar sempre?

Não. Os ajustes permanecem após fechar o programa e reiniciar. O Leve11 não instala serviço, tarefa agendada ou processo de bandeja. Reveja as opções se novos aplicativos ou uma atualização mudarem o comportamento do computador.

## Restaurar ajustes

Na aba **Histórico**, selecione a sessão mais recente ainda ativa e clique em **Restaurar sessão selecionada**. Restaure sessões anteriores em ordem inversa. Alterações feitas por outros programas são sinalizadas como conflito e preservadas.

Os backups ficam em `%LOCALAPPDATA%\Leve11\history`. Guarde essa pasta. São backups dos ajustes, não uma imagem completa do Windows. Aplicativos desinstalados precisam ser reinstalados pela Store; seus dados locais não são guardados pelo Leve11.

## Drivers

Crie o backup enquanto o dispositivo funciona. O backup do driver atual não cria uma versão anterior ao problema. Em **Reinstalar backup**, selecione `driver-backup.json` e mantenha junto dele toda a pasta `package`.

O Windows decide se o pacote é compatível e tem prioridade: reinstalar não força uma versão antiga nem garante corrigir o bug. **Reverter driver...** mostra como usar a reversão nativa pelo Gerenciador de Dispositivos, quando existe uma versão anterior disponível. Nenhum driver é trocado automaticamente após o diagnóstico.

Backups e logs ficam em `%LOCALAPPDATA%\Leve11\drivers`. Use seus próprios backups confiáveis. Drivers nativos do Windows não são exportados pela opção de backup de pacotes de terceiros.

## Malware

**Consultar estado** não executa uma varredura. Nenhuma lista vazia garante ausência de malware. O programa identifica consultas incompletas e Defender passivo ou indisponível, sem interferir em outro antivírus.

Verificações rápida/completa exigem confirmação. O Defender pode colocar arquivos em quarentena conforme suas políticas. Durante a verificação, mantenha o Leve11 aberto; o botão **Segurança do Windows** permite acompanhar ou cancelar pelo próprio Windows. A verificação completa pode levar horas.

**Offline...** abre instruções: a confirmação da verificação e da reinicialização fica na Segurança do Windows. Salve seu trabalho antes. Logs das verificações iniciadas pelo programa ficam em `%LOCALAPPDATA%\Leve11\security`.

## Sobre esta versão

Versão **1.1.0**, licença MIT. Validada com 59 testes do motor/recuperação, testes CLI e carregamento da interface. Reinstalação de drivers e varreduras foram testadas com simulações; não há homologação em todas as builds do Windows nem benchmark de economia de RAM.

Os ajustes de desempenho preservam Defender, Windows Update, paginação e serviços. A ferramenta usa recursos do Windows e não baixa drivers de sites externos.