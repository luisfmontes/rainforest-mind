# Plano: Decisão e opção que evaporam entre design, plano e revisão

Design: docs/rainforest/design/decisao-que-evapora-na-esteira.md

Este plano usa o formato que ele mesmo introduz (`atende:` e `arquivos:`), por dois
motivos: é o primeiro exercício real do formato, e um formato que não sobrevive ao
próprio trabalho não deveria ser cobrado de ninguém.

## O que não pode quebrar

- `bash hooks/testa-contexto-sessao.sh` continua em **123 ok / 0 falhas**.
- `bash hooks/testa-heartbeat-poda.sh` continua em **6 ok / 0 falhas**.
- `bash scripts/testa-estado.sh` continua verde — é o script que ganha trava nova.
- `estado.cjs marcar` continua aceitando `--json` arbitrário: metadado novo não pode
  passar a ser recusado por não estar numa lista fechada.
- `estado.cjs` continua resolvendo caminho por `RFM_ESTADO_ROOT`/`CLAUDE_PROJECT_DIR`/
  `cwd` — a trava nova lê design e plano do **projeto**, nunca da pasta de dados do
  usuário.
- Nenhuma escrita em `C:\Users\Luis\.rainforest\` por teste nenhum.
- `arqueologia`, `executar`, `verificar` e `fechar` seguem sem exigência nova.

## Tarefas

### 1. `conferir-esteira.cjs` com os três subcomandos [tipo: implementar]
atende: D1, D3, D6, D7, D8
arquivos: `scripts/conferir-esteira.cjs`
depende de: nenhuma
paralela: sim
pronto quando: `node scripts/conferir-esteira.cjs design --slug decisao-que-evapora-na-esteira` sai `0`; `node scripts/conferir-esteira.cjs cobertura --slug decisao-que-evapora-na-esteira` sai `0`

Subcomandos:
- `design --slug <s>` — exige as seções `## Objetivo`, `## Decisões fechadas`,
  `## Avaliado e descartado`, `## Fora de escopo`, `## Em aberto`; exige decisões
  marcadas `**D<n> — ...**` com `n` sequencial de 1, sem buraco e sem repetido.
- `cobertura --slug <s>` — casa `D<n>` do design com `atende:` das tarefas do plano.
  Barra **nos dois sentidos** (D8): decisão sem tarefa, e tarefa com `atende:` vazio
  ou citando `D<n>` inexistente.
- `creep --slug <s> --base <ref> --head <ref>` — roda `git diff --name-only
  <base>...<head>` e acusa arquivo que não casa com nenhum glob de `arquivos:`.

Exit: `0` passou, `2` recusa deliberada, `1` erro de uso — a mesma convenção do
`estado.cjs`.

### 2. Trava no `estado.cjs marcar` [tipo: implementar]
atende: D4, D5
arquivos: `scripts/estado.cjs`
depende de: 1
paralela: nao
pronto quando: `node scripts/estado.cjs marcar --estagio plano --status ok` sai `2` contra um fixture cuja decisão `D2` não tem tarefa, e sai `0` depois de a tarefa entrar

- `--estagio design --status aprovado` → roda `conferir-esteira design`.
- `--estagio plano --status ok` → roda `conferir-esteira cobertura`.
- `--estagio revisar --status ok` → roda `conferir-esteira creep`, com `base` e `head`
  vindos do `--json`. **Sem `base`/`head` no json, recusa** — fechar a revisão sem
  poder provar ausência de creep é o buraco que D4 fecha.
- A trava só age quando o arquivo alvo existe; projeto que não usa design/plano não
  passa a ser barrado por isso.

### 3. Bateria do `conferir-esteira` [tipo: teste]
atende: D1, D7
arquivos: `scripts/testa-conferir-esteira.sh`
depende de: 1
paralela: nao
pronto quando: `bash scripts/testa-conferir-esteira.sh` sai `0`

Casos obrigatórios, cada um exigindo exit `2`: seção ausente no design; `D` repetido;
`D` com buraco na sequência; decisão sem tarefa; tarefa com `atende:` vazio; tarefa
citando `D` inexistente; arquivo do diff fora de todo glob. Mais os simétricos que
exigem exit `0`.

### 4. Templates das três skills [tipo: docs]
atende: D2, D3, D4, D6
arquivos: `skills/brainstorm/SKILL.md`, `skills/plano/SKILL.md`, `skills/revisar/SKILL.md`
depende de: nenhuma
paralela: sim
pronto quando: `grep -c "Avaliado e descartado" skills/brainstorm/SKILL.md` ≥ `1`; `grep -c "atende:" skills/plano/SKILL.md` ≥ `1`; `grep -c "arquivos:" skills/plano/SKILL.md` ≥ `1`; `grep -c "emendar o plano" skills/revisar/SKILL.md` ≥ `1`

### 5. README e versão [tipo: docs]
atende: D7
arquivos: `README.md`, `.claude-plugin/plugin.json`
depende de: 1, 2, 4
paralela: nao
pronto quando: `grep -c "conferir-esteira" README.md` ≥ `1`; `node -e "console.log(require('./.claude-plugin/plugin.json').version)"` devolve `0.64.0`
