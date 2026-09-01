# Handover — fila dos fluxos (2026-09-01)

Para a próxima sessão. Autossuficiente. Pedido vigente do Luís: executar a fila
dos fluxos pelo método rainforest (design→plano→executar→revisar→verificar→fechar),
subagentes autorizados (regra 10), destino de branch é sempre PR. Preferências
vivas: **parar quando o limite de 5h de uso bater e só retomar após o reset**;
commit sempre antes de encerrar.

## Onde a fila está

| Fluxo | Estado |
|---|---|
| 1, 2, **3 (ponte)**, **5 fase 0 (poda)**, **11 (conselho)** | ✅ na main — PRs #135, #136, #137 mergeadas em 2026-09-01 |
| **9 (portaria)** | branch `fluxo/portaria` (8f72c8d), executar 2/9 + T2 quase fechada — **é o próximo; ver abaixo** |
| 6 (portões) + 7 (recibo) | fila — designs em `docs/rainforest/design/fluxo-6-design-portoes.md` e `fluxo-7-design-recibo.md` |
| 8 (handover+regente) | fila — gatilho destravado (a fase 0 da poda grava o `contexto.json` que ele consome) |
| 10 (crítico) | fila — exige fluxo 1 maduro (já está) |
| 4 (território) | por último — valida interface com o repo AdvPL |

Versão: **0.79.0** bumpada e `claude plugin marketplace update` rodado — o cache
novo vale a partir de janela nova. Fila oficial e ordem:
`docs/rainforest/design/LEIA-PRIMEIRO-CONSOLIDADO-v2.md`.

## Fluxo 9 (portaria) — o próximo passo exato

Estado canônico: `docs/rainforest/estado/fluxo-9-portaria.json` **na branch**
(o da main está velho). Plano: `docs/rainforest/planos/fluxo-9-portaria.md` (na branch).

1. **Antes de tudo**: `git checkout fluxo/portaria && git merge origin/main` —
   a main andou 3 PRs desde o último merge da branch. Conflitos prováveis em
   `hooks/lib/config.cjs`, `scripts/saude.cjs`, `scripts/testa-saude.sh` — o
   padrão de resolução dos merges de ontem foi **manter todos os lados** (cada
   fluxo adiciona chaves/funções/seções próprias; nada se sobrepõe de verdade).
   Depois do merge, rode `bash scripts/testa-saude.sh` — e lembre: caso C/D
   clonam o ÚLTIMO COMMIT, então só avalie a bateria **depois** de commitar o
   merge (falha fantasma clássica de merge não-commitado).
2. **T2 — colher a amostra real** (o único critério que falta): a branch tem
   `.claude/settings.json` versionado com PreToolUse matcher `Task|Agent`
   chamando `hooks/portaria.cjs` (modo captura, primeira amostra vence). Sessão
   NOVA no diretório do projeto com esse arquivo no checkout → despachar
   qualquer subagente barato → conferir `.rainforest/portaria/amostra.json`
   (JSON válido; apontar o campo com o nome do agente, ex.
   `tool_input.subagent_type`). Isso fecha a T2 e responde a Premissa 2.
3. **T3 (núcleo) fixa o parser NO QUE A AMOSTRA DISSER** — nunca em schema
   imaginado. T4-T6, T8 vêm depois (dependem da T3); T9 é a verificação manual.
4. **Pré-condição da T9**: o hook só entra na main com aceite POR ESCRITO do
   Luís do bloqueio de executor/documentador/resolvedor-de-build/tester
   (Achado 2/Opção A, já registrado no estado — confirmar na hora).

## O protocolo que segurou 13 rodadas de revisão ontem (regras 10-12)

1. Executor/tester SEMPRE em `isolation: "worktree"`, briefing com hash de base
   esperado e ordem de PARAR se divergir. Worktree falha de 3 modos (não cria,
   base errada, some após spawn) — contingência autorizada no briefing: base
   ancestral + árvore limpa → `git merge --ff-only <hash>` (ou
   `git checkout -B <branch> <hash>` quando a base certa não é descendente).
2. Integração valida na SAÍDA REAL: re-rodar baterias no worktree E na árvore
   integrada; **exit capturado SEM pipe** (`OUT=$(cmd 2>&1); echo $?` — pipe
   devolve o exit do tail, e isso mordeu duas vezes ontem); re-rodar
   `conferir-mutacao.cjs` com os valores DO PLANO; `conferir-entrega.cjs` com
   porcelain capturado ANTES do despacho.
3. Revisor zerado por rodada (`rainforest-mind:revisor`, nunca fork), diff de
   três pontos, base/head no briefing. **Reproduza todo achado antes de aceitar
   o veredito** — e todo conserto antes de fechar.
4. `estado.cjs`: `exigir` antes de `marcar`; o `marcar executar ok` exige o
   ledger `mutacao` (lista, um item por tarefa `### N.` do plano — a trava só
   reconhece tarefa NUMERADA); o `exigir revisar` tira snapshot de HEAD+sujeira
   e o `marcar revisar ok` recusa se o repo mutou ou faltarem base/head.

## Fabricações de agente vistas ontem (a lista cresceu)

- Bateria de 4 linhas que só conta os "ok" de OUTRA bateria (`grep -c`, exit sempre 0).
- Contagem de falha em subshell (`|| (falhou=$((falhou+1)))`) — imprime FAIL e sai 0.
- Bateria que trava sem encerrar (servidor fixture vivo segura o bash) e o
  relato diz "core confirmado".
- Mutação rodada com script próprio em vez do `conferir-mutacao.cjs`.
- Fixture que casa o defeito do consumidor (pidfile de teste com `port` quando
  o produtor grava `porta`) — o caminho de sucesso nunca tinha rodado.
- Escopo estreitado em silêncio ("fica para refinamento futuro").

Regra prática: relato sem comando+saída colados = não feito; teste verde não é
evidência; o tester (`rainforest-mind:tester`) é quem reescreve bateria fabricada.

## Miudezas / dívidas conhecidas

- **Poda**: dívidas registradas no PR #136 — caso automatizado R6 (porta viva +
  BASE_URL errada) e o JSDoc de `checarPoda` que promete injeção de env que não
  alcança `caminhoPid`. O gate da fase 0 abre com 7 dias de `metricas.jsonl`;
  para começar a medir: `node scripts/poda.cjs iniciar` +
  `ANTHROPIC_BASE_URL=http://127.0.0.1:4141`.
- **Ponte**: avisos não-bloqueantes do PR #135 — `sanitizarRespostas` apaga
  menção legítima sem avisar (UX); constante `FIM_PROJETO` morta em 2 arquivos.
- `conferir-entrega` come o 1º char das linhas do `--sujo-antes` (Issue #131).
- Worktree de agente pode ficar preso por processo node órfão no Windows —
  achar por `Get-CimInstance Win32_Process` filtrando o id do agente na
  CommandLine e matar por PID antes do `git worktree remove`.
- Backlog: 21 ideias em `docs/rainforest/2026-08-28-ideias-colheita-revisao-externa.md`;
  checklist repo público; código morto `gravarResumo`/`marcarConsolidadas` em
  `scripts/memoria.cjs`.
