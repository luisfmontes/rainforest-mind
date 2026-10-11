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
arquivos: `scripts/conta.cjs`, `scripts/testa-conta.sh`, `scripts/fixtures/conta/servidor.cjs` (servidor falso da bateria, emenda da revisão)
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
arquivos: `hooks/conta.ts`, `hooks/conta-puro.mjs`, `hooks/mod.tsx`, `hooks/testa-mod-conta.cjs`, `hooks/mod-painel.test.tsx` (caso do `claude plugin test` que o T8c exigiu, emenda da revisão)
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
prova: `bash -c "! git grep -q transferir-entre-contas -- ':!docs'"`
mutacao:
  arquivo: `scripts/transferir.cjs`
  de: `if (paraClaude) return sair(2, MSG_SAIU);`
  para: `if (false) return sair(2, MSG_SAIU);`
  bateria: `bash scripts/testa-transferir.sh`
  fixture: caso "transferir claude recusa e aponta o /conta"
pronto quando: com `node scripts/transferir.cjs claude`, exit 2 e a frase que aponta o `/conta`; `node scripts/transferir.cjs` sem argumento segue indo para o Codex; nenhum arquivo rastreado fora de `docs/` (o histórico de design e plano fica) cita `transferir-entre-contas` — provado por `bash scripts/testa-transferir.sh` e `bash scripts/testa-transferir-para-codex.sh` com `0 falha(s)` e `git grep -c transferir-entre-contas -- ':!docs'` sem resultado.

## Rodada 2 (revisão de 2026-10-11 reprovou com 11 achados; D13 decidida pelo Luís)

### 11. Desfazer que falha não lança [tipo: implementar]
atende: D2, D11
arquivos: `scripts/lib/conta-mover.cjs`, `scripts/testa-conta-mover.sh`
depende de: 10
paralela: nao
Achado 4: `desfazer()` que falha propaga exceção e deixa a troca pela metade. O `mover` passa a nunca lançar depois da primeira gravação: tenta desfazer tudo, e se alguma gravação do desfazer falhar devolve `{ ok: false, motivo: 'desfazer_falhou', pendentes }` (`pendentes` = arquivos não restaurados). Contém literalmente `if (!desfeito) return { ok: false, motivo: 'desfazer_falhou', pendentes };`.
prova: `bash -c "grep -q desfazer_falhou scripts/lib/conta-mover.cjs"`
mutacao:
  arquivo: `scripts/lib/conta-mover.cjs`
  de: `if (!desfeito) return { ok: false, motivo: 'desfazer_falhou', pendentes };`
  para: `if (false) return { ok: false, motivo: 'desfazer_falhou', pendentes };`
  bateria: `bash scripts/testa-conta-mover.sh`
  fixture: caso "desfazer que falha não lança e devolve desfazer_falhou"
pronto quando: com a 2ª gravação e uma gravação do desfazer falhando (rename forçado a falhar no teste), `mover` devolve `motivo: desfazer_falhou` sem lançar — provado pelo caso nomeado de `bash scripts/testa-conta-mover.sh` e pela mutação acima vermelha.

### 12. O vigia renova os logins guardados [tipo: implementar]
atende: D13, D3, D10
arquivos: `scripts/lib/conta-api.cjs`, `scripts/conta.cjs`, `scripts/fixtures/conta/servidor.cjs`, `scripts/testa-conta-api.cjs`, `scripts/testa-conta.sh`
depende de: 10
paralela: nao
Achados 1a, 1b, 8 e o timeout do 11. `conta-api.cjs` ganha `renovar(cred)` (POST JSON em `<base>/v1/oauth/token`, `grant_type: refresh_token`, `client_id` público do CLI, `scope` = `cred.scopes.join(' ')`; resposta sem `refresh_token` mantém o atual; `expiresAt = agora + expires_in*1000`), e todo `fetch` leva timeout de 30 s. `conta.cjs` chama, antes de coletar usos e de decidir, `await renovarOciosos(c, estado);`: para cada `reserva-*.json` e `estacionado-*.json` com `expiresAt` a menos de 1 h, renova e grava atômico no mesmo arquivo (0o600); falha de renovação vira evento `renovacao_falhou` sem credencial e não derruba a rodada. `coletarUsos` não aborta mais a rodada por erro de uma conta: aquela conta fica sem dado. Leitura de uso com `idadeMs` acima de 15 min não decide troca (a conta fica sem dado). O servidor falso passa a rejeitar com 401 token vencido, responder `/v1/oauth/token` girando o refresh token (o antigo deixa de valer) e ter `resets_at` configurável por caso.
prova: `bash -c "grep -q renovarOciosos scripts/conta.cjs"`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `await renovarOciosos(c, estado);`
  para: `await Promise.resolve(estado);`
  bateria: `bash scripts/testa-conta.sh`
  fixture: caso "(k) volta automática com reserva e estacionado vencidos"
pronto quando: com a pasta trabalho trocada para a pessoal, `reserva-team` e `estacionado-trabalho` com access token vencido e `resets_at` do limite já passado, um `vigiar` renova os dois (refresh token girado no arquivo, o antigo recusado pelo servidor) e volta a pasta à conta team; com a renovação respondendo 500, a rodada sai 0 e grava `renovacao_falhou` sem credencial — provado pelos casos (k) e (k2) de `bash scripts/testa-conta.sh` e pela mutação acima vermelha.

### 13. Estado e identidade sob a trava [tipo: implementar]
atende: D9, D10, D11
arquivos: `scripts/conta.cjs`, `scripts/testa-conta.sh`, `scripts/testa-conta-preparar.sh`
depende de: 12
paralela: nao
Achados 2, 3 e a duplicata do 4. `preparar` roda sob a trava e recusa quando o slot de reserva daquela conta foi esvaziado por troca em curso (alguma pasta fora de casa usando aquela conta), com a frase `a reserva de <conta> está em uso numa pasta trocada: volte a pasta antes de preparar`; contém literalmente `if (slotEmUso(c, conta)) return sair(1, MSG_SLOT_EM_USO(alvo));`. `registrarCasas` nunca sobrescreve um e-mail já registrado para a conta; divergência vira evento `identidade_divergente` e nada é gravado. `status` grava o estado só sob a trava (sem a trava: mostra, não grava). `vigiar` e `status` detectam o mesmo refresh token (por `sha256[0:12]`) em dois arquivos e gravam evento `credencial_duplicada` sem mover nada. Volta que falha passa a gravar evento `falhou`, não só stdout.
prova: `bash -c "grep -q slotEmUso scripts/conta.cjs"`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (slotEmUso(c, conta)) return sair(1, MSG_SLOT_EM_USO(alvo));`
  para: `if (false) return sair(1, MSG_SLOT_EM_USO(alvo));`
  bateria: `bash scripts/testa-conta-preparar.sh`
  fixture: caso "preparar recusa o slot esvaziado pela troca"
pronto quando: com a pasta trabalho trocada, `preparar pessoal` sai 1 com a frase e não grava; com o estado dizendo "em casa" e a pasta com login de outra conta, `status` não altera `contas.<conta>.email` e grava `identidade_divergente`; com o mesmo refresh token em pasta e reserva, `vigiar` grava `credencial_duplicada` e não move — provado pelos casos nomeados em `testa-conta-preparar.sh` e `testa-conta.sh` e pela mutação acima vermelha.

### 14. Limite certo, recuo e dados fixos [tipo: implementar]
atende: D3, D4, D6
arquivos: `scripts/conta.cjs`, `scripts/testa-conta.sh`
depende de: 13
paralela: nao
Achados 5, 6, 7 e o resto do 11. Com os dois limites passados, `travouPor` é o de `resets_at` mais tardio; contém literalmente `return passaram.reduce((a, b) => (Date.parse(b.resetsAt) > Date.parse(a.resetsAt) ? b : a));`. Depois de um evento `falhou` de troca automática numa pasta, o vigia não tenta de novo nessa pasta por 15 min. `dadosDir()` ignora a raiz de projeto (`<cwd>/.rainforest`): fora de `RFM_CONTA_DADOS` (teste), é sempre a raiz de dados do usuário. `eventos` pula linha que não é JSON em vez de sair 1. Trava vencida só é tomada por quem consegue renomeá-la (rename atômico), nunca por dois.
prova: `bash -c "grep -q 'passaram.reduce' scripts/conta.cjs"`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `return passaram.reduce((a, b) => (Date.parse(b.resetsAt) > Date.parse(a.resetsAt) ? b : a));`
  para: `return passaram[0];`
  bateria: `bash scripts/testa-conta.sh`
  fixture: caso "(m) com os dois limites passados, a volta espera o reset mais tardio"
pronto quando: com a team a 99% nas duas janelas (5 h reseta antes da semana), `vigiar` troca e grava `travouPor.limite = seven_day`; com `/profile` falhando, duas rodadas seguidas fazem uma tentativa só; com o cwd num projeto que tem `.rainforest/FOCO.md`, `status` lê a pasta de dados do usuário; `eventos` com uma linha corrompida sai 0 e lista as válidas — provado pelos casos nomeados de `testa-conta.sh` e pela mutação acima vermelha.

### 15. Doc e dados da rodada 2 [tipo: docs]
atende: D7, D13
arquivos: `README.md`, `scripts/fixtures/conta/profile.json`, `relatorios/2026-10-10-troca-de-conta-medicao.md`, `docs/rainforest/design/2026-10-10-troca-de-conta.md`
depende de: 10
paralela: nao
Achados 9 e 10: README diz que `/conta` age na pasta da sessão; fixture sem datas de conta real; relatório sem os nomes das restrições da organização; design com a D13.
mutacao: n/a
  motivo: texto e dado de fixture, sem comportamento a inverter.
pronto quando: `README.md` descreve a pasta da sessão como `commands/conta.md`; `grep -E '2026-0[38]-' scripts/fixtures/conta/profile.json` sem resultado; o relatório não cita `require_trusted_devices` nem `allow_quick_web_setup` — provado pelos dois `grep` sem resultado.

## Rodada 3 (revisão rodada 2 reprovou com 7 achados; exceção da D11 decidida pelo Luís)

### 16. Preparar confere a conta pelo registro e a volta destrava [tipo: implementar]
atende: D9, D10, D11
arquivos: `scripts/conta.cjs`, `scripts/lib/conta-decidir.cjs`, `scripts/testa-conta-preparar.sh`, `scripts/testa-conta-decidir.cjs`, `scripts/testa-conta.sh`
depende de: 15
paralela: nao
Achado 1: `preparar` tira o e-mail esperado de `estado.contas[conta].email` (registrado sob a trava), nunca do `.claude.json` da pasta, e recusa quando a pasta `alvo` está fora de casa. Achado 5 (exceção da D11): em `checarVida`, o login que sai dispensa a guarda quando `expiresAt` passou há mais de 10 min; contém literalmente `const saiOcioso = agoraMs - ms(pasta.expiresAt) > OCIOSO_MS;`. Achado 2: o uso de uma conta é lido com o token da pasta e, se der 401 ou estiver vencido, com o da reserva daquela conta.
prova: `bash -c "grep -q saiOcioso scripts/lib/conta-decidir.cjs"`
mutacao:
  arquivo: `scripts/lib/conta-decidir.cjs`
  de: `const saiOcioso = agoraMs - ms(expiraSai) > OCIOSO_MS;`
  para: `const saiOcioso = false;`
  bateria: `node scripts/testa-conta-decidir.cjs`
  fixture: caso "volta com o login da pasta vencido há mais de 10 min não espera"
pronto quando: com a pasta trabalho trocada, `preparar trabalho` sai 1 sem rodar o `claude`; com o e-mail registrado da team e o navegador autorizando a pessoal, nada é gravado; com a pasta trocada, o login dela vencido há 20 min e o reset passado, `decidir` devolve `voltar` (e vencido há 5 min devolve `esperar`); com o token da pasta pessoal vencido e a `reserva-pessoal` válida, `vigiar` lê o uso da pessoal e troca — provado pelos casos nomeados em `testa-conta-preparar.sh`, `testa-conta-decidir.cjs` e `testa-conta.sh` e pela mutação acima vermelha. (Emenda de 2026-10-11: a tarefa 19 levou a linha para `avaliarVida`, com o parâmetro `expiraSai`; o alvo de mutação acompanha.)

### 17. Falha visível e reserva refazível [tipo: implementar]
atende: D6, D9, D11, D13
arquivos: `scripts/conta.cjs`, `hooks/conta-puro.mjs`, `hooks/testa-mod-conta.cjs`, `scripts/testa-conta.sh`, `scripts/testa-conta-preparar.sh`
depende de: 16
paralela: nao
Achados 3, 4, 7. Evento `falhou` com `desfazer_falhou` leva `pendentes` (nomes de arquivo, sem caminho absoluto nem credencial) e o aviso diz que a troca ficou pela metade e quais arquivos; contém literalmente `if (r.motivo === 'desfazer_falhou') return fraseMetade(ev);` em `conta-puro.mjs`. `renovacao_falhou`, `credencial_duplicada` e `identidade_divergente` viram aviso; `status` mostra a última falha de renovação por conta. `preparar --refazer` substitui uma reserva existente quando ela não está em uso por troca e o login dela não renova (o servidor recusa). Mensagens de erro de leitura de arquivo de credencial nunca levam `e.message` de `JSON.parse`, só o nome do arquivo.
prova: `bash -c "grep -q fraseMetade hooks/conta-puro.mjs"`
mutacao:
  arquivo: `hooks/conta-puro.mjs`
  de: `if (r.motivo === 'desfazer_falhou') return fraseMetade(ev);`
  para: `if (false) return fraseMetade(ev);`
  bateria: `node hooks/testa-mod-conta.cjs`
  fixture: caso "desfazer_falhou avisa troca pela metade com os arquivos"
pronto quando: com um evento `falhou` de `desfazer_falhou`, a frase diz "pela metade" e nomeia os arquivos pendentes; com `renovacao_falhou`, sai aviso; com a reserva morta (servidor recusa a renovação), `preparar --refazer pessoal` grava a nova; com `reserva-team.json` corrompido contendo um trecho de token, nenhuma saída contém o trecho — provado pelos casos nomeados e pela mutação acima vermelha.

### 18. Trava e lacunas de bateria [tipo: implementar]
atende: D5, D11, D13
arquivos: `scripts/conta.cjs`, `scripts/testa-conta.sh`, `scripts/testa-conta-api.cjs`, `scripts/fixtures/conta/servidor.cjs`
depende de: 17
paralela: nao
Achado 6: tomada de trava vencida sem janela para um terceiro (ex.: o vencedor do rename grava a trava nova direto, sem devolver a antiga; ou trava por diretório com `mkdir` atômico). Lacunas: caso com `vigia.lock` fresco e `status` que não grava `estado.json` nem eventos; caso com o login da PASTA a menos de 1 h de vencer e o servidor falso contando POSTs em `/v1/oauth/token`, que tem de ficar em zero; caso de timeout com servidor que não responde (timeout reduzido por variável de teste só com `RFM_TEST=1`). Contém literalmente `if (!/^(reserva|estacionado)-[\w-]+\.json$/.test(nome)) continue;` no laço de `renovarOciosos`.
prova-na-base: verde — a linha do laço já existe; a tarefa acrescenta o caso que a protege e o conserto da trava
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (!/^(reserva|estacionado)-[\w-]+\.json$/.test(nome)) continue;`
  para: `if (false) continue;`
  bateria: `bash scripts/testa-conta.sh`
  fixture: caso "renovarOciosos nunca renova o login de uma pasta"
pronto quando: com a pasta a 30 min de vencer, um `vigiar` faz zero POSTs de token; com a trava fresca, `status` não muda `estado.json`; com o servidor mudo, `uso` falha dentro do timeout de teste — provado pelos casos nomeados e pela mutação acima vermelha.

## Rodada 4 (revisão rodada 3 reprovou com 2 achados; 4ª rodada liberada pelo Luís, impasse em `docs/rainforest/portoes/2026-10-10-troca-de-conta-impasse.md`)

### 19. A troca manual aplica a guarda de vida [tipo: implementar]
atende: D7, D11
arquivos: `scripts/conta.cjs`, `scripts/lib/conta-decidir.cjs`, `scripts/testa-conta.sh`, `scripts/testa-conta-decidir.cjs`, `README.md`
depende de: 18
paralela: nao
Achado 1 da revisão rodada 3. A regra de vida da D11 (os dois logins com 30 min; o login que sai, vencido há mais de 10 min, dispensa a guarda) sai de `checarVida` para uma função pura exportada por `conta-decidir.cjs`, usada pelo `checarVida` do vigia e pelo `trocar` manual, sem duplicar a conta. No `trocar`, depois de conferir que o login que entra existe e antes de `aplicarTroca`, `adiada` é a mensagem de recusa (ou `null`); contém literalmente `if (adiada) return sair(1, adiada);`. A mensagem diz qual login está curto e quando tentar de novo (login que entra: o vigia o renova na próxima rodada, "em 1 min"; login que sai: o horário em que ele completa 10 min vencido). O README (linha do "Uma credencial nunca fica em dois lugares") passa a citar a exceção dos 10 min e que a troca manual segue a mesma guarda.
prova: `bash -c "grep -qF 'if (adiada) return sair(1, adiada);' scripts/conta.cjs"`
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (adiada) return sair(1, adiada);`
  para: `if (false) return sair(1, adiada);`
  bateria: `bash scripts/testa-conta.sh`
  fixture: caso "troca manual com o login da pasta a 2 min de vencer recusa e não move"
pronto quando: com o login da pasta trabalho a 2 min de vencer e a reserva pessoal viva, `trocar pessoal --pasta trabalho` sai 1, a mensagem diz quando tentar de novo e nenhum arquivo de credencial muda (hash igual antes e depois); com o login da pasta vencido há 20 min, a mesma troca sai 0; com a reserva que entra a 2 min de vencer, sai 1; o vigia continua com os casos de fronteira de 9 e 11 min verdes — provado pelos casos nomeados de `testa-conta.sh` e `testa-conta-decidir.cjs` e pela mutação acima vermelha.

### 20. Aviso de troca não desfeita [tipo: implementar]
atende: D6
arquivos: `hooks/conta-puro.mjs`, `hooks/testa-mod-conta.cjs`
depende de: 19
paralela: nao
Achado 2 da revisão rodada 3. Evento `falhou` cujo motivo traz `desfeito=false` vira aviso de que a troca NÃO foi desfeita e a pasta pode ter ficado com o login de outra conta, com o caminho para conferir (`/conta`); nunca "foi desfeita". Contém literalmente `if (/desfeito=false/.test(String(ev.motivo || ''))) return fraseNaoDesfeita(e);` antes do retorno "foi desfeita".
prova: `bash -c "grep -q fraseNaoDesfeita hooks/conta-puro.mjs"`
mutacao:
  arquivo: `hooks/conta-puro.mjs`
  de: `if (/desfeito=false/.test(String(ev.motivo || ''))) return fraseNaoDesfeita(e);`
  para: `if (false) return fraseNaoDesfeita(e);`
  bateria: `node hooks/testa-mod-conta.cjs`
  fixture: caso "falhou com desfeito=false não diz que a troca foi desfeita"
pronto quando: com o evento `falhou` de motivo "servidor confirmou X, esperado Y; desfeito=false", a frase não contém "foi desfeita", diz que a troca não foi desfeita e aponta o `/conta`; com "desfeito=true", segue "foi desfeita" — provado pelos casos nomeados de `testa-mod-conta.cjs` e pela mutação acima vermelha.
