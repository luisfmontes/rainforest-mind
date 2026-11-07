# Plano: as recusas do corpo do PR dão uma receita só, a que passa

Design: docs/rainforest/design/2026-11-07-receita-corpo-pr.md

## O que não pode quebrar
- Toda recusa de hoje continua recusando (exit 2) exatamente os mesmos comandos; só o texto do stderr muda.
- `gh pr create --body-file "<caminho literal existente>"` sem palavra de fechamento continua saindo 0.
- `bash hooks/testa-gate-fechar-issue.sh` continua verde sem ser editada. Ela afirma trechos das recusas: "variável que o gate não resolve" (350a), "substituição de comando" (caso i), "Grave o corpo antes"/"grave o corpo antes" (407-5, 407-6) e a ausência de "não consegui ler" quando um heredoc cria o arquivo (407-1, 407-4). O texto novo mantém os quatro: a receita abre com "Grave o corpo antes", e a recusa de heredoc ilegível da tarefa 2 não usa "não consegui ler".

## Tarefas

### 1. Receita única no fim das cinco recusas do corpo [tipo: implementar]
atende: D1
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-receita-corpo.sh`
depende de: nenhuma
busca:
- repo | rg -n "function bloqueia|Razão: --body-file|Razão: o corpo do PR" hooks/gate-fechar-issue.cjs | bloqueia() em :633 e as cinco recusas do corpo entre :1040 e :1080; estender
- livro | pulado: texto de mensagem do próprio gate, sem mecanismo a enxertar
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const receita = RECEITA_CORPO_PR;`
  para: `const receita = "";`
  bateria: `bash hooks/testa-gate-receita-corpo.sh`
  fixture: `testa-gate-receita-corpo.sh, casos "(1) variável", "(2) cwd incerto", "(3) arquivo inexistente", "(5) --body com crase", "(6) editor interativo"`
prova: `bash hooks/testa-gate-receita-corpo.sh`
pronto quando: com o payload real de `PreToolUse` (`{"cwd":...,"tool_name":"Bash","tool_input":{"command":...}}`) no stdin de `node hooks/gate-fechar-issue.cjs`, e um `gh` falso no PATH que sai 1, cada um destes comandos sai 2 e o stderr contém a linha `Receita que passa:` seguida do passo do Write e do comando `gh pr create ... --body-file "<caminho literal>"`: `gh pr create --title t --body-file "$X/pr.md"`, `cd $(pwd)/x && gh pr create --title t --body-file corpo.md`, `gh pr create --title t --body-file "C:/rfm-nao-existe-<aleatório>/pr.md"`, `gh pr create --title t --body "uso de \`x\`"` e `gh pr create --title t`; o stderr do caso da crase não contém mais `texto-plano`; o vizinho legítimo, `gh pr create --title t --body-file "<arquivo literal existente, sem palavra de fechamento>"`, sai 0 — provado por `bash hooks/testa-gate-receita-corpo.sh` saindo 0 com uma linha `ok` por caso e por asserção, nenhum caso afirmando sobre o texto do fonte

Forma prescrita:
- Constante `RECEITA_CORPO_PR` no topo do arquivo, junto das outras constantes, com este texto (as quebras de linha são `\n`):
  `Receita que passa:\n  1. Grave o corpo antes, com a ferramenta de escrita (Write), num caminho absoluto literal do Windows, por exemplo o scratchpad da sessão;\n  2. num comando que só tem o gh: gh pr create --title "<título>" --body-file "<caminho literal>" (ou gh pr edit <n> --body-file "<caminho literal>").\nComando barrado não roda nenhuma parte: o arquivo que ele criaria não existe.\n`
- Função nova, logo depois de `bloqueia`:
  ```
  function bloqueiaCorpo(razao) {
    const receita = RECEITA_CORPO_PR;
    bloqueia(`BLOQUEADO pelo gate de fechamento de Issue do rainforest-mind.\n\nRazão: ${razao}\n\n${receita}`);
  }
  ```
- As cinco recusas dentro de `if (!corpoDoPR.legivel)` passam a chamar `bloqueiaCorpo(<razão>)`. A razão é o texto que vem hoje depois de `Razão: `, mais a explicação que cada uma já tem, menos a sugestão de saída própria. Ficam assim:
  - variável: `--body-file contém uma variável que o gate não resolve ($, crase). O gate lê o arquivo antes de o 'gh' rodar e não expande variável.`
  - cwd incerto: `--body-file usa caminho relativo, e o diretório efetivo deste comando não pôde ser determinado com segurança (cd/pushd dinâmico ou não resolvível antes do 'gh').`
  - arquivo ilegível: `não consegui ler o arquivo de corpo do PR — o gate o lê ANTES de o comando rodar, e nada neste comando o cria por heredoc.` (a tarefa 2 acrescenta o motivo)
  - crase: `o corpo do PR contém substituição de comando ($(...) ou backticks), não consegui ler com segurança.` (sem a sugestão `--body "texto-plano"`)
  - editor: `o corpo do PR vem de editor interativo (sem --body ou --body-file); se ele citar 'closes #N', a checagem não consegue ler.`
- **Bateria nova** `hooks/testa-gate-receita-corpo.sh`, no molde do bloco `#407` de `hooks/testa-gate-fechar-issue.sh`. Cabeçalho: `set -u`, `SRC="$(cd "$(dirname "$0")/.." && pwd)"`, `SBP="$(mktemp -d)"`, `trap 'rm -rf "$SBP"' EXIT`, `SBP_WIN="$(cygpath -m "$SBP")"`, e os contadores e helpers copiados das linhas 15-17 da bateria antiga (`ok=0; falhou=0`, `test_ok`, `test_fail`). Um `gh` falso em `$SBP/bin/gh` (`#!/bin/sh` + `exit 1`, `chmod +x`) fica à frente do PATH, para que nenhum caso consulte o GitHub real. Payload por `node -e 'const [cwd,cmd]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd,tool_name:"Bash",tool_input:{command:cmd}}))' "$SBP_WIN" "<comando>"`; cada caso roda `printf '%s' "$PAYLOAD" | PATH="$SBP/bin:$PATH" node "$SRC/hooks/gate-fechar-issue.cjs" >/dev/null 2>"$SBP/err"`, guarda o exit e afirma por `grep -qF` no `$SBP/err`. Caminhos: `(1)` usa o texto literal `"$X/pr.md"` dentro do comando (aspas simples no bash, para o `$X` chegar cru ao gate); `(3)` usa `C:/rfm-nao-existe-$$/pr.md`; `(7)` cria `$SBP/corpo-ok.md` com `printf 'corpo sem palavra de fechamento\n'` e passa `$SBP_WIN/corpo-ok.md`. Na tarefa 1, o caso `(3)` afirma só exit 2 e `Receita que passa:`. Os nomes dos casos começam com `(1) variável`, `(2) cwd incerto`, `(3) arquivo inexistente`, `(5) --body com crase`, `(6) editor interativo` e `(7) vizinho legítimo`; o número 4 fica para a tarefa 2. Termina com `ok: <n>   falhou: <m>` e sai 1 com falha.
- `pronto quando` inclui também `bash hooks/testa-gate-fechar-issue.sh` saindo 0, sem edição.

### 2. A recusa de arquivo ilegível diz o caminho e o motivo [tipo: implementar]
atende: D2
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-receita-corpo.sh`
depende de: 1
busca:
- repo | rg -n "readFileSync\(caminhoResolvido" hooks/gate-fechar-issue.cjs | o catch de extrairCorpoDoPR descarta o erro; estender
- livro | pulado: texto de mensagem do próprio gate
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `if (codigo === "ENOENT") return`
  para: `if (false) return`
  bateria: `bash hooks/testa-gate-receita-corpo.sh`
  fixture: `testa-gate-receita-corpo.sh, caso "(3) arquivo inexistente"`
prova: `bash hooks/testa-gate-receita-corpo.sh`
pronto quando: com o mesmo payload real, `gh pr create --title t --body-file "C:/rfm-nao-existe-<aleatório>/pr.md"` sai 2 e o stderr contém `não existe em C:/rfm-nao-existe-<aleatório>/pr.md`; `gh pr create --title t --body-file /tmp/rfm-<aleatório>.md` sai 2 e o stderr contém `/tmp do Git Bash`; `--body-file "<diretório existente>"` sai 2 e o stderr contém `EISDIR`; os três ainda trazem `Receita que passa:` — provado por `bash hooks/testa-gate-receita-corpo.sh` saindo 0, nenhum caso afirmando sobre o texto do fonte

Forma prescrita:
- No `catch` do `readFileSync(caminhoResolvido, "utf8")` de `extrairCorpoDoPR`, o retorno ganha `caminho: arquivo` (o valor depois do `normalizarMsys`, como o usuário escreveu) e `codigo: e.code`: `catch (e) { return { tipo: "arquivo", conteudo: null, legivel: false, caminho: arquivo, codigo: e && e.code }; }`.
- Função nova, logo depois de `bloqueiaCorpo`:
  ```
  function motivoDaLeitura(caminho, codigo) {
    if (/^\/(?![A-Za-z](\/|$))/.test(caminho)) return `${caminho} é caminho do Git Bash: o gate roda em node no Windows e não enxerga o /tmp do Git Bash; use caminho absoluto do Windows.`;
    if (codigo === "ENOENT") return `o arquivo não existe em ${caminho}.`;
    return `erro ${codigo || "desconhecido"} ao ler ${caminho}.`;
  }
  ```
- O retorno de heredoc ilegível de `extrairCorpoDoPR` (`if (corpoCriado !== null) return { tipo: "arquivo", ... legivel: corpoCriado.legivel }`) ganha `heredoc: true`. Na cadeia de recusas, logo antes do ramo do arquivo ilegível, entra `else if (corpoDoPR.tipo === "arquivo" && corpoDoPR.heredoc)` com `bloqueiaCorpo("o heredoc deste comando, que cria o --body-file, tem $ ou crase com delimitador sem aspas, e o gate não lê o que a substituição produz.")`. Ele não chama `motivoDaLeitura` e não diz "não consegui ler".
- A recusa do arquivo ilegível (sem heredoc) chama `bloqueiaCorpo(<razão da tarefa 1> + " " + motivoDaLeitura(corpoDoPR.caminho, corpoDoPR.codigo))`.
- A mutação troca só o prefixo `if (codigo === "ENOENT") return` por `if (false) return`; o resto da linha fica.
- *Emenda da revisão 1:* o retorno do `catch` leva também `resolvido: caminhoResolvido`, e `motivoDaLeitura(caminho, resolvido, codigo)` cita `<caminho> (resolvido para <resolvido com />)` quando os dois diferem (relativo), como o D2 pede ("o caminho resolvido"); `--body-file -` diz que lê do stdin; `--body-file` vazio diz que veio vazio; a regex do Git Bash exclui `//` (UNC). A bateria ganha `(10) relativo`, `(11) UNC` e `(12) stdin`.
- **Bateria:** o caso `(3) arquivo inexistente` ganha a asserção `não existe em C:/rfm-nao-existe-$$/pr.md`; entram `(4) /tmp do Git Bash` (`--body-file /tmp/rfm-$$.md`, asserção `/tmp do Git Bash`), `(8) diretório` (`--body-file "$SBP_WIN"`, asserção `EISDIR`) e `(9) heredoc ilegível` (comando de duas linhas `cat > x.md <<EOF` / `Closes #$N` / `EOF` / `gh pr create --title t --body-file x.md`, montado com `printf`, asserção `heredoc deste comando` e ausência de `não consegui ler`).
- `pronto quando` inclui também `bash hooks/testa-gate-fechar-issue.sh` saindo 0, sem edição.

### 3. Versão PATCH, README e CHANGELOG [tipo: docs]
atende: D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 2
mutacao: n/a
  motivo: só versão e texto; o comportamento é medido pelas tarefas 1 e 2
pronto quando: com a `main` trazida para a branch (`git merge --ff-only` não serve se houver commit próprio; use `git merge origin/main`), `node scripts/conferir-versao.cjs` sai 0, os dois `plugin.json` e o selo do README (URL `vers%C3%A3o-X` e `alt` `versão X`) dizem a versão seguinte à da `main` na casa PATCH, e o CHANGELOG abre com essa versão descrevendo pelo comportamento o que a recusa do corpo passa a dizer (a receita e, no arquivo ilegível, o caminho e o motivo); o `README.en.md` fica intocado — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A2 '^## ' CHANGELOG.md`

Forma: a versão vem de `git fetch origin && MSYS_NO_PATHCONV=1 git show origin/main:.claude-plugin/plugin.json`, PATCH + 1 sobre ela. Conflito do `git merge origin/main` em `CHANGELOG.md`, `README.md` ou `plugin.json` se resolve ficando com o lado da `main` e aplicando o bump por cima. Entrada do CHANGELOG no formato das vizinhas: `## X.Y.Z — 2026-11-07`, linha em branco, `- **<título curto>.** <descrição>`.
