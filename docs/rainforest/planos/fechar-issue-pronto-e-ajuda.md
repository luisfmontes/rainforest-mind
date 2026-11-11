# Plano: fechar-issue aceita "Pronto quando" e o gate deixa passar a ajuda do gh

Design: docs/rainforest/design/fechar-issue-pronto-e-ajuda.md

## O que não pode quebrar
- `gh pr create` sem corpo, ou com corpo citando `Closes #N` sem evidência, continua saindo 2 no gate.
- `fechar-issue.cjs` continua recusando Issue sem critério nenhum e as variantes (j) e (k) do cabeçalho canônico.
- As baterias `hooks/testa-gate-pr-flag-curta.sh` (40 ok), `hooks/testa-gate-fechar-issue.sh` e `scripts/testa-fechar-issue.sh` continuam verdes.

## Tarefas

### 1. fechar-issue aceita as formas de "Pronto quando" [tipo: implementar]
atende: D1, D2
arquivos: `scripts/fechar-issue.cjs`, `scripts/testa-fechar-issue.sh`
depende de: nenhuma
busca:
- repo | grep -n "temCriterio" scripts/fechar-issue.cjs | uma regex só, linha 163, só o cabeçalho canônico
desfecho: estender
mutacao:
  arquivo: `scripts/fechar-issue.cjs`
  de: `|| RE_PRONTO_QUANDO.test(issueBody)`
  para: `|| false`
  bateria: `bash scripts/testa-fechar-issue.sh`
  fixture: `testa-fechar-issue.sh, casos novos (q), (r), (s) e (t)`
prova-na-base: verde — a bateria de hoje passa na base e o fechar-issue só se exercita com o gh falso que a própria bateria monta; os casos (q) a (t) nascem com a tarefa e a mutação mede que eles mordem
pronto quando: com o corpo de Issue que o `gh` falso devolve, `node scripts/fechar-issue.cjs <n> --comando x --saida y` sai 0 e comenta para cada uma das três formas — `## Pronto quando` (caso q), `**Pronto quando:** ...` (caso r) e `Pronto quando: ...` no início da linha (caso s) —, sai 2 para corpo sem critério (caso b, que já existe) e continua saindo 2 nos casos (j) e (k); a recusa cita "Pronto quando" — provado por `bash scripts/testa-fechar-issue.sh` terminando sem `FALHA` e com exit 0, e pela mutação acima deixando a bateria vermelha

Forma prescrita (código a nascer): duas constantes logo depois dos `require` (linhas 17-22), `RE_CRITERIO` (a regex de hoje, intacta) e `RE_PRONTO_QUANDO = /^(?:#{2,3}\s+Pronto quando\b|(?:[-*]\s+)?\*\*Pronto quando:\*\*|Pronto quando:)/m`, e a linha `const temCriterio = RE_CRITERIO.test(issueBody) || RE_PRONTO_QUANDO.test(issueBody);`. A mensagem de recusa vira `RECUSADO: a Issue #<n> nao tem criterio de pronto ("## Critério de pronto (falsificável)" ou "Pronto quando:")`. Os casos novos seguem a forma do `gh` falso da bateria (variável que escolhe o corpo, linhas 40-56). Nenhum caso afirma sobre o texto do fonte.

*Emenda do leitor cego (bateria):* no stub do `gh` falso, três variáveis novas, `GH_CORPO_PRONTO_H2`, `GH_CORPO_PRONTO_NEGRITO` e `GH_CORPO_PRONTO_LINHA`, lidas junto das existentes e testadas em ramos `else if` ANTES do `else` final, devolvendo respectivamente `"Como reproduzir: passo1 passo2\n## Pronto quando\ncomando esperado"`, `"Como reproduzir: passo1 passo2\n**Pronto quando:** comando esperado"` e `"Como reproduzir: passo1 passo2\nPronto quando: comando esperado"`. Os casos (q), (r) e (s) entram depois do último caso existente, o (p) (os rótulos (l) e (m) já existem com outro conteúdo) e antes do placar final, copiando a estrutura do caso (a) (subshell com `PATH`, `GH_LOG` próprio e a variável do caso; exit 0; o log tem `issue comment` e `issue close`). O caso (t) usa o corpo sem critério (nenhuma variável), redireciona o stderr para `$SBP/err-t` e afirma exit 2 e `grep -q "Pronto quando" "$SBP/err-t"`. Os casos (b), (j) e (k) ficam intocados.

### 2. O gate deixa passar a ajuda do gh [tipo: implementar]
atende: D3, D4, D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-pr-flag-curta.sh`
depende de: nenhuma
busca:
- repo | grep -n "AJUDA_PR_MERGE" hooks/gate-fechar-issue.cjs | só o `gh pr merge` trata ajuda (linha 761, uso 943)
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (ehAjudaDoGh(subcomandos)) return;`
  para: `if (false) return;`
  bateria: `bash hooks/testa-gate-pr-flag-curta.sh`
  fixture: `testa-gate-pr-flag-curta.sh, casos h1, h2 e h6 (gh pr create --help, gh pr create -h, gh help pr create)`
prova: `node -e 'process.stdout.write(JSON.stringify({cwd:process.cwd(),tool_name:"Bash",tool_input:{command:"gh help pr create"}}))' | node hooks/gate-fechar-issue.cjs`
pronto quando: com o payload real de PreToolUse (o `roda` da bateria), `gh pr create --help`, `gh pr create -h`, `gh pr edit --help`, `gh issue create --help`, `gh issue comment --help` e `gh help pr create` saem 0, e continuam saindo 2: `gh pr create --title t`, `gh pr create --title t --help` (ajuda misturada, D4), `gh pr create --help --body "Closes #12"` e `gh pr create -dh` — provado por `bash hooks/testa-gate-pr-flag-curta.sh` terminando em `ok: 51   falhou: 0` (40 de hoje + 11 novos) com exit 0, e pela mutação acima deixando a bateria vermelha

Forma prescrita (código a nascer): `const AJUDA_GH = new Set(["--help", "-h"]);` junto ao `AJUDA_PR_MERGE`, e a função de uma expressão só, sem ramo e sem print: `function ehAjudaDoGh(subcomandos) { return subcomandos[0] === "help" || (subcomandos.length === 3 && AJUDA_GH.has(subcomandos[2])); }`. A chamada `if (ehAjudaDoGh(subcomandos)) return;` entra no `verificarComandoGh` logo depois do bloco que recusa subcomando por variável e antes do bloco `gh api`. Medido em 2026-11-11 antes da mudança: barram (exit 2) `gh pr create --help`, `gh pr create -h`, `gh help pr create`; já passam (exit 0) `gh pr edit --help`, `gh issue create --help`, `gh issue comment --help`.

*Emenda do leitor cego (bateria):* dez casos novos num bloco `echo "== (h1..h10) ajuda do gh =="` depois do caso (f1) e antes do `echo` do placar. Cada caso é só `roda` + `sai` (sem `tem`), então soma exatamente 1 ok: (h1) `gh pr create --help` → 0; (h2) `gh pr create -h` → 0; (h3) `gh pr edit --help` → 0; (h4) `gh issue create --help` → 0; (h5) `gh issue comment --help` → 0; (h6) `gh help pr create` → 0; (h7) `gh pr create --title t` → 2; (h8) `gh pr create --title t --help` → 2; (h9) `gh pr create --help --body "Closes #12"` → 2; (h10) `gh pr create -dh` → 2. *Emenda do D5:* (h11) `` gh help pr `gh issue close 12` `` → 2, e a função ganha a guarda `` !subcomandos.some((t) => /[$`]/.test(t)) && `` antes do resto da expressão. Redirecionamento e `-R` antes do grupo não são casos desta tarefa.

### 3. Versão PATCH e CHANGELOG [tipo: docs]
atende: D1, D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2
mutacao: n/a
  motivo: só versão e texto; comportamento medido pelas tarefas 1 e 2
pronto quando: com a `main` trazida para a branch (`git fetch origin && git merge origin/main`; conflito fora de versão e CHANGELOG: pare e relate), `node scripts/conferir-versao.cjs` sai 0 e os quatro lugares (dois `plugin.json`, selo do README com `vers%C3%A3o-X-` e `alt="versão X"`, topo do CHANGELOG `## X — 2026-11-11`) dizem a versão seguinte à da `main` na casa PATCH; o CHANGELOG descreve pelo comportamento as formas de "Pronto quando" aceitas e a ajuda do `gh` que passa — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A3 '^## ' CHANGELOG.md`

### 4. Revisão 1: "Pronto quando" na mesma linha e casos que faltavam [tipo: implementar]
atende: D1
arquivos: `scripts/fechar-issue.cjs`, `scripts/testa-fechar-issue.sh`
depende de: 3
busca:
- repo | grep -n "RE_PRONTO_QUANDO" scripts/fechar-issue.cjs | a regex da tarefa 1 usa \s+, que com /m atravessa linha
desfecho: estender
mutacao:
  arquivo: `scripts/fechar-issue.cjs`
  de: `#{2,3}[ \t]+Pronto quando`
  para: `#{2,3}\s+Pronto quando`
  bateria: `bash scripts/testa-fechar-issue.sh`
  fixture: `testa-fechar-issue.sh, caso (w)`
prova-na-base: verde — os casos (u), (v) e (w) nascem com esta tarefa; a bateria de antes passa e as três mutações (#{2}, sem o prefixo de lista, \s+) deixam (u), (v) e (w) vermelhos
pronto quando: com o corpo de Issue do gh falso, `### Pronto quando` (u) e `- **Pronto quando:** ...` (v) saem 0 e fecham, e `##` vazio com "Pronto quando" na linha seguinte (w) sai 2 sem fechar — provado por `bash scripts/testa-fechar-issue.sh` terminando em `54 ok, 0 falha(s)`
