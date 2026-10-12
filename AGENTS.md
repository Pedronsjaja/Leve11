# Instrucoes do projeto

PowerShell Windows 5.1; src/Engine.ps1 e src/Recovery.ps1 implementam operacoes, Leve11.ps1 e entrada. Preservar WhatIf, backups, journal e validacao de destinos. Testes nao podem otimizar/remover aplicativos reais.

Ler README e docs antes de alterar. Preservar arquitetura, dados brutos e
autoria/licencas dos materiais externos. Nao inventar hardware, medidas ou
resultados. Marcar UNKNOWN/NOT_MEASURED e separar SIMULATED de REAL.
Fazer mudancas pequenas, com regressao para defeitos corrigidos.

Validacao: powershell.exe -NoProfile -File tests/Test-Engine.ps1; repetir para Test-Recovery.ps1 e Test-CLI.ps1.

Definition of Done: verificacoes pertinentes, documentacao das alteracoes,
comandos reproduziveis e limites de validacao. Inspecao estatica nao comprova
funcionamento fisico. Ver docs/engineering-status.md para prioridades e estudo.
