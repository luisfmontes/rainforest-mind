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
  fixture: `testa-gate-pr-flag-curta.sh, caso "(c10) create -B main --fill"`
prova: `bash hooks/testa-gate-pr-flag-curta.sh`
pronto quando: com o payload real de `PreToolUse` (`{"cwd":...,"tool_name":"Bash","tool_input":{"command":...}}`) no stdin de `node hooks/gate-fechar-issue.cjs` e um `gh` falso no PATH que sai 1 (a Issue não tem evidência legível), cada linha da tabela de casos abaixo dá o exit e o trecho de stderr da tabela — provado por `bash hooks/testa-gate-pr-flag-curta.sh` saindo 0 com uma linha `ok` por asserção, nenhum caso afirmando sobre o texto do fonte; e `bash hooks/testa-gate-fechar-issue.sh` e `bash hooks/testa-gate-receita-corpo.sh` saindo 0 sem edição

Tabela de casos (`<C>` = `$SBP_WIN/c.md` contendo `Closes #12`; `<N>` = `$SBP_WIN/n.md` contendo `corpo sem palavra de fechamento`; `<F>` = `$SBP_WIN/f.md` contendo `Fecha #12`). Na bateria, o nome de cada caso começa pelo id:

| id | comando | exit | stderr contém |
|---|---|---|---|
| (c1) create -B main antes do --body-file | `gh pr create -B main --title t --body-file <C>` | 2 | `#12` |
| (c2) edit -B main antes do --body-file | `gh pr edit 5 -B main --body-file <C>` | 2 | `#12` |
| (c3) create -F | `gh pr create --title t -F <C>` | 2 | `#12` |
| (c4) edit -F | `gh pr edit 5 -F <C>` | 2 | `#12` |
| (c5) edit -F= | `gh pr edit 5 -F=<C>` | 2 | `#12` |
| (c6) edit -F colado | `gh pr edit 5 -F<C>` | 2 | `#12` |
| (c7) edit -b colado | `gh pr edit 5 -b"Closes #12"` | 2 | `#12` |
| (c8) -b benigno antes do --body-file | `gh pr create --title t -b x --body-file <C>` | 2 | `#12` |
| (c9) --body-file benigno antes do -b | `gh pr create --title t --body-file <N> -b "Closes #12"` | 2 | `#12` |
| (c10) create -B main --fill | `gh pr create -B main --fill` | 2 | `editor interativo` |
| (c11) issue comment -F com palavra falsa | `gh issue comment 1 -F <F>` | 2 | `Closes #12` |
| (v1) create -F sem fechamento | `gh pr create --title t -F <N>` | 0 | — |
| (v2) create -B main com corpo benigno | `gh pr create -B main --title t --body-file <N>` | 0 | — |
| (v3) edit -B sem corpo | `gh pr edit 5 -B main` | 0 | — |
| (v4) edit só título | `gh pr edit 5 --title x` | 0 | — |
| (f1) create -f | `gh pr create --title t -f` | 2 | `editor interativo` |

O `(c10)` é o caso que só a caixa exata separa: hoje `-B main` vira corpo "main" e o `--fill` (corpo dos commits, que o gate não lê) passa com 0; com a caixa exata não há corpo e cai na recusa "editor interativo". O `(c11)` prova que `gh issue create`/`gh issue comment` (os outros dois chamadores de `extrairCorpoDoPR`, em `:1114` e `:1124`) herdam o `-F` **de propósito**: o `gh` aceita `-F` nos dois, e lá a checagem é só de palavra-chave falsa (o stderr sugere `Closes #12`, como o caso 614-7 da bateria antiga).

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
- A ordem interna de cada ramo (variável, cwd incerto, heredoc, leitura do disco) **não muda**, e os retornos de hoje ficam com os mesmos campos (`caminho`/`resolvido`/`codigo` no ENOENT, `heredoc`, `variavel`, `cwdIncerto`): só `return X` vira `achados.push(X); continue;`.
- Valor ausente (`colado === null` e `i + 1 >= toks.length`) = `continue` sem empurrar nada, como hoje. Valor colado vazio (`-F=`, `--body-file=`) segue o fluxo normal: string vazia vai para o ramo e a recusa é a de hoje para arquivo ilegível (`--body-file veio vazio.`).
- **Bateria nova** `hooks/testa-gate-pr-flag-curta.sh`, no molde de `hooks/testa-gate-receita-corpo.sh` (copiar o cabeçalho, o `gh` falso que sai 1 e as funções `roda`, `tem`, `sai`). Cria `c.md`, `n.md` e `f.md` com `printf` no `$SBP`. Um bloco por linha da tabela, na ordem da tabela: `roda '<comando>'`, `sai "<id>" <exit>` e, quando a coluna tem trecho, `tem "<id>" "<trecho>"`. Termina com `echo "ok: $ok   falhou: $falhou"` e `[ "$falhou" -eq 0 ]`. **Não** registrar em `scripts/baterias-obrigatorias.txt` (a bateria-molde também não está lá).
- Mutações extras que a integração re-roda à mão (fora da catraca, uma por decisão): D2 — `new Set(["--body-file", "-F"])` → `new Set(["--body-file"])` deixa `(c3)`..`(c6)` vermelhos; D3 — `conteudo: achados.map((a) => a.conteudo).join("\n")` → `conteudo: achados[0].conteudo` deixa `(c8)` vermelho.
- Parada (D4): alias do `gh`, `gh api`, env do `gh`, `--template` e flag longa abreviada ficam fora. *Emenda da revisão 1:* a frase que estava aqui ("valor de outra flag que começa com `-b`/`-F` é lido como flag, como já era") era falsa — virou o D5 e a tarefa 3.

### 3. Valor de outra flag não é lido como flag (emenda da revisão 1) [tipo: implementar]
atende: D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-pr-flag-curta.sh`
depende de: 1
busca:
- repo | rg -n "COM_VALOR_PR_MERGE" hooks/gate-fechar-issue.cjs | o pr merge já pula o valor das flags que o levam (:711); estender o mesmo padrão ao extrairCorpoDoPR
- doc | https://cli.github.com/manual/gh_pr_create | flags de valor do create
- doc | https://cli.github.com/manual/gh_pr_edit | flags de valor do edit (sem atalho booleano)
- livro | pulado: correção de parser do próprio gate
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (colado === null) i += 1;`
  para: `if (false) i += 1;`
  bateria: `bash hooks/testa-gate-pr-flag-curta.sh`
  fixture: `testa-gate-pr-flag-curta.sh, caso "(c12) create --fill com título -bar"`
prova-na-base: verde — na base 7882b947 o (c12) já sai 2 (a regressão nasceu na tarefa 1); a prova é a mutação acima, que reverte o D5 sobre o HEAD da tarefa 1
pronto quando: com o mesmo payload real e o mesmo `gh` falso da tarefa 1, as linhas novas da tabela abaixo dão o exit e o trecho da tabela, e as 16 linhas antigas continuam iguais — provado por `bash hooks/testa-gate-pr-flag-curta.sh` saindo 0, nenhum caso afirmando sobre o texto do fonte; e `bash hooks/testa-gate-fechar-issue.sh` e `bash hooks/testa-gate-receita-corpo.sh` saindo 0 sem edição

| id | comando | exit | stderr contém |
|---|---|---|---|
| (c12) create --fill com título -bar | `gh pr create --fill --title "-bar"` | 2 | `editor interativo` |
| (c13) create --fill com -t -Fx | `gh pr create --fill -t "-Fx"` | 2 | `editor interativo` |
| (v5) título -bar com corpo benigno | `gh pr create --title "-bar" --body-file <N>` | 0 | — |
| (v6) corpo direto começando com -F | `gh pr create --title t --body "-Fx sem fechamento"` | 0 | — |

Forma prescrita:
- Constante logo abaixo de `FLAGS_CORPO_ARQUIVO`:
  ```
  // Flags de valor do pr create/edit e issue create/comment (D5): o token
  // seguinte é o valor delas, nunca uma flag.
  const FLAGS_COM_VALOR = new Set([
    "--title", "-t", "--base", "-B", "--head", "-H", "--repo", "-R",
    "--assignee", "-a", "--label", "-l", "--milestone", "-m", "--project", "-p",
    "--reviewer", "-r", "--template", "-T", "--recover",
    "--add-assignee", "--add-label", "--add-project", "--add-reviewer",
    "--remove-assignee", "--remove-label", "--remove-project", "--remove-reviewer",
  ]);
  ```
- No laço, logo depois de calcular `colado` e antes do ramo de corpo direto:
  ```
  if ((longa || curta) && FLAGS_COM_VALOR.has(chave)) {
    if (colado === null) i += 1;
    continue;
  }
  ```
- Nos dois ramos de corpo, onde o valor vem de `toks[i + 1].v`, acrescentar `i += 1;` logo depois da atribuição (ex.: `corpo = toks[i + 1].v;` vira `corpo = toks[i + 1].v; i += 1;`), para o valor do corpo também não ser relido como flag (caso `(v6)`).
- Bateria: os quatro casos entram depois do `(c11)`/`(v4)`, no mesmo formato (`roda`, `sai`, `tem`).

### 4. Issue com corpo ilegível ainda checa a palavra falsa dos legíveis (emenda da revisão 2) [tipo: implementar]
atende: D3
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-pr-flag-curta.sh`
depende de: 3
busca:
- repo | rg -n "corpoIssue|corpoComentario" hooks/gate-fechar-issue.cjs | os dois chamadores de issue só checam palavra falsa com legivel; estender o retorno do D3
- livro | pulado: correção do próprio gate
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (ilegivel) return { ...ilegivel, conteudoLegivel:`
  para: `if (ilegivel) return { ...ilegivel, conteudoNaoUsado:`
  bateria: `bash hooks/testa-gate-pr-flag-curta.sh`
  fixture: `testa-gate-pr-flag-curta.sh, caso "(c14) issue comment com palavra falsa e -F inexistente"`
prova: `bash hooks/testa-gate-pr-flag-curta.sh`
pronto quando: com o mesmo payload real e `gh` falso, `gh issue comment 1 -b "Fecha #12" -F <caminho inexistente>` sai 2 com `Closes #12` no stderr (na base 7882b947 já saía 2; no HEAD da tarefa 3 sai 0), e `gh issue comment 1 -b "Segue #12" -F <caminho inexistente>` sai 0 — provado por `bash hooks/testa-gate-pr-flag-curta.sh` saindo 0, e as duas baterias antigas saindo 0 sem edição

Forma prescrita:
- O retorno do ilegível no fim de `extrairCorpoDoPR` vira `if (ilegivel) return { ...ilegivel, conteudoLegivel: achados.filter((a) => a.legivel).map((a) => a.conteudo).join("\n") };`.
- Nos chamadores de `issue create` e `issue comment`, `const texto = corpo.legivel ? corpo.conteudo : corpo.conteudoLegivel;` e `if (texto) verificarFalsasChaves(texto);` no lugar do `if (corpo.legivel && corpo.conteudo)`.
- O docblock de `extrairCorpoDoPR` volta a ficar colado na função (as constantes sobem para antes dele) e passa a dizer: lê `-b`/`--body` e `-F`/`--body-file` com valor separado, `=` ou colado, pula o valor das `FLAGS_COM_VALOR`, junta todas as ocorrências legíveis, e devolve a primeira ilegível com `conteudoLegivel`.
- Bateria: cabeçalho cita D1, D2, D3 e D5; a seção `(c1..c11)` vira `(c1..c14)`; casos `(c14)` e `(v7)` com os dois comandos acima.

### 2. Versão PATCH, README e CHANGELOG [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 3
*Emenda da revisão 1:* o CHANGELOG diz que, **no PR**, todos os corpos são checados (achado 2: no `issue create`/`issue comment` um corpo ilegível faz a checagem de palavra falsa ser pulada), diz que valor de outra flag não é lido como flag (D5) e põe flag curta agrupada entre o que fica fora.
mutacao: n/a
  motivo: só versão e texto; o comportamento é medido pela tarefa 1
pronto quando: com a `main` trazida para a branch (`git merge origin/main`), `node scripts/conferir-versao.cjs` sai 0, os quatro lugares — `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, o selo do README (`vers%C3%A3o-X-` e `alt="versão X"`) e o topo do CHANGELOG (`## X — AAAA-MM-DD`, data do dia) — dizem a versão seguinte à da `main` na casa PATCH (2.11.1 se a `main` ainda estiver em 2.11.0), e o CHANGELOG abre com essa versão descrevendo pelo comportamento as grafias que o gate passa a ler (`-F`, valor colado, `-B` deixa de ser corpo, todas as ocorrências) e o que fica fora pelo D4 — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A3 '^## ' CHANGELOG.md`
