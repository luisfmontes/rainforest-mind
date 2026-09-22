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
pronto quando: com um worktree inexistente em `--worktree`, `python scripts/conferir-entrega.py` sai **69** com stderr começando por `nao-verificavel:`; com commit vazio sai **1** nomeando `commit do agente vazio`; com `--escopo` e arquivo fora dele sai **1**; com porcelain em BOM aprova — provado por `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` devolvendo `== resultado: N ok, 0 falha(s) ==` com **N igual** ao de `bash scripts/testa-conferir-entrega.sh` (contra o `.cjs`). As outras três garantias têm alvo de mutação também declarado aqui, cada um com a mesma bateria ficando vermelha pelo `node scripts/conferir-mutacao.cjs`: BOM `if conteudo.startswith("\ufeff"):` → `if False:`; commit vazio `COMMIT_VAZIO_REPROVA = True` → `COMMIT_VAZIO_REPROVA = False`; escopo `ap.add_argument("--escopo",` → `ap.add_argument("--escopo-mutado",`. As quatro linhas-alvo existem literalmente no `.py` entregue.

### 4. O CI roda o gêmeo em passo próprio [tipo: configurar]
atende: D5
arquivos: `.github/workflows/baterias.yml`, `CONTRIBUTING.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: é passo de workflow; a falsificação é o passo aparecer e rodar no log do CI do PR, não um ramo de código a inverter
pronto quando: no run de CI do PR desta rodada, o job `baterias` mostra um passo cujo comando é `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`, com `== resultado: N ok, 0 falha(s) ==` no log — provado por `gh run view <run> --log | grep -E "gemeo|resultado: [0-9]+ ok, 0 falha"`; o `CONTRIBUTING.md` diz que o CI roda essa linha, coerente com D5 (passo separado, não dentro da bateria padrão).

### 5. Suíte de eval de gatilho publicada em PR próprio, fora desta rodada [tipo: configurar]
atende: D6
arquivos: `evals/README.md`, `evals/gatilho-*/case.yaml`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: emenda D6 — a suíte não entra nesta entrega; a mutação planejada foi tentada e mostrou que o desenho não a torna possível (grader with-only fora do score), registrado no PR #311 e na #302
pronto quando: com a branch `fluxo/eval-gatilho-302` no origin, o PR #311 existe em rascunho contra a `main` e o diff do PR #310 não contém nenhum caminho sob `evals/` — provado por `gh pr view 311 --json isDraft,headRefName` devolvendo `isDraft: true` e `git diff --name-only origin/main...HEAD -- evals/` vazio.

### 6. Custo na #302, versão e changelog [tipo: docs]
atende: D7, D8
arquivos: `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3, 4, 5
paralela: nao
mutacao: n/a
  motivo: bump de versão e texto de changelog, sem comportamento a inverter
pronto quando: com `origin/main` no momento do `fechar`, a versão no `plugin.json` e no badge do README é o minor seguinte ao dela — provado por `node scripts/conferir-versao.cjs` saindo 0; a #302 recebe comentário com o custo medido (~US$ 11,70) e os dois achados, e continua aberta; o CHANGELOG não anuncia a suíte de eval; #309 e #303 fecham pelo PR.

### 7. A bateria do conferir-entrega deixa o interpretador do gêmeo no PATH sem git [tipo: teste]
atende: D4, D5
arquivos: `scripts/testa-conferir-entrega.sh`
depende de: 3
paralela: nao
mutacao:
  arquivo: `scripts/testa-conferir-entrega.sh`
  de: `PATH_SEM_GIT="$NODE_DIR:$INTERP_DIR"`
  para: `PATH_SEM_GIT="$NODE_DIR"`
  bateria: `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`
  fixture: testa-conferir-entrega.sh, caso "git fora do PATH -> exit 69 (ambiente, nao 'nao e repositorio git')"
pronto quando: com o gêmeo Python como `CONFERIR` e o PATH do filho reduzido a node + interpretador (sem git), o caso "git fora do PATH" recebe **69** do `.py` em vez de **127** do `env` — provado por `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` devolvendo `== resultado: 73 ok, 0 falha(s) ==` (antes da emenda: 71 ok, 2 falhas, ambas nesse caso), e pelo mesmo comando sem `CONFERIR` continuar em 73 ok. Emenda de 2026-09-22 na revisão: o conserto foi feito na integração da tarefa 3 e ficou sem tarefa.

### 8. `coproc` também é palavra reservada que precede comando [tipo: implementar]
atende: D1, D3
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`
depende de: 1
paralela: sim
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `"do", "then", "else", "elif", "while", "until", "if", "!", "coproc",`
  para: `"do", "then", "else", "elif", "while", "until", "if", "!",`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "coproc (#309, revisao)"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, `coproc bash -c "gh issue close 12"` sai **2** no `gate-fechar-issue.cjs` (antes: 0, medido na revisão de 2026-09-22) e `coproc git add -A` sai **2** no `gate-staging-total.cjs` — provado pelas duas baterias com os casos impressos. Achado 1 da revisão.

### 9. Parâmetro especial (`$@`, `$*`, `$#`, `$?`, `$$`, `$!`, `$-`) é construção ilegível [tipo: implementar]
atende: D2, D3
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `return /\$\(|`|\$[A-Za-z_{0-9@*#?$!-]/.test(str);`
  para: `return /\$\(|`|\$[A-Za-z_{0-9]/.test(str);`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "parametro especial (#309, revisao)"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, `set -- -c "gh issue close 12"; bash "$@"`, `bash "$*"`, `eval "$@"` e `eval $@` saem **2** no `gate-fechar-issue.cjs` (antes: 0), e `bash "$t"` continua **0** — provado por `bash hooks/testa-gate-fechar-issue.sh` com os casos impressos. Achado 2 da revisão.

### 10. O workflow volta a ser escaneado pelo gate de publicação inteiro [tipo: implementar]
atende: D5
arquivos: `.github/workflows/baterias.yml`, `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`
depende de: 4
paralela: sim
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: `(?![\w.-]+\.(?:invalid|example|test|localhost)\b)`
  para: `(?!x^)`
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: testa-conferir-publicacao.sh, secao "TLD reservado (RFC 2606)"
pronto quando: com o `.github/workflows/baterias.yml` real, `head -5` não contém `rainforest-gate: dados-de-exemplo` e `node scripts/conferir-publicacao.cjs .github/workflows/baterias.yml` sai **0** sem achado — o e-mail `ci@rainforest.invalid` deixa de ser achado porque TLD reservado (`.invalid`, `.example`, `.test`, `.localhost`) não é endereço real, e o id de run no comentário é reescrito sem a sequência de 11 dígitos; `nome@empresa.com.br` continua achado — provado por `bash scripts/testa-conferir-publicacao.sh` com os casos impressos. Achado 3 da revisão.
