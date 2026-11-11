# Plano: gate-fechar-issue lê -F, forma colada e flag curta com caixa exata

Design: docs/rainforest/design/gate-pr-flag-curta.md

## O que não pode quebrar
- `bash hooks/testa-gate-fechar-issue.sh` e `bash hooks/testa-gate-receita-corpo.sh` continuam verdes **sem edição**.
- `gh pr create --title t --body-file "<arquivo literal sem palavra de fechamento>"` continua saindo 0; `gh pr edit 5 --title x` (sem corpo) continua saindo 0.
- As recusas que existem hoje continuam recusando; o texto delas não muda (D1/D2 de `2026-11-07-receita-corpo-pr`).
- `gh pr merge` (`COM_VALOR_PR_MERGE`) não é tocado.

## Tarefas

### 1. extrairCorpoDoPR: caixa exata na flag curta, -F, forma colada e todas as ocorrências [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-pr-flag-curta.sh`
depende de: nenhuma
busca:
- repo | rg -n "toLowerCase|COM_VALOR_PR_MERGE" hooks/gate-fechar-issue.cjs | o laço de extrairCorpoDoPR (:579) baixa a caixa da chave; o pr merge (:711) já compara com caixa exata; estender
- doc | https://cli.github.com/manual/gh_pr_create | -b/--body, -F/--body-file, -B/--base, -f/--fill
- doc | https://github.com/spf13/pflag | flag curta aceita valor em token separado, com = e colado
- livro | pulado: correção de parser do próprio gate, sem mecanismo de terceiro a enxertar
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `: tok.slice(0, 2);`
  para: `: tok.slice(0, 2).toLowerCase();`
  bateria: `bash hooks/testa-gate-pr-flag-curta.sh`
  fixture: `testa-gate-pr-flag-curta.sh, casos "(c1) create -B main antes do --body-file" e "(c2) edit -B main antes do --body-file"`
prova: `bash hooks/testa-gate-pr-flag-curta.sh`
pronto quando: com o payload real de `PreToolUse` (`{"cwd":...,"tool_name":"Bash","tool_input":{"command":...}}`) no stdin de `node hooks/gate-fechar-issue.cjs` e um `gh` falso no PATH que sai 1 (a Issue não tem evidência legível), saem **2 citando `#12`** os contornos: `gh pr create -B main --title t --body-file <C>`, `gh pr edit 5 -B main --body-file <C>`, `gh pr create --title t -F <C>`, `gh pr edit 5 -F <C>`, `gh pr edit 5 -F=<C>`, `gh pr edit 5 -F<C>`, `gh pr edit 5 -b"Closes #12"`, `gh pr create --title t -b x --body-file <C>` e `gh pr create --title t --body-file <N> -b "Closes #12"`; e saem **0** os vizinhos legítimos: `gh pr create --title t -F <N>`, `gh pr create -B main --title t --body-file <N>`, `gh pr edit 5 -B main` e `gh pr edit 5 --title x` — onde `<C>` é arquivo literal com `Closes #12` e `<N>` arquivo literal sem palavra de fechamento; e `gh pr create --title t -f` continua saindo 2 com a razão "editor interativo" — provado por `bash hooks/testa-gate-pr-flag-curta.sh` saindo 0 com uma linha `ok` por caso, nenhum caso afirmando sobre o texto do fonte; e `bash hooks/testa-gate-fechar-issue.sh` e `bash hooks/testa-gate-receita-corpo.sh` saindo 0 sem edição

Forma prescrita (dentro de `extrairCorpoDoPR`):
- Duas constantes logo acima da função: `const FLAGS_CORPO_DIRETO = new Set(["--body", "-b"]);` e `const FLAGS_CORPO_ARQUIVO = new Set(["--body-file", "-F"]);`.
- No laço, a chave e o valor colado saem assim (flag longa em minúsculas, como hoje; curta com a caixa do token):
  ```
  const longa = tok.startsWith("--");
  const curta = !longa && /^-[A-Za-z]/.test(tok);
  const chave = longa
    ? (pontoIgual === -1 ? tok : tok.slice(0, pontoIgual)).toLowerCase()
    : tok.slice(0, 2);
  // valor na mesma palavra: --x=v, -Fv ou -F=v (pflag)
  const colado = longa
    ? (pontoIgual === -1 ? null : tok.slice(pontoIgual + 1))
    : (curta && tok.length > 2 ? tok.slice(2).replace(/^=/, "") : null);
  ```
  e os ramos passam a testar `FLAGS_CORPO_DIRETO.has(chave)` / `FLAGS_CORPO_ARQUIVO.has(chave)` (só quando `longa || curta`), lendo `colado` se não for `null` e senão `toks[i + 1].v`.
- Cada ramo, em vez de `return`, empurra o resultado num array `achados` e segue o laço (`continue`). Depois do laço:
  ```
  if (achados.length === 0) return { tipo: "nenhum", conteudo: null, legivel: false };
  const ilegivel = achados.find((a) => !a.legivel);
  if (ilegivel) return ilegivel;
  return { ...achados[0], conteudo: achados.map((a) => a.conteudo).join("\n") };
  ```
- Os retornos internos de hoje (variável, cwd incerto, heredoc, ENOENT com `caminho`/`resolvido`/`codigo`) ficam com os mesmos campos — só viram `achados.push(...)`.
- **Bateria nova** `hooks/testa-gate-pr-flag-curta.sh`, no molde de `hooks/testa-gate-receita-corpo.sh` (cabeçalho, `gh` falso que sai 1, `roda`, `tem`, `sai`). `<C>` = `$SBP_WIN/c.md` com `Closes #12`; `<N>` = `$SBP_WIN/n.md` com `corpo sem palavra de fechamento`. Casos `(c1)`..`(c9)` são os contornos (exit 2 e `tem ... "#12"`), `(v1)`..`(v4)` os vizinhos (exit 0), `(f1)` o `-f` (exit 2, `tem ... "editor interativo"`). Termina com `ok: <n>   falhou: <m>` e sai 1 com falha.
- Mutações extras que a integração re-roda à mão (fora da catraca, uma por decisão): D2 — `new Set(["--body-file", "-F"])` → `new Set(["--body-file"])` deixa `(c3)`..`(c6)` vermelhos; D3 — `conteudo: achados.map((a) => a.conteudo).join("\n")` → `conteudo: achados[0].conteudo` deixa `(c8)` vermelho.
- Parada (D4): alias do `gh`, `gh api`, env do `gh`, `--template`/`--fill` e flag longa abreviada ficam fora; achado de revisão nessas classes não reabre esta tarefa.

### 2. Versão PATCH, README e CHANGELOG [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1
mutacao: n/a
  motivo: só versão e texto; o comportamento é medido pela tarefa 1
pronto quando: com a `main` trazida para a branch (`git merge origin/main`), `node scripts/conferir-versao.cjs` sai 0, os dois `plugin.json` e o selo do README dizem a versão seguinte à da `main` na casa PATCH, e o CHANGELOG abre com essa versão descrevendo pelo comportamento as grafias que o gate passa a ler (`-F`, valor colado, `-B` deixa de ser corpo, todas as ocorrências) e o que fica fora pelo D4 — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A3 '^## ' CHANGELOG.md`
