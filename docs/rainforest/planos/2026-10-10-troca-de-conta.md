# Plano: Troca automática de conta Claude pelo uso

Design: docs/rainforest/design/2026-10-10-troca-de-conta.md

**Slug:** `2026-10-10-troca-de-conta` · **Branch:** `fluxo/troca-de-conta`

Dez tarefas, doze decisões. Três ondas:

- **Onda 1** (arquivos disjuntos): T1 (decisão pura), T2 (mover credencial), T3 (servidor).
- **Onda 2**: T4 (CLI `conta.cjs`, junta 1–3); depois T5 a T8 em série (T5 e T7 tocam o mesmo `conta.cjs`).
- **Onda 3**: T9 (medição real com as contas do Luís) e, só com T9 aprovada, T10 (sai o `/transferir claude`).

**Restrições que valem para todas:**
- O repo é público: nenhum caminho desta máquina, e-mail, token ou id de conta em código, teste ou fixture. Fixture de servidor é a resposta real com os identificadores trocados por `x@exemplo.invalid` e uuid zerado.
- **Nenhuma bateria toca `~/.claude`, `~/.claude-personal` nem a pasta de dados real.** Toda pasta de conta em teste é `mktemp -d`, passada por `RFM_CONTA_PASTA_TRABALHO`, `RFM_CONTA_PASTA_PESSOAL` e `RFM_CONTA_DADOS`. O servidor em teste é um `http.createServer` local, apontado por `RFM_CONTA_API` (só aceito com `RFM_TEST=1`).
- Credencial nunca vai para stdout, stderr nem log: o log guarda só a impressão `sha256(refreshToken)[0:12]`.
- Toda asserção de bateria tem os dois ramos (`if/else`); `de:`/`para:` são literais que a tarefa obriga a escrever.

## O que não pode quebrar
- Sessões abertas em `~/.claude` e `~/.claude-personal` continuam autenticadas depois de qualquer troca, volta ou falha no meio dela: nenhum `refreshToken` fica em dois arquivos ao mesmo tempo.
- `mcpOAuth` e `trustedDeviceToken` de cada `.credentials.json` ficam byte a byte onde estavam.
- O `/transferir codex` (`node scripts/transferir.cjs` sem argumento) segue funcionando: `bash scripts/testa-transferir-para-codex.sh` verde.
- Todas as baterias `scripts/testa-*.sh`, `scripts/testa-*.cjs` e `hooks/testa-*.cjs` continuam verdes.

## Tarefas

### 1. Decisão pura: trocar, voltar ou nada [tipo: implementar]
atende: D1, D3, D4, D8, D11
arquivos: `scripts/lib/conta-decidir.cjs`, `scripts/testa-conta-decidir.cjs`
depende de: nenhuma
paralela: sim
Função `decidir({ pastas, usos, reservas, config, agora })`, sem I/O, que devolve uma lista de ações `{ tipo: 'trocar'|'voltar', pasta, conta, motivo }`. Regras: troca a pasta cuja conta em uso passou de `config.trocarEm` (97) na `five_hour` ou na `seven_day`, para a outra conta, só se ela estiver abaixo de `config.destinoMax5h` (60) e `config.destinoMaxSemana` (85) e tiver reserva; volta quando `agora` passou do `resets_at` do limite que travou; pasta com `manual: true` nunca recebe ação automática (D8); ação que move credencial com menos de 30 min de `expiresAt` sai como `{ tipo: 'esperar' }`. A função contém literalmente a linha `const MIN_VIDA_MS = 30 * 60 * 1000;` e a comparação `if (pasta.manual) continue;`.
prova: `node scripts/testa-conta-decidir.cjs`
mutacao:
  arquivo: `scripts/lib/conta-decidir.cjs`
  de: `if (pasta.manual) continue;`
  para: `if (false) continue;`
  bateria: `node scripts/testa-conta-decidir.cjs`
  fixture: caso "pasta trocada na mão não volta sozinha mesmo depois do reset"
pronto quando: com o `/api/oauth/usage` real das duas contas medido em 2026-10-10 (team: five_hour 15, seven_day 53; pessoal: five_hour 15, seven_day 5) como fixture e cada caso derivado trocando só `utilization`/`resets_at`, `decidir` devolve: troca da pasta trabalho para a conta pessoal quando seven_day da team = 97; nada quando o destino está em 61% na 5 h; volta depois do `resets_at`; nada para pasta `manual`; `esperar` com `expiresAt` a 29 min — provado por `node scripts/testa-conta-decidir.cjs` imprimindo `ok` por caso e `0 falha(s)`.

### 2. Mover credencial sem copiar [tipo: implementar]
atende: D2, D11
arquivos: `scripts/lib/conta-mover.cjs`, `scripts/testa-conta-mover.sh`
depende de: nenhuma
paralela: sim
`mover({ pasta, reservaEntra, reservaSai })`: lê `.credentials.json` da pasta e os dois arquivos de reserva; relê os três imediatamente antes de gravar e desiste (exit lógico `mudou`) se algum mudou desde a primeira leitura; grava só a chave `claudeAiOauth` (a da reserva que entra vai para a pasta, a da pasta vai para a reserva que sai, e a reserva que entra fica vazia); cada gravação é escrita atômica (arquivo temporário + rename) e relida inteira; leitura que não bate desfaz as anteriores. Atualiza `oauthAccount` do `.claude.json` da pasta com o dono informado pelo chamador. Depois de gravar, confere que nenhum `refreshToken` aparece em dois dos três arquivos. A conferência final contém literalmente `if (impressoes.size !== total) throw new Error('credencial em dois lugares');`.
prova: `bash scripts/testa-conta-mover.sh`
mutacao:
  arquivo: `scripts/lib/conta-mover.cjs`
  de: `if (impressoes.size !== total) throw new Error('credencial em dois lugares');`
  para: `if (false) throw new Error('credencial em dois lugares');`
  bateria: `bash scripts/testa-conta-mover.sh`
  fixture: caso "reserva que entra igual ao login da pasta é recusada e nada muda"
pronto quando: com um `.credentials.json` no formato real desta máquina (chaves de topo `mcpOAuth`, `claudeAiOauth`, `trustedDeviceToken`; `claudeAiOauth` com `accessToken`, `refreshToken`, `expiresAt`, `refreshTokenExpiresAt`, `scopes`, `subscriptionType`, `rateLimitTier`) com tokens falsos, a troca deixa `mcpOAuth` e `trustedDeviceToken` com o mesmo sha256 de antes, o `claudeAiOauth` da reserva na pasta, o da pasta na reserva de saída, a reserva de entrada sem `claudeAiOauth`; arquivo alterado entre a leitura e a gravação faz sair sem mudar nenhum byte; e reserva igual ao login da pasta é recusada com os três arquivos intactos — provado por `bash scripts/testa-conta-mover.sh` com `0 falha(s)` e os sha256 de antes/depois impressos.

### 3. Servidor: identidade e uso com cache [tipo: implementar]
atende: D10
arquivos: `scripts/lib/conta-api.cjs`, `scripts/testa-conta-api.cjs`, `scripts/fixtures/conta/usage.json`, `scripts/fixtures/conta/profile.json`
depende de: nenhuma
paralela: sim
`dono(token)` chama `GET /api/oauth/profile`; `uso(conta, token)` chama `GET /api/oauth/usage` com header `anthropic-beta: oauth-2025-04-20`. O uso passa por um cache em `<dados>/contas/uso-cache.json`: leitura mais nova que 4 min é reaproveitada (1 min quando a última leitura estava em 85% ou mais); HTTP 429 grava espera de 3 min para aquela conta e devolve a última leitura com a idade real. Primeiro passo da tarefa: capturar a resposta real dos dois endpoints com a conta pessoal desta máquina, trocar e-mail, nome e uuid, e gravar as duas fixtures. A espera contém literalmente `if (r.status === 429) cache[conta].esperaAte = agora + ESPERA_429_MS;`.
prova: `node scripts/testa-conta-api.cjs`
mutacao:
  arquivo: `scripts/lib/conta-api.cjs`
  de: `if (r.status === 429) cache[conta].esperaAte = agora + ESPERA_429_MS;`
  para: `if (false) cache[conta].esperaAte = agora + ESPERA_429_MS;`
  bateria: `node scripts/testa-conta-api.cjs`
  fixture: caso "depois de um 429 a segunda chamada não chega ao servidor"
pronto quando: com um servidor local servindo as fixtures reais, duas chamadas a `uso` em menos de 4 min fazem 1 requisição; com o servidor devolvendo 429, a chamada seguinte não chega ao servidor e devolve a leitura anterior com a idade; e `dono` devolve o e-mail da fixture — provado por `node scripts/testa-conta-api.cjs` com a contagem de requisições do servidor impressa por caso e `0 falha(s)`.

### 4. CLI `conta.cjs`: status, trocar, vigiar, eventos [tipo: implementar]
atende: D2, D3, D5, D6, D7, D8
arquivos: `scripts/conta.cjs`, `scripts/testa-conta.sh`
depende de: 1, 2, 3
paralela: nao
Subcomandos: `status` (uso das duas contas, que login está em cada pasta perguntado ao servidor, reservas, se a troca automática está ligada); `trocar <pessoal|trabalho> [--pasta trabalho|pessoal]` (troca manual, marca a pasta `manual: true`; trocar a pasta para a própria conta desmarca); `vigiar` (uma rodada: trava em `<dados>/contas/vigia.lock` com dono pelo PID e validade de 5 min, lê uso, chama `decidir`, executa com `mover`, confere o dono no servidor depois de mover e desfaz se não bater); `eventos --desde <ms>` (linhas de `<dados>/contas/eventos.jsonl` mais novas). Toda troca e volta acrescenta uma linha `{em, tipo, pasta, de, para, motivo, manual}` ao `eventos.jsonl`. Estado (`manual`, conta atual de cada pasta, limite que travou) em `<dados>/contas/estado.json`, escrito atômico. A trava contém literalmente `if (!pegarTrava(lock)) return sair(0, 'outra rodada em curso');`.
prova: `bash scripts/testa-conta.sh`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (!pegarTrava(lock)) return sair(0, 'outra rodada em curso');`
  para: `if (false) return sair(0, 'outra rodada em curso');`
  bateria: `bash scripts/testa-conta.sh`
  fixture: caso "duas rodadas de vigiar simultâneas fazem uma troca só"
pronto quando: com duas pastas temporárias no formato real, reservas com tokens falsos e o servidor local da T3 reportando a team em 97% na semana, `node scripts/conta.cjs vigiar` troca a pasta trabalho para a pessoal, grava uma linha em `eventos.jsonl` e `status` mostra a pasta trabalho na conta pessoal; duas rodadas simultâneas produzem uma troca só; `trocar trabalho --pasta trabalho` desfaz e desmarca `manual`; a saída de `status` é legível sem JSON (a pessoa vê, por pasta, a conta em uso e os dois percentuais) — provado por `bash scripts/testa-conta.sh` com `0 falha(s)`.

### 5. Preparar as reservas [tipo: implementar]
atende: D9
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-preparar.sh`
depende de: 4
paralela: nao
`conta.cjs preparar <pessoal|trabalho>`: cria pasta temporária com `.claude.json` vazio, roda `claude auth login` com `CLAUDE_CONFIG_DIR` apontado para ela (o executável achado por `scripts/lib/achar-executavel-claude.cjs`), pergunta ao servidor o dono do login novo e só grava a reserva se o e-mail for o da conta pedida (o e-mail esperado é o `oauthAccount.emailAddress` da pasta dona da conta). Grava em `<dados>/contas/reserva-<conta>.json` e apaga a pasta temporária. Login de conta errada não grava nada e diz qual conta veio. A troca automática só liga (`estado.json` `automatico: true`) quando as duas reservas existem. A conferência contém literalmente `if (veio.email !== esperado) return sair(3, 'o navegador autorizou ' + veio.email);`.
prova: `bash scripts/testa-conta-preparar.sh`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (veio.email !== esperado) return sair(3, 'o navegador autorizou ' + veio.email);`
  para: `if (false) return sair(3, 'o navegador autorizou ' + veio.email);`
  bateria: `bash scripts/testa-conta-preparar.sh`
  fixture: caso "login da conta errada não grava reserva"
pronto quando: com um `claude` falso (variável `RFM_CONTA_CLAUDE`, só com `RFM_TEST=1`) que grava um `.credentials.json` no formato real na pasta recebida e o servidor local dizendo o dono, a reserva é gravada quando o dono bate, nada é gravado e o exit é 3 com o e-mail que veio quando não bate, e a pasta temporária some nos dois casos — provado por `bash scripts/testa-conta-preparar.sh` com `0 falha(s)`.

### 6. Comando `/conta` [tipo: configurar]
atende: D7
arquivos: `commands/conta.md`, `README.md`
depende de: 4
paralela: nao
`commands/conta.md` roda `node "${CLAUDE_PLUGIN_ROOT}/scripts/conta.cjs" $ARGUMENTS`, com `status` como padrão sem argumento, e explica `pessoal`, `trabalho` e `preparar`. README ganha a seção da troca de conta com o que acontece na troca, na volta e na troca manual.
mutacao: n/a
  motivo: arquivo de comando e documentação, sem lógica; a falsificação é o comando real casar com a interface da T4.
pronto quando: com o texto do `commands/conta.md`, a linha de comando extraída dele (trocando `${CLAUDE_PLUGIN_ROOT}` pela raiz do worktree e `$ARGUMENTS` por `status`) roda contra as pastas temporárias da T4 e sai 0 imprimindo as duas pastas; e cada número citado no README (97, 60, 85, 30 min, 1 min) é o mesmo do design — provado por `bash scripts/testa-conta.sh` no caso "comando do /conta casa com o CLI" e por `grep -c` dos cinco números no README conferido contra o design na revisão.

### 7. Agendamento do vigia [tipo: implementar]
atende: D5
arquivos: `scripts/conta.cjs`, `scripts/testa-conta-agendar.sh`
depende de: 4
paralela: nao
`conta.cjs agendar` monta o comando `schtasks /Create /TN "\ClaudeVigias\troca-de-conta" /SC MINUTE /MO 1 /F /TR "<conhost.exe> --headless <node> <conta.cjs> vigiar"` com caminhos absolutos achados na hora, **sem** EndBoundary; `desagendar` remove; `--imprimir` só mostra o comando. Sem `--imprimir`, só roda depois de as duas reservas existirem. A montagem contém literalmente `const argv = ['/Create', '/TN', TAREFA, '/SC', 'MINUTE', '/MO', '1', '/F', '/TR', acao];`.
prova: `bash scripts/testa-conta-agendar.sh`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `const argv = ['/Create', '/TN', TAREFA, '/SC', 'MINUTE', '/MO', '1', '/F', '/TR', acao];`
  para: `const argv = ['/Create', '/TN', TAREFA, '/SC', 'MINUTE', '/MO', '5', '/F', '/TR', acao];`
  bateria: `bash scripts/testa-conta-agendar.sh`
  fixture: caso "agendar --imprimir roda a cada 1 minuto"
pronto quando: com `node scripts/conta.cjs agendar --imprimir`, a saída traz `/SC MINUTE /MO 1`, `--headless`, caminhos absolutos de node e do `conta.cjs`, e nenhum `/ED`; sem as duas reservas, `agendar` recusa sem chamar `schtasks` — provado por `bash scripts/testa-conta-agendar.sh` com `0 falha(s)`. A bateria nunca chama `schtasks` de verdade.

### 8. Aviso nas sessões abertas [tipo: implementar]
atende: D6
arquivos: `hooks/conta.ts`, `hooks/conta-puro.mjs`, `hooks/mod.tsx`, `hooks/testa-mod-conta.cjs`
depende de: 4
paralela: nao
Módulo do mod, importado por `hooks/mod.tsx` como `pr.tsx`: a cada 60 s roda `node <raiz>/scripts/conta.cjs eventos --desde <ultima>` e, para cada evento novo, mostra `$.ui.notify` com a frase de `frase(evento)` (em `conta-puro.mjs`), por exemplo "Conta: a pasta trabalho passou para a conta pessoal (team em 97% na semana). Volta às 19h59.". `ultima` começa no momento em que a sessão abriu, para não repetir eventos antigos. `frase` contém literalmente `if (e.tipo === 'voltar') return 'Conta: a pasta ' + e.pasta + ' voltou para a conta ' + e.para + '.';`.
prova: `node hooks/testa-mod-conta.cjs`
mutacao:
  arquivo: `hooks/conta-puro.mjs`
  de: `if (e.tipo === 'voltar') return 'Conta: a pasta ' + e.pasta + ' voltou para a conta ' + e.para + '.';`
  para: `if (e.tipo === 'voltar') return '';`
  bateria: `node hooks/testa-mod-conta.cjs`
  fixture: caso "evento de volta vira aviso com a pasta e a conta"
pronto quando: com linhas de `eventos.jsonl` geradas pelo `conta.cjs` real da T4 (troca automática, volta, troca manual), `frase` devolve, para cada uma, um texto que diz qual pasta, de qual conta para qual, o motivo e, na troca automática, a hora da volta; evento anterior à abertura da sessão não gera aviso — provado por `node hooks/testa-mod-conta.cjs` com `0 falha(s)`.

### 9. Medição real com as contas do Luís [tipo: pesquisar]
atende: D1, D2, D9
arquivos: `docs/rainforest/estado/2026-10-10-troca-de-conta.json`, `relatorios/2026-10-10-troca-de-conta-medicao.md`
depende de: 5, 6, 7, 8
paralela: nao
Com o Luís presente: `/conta preparar pessoal` e `/conta preparar trabalho` (dois logins no navegador), `/conta trabalho --pasta pessoal` e volta. Medir: (a) uma sessão aberta em `~/.claude-personal` continua respondendo depois da troca e o `/api/oauth/profile` do token dela diz a conta team; (b) as duas sessões continuam autenticadas 10 min depois de voltar (nenhum "please run /login"); (c) com a pasta `~/.claude` no login pessoal, `claude -p --debug` mostra se o `cc-plugin-sec-default` e o que vem da organização seguem ativos — o resultado entra no relatório e, se a org deixar de valer, vira pergunta ao Luís antes de ligar a troca automática; (d) `conta.cjs agendar` real e uma rodada observada no log.
mutacao: n/a
  motivo: medição em ambiente real, com credenciais do usuário; não há linha de produção a inverter.
pronto quando: com as duas contas reais desta máquina, o relatório traz, para (a)–(d), o comando literal e a saída colada (tokens e e-mails mascarados), e `node scripts/conta.cjs status` no fim mostra cada pasta na própria conta e as duas reservas presentes — provado pela saída colada no relatório e conferida pela janela principal.

### 10. Sai o `/transferir claude` [tipo: implementar]
atende: D12
arquivos: `scripts/transferir.cjs`, `scripts/transferir-entre-contas.cjs`, `scripts/testa-transferir-entre-contas.sh`, `scripts/testa-transferir.sh`, `commands/transferir.md`, `README.md`
depende de: 9
paralela: nao
`transferir.cjs claude` passa a recusar com exit 2 e a frase "o /transferir claude saiu: use /conta para trocar a conta da pasta". Apagar `transferir-entre-contas.cjs` e a bateria dele; `commands/transferir.md` e README deixam de citar o destino `claude`. O despachante contém literalmente `if (paraClaude) return sair(2, MSG_SAIU);`.
prova: `bash -c "! git grep -q transferir-entre-contas"`
mutacao:
  arquivo: `scripts/transferir.cjs`
  de: `if (paraClaude) return sair(2, MSG_SAIU);`
  para: `if (false) return sair(2, MSG_SAIU);`
  bateria: `bash scripts/testa-transferir.sh`
  fixture: caso "transferir claude recusa e aponta o /conta"
pronto quando: com `node scripts/transferir.cjs claude`, exit 2 e a frase que aponta o `/conta`; `node scripts/transferir.cjs` sem argumento segue indo para o Codex; nenhum arquivo rastreado cita `transferir-entre-contas` — provado por `bash scripts/testa-transferir.sh` e `bash scripts/testa-transferir-para-codex.sh` com `0 falha(s)` e `git grep -c transferir-entre-contas` sem resultado.
