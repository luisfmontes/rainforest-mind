# Plano: gate-worktree fecha para subagente quando o git não responde num repositório

Design: docs/rainforest/design/2026-11-09-gate-git-quebrado.md

## O que não pode quebrar
- Todo caso de `hooks/testa-gate-worktree.sh` e de `scripts/testa-conferir-mutacao.sh` sai igual a hoje.
- Com o git funcionando, nenhuma decisão do gate muda, salvo o falso positivo de `/worktrees/` no caminho.
- A janela principal nunca é barrada por git sem resposta.
- Pasta sem `.git` em nenhum ancestral segue livre, com ou sem git.

## Tarefas

### 1. `ehWorktree` pelo `--git-common-dir` [tipo: implementar]
atende: D5
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: nenhuma
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `ehWorktree: resolverGit(dir, gitDir) !== resolverGit(dir, comum),`
  para: `ehWorktree: gitDir.replace(/\\/g, "/").includes("/worktrees/"),`
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: `testa-gate-worktree.sh, caso "checkout principal sob pasta worktrees, a partir de subpasta, barra"`
prova: `D=$(mktemp -d) && git init -q "$D/worktrees/proj" && mkdir -p "$D/worktrees/proj/sub" && W=$(cygpath -m "$D/worktrees/proj/sub") && printf '{"agent_id":"a","agent_type":"x","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/f.txt"}}' "$W" "$W" | env RFM_ROOT="$(mktemp -d)" node hooks/gate-worktree.cjs > /dev/null 2>&1; test $? -eq 2`
pronto quando: com um checkout principal real em `<tmp>/worktrees/proj` e um payload `PreToolUse` de subagente (`agent_id`) com `Write` em `<tmp>/worktrees/proj/sub/f.txt` e `cwd` na subpasta, o hook sai 2; o mesmo `Write` a partir de subpasta de um worktree linkado sai 0 — provado por `bash hooks/testa-gate-worktree.sh` saindo 0 com os dois casos listados pelo nome, e pela mutação acima deixando vermelho o primeiro

Forma prescrita:
- Em `hooks/gate-worktree.cjs`, `const { caminhoReal, acharGitAcima } = require(path.join(__dirname, "lib", "caminho-real.cjs"));` junto dos outros `require` (o `acharGitAcima` chega na tarefa 2; nesta tarefa só `caminhoReal`).
- `function resolverGit(dir, p) { return caminhoReal(path.resolve(dir, p)).replace(/\\/g, "/"); }` logo antes de `estadoDoRepo`.
- `estadoDoRepo`: `const saida = git(dir, ["rev-parse", "--git-dir", "--git-common-dir"]);` no lugar da leitura do `--git-dir`, e `const [gitDir, comum] = saida.split(/\r?\n/);` depois do ramo de `null`; a linha do `ehWorktree` é a do `de:` acima.
- **Bateria:** seção nova em `hooks/testa-gate-worktree.sh`, antes da linha do `== resultado`, `echo "== git sem resposta e pasta chamada worktrees (#671) =="`. Repositório real em `$RAIZ/worktrees/proj` com `sub/`, o payload pelo helper `j` já existente (`j Write file_path "<caminho>" "<cwd>"`). Casos: `checkout principal sob pasta worktrees, a partir de subpasta, barra` (2) e `subpasta de worktree linkado passa` (0, em `$WT/sub`, criada pela seção).

### 2. Git sem resposta com `.git` acima fecha o gate para subagente [tipo: implementar]
atende: D1, D2, D4, D6
arquivos: `hooks/gate-worktree.cjs`, `hooks/lib/caminho-real.cjs`, `scripts/conferir-mutacao.cjs`, `hooks/testa-gate-worktree.sh`, `hooks/testa-caminho-real.sh`
depende de: 1
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (saida === null) return estadoSemGit(dir);`
  para: `if (saida === null) return null;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: `testa-gate-worktree.sh, caso "git sem resposta no checkout principal barra subagente"`
prova: `D=$(mktemp -d) && git init -q "$D/r" && W=$(cygpath -m "$D/r") && V=$(mktemp -d) && N=$(command -v node) && printf '{"agent_id":"a","agent_type":"x","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/f.txt"}}' "$W" "$W" | env RFM_ROOT="$(mktemp -d)" PATH="$V" "$N" hooks/gate-worktree.cjs > /dev/null 2>&1; test $? -eq 2`
pronto quando: sem `git` no PATH do processo (PATH numa pasta vazia, `node` por caminho absoluto), um `Write` de subagente no checkout principal sai 2 com `git não respondeu num repositório` no stderr; o mesmo `Write` num worktree linkado (`.git` arquivo) sai 0; numa pasta sem `.git` em ancestral nenhum sai 0; e `scripts/conferir-mutacao.cjs` continua distinguindo "fora de repo" de "git que falha" no modo no lugar — provado por `bash hooks/testa-gate-worktree.sh`, `bash hooks/testa-caminho-real.sh` e `bash scripts/testa-conferir-mutacao.sh` saindo 0, e pela mutação acima deixando vermelho o primeiro

Forma prescrita:
- `hooks/lib/caminho-real.cjs`: `function acharGitAcima(dir)` sobe de `path.resolve(dir)` até a raiz; na primeira pasta com `fs.existsSync(path.join(d, '.git'))`, devolve `{ dir: d, ehArquivo: !statSync(...).isDirectory() }` (`statSync` em `try`; falhou, `ehArquivo: false`); na raiz sem achar, `null`. Exportada junto de `caminhoReal`, e o comentário do topo do arquivo cita o uso novo.
- `scripts/conferir-mutacao.cjs`: a função `temGitAcima` sai, e a chamada passa a `Boolean(acharGitAcima(<mesmo argumento>))`, com o `require` em `hooks/lib/caminho-real.cjs`.
- `hooks/gate-worktree.cjs`: `const AVISOU_SEM_GIT = new Set();` e `function estadoSemGit(dir)` antes de `estadoDoRepo`: `const achado = acharGitAcima(dir); if (!achado) return null;`; `const raiz = achado.dir.replace(/\\/g, "/");`; se `raiz` ainda não está no `Set`, grava e `process.stderr.write(\`[gate-worktree] git não respondeu num repositório (${raiz}): gate fechado para escrita de subagente fora de worktree linkado.\n\`)`; devolve `{ toplevel: raiz, ehWorktree: achado.ehArquivo, gitQuebrado: true }`.
- `estadoDoRepo`: o bloco `if (gitDir === null) { ... }` inteiro dá lugar à linha do `de:` acima. O comentário da função é reescrito: diz os três casos (fora de repositório livre, git sem resposta com `.git` acima fechado para subagente e livre para a janela principal, worktree por `--git-common-dir`) e mantém a razão de avisar em stderr.
- **Bateria:** na mesma seção, helper `gate_sem_git` (nome, exit esperado, json, [texto esperado na saída]): `printf '%s' "$json" | env PATH="$VAZIA" "$NODE_ABS" "$GATE"`, com `VAZIA` uma pasta de `mktemp -d` e `NODE_ABS=$(command -v node)`. Casos: `git sem resposta no checkout principal barra subagente` (2, com `git não respondeu num repositório`), `git sem resposta em worktree linkado passa` (0), `git sem resposta fora de repositorio passa` (0, em `$FORA`).

### 3. A janela principal segue livre com o git sem resposta [tipo: implementar]
atende: D3
arquivos: `hooks/gate-worktree.cjs`, `hooks/testa-gate-worktree.sh`
depende de: 2
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `if (!daqui || daqui.gitQuebrado) return; // fora de repo git, ou git sem resposta: nao ha HEAD para medir`
  para: `if (!daqui) return;`
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: `testa-gate-worktree.sh, caso "git sem resposta nao barra a janela principal na sessao co-locada"`
prova-na-base: verde — na base o gate já libera a janela principal com o git sem resposta; a tarefa impede que a tarefa 2 mude isso
pronto quando: com outra sessão registrada no mesmo diretório e sem `git` no PATH, o payload da janela principal (sem `agent_id`) com `git checkout -b x` em `$R` sai 0 — provado por `bash hooks/testa-gate-worktree.sh` saindo 0 com o caso listado pelo nome, e pela mutação acima deixando esse caso vermelho

Forma prescrita:
- `gateDeSessaoColocada`: a linha `if (!daqui) return; // fora de repo git: nao ha HEAD para mover` vira a do `de:` acima.
- **Bateria:** logo depois do bloco `sessoes.json ausente`/`ilegivel` (depois de `mv "$DADOS/sessoes.bak" "$DADOS/sessoes.json"`), o caso do `fixture:`, com `RFM_ROOT="$DADOSW"` e o `$(p "git checkout -b x" "$R")`, rodado como no `gate_sem_git`. `VAZIA` e `NODE_ABS` são definidos no topo do arquivo, junto de `FORA`.

### 4. Documentação, versão 2.10.1 e CHANGELOG [tipo: docs]
atende: D7
arquivos: `docs/travas-mecanicas.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 3
mutacao: n/a
  motivo: texto e versão; o comportamento é medido pelas tarefas 1 a 3
Forma: a linha do `gate-worktree.cjs` em `docs/travas-mecanicas.md` ganha, no fim da descrição, a frase: "Git sem resposta dentro de repositório fecha para subagente fora de worktree linkado, com aviso em stderr; a janela principal segue livre (#671)." Selo do README (`vers%C3%A3o-2.10.1` e `versão 2.10.1`), `README.en.md` intocado, os dois `plugin.json`. CHANGELOG `## 2.10.1 — 2026-11-09` acima da 2.10.0, item `- **O gate-worktree fecha para subagente quando o git não responde num repositório.** <o que faz e o que segue livre>`, e a menção ao falso positivo de `/worktrees/` no caminho.
pronto quando: com o repositório deste worktree, `node scripts/conferir-versao.cjs` sai 0, os dois `plugin.json` dizem `"version": "2.10.1"`, o selo do README diz `versão 2.10.1`, e o texto de `docs/travas-mecanicas.md` e do CHANGELOG descreve os mesmos três casos do D1 a D3 (subagente em principal barra, worktree linkado passa, janela principal livre) — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n "2.10.1" README.md CHANGELOG.md; grep -n "#671" docs/travas-mecanicas.md`

## Emendas do leitor cego

- Tarefa 1: o teste do ramo vira `if (saida === null) {` com o bloco antigo intacto, e só depois `const [gitDir, comum] = saida.split(...)`.
- Tarefa 2: `gate_sem_git`, `VAZIA` e `NODE_ABS` ficam no topo da bateria, junto de `FORA`, com quinto parâmetro opcional de `RFM_ROOT`; a tarefa 3 passa `"$DADOSW"`, senão o gate sai antes de medir a sessão co-locada. `estadoSemGit` devolve `null` para diretório inexistente (caso: `cwd inexistente dentro de repositorio nao vira git quebrado`, com o `$G13` da seção #530). O aviso é neutro (D4). O caso "fora de repositório" pula, com mensagem, se a pasta temporária tiver `.git` em ancestral. `acharGitAcima` ganha casos em `hooks/testa-caminho-real.sh` (`.git` pasta, `.git` arquivo, nenhum).
- Tarefa 1: caso `checkout principal por nome curto, subpasta, barra` (`cygpath -d`; pulado no volume sem 8.3). É o lado perigoso: `--git-dir` longo contra `--git-common-dir` relativo sobre `dir` curto.
- Tarefa 3: o `if (!estado) continue;` do laço também ignora `gitQuebrado`, e o comentário de `gateDeSessaoColocada` passa a dizer que o princípio de liberar vale para a janela principal.
- Tarefa 4: a frase entra no fim da segunda coluna da linha do `gate-worktree.cjs`.
