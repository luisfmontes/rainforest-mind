# Plano: Zerar as Issues abertas, rodada 8 — gate bash "$t" e bypass do for/do (#309), gêmeo Python do conferir-entrega (#303), eval de gatilho (#302)

Design: docs/rainforest/design/zerar-issues-8.md

## O que não pode quebrar
- Tudo que os três gates de texto (`gate-fechar-issue`, `gate-mensagem-commit`, `gate-staging-total`) e o `gate-worktree` barram hoje continua barrado: `bash -c "gh issue close 12"`, `bash $CMD`, `bash "$f" "gh issue close 12"` saem 2.
- `bash scripts/testa-conferir-entrega.sh` contra o `.cjs` (caminho default) continua exit 0 com a contagem de hoje (73 ok).
- A bateria padrão (`bash scripts/varrer-baterias.sh`) não passa a depender de credencial nem de rede: a eval de gatilho nunca entra nela.

## Tarefas

### 1. Palavra reservada não tira o wrapper da posição de comando [tipo: implementar]
atende: D1, D3
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-staging-total.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `const PALAVRAS_RESERVADAS = new Set([`
  para: `const PALAVRAS_RESERVADAS = new Set([]); const _mutacao = new Set([`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "bypass por palavra reservada (#309)"
pronto quando: com o payload PreToolUse real (`{"cwd":<worktree>,"tool_name":"Bash","tool_input":{"command":...}}`) e `gh` de sandbox no PATH, `for t in x; do bash -c "gh issue close 12"; done`, `if true; then bash -c "gh issue close 12"; fi`, `while true; do bash -c "gh issue close 12"; done`, `! bash -c "gh issue close 12"` e `{ bash -c "gh issue close 12"; }` saem **2** no `gate-fechar-issue.cjs` (hoje o primeiro sai 0) — provado por `bash hooks/testa-gate-fechar-issue.sh` com a seção nova e cada caso impresso com o exit; a declaração vive numa linha única que começa exatamente com `const PALAVRAS_RESERVADAS = new Set([` (é o alvo da mutação) e é consultada em `posicaoDeComando`. Antes de escrever, medir quais palavras realmente vazam (inclusive `(`, `until`, `elif`, `else`) e pôr no conjunto só as que vazam, com o exit de antes colado no relato.

### 2. Variável entre aspas como último argumento é caminho de script [tipo: implementar]
atende: D2, D3
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-staging-total.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `if (ehVariavelCitadaFinal(current)) {`
  para: `if (false && ehVariavelCitadaFinal(current)) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "(#309) bash \"$t\" como ultimo argumento"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, a linha exata da issue `for t in $(grep -lE "CHANGELOG|badge|plugin\.json" scripts/testa-*.sh hooks/testa-*.sh); do bash "$t"; done`, `bash "$t"`, `bash "${t}"`, `bash "$t" 2>&1` e `bash "$t" > log` saem **0**, enquanto `bash "$f" "gh issue close 12"`, `bash $t`, `bash "$t" x` e `for t in x; do bash -c "gh issue close 12"; done` saem **2** — nos três gates de texto, provado por `bash hooks/testa-gate-fechar-issue.sh && bash hooks/testa-gate-mensagem-commit.sh && bash hooks/testa-gate-staging-total.sh` com os casos impressos; o ramo novo mora em `desempacotarWrapperDeString` atrás da linha exata `if (ehVariavelCitadaFinal(current)) {`.

### 3. Portar ao gêmeo Python as quatro garantias que faltam [tipo: implementar]
atende: D4, D5
arquivos: `scripts/conferir-entrega.py`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-entrega.py`
  de: `EXIT_NAO_VERIFICAVEL = 69`
  para: `EXIT_NAO_VERIFICAVEL = 2`
  bateria: `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`
  fixture: testa-conferir-entrega.sh, secao "D5 (2026-09-12): exit 69 = nao-verificavel, ambiente e nao conteudo"
pronto quando: com um worktree inexistente em `--worktree`, `python scripts/conferir-entrega.py` sai **69** com stderr começando por `nao-verificavel:`; com commit vazio sai **1** nomeando `commit do agente vazio`; com `--escopo` e arquivo fora dele sai **1**; com porcelain em BOM aprova — provado por `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` devolvendo `== resultado: N ok, 0 falha(s) ==` com **N igual** ao de `bash scripts/testa-conferir-entrega.sh` (contra o `.cjs`). As outras três garantias têm alvo de mutação também declarado aqui, cada um com a mesma bateria ficando vermelha pelo `node scripts/conferir-mutacao.cjs`: BOM `if conteudo.startswith("﻿"):` → `if False:`; commit vazio `COMMIT_VAZIO_REPROVA = True` → `COMMIT_VAZIO_REPROVA = False`; escopo `ap.add_argument("--escopo",` → `ap.add_argument("--escopo-mutado",`. As quatro linhas-alvo existem literalmente no `.py` entregue.

### 4. O CI roda o gêmeo em passo próprio [tipo: configurar]
atende: D5
arquivos: `.github/workflows/baterias.yml`, `CONTRIBUTING.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: é passo de workflow; a falsificação é o passo aparecer e rodar no log do CI do PR, não um ramo de código a inverter
pronto quando: no run de CI do PR desta rodada, o job `baterias` mostra um passo cujo comando é `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`, com `== resultado: N ok, 0 falha(s) ==` no log — provado por `gh run view <run> --log | grep -E "gemeo|resultado: [0-9]+ ok, 0 falha"`; o `CONTRIBUTING.md` diz que o CI roda essa linha, coerente com D5 (passo separado, não dentro da bateria padrão).

### 5. Suíte de eval de gatilho com os 7 pares de colisão [tipo: implementar]
atende: D6
arquivos: `evals/`, `evals/gatilho-*/case.yaml`, `evals/README.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `skills/depurar/SKILL.md`
  de: `description: Use quando algo está quebrado, falhando, com erro, lento ou intermitente`
  para: `description: Use para formatar tabelas em markdown`
  bateria: `claude plugin eval . --trust-plugin --no-publish --runs 1 --case "*depurar*"`
  fixture: evals/gatilho-depurar-vs-executar/case.yaml
pronto quando: com `claude plugin eval . --trust-plugin --no-publish --runs 1` rodado de verdade na raiz do worktree, os 7 casos da tabela da #302 (divergir×brainstorm, revisar×enxugar/verificar, enxugar×revisar, depurar×executar, arqueologia×analisar, verificar×revisar, limpar×fechar) aparecem no relatório, cada um com pedidos que devem acionar a skill dona (grader `tool_used: Skill` com o nome dela) e pedidos que não devem (nomeando a dona), e o braço baseline `with-without` roda — o relatório (`evals/results/<ts>/aggregate-result.json`) é lido e o `evals/README.md` registra por skill **acrescenta** ou **peso morto** e o custo total em USD da rodada; com a mutação aplicada o caso depurar sai abaixo do threshold (exit 1). Nenhum `skipped`. `--max-cost-usd` usado para limitar a rodada.

### 6. Custo na #302, versão e changelog [tipo: docs]
atende: D7, D8
arquivos: `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3, 4, 5
paralela: nao
mutacao: n/a
  motivo: bump de versão e texto de changelog, sem comportamento a inverter
pronto quando: com `origin/main` no momento do `fechar`, a versão no `plugin.json` e no badge do README é o minor seguinte ao dela — provado por `node scripts/conferir-versao.cjs` saindo 0; a #302 recebe comentário com o custo medido na tarefa 5 (o mesmo número do `evals/README.md`) e continua aberta; #309 e #303 fecham pelo PR.
