# Integração — zerar-issues-16

Onda única de 15 executores (haiku, `isolation: "worktree"`, base `a85f9315`) para
as tarefas 1 e 3–16; a 2 (mesmo arquivo da 1, serial) e a 17 foram feitas na janela
principal, e a 13 foi refeita lá. Cada entrega passou
por `conferir-entrega.cjs`, pelo critério do plano rodado de novo e pela catraca
re-rodada na branch integrada.

## Entregas

| Tarefa | Commit do agente | Veredito na integração | O que a integração fez |
|---|---|---|---|
| 1 (#405) | df404c81, aec93d3c | **reprovada**: regressão de 33 casos (`bash $CMD`, `"$t"`, `"$@"` passaram a sair 0) | isenção restrita a token que mistura literal e expansão (`caminhoComVariavelELiteral`) |
| 2 (#407) | — | janela principal | `corpoDeHeredocQueCria` lê o corpo do heredoc do próprio comando |
| 3 (#402) | 01e4c782 | ok | casos de toggle após a T5 |
| 4 (#396) | f0233f29 | parcial + **incidente** (abaixo) | aviso passa a sugerir abrir o fluxo; caso de config `false` reincluído |
| 5 (#401) | 0325211e | **reprovada**: reescreveu `testa-config.sh` (45 → 11 casos) | base restaurada + casos novos; `hookEventName` no hook |
| 6 (#397) | 1bebc013 | **incompleta** e editou plano histórico | só `contar-ocorrencias.cjs` aproveitado; recusas refeitas uma a uma |
| 7 (#398) | 46bdb2da | **reprovada**: conferência pulada com `--shard` | conferência antes da repartição; `\r` tirado |
| 8 (#398) | 1ede87ee | ok | caso do bash do WSL / System32 |
| 9 (#398) | 65d98409 | ok | — |
| 10 (#398) | 5d8da7c8 | **reprovada**: guarda inerte (raiz real calculada com `RFM_ROOT` no env) | `env -u RFM_ROOT`, `RFM_RAIZ_REAL_FALSA`, caminho normalizado |
| 11 (#399) | a8677fb8 | parcial: D22 sem caso | caso (t) com base concluída via push |
| 12 (#400) | a878143e | **reprovada**: catraca verde | shim de git que `caminhoExecutavel` usa; casos de snapshot alheio, gravar e vizinhas |
| 13 (#403) | f3921a3b | **reprovada**: staging-total 151/171, git-verificacao 124/147 | refeita na janela principal |
| 14 (#403) | daa22dc0 | ok | — |
| 15 (#404) | — | ok | — |
| 16 (#408) | 22b7eccc | ok | `TZ` fixado na bateria |
| 17 | — | janela principal | registro, versão, docs |

Sete das quinze entregas de agente não passaram como vieram (1, 5, 6, 7, 10, 12, 13),
e duas precisaram de complemento (4, 11). Nenhuma das reprovadas foi pega pelo
relato do agente: todas apareceram ao rodar a bateria ou a catraca na integração.

## T13 na janela principal

Um registrador de payload (preload que grava o que cada gate lê do fd 0) rodou as
três baterias antes e depois da troca de `printf`/`esc()` por `JSON.stringify`.
Os payloads ficaram idênticos (chaves ordenadas, pasta temporária neutralizada),
salvo seis que eram JSON inválido antes — verde sem o gate olhar — e agora são
avaliados, ainda verdes. Placar 207/147/171 → 208/148/172 (um caso de aspas em cada).

## Catracas e varredura na branch integrada

`conferir-fluxo.cjs mutacoes` re-rodou as catracas: 1–9, 11–14 e 16 vermelhas
(exit 0); 10 e 17 n/a pelo plano. A 15 não mediu na cópia temporária da catraca:
`testa-saude.sh` leva 5m41 no worktree (o caso K roda a bateria inteira de novo) e
na cópia passou de 20 min no baseline (exit 4). Foi medida à mão, no worktree, pelo
mesmo procedimento: `if (hashes.size > 1) {` → `if (false) {` derruba o caso N1
(76 ok, 1 falha) e o fonte volta íntegro.

A primeira varredura completa deu 7 vermelhas que a base não tem. Todas eram desta
branch e foram consertadas (commit `25de29b1`): a data local da #408 quebrava o
casamento de observação servida em `scripts/lib/utilidade.cjs` (só aparecia fora
de UTC — o caso agora fixa o fuso); `aviso-fluxo.cjs` sem marca de categoria; a
linha nova da skill `plano` estourava 16 KB; a pasta `System32` falsa da T8 vazava
um `mktemp` por rodada; `testa-estado` não copiava a dependência nova do
`conferir-fluxo`; duas baterias contavam hooks registrados. Segunda varredura:
175 baterias verdes.

## Incidente

O briefing da T4 mandou gravar a mensagem de commit em `$TEMP/msg-...` pela
ferramenta Write, que criou uma pasta de nome literal `$TEMP` no worktree; o
agente, ao limpar, rodou `rm -rf "$TEMP"` no shell, onde a variável expandiu para
a Temp real do usuário. O scratchpad da sessão e o snapshot `--sujo-antes` se
perderam. Observação plantada (`obs-2026-10-06-briefing-temp-vira-rm-rf-da-temp-real`);
os briefings seguintes passaram a usar `F=$(mktemp)` no próprio Bash.

## Revisão, rodada 1: reprovada

Dois revisores (hooks e scripts) reprovaram com 8 achados bloqueantes, todos com
sonda confirmada: o `gate-subagente-sem-instalar` deixava instalação passar fora
da primeira palavra e no PowerShell, barrava `yarn test`/`npm test -- add`, e
tinha buracos no arquivo e na variável de desligar; `limpar-worktrees` tratava
todo rastreado modificado como em uso; `conferir-entrega` lia git falhando no
principal como "intacto"; `saude` caía com link quebrado; a bateria de backup
dependia da máquina. Consertados em `0932be43` e `61a1b643`, cada um com caso que
fica vermelho sem o conserto, junto com os achados menores (lock de mutação, lista
de obrigatórias ausente, heredoc que reescreve body-file existente, `esc()`
restante, review-codex 7b/10). Catracas re-rodadas (14 vermelhas, 15 à mão, 10 e
17 n/a) e varredura completa: 175 verdes.

## Revisão, rodadas 2 a 5

| Rodada | Bloqueantes | Consertados em |
|---|---|---|
| 2 | gate de instalação: flag com valor antes do verbo, `&`/`.` do PowerShell, `pwsh` com flags antes de `-Command`; restauração do fonte nas fixtures de cobertura sem conferência de sha256 (D18) | `93e3ce59`, `2e882c3a` |
| 3 | gate de instalação: redirecionamento colado a alvo citado; lock das fixtures retomado como pid morto depois de restauração que falhou | `c439514d` |
| 4 | `conferir-entrega`: snapshot de outra árvore saía 1, o D24 pede 2 (a bateria esperava 1) | `e1e68fda` |
| 5 | nenhum (só scripts; hooks aprovou na 4ª sem mudança depois) | — |

Cada conserto tem caso que fica vermelho contra o commit anterior, e as
catracas das tarefas tocadas foram re-rodadas vermelhas. Junto foram os
não bloqueantes baratos: atribuição citada antes do comando, `yarn global add`,
nome acentuado no `limpar-worktrees` (`core.quotepath=false`), heredocs somados
no `--body-file` (último escritor, `>>`, `tee -a`, delimitador nu com expansão),
erro de lock que não é EEXIST saindo 69, frase truncada em `skills/plano`.

O teto de 3 reprovações foi atingido na 3ª e de novo na 4ª; o usuário liberou
a 4ª e a 5ª rodada (`docs/rainforest/portoes/2026-10-06-zerar-issues-16-impasse.md`).

**Ressalva do usuário na rodada 3:** desligar gate deveria ser só pela variável
`RAINFOREST_GATE_OFF` ou pelo config, sem o arquivo `.rainforest-gate-off` em
repo de cliente. Os gates ainda leem o arquivo; a remoção vai em fluxo próprio
depois deste PR.

### Não bloqueantes que ficaram

- Gate de instalação: escrever o arquivo de desligar por interpretador
  (`python -c`, `node -e`), `npm ic`/`install-ci-test`, `corepack yarn add`,
  atribuição com crase, `Start-Process npm`, `npx npm install`; `npm update` e
  afins fora do D6.
- `gate-fechar-issue`: acréscimo fora de heredoc (`echo ... >> x.md`) depois de
  heredoc benigno; heredoc com redirecionamento depois do `<<`; mensagem
  imprecisa quando o corpo é ilegível por expansão.
- `limpar-worktrees`: mtime de pasta não rastreada; mtime do índice (D21) não
  lido; `RFM_LIMPAR_APOS_LISTAR` é gancho de teste em código de produção.
- `conferir-entrega`: `git diff` que falha devolve conjunto vazio em vez de 69;
  texto `nao-verificavel:` mais específico que o do D23.
- `conferir-cobertura-fixtures`: SIGKILL no meio da mutação deixa lock de pid
  morto que se retoma; corrida estreita na retomada de lock obsoleto.
- `conferir-fluxo`: parser de `arquivos:` só lê caminhos entre crases.
- D19: as baterias de memória conferem que nenhum nome da raiz real sumiu, não
  que nenhum foi acrescentado.

## Verificar

A catraca da tarefa 15 não cabia no teto de 300 s com a seção K da
`testa-saude.sh` (que roda a bateria inteira de novo). Emenda no plano: a
bateria da catraca roda com `RFM_TESTA_SAUDE_ANINHADA=1` e teto de 15 min; o
caso N1, o desta tarefa, não depende da seção K.
