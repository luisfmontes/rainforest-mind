# testa-rodar-longo.sh confere a identidade do processo, não só o PID

## Objetivo
A checagem final de `scripts/testa-rodar-longo.sh` ("nenhum PID registrado segue vivo") falha de vez em quando no CI Windows (Issue #632). A causa medida em 2026-10-29 não é a hipótese da Issue (filho do vigia morto): é reuso de PID. Rodando a bateria instrumentada 3 em paralelo, 3 de 36 execuções acusaram vivo o PID do vigia ou do comando de casos que tinham terminado havia mais de 10 s (`comando que sai 3`, `iniciar volta na hora`, `comando inexistente`), e menos de 1 s depois o `Get-CimInstance` já não achava processo nenhum com aquele PID: era outro processo, de vida curta, que herdou o número. Além do falso vermelho, a checagem faz `process.kill` no PID achado, ou seja, mata um processo que não é da bateria.

Este trabalho faz a checagem final contar e matar só o processo que é de fato da bateria, e mantém o vermelho para processo da bateria que sobreviveu.

Conduzido pela sessão a partir da Issue #632 em 2026-10-29, sob a autorização permanente de seguir o fluxo com a recomendada. As decisões ficam marcadas no PR para veto.

## Decisões fechadas
- **D1 — Marca única por execução nos comandos da bateria** — a bateria gera `MARCA=rl-bateria-<pid do shell>-<aleatório>` e a põe em todo comando que passa ao `rodar-longo.cjs iniciar` (`bash -c ": $MARCA; exit 3"`; no caso do comando inexistente, como argumento dele). A marca aparece na linha de comando do vigia (que recebe o comando depois do `--`) e na do `bash` do comando. — porquê: é o único traço que distingue o processo da bateria de outro que herdou o PID; nome da imagem (`node.exe`, `bash.exe`) não distingue, porque a própria bateria e o runner sobem os mesmos executáveis.
- **D2 — Identidade pela linha de comando, consultada só para PID vivo** — `eh_da_bateria <pid>` devolve 0 quando a linha de comando do processo contém a `MARCA`: no Windows por `Get-CimInstance Win32_Process` (PowerShell), fora dele por `ps -o args= -p`. A checagem final só consulta o PID que `esta_vivo` já acusou, então o custo do PowerShell (~1 s) aparece só no caso raro. — porquê: consultar todo PID custaria 14 PowerShells por execução; o reuso é raro.
- **D3 — PID vivo de outro dono não conta e não morre** — vivo e sem a marca: a bateria imprime `PID <n> reaproveitado por outro processo, ignorado` e segue, sem `process.kill`. Vivo e com a marca: conta como vivo e é morto, como hoje. — porquê: regra 15, processo morre pelo PID desta sessão; o `process.kill` atual pode derrubar processo do runner ou de outra sessão.
- **D4 — Consulta que não responde fecha para o lado do vermelho** — se o processo continua vivo depois da consulta e a linha de comando veio vazia (PowerShell ausente, acesso negado), conta como vivo (vermelho), mas não é morto, porque pode ser alheio (emenda da revisão 1). Só "a consulta não achou o processo" ou "achou com outra linha de comando" liberam. — porquê: a trava não pode virar passe livre por falha de ambiente.
- **D5 — Controles dentro da bateria** — casos novos: (a) um processo da bateria vivo (comando com a marca e `sleep`) é reconhecido por `eh_da_bateria`, e depois é morto; (b) um processo vivo sem a marca (um `node` de espera subido pela própria bateria sem a marca) não é reconhecido; e, por emenda das revisões 1 e 2, (c) a consulta sem resposta com o processo vivo devolve "vivo sem dono", e (d) um processo alheio vivo registrado antes do laço final não é contado nem morto. — porquê: sem eles, uma `eh_da_bateria` que devolve sempre "não é" deixaria a checagem final verde sem medir nada.
- **D6 — A Issue #632 fecha com a causa corrigida** — o corpo da Issue tinha a hipótese do filho do vigia morto; o PR diz que a medição a derrubou e qual foi a causa. — porquê: a Issue é o registro de quem procurar a falha depois.
- **D7 — Contra quem protege, e o que fica fora** — protege contra falso vermelho por reuso de PID e contra matar processo alheio. Não protege contra processo filho que a bateria não registra (o `sleep` dentro do `bash` do comando): a checagem continua sendo sobre os PIDs registrados, vigia e comando. Medido em 2026-10-29: o comando registrado é o `bash.exe` externo que o vigia sobe, e a linha de comando dele traz o texto inteiro (`bash.exe -c "'bash' '-c' ': marca; sleep 5'"`), então a marca aparece nele. O `scripts/rodar-longo.cjs` não muda.
- **D8 — Versão 2.2.1** — PATCH, com CHANGELOG e bump nos dois `plugin.json` e no badge do README. — porquê: conserto de bateria, sem contrato novo (tabela do `CONTRIBUTING.md`).

## Avaliado e descartado
- **Comparar hora de criação do processo com a hora do registro** — o comando rápido (`exit 3`) morre antes de a bateria registrar o PID, e um processo que herdasse o número nesse intervalo teria hora de criação anterior ao registro. A linha de comando não tem essa janela.
- **Esperar e checar de novo** — reduziria a taxa, não a zeraria, e continuaria matando o processo alheio que estivesse vivo na segunda olhada.
- **Mudar o `rodar-longo.cjs` para gravar a hora de nascimento** — o script está certo; o defeito é da medição.

## Fora de escopo
- Processo filho não registrado (o `sleep 30` do caso "vigia morto") continua fora da checagem por PID, como hoje.

## Varredura
docs/rainforest/varredura/2026-10-29-rodar-longo-flaky.txt — a única Issue aberta no tema é a própria #632. Nenhuma outra bateria checa vida de processo por `process.kill(Number(...))`.

## Em aberto
nada
