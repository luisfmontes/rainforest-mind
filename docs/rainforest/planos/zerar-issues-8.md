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
arquivos: `.github/workflows/baterias.yml`, `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`, `hooks/testa-gate-publicacao-destino.sh`
depende de: 4
paralela: sim
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: `(?![\w.-]+\.(?:invalid|example|test|localhost)(?![-\w]|\.\w))`
  para: `(?!x^)`
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: testa-conferir-publicacao.sh, secao "TLD reservado (RFC 2606)"
pronto quando: com o `.github/workflows/baterias.yml` real, `head -5` não contém `rainforest-gate: dados-de-exemplo` e `node scripts/conferir-publicacao.cjs .github/workflows/baterias.yml` sai **0** sem achado — o e-mail `ci@rainforest.invalid` deixa de ser achado porque TLD reservado (`.invalid`, `.example`, `.test`, `.localhost`) não é endereço real, e o id de run no comentário é reescrito sem a sequência de 11 dígitos; `nome@empresa.com.br` e `x@foo.test.com` (reservado fora do último rótulo) continuam achado; o próprio `scripts/conferir-publicacao.cjs`, cujos comentários são exemplos das formas que ele pega, leva o marcador nas primeiras linhas (o mesmo que a bateria dele já usa) — provado por `bash scripts/testa-conferir-publicacao.sh` com os casos impressos. O caso "arquivo vizinho SEM marcador" de `hooks/testa-gate-publicacao-destino.sh` usava o próprio conferidor como vizinho e passa a usar `scripts/conferir-entrega.cjs`, que segue sem marcador. Achado 3 da revisão.

### 11. `|&` é fronteira de segmento, como `&&` e `||` [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/lib/cwd-efetivo.cjs`, `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-staging-total.sh` (os gates `staging-total` e `mensagem-commit` não são tocados: a segmentação deles vem de `segmentosComAspas`, em `cwd-efetivo.cjs`)
depende de: 8
paralela: sim
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `const OPERADORES_DE_DOIS = new Set(["|&"]);`
  para: `const OPERADORES_DE_DOIS = new Set([]);`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "pipe com stderr (|&) (#309, revisao 2)"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, `echo hi |& bash -c "gh issue close 12"` sai **2** no `gate-fechar-issue.cjs` e `echo hi |& git add -A` sai **2** no `gate-staging-total.cjs` — os dois saem **0** hoje, inclusive na `origin/main` (medido em 2026-09-22); `echo a | grep b` e `echo a || echo b` continuam com o exit de hoje. Achado 1 da revisão 2.

### 12. Continuação de linha dentro da string do wrapper não parte o comando [tipo: implementar]
atende: D2, D3
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 9
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `interno = colapsaContinuacaoDeLinha(interno);`
  para: `interno = interno;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "continuacao de linha dentro da string (#309, revisao 2)"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, `bash -c "gh issue \<LF>close 12"` (contrabarra seguida de quebra de linha dentro das aspas, que o bash colapsa antes de executar) sai **2**, e `bash -c "git add \<LF>-A"` sai **2** no `gate-staging-total.cjs` — hoje os dois saem **0**, inclusive na `origin/main`; comando legítimo de várias linhas sem contrabarra continua com o exit de hoje. Achado 2 da revisão 2.

### 13. Continuação de linha no topo do comando, sem wrapper [tipo: implementar]
atende: D1, D3
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-staging-total.sh`
depende de: 12
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `cmd = colapsaContinuacaoDeLinha(cmd);`
  para: `cmd = cmd;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "continuacao de linha no topo (#309, revisao 2)"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, `gh issue <contrabarra><LF>close 12` mandado direto, **sem wrapper**, sai **2** (hoje sai 0, inclusive depois das tarefas 11 e 12), e `git add <contrabarra><LF>-A` sai **2** no `gate-staging-total.cjs`; comando de várias linhas sem contrabarra (`gh issue<LF>close 12`) continua **0**, e contrabarra dentro de aspas simples segue o que o bash faz (medir e dizer o que mediu). Achado que a tarefa 12 deixou de fora, nomeado pelo próprio executor.

### 14. Colapso de continuação segue o bash: paridade de contrabarra e estado de aspas [tipo: implementar]
atende: D1, D2, D3
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-staging-total.sh`
depende de: 13
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `function colapsaContinuacaoDeLinha(str) {`
  para: `function colapsaContinuacaoDeLinha(str) { return str.replace(/\\r?\n/g, "");`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, secao "continuacao de linha: paridade e aspas (#309, revisao 3)"
pronto quando: com o payload PreToolUse real e `gh` de sandbox, (a) `echo hi \<LF>gh issue close 12` (duas contrabarras — no bash a primeira escapa a segunda e a quebra separa comandos) sai **2**, como saía em `origin/main` antes desta rodada e como passou a sair **0** depois da tarefa 13; (b) `gh pr create --body "it's done, closes \<LF>#42, don't worry"` sai **2**, porque o bash colapsa e o corpo vira `closes #42` (na `origin/main` também saía 0 — é buraco antigo, não regressão); (c) `echo hi \<LF>gh issue close 12` (contrabarra única) continua **2** e `echo 'a\<LF>b'` (aspas simples de verdade) continua **0**. O colapso passa a varrer caractere a caractere, com estado de aspas simples/duplas e contagem de contrabarras, em vez de regex sobre o texto mascarado. Achados 1 e 2 da revisão 3.

### 15. Bateria de unidade do colapso, e contrabarra solta no fim [tipo: teste]
atende: D1, D2, D3
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-colapso-continuacao.cjs`, `hooks/testa-colapso-continuacao.sh`
depende de: 14
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `const pares = Math.floor(qtd / 2) * 2;`
  para: `const pares = 0;`
  bateria: `bash hooks/testa-colapso-continuacao.sh`
  fixture: testa-colapso-continuacao.cjs, casos de 2, 3 e 4 contrabarras
pronto quando: `bash hooks/testa-colapso-continuacao.sh` afere a STRING devolvida por `colapsaContinuacaoDeLinha` (não o exit do gate) em 19 casos medidos contra o bash real, e sai `== resultado: 19 ok, 0 falha(s) ==`; com `echo hi\` (contrabarra solta no fim, sem nada depois) a função devolve `echo hi`, como o bash, em vez de preservar a contrabarra. Achados 1 e 2 da revisão 4: os casos do gate `hc` e `hf` davam o mesmo exit com a função certa ou quebrada, porque outra camada do gate já barrava.
