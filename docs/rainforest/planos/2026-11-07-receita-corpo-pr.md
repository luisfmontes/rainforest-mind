# Plano: as recusas do corpo do PR dão uma receita só, a que passa

Design: docs/rainforest/design/2026-11-07-receita-corpo-pr.md

## O que não pode quebrar
- Toda recusa de hoje continua recusando (exit 2) exatamente os mesmos comandos; só o texto do stderr muda.
- `gh pr create --body-file "<caminho literal existente>"` sem palavra de fechamento continua saindo 0.
- `bash hooks/testa-gate-fechar-issue.sh` continua verde. Ela tem asserções sobre trechos das recusas (por exemplo "variável que o gate não resolve" no caso 350a), e esses trechos ficam.

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
  `Receita que passa:\n  1. grave o corpo com a ferramenta de escrita (Write) num caminho absoluto literal, por exemplo o scratchpad da sessão;\n  2. num comando que só tem o gh: gh pr create --title "<título>" --body-file "<caminho literal>".\nComando barrado não roda nenhuma parte: o arquivo que ele criaria não existe.\n`
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
- **Bateria nova** `hooks/testa-gate-receita-corpo.sh`, no molde do bloco `#407` de `hooks/testa-gate-fechar-issue.sh` (payload montado por `node -e` com `JSON.stringify`). Ela usa `SRC=$(cd "$(dirname "$0")/.." && pwd)`, um sandbox `mktemp -d` com `trap 'rm -rf' EXIT`, e um `gh` falso em `$SBP/bin/gh` (`#!/bin/sh` + `exit 1`) posto à frente do PATH. Cada caso guarda o exit do `node` e o stderr num arquivo e afirma por `grep -qF`. Os nomes dos casos começam com `(1) variável`, `(2) cwd incerto`, `(3) arquivo inexistente`, `(5) --body com crase`, `(6) editor interativo` e `(7) vizinho legítimo`; o número 4 fica para a tarefa 2. Termina com `ok: <n>   falhou: <m>` e sai 1 com falha.

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
- A recusa do arquivo ilegível chama `bloqueiaCorpo(<razão da tarefa 1> + " " + motivoDaLeitura(corpoDoPR.caminho, corpoDoPR.codigo))`.
- **Bateria:** o caso `(3) arquivo inexistente` ganha a asserção `não existe em <caminho>`; entram `(4) /tmp do Git Bash` e `(8) diretório` (`--body-file` apontando para o próprio sandbox, convertido com `cygpath -m`, e asserção `EISDIR`).

### 3. Versão PATCH, README e CHANGELOG [tipo: docs]
atende: D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 2
mutacao: n/a
  motivo: só versão e texto; o comportamento é medido pelas tarefas 1 e 2
pronto quando: com a `main` trazida para a branch (`git merge --ff-only` não serve se houver commit próprio; use `git merge origin/main`), `node scripts/conferir-versao.cjs` sai 0, os dois `plugin.json` e o selo do README (URL `vers%C3%A3o-X` e `alt` `versão X`) dizem a versão seguinte à da `main` na casa PATCH, e o CHANGELOG abre com essa versão descrevendo pelo comportamento o que a recusa do corpo passa a dizer (a receita e, no arquivo ilegível, o caminho e o motivo); o `README.en.md` fica intocado — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; sed -n 7p README.md; sed -n 13,16p CHANGELOG.md`
