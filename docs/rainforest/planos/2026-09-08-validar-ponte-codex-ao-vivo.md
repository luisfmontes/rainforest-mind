# Plano — validar a ponte Codex ao vivo com o plugin 1.8.0 (e Codex sem cota)

Design: `docs/rainforest/design/2026-09-08-validar-ponte-codex-ao-vivo.md`.
Branch `fluxo/validar-ponte-codex-ao-vivo` (a portaria casa a branch com o slug
sem a data; a primeira tentativa, com a data na branch, foi negada por "sem
estágio ativo"), base `origin/main` = `29b67d3`.

## Invariantes

- Toda chamada real a `codex` acontece só na tarefa 5; as demais usam dublê
  (`RFM_TEST=1` + `CODEX_CMD`).
- Exit 0 de `despachar-codex.cjs` continua significando "Codex respondeu";
  exit 75 é novo e passageiro; exit 1 e 124 não mudam de sentido.
- Nenhuma Issue para erro deste trabalho (D4).

## Tarefas

### 1. `despachar-codex.cjs` reconhece "sem cota" → exit 75 e linha legível [tipo: implementar]
atende: D5
arquivos: `scripts/despachar-codex.cjs`, `hooks/lib/codex-cota.cjs`, `scripts/fixtures/codex-duble.cjs`, `scripts/testa-despachar-codex.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/despachar-codex.cjs`
  de: quando o stderr do Codex casa `/hit your usage limit/i` (ou o stdout, no `--json`), o script escreve `codex sem cota: <linha original>` numa linha própria do stderr, logo depois de `comando:`, e sai 75 (detector compartilhado em `hooks/lib/codex-cota.cjs`)
  para: ignora o padrão e propaga o exit do Codex (1) sem a linha
  bateria: `bash scripts/testa-despachar-codex.sh`
  fixture: dublê em modo `semcota` (stderr com a mensagem real medida em 2026-09-08, exit 1); caso "sem cota → exit 75, primeira linha do stderr começa com `codex sem cota:`, dublê chamado, -o não fica"
pronto quando: `bash scripts/testa-despachar-codex.sh` verde com o caso novo, e a mensagem medida em 2026-09-08 (`ERROR: You've hit your usage limit ... try again at 5:41 PM`) casa o padrão — provado por `node -e` aplicando a regex do script sobre a string literal

### 2. `gate-review-codex.cjs` repete a causa no `reason` [tipo: implementar]
atende: D5
arquivos: `hooks/gate-review-codex.cjs`, `hooks/testa-gate-review-codex.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/gate-review-codex.cjs`
  de: exit 75 do despacho → `reason` contém a linha `codex sem cota: ...` vinda do stderr
  para: exit 75 tratado como qualquer exit ≠ 0, `reason` genérico "exit 75"
  bateria: `bash hooks/testa-gate-review-codex.sh`
  fixture: dublê (`RFM_DUBLE_SCRIPT`) com `RFM_DUBLE_EXIT=75` e stderr `codex sem cota: ...`; caso "sem cota → decision block e reason cita `codex sem cota`"
pronto quando: `bash hooks/testa-gate-review-codex.sh` verde com o caso novo e o `reason` do JSON contém `codex sem cota`

### 3. `transferir-para-codex.cjs` reconhece "sem cota" [tipo: implementar]
atende: D5
arquivos: `scripts/transferir-para-codex.cjs`, `scripts/testa-transferir-para-codex.sh`, `scripts/fixtures/codex-duble.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/transferir-para-codex.cjs`
  de: evento `{"type":"error","message":"You've hit your usage limit..."}` no stdout `--json`, ou o mesmo texto no stderr → `codex sem cota: <mensagem>` no stderr e exit 75
  para: cai no erro genérico "sem thread.started", exit 1
  bateria: `bash scripts/testa-transferir-para-codex.sh`
  fixture: dublê em modo `semcota-json` (emite `thread.started`, `turn.started`, `error` com a mensagem, `turn.failed`); caso "sem cota → exit 75 e stderr cita `codex sem cota`"
pronto quando: `bash scripts/testa-transferir-para-codex.sh` verde com o caso novo

### 4. Documentação [tipo: docs]
atende: D5
arquivos: `skills/rainforest-mind/references/regra-10-runtime.md`, `README.md`, `docs/rainforest/relatorios/2026-09-08-validacao-runtime-codex.md`
depende de: 1, 2, 3
paralela: nao
mutacao: n/a
  motivo: documentação; a falsificação é coerência com o exit 75 do código.
pronto quando: `regra-10-runtime.md` cita exit 75 e a linha `codex sem cota:` (≤ 3300 B, catraca em `bash hooks/testa-contexto-sessao.sh` seção 7.5); o relatório ganha a seção "Codex sem cota" com a medição de 2026-09-08 colada

### 5. Validação ao vivo com o plugin 1.8.0 [tipo: teste]
atende: D1, D2, D3, D4
arquivos: `docs/rainforest/relatorios/2026-09-08-validacao-runtime-codex.md`
depende de: nenhuma (roda quando a cota voltar, 17:41 de 2026-09-08)
paralela: nao
mutacao: n/a
  motivo: validação com binário externo e agente do cache instalado; não há linha de produção a inverter neste repositório.
pronto quando: despacho pelo `Agent` do `rainforest-mind:executor` (cache 1.8.0), `isolation: "worktree"`, briefing cuja primeira linha é `Runtime: codex` e que NÃO traz `Despacho:` nem instrução de ponte, devolve saída literal de um `codex exec` real; colado no relatório: (a) a linha `comando: codex exec ...` do stderr do despacho; (b) a última linha de `.rainforest/portaria/despachos.jsonl` do worktree desta sessão, com `"runtime":"codex"`, gravada pela portaria viva (sem rodar o hook à mão); (c) `git log -1` do worktree do agente com o commit feito pela ponte; tudo re-derivado de `git` nesta sessão, nunca copiado do relato

### 7. Emenda — o preâmbulo sozinho não segura: bloco de ponte no briefing [tipo: implementar]
atende: D1, D4
arquivos: `agents/arqueologo.md`, `agents/auditor-de-seguranca.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/executor.md`, `agents/planejador.md`, `agents/resolvedor-de-build.md`, `agents/revisor.md`, `agents/tester.md`, `skills/rainforest-mind/references/regra-10-runtime.md`, `skills/modo-dev/SKILL.md`, `skills/executar/SKILL.md`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: instrução de prompt (preâmbulo e bloco de briefing); a falsificação é comportamental, no despacho real.
pronto quando: a T5 rodou duas vezes ao vivo com o plugin 1.8.0 — (i) só com `Runtime: codex`, como D2 mandava: o executor ignorou o preâmbulo, fez a tarefa em PowerShell/Write e não chamou `despachar-codex.cjs` (transcript do subagente: zero ocorrências de `despachar-codex`, nove chamadas de ferramenta, nenhuma delas o script); (ii) com o bloco de ponte de `regra-10-runtime.md` no briefing: saída literal de `codex exec` real, `comando:` no stderr e commit da ponte re-derivado de `git`. Os dois relatos colados no relatório. O preâmbulo endurecido (passo zero, entrega inválida) só se prova na próxima versão instalada — registrado como lacuna, não como cumprido.

### 6. Versão [tipo: docs]
atende: D5
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3, 4, 5, 7
paralela: nao
mutacao: n/a
  motivo: bump.
pronto quando: `1.8.0` → `1.8.1` (PATCH: correção de legibilidade e exit code de falha passageira, sem contrato novo) no último commit da branch; `node scripts/conferir-versao.cjs` sai 0
