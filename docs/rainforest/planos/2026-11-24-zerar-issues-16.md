# Plano: Rodada 16 — gate-pergunta-memoria, integrar-tarefa e mensagem do gate de publicação

Design: docs/rainforest/design/2026-11-24-zerar-issues-16.md

## O que não pode quebrar

- Todo caso existente de `scripts/testa-integrar-tarefa.sh`, `hooks/testa-gate-pergunta-memoria.cjs` e `hooks/testa-gate-publicacao-destino.sh` mantém o exit esperado. Nenhum caso é apagado.
- `repositoriosDoGitHub(gitTop)` continua devolvendo a lista de `dono/repo` (array de strings): `declaradaPrivada` e `bloqueia` contam `.length`.
- O P1 de `hooks/testa-gate-pergunta-memoria.cjs` (pergunta em prosa que a memória responde) continua exit 2.

## Tarefas

As três primeiras são independentes (arquivos distintos). A 4 fecha a versão.

### 1. `integrar-tarefa`: `maxBuffer` e erro na recusa [tipo: implementar]
atende: D1
arquivos: `scripts/integrar-tarefa.cjs`, `scripts/testa-integrar-tarefa.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz scripts/lib | nada equivalente: não há helper comum de git com buffer grande; estendo git() de scripts/integrar-tarefa.cjs:68
desfecho: estender
O que fazer:
- Em `scripts/integrar-tarefa.cjs`, antes de `function git(`, a constante `const MAX_BUFFER_GIT = 1024 * 1024 * 1024;` com comentário citando a #731 (padrão do Node é 1 MiB; diff com arquivo grande dava `ENOBUFS`). O `spawnSync` de `git()` passa a ser `spawnSync(GIT, args, { cwd, encoding: 'utf8', stdio: 'pipe', maxBuffer: MAX_BUFFER_GIT })`.
- Em `recusar`, depois das linhas de `stdout`/`stderr`: `if (res && res.error) process.stderr.write(\`erro do processo: ${res.error.code || ''} ${res.error.message}\n\`);`.
- Bateria: seção nova `echo "== #731: entrega com arquivo de mais de 1 MiB integra =="` logo depois da seção "agente com 2 commits traz os dois". `caixa_nova`, `abrir_fluxo`, `despachar grande`; acrescenta a `$WT/src/alfa.cjs` uma linha de comentário `// ` seguida de `head -c 1200000 /dev/urandom | base64 -w0` (cerca de 1,6 MB); `agente_commita "alfa: arquivo grande"`; `integrar 1`; afirma `igual "integrar tarefa 1 sai 0" "0" "$RC"`, `igual "JSON diz aceito" "aceito" ...` e `igual "1 commit novo na branch" "1" ...`.
mutacao:
  arquivo: `scripts/integrar-tarefa.cjs`
  de: `stdio: 'pipe', maxBuffer: MAX_BUFFER_GIT })`
  para: `stdio: 'pipe' })`
  bateria: `bash scripts/testa-integrar-tarefa.sh`
  fixture: testa-integrar-tarefa.sh, seção "#731: entrega com arquivo de mais de 1 MiB integra", caso "integrar tarefa 1 sai 0"
prova-na-base: verde — o caso só existe na bateria que esta tarefa escreve; rodado contra o fonte da base, ele sai 2 com `RECUSADO: diff` (o mesmo da Issue)
pronto quando: com um commit de agente que traz arquivo de mais de 1 MiB no escopo da tarefa (a entrada da Issue: o `.glb` de 2 MB), provado por `bash scripts/testa-integrar-tarefa.sh` com `ok` nos três casos da seção #731 e placar de 0 falhas.

### 2. `gate-pergunta-memoria`: nome de objeto sai da pergunta [tipo: implementar]
atende: D2
arquivos: `hooks/gate-pergunta-memoria.cjs`, `hooks/testa-gate-pergunta-memoria.cjs`
depende de: nenhuma
busca:
- catalogo | termosDe em hooks/gate-pergunta-memoria.cjs:59 | estendo antes de termosDe; nenhuma lib tira código inline de texto
desfecho: estender
O que fazer:
- Função `function semNomesDeObjeto(texto)` logo depois de `termosDe`, com comentário citando a #730 e a D2 emendada: parte por espaço em branco, descarta a palavra que casa `RE_FORMA_DE_CAMINHO = /[\p{L}\p{N}]\/[\p{L}\p{N}]/u` (caminho, branch, com ou sem crase em volta) e junta com espaço. Emenda de 2026-11-24 (executar): código inline e kebab sem barra ficam, porque tirá-los derrubava o P1.
- Em `main`, a chamada passa a ser `const m = melhorMemoria(termosDe(semNomesDeObjeto(p.texto)), lista);`. A extração da memória (`memorias`) não muda.
- Bateria, dois casos novos antes do laço de limpeza, com `cenarioMemoria({ texto, name: 'project-abacate-modelo-padrao', description: 'design do modelo padrao do abacate e quem assumiu a implementacao' })`:
  - P25: `Q2: Posso apagar o worktree e a branch antigos \`refactor/abacate-modelo-padrao\`? Recomendo apagar.` → exit 0.
  - P26: o mesmo sem as crases (`refactor/abacate-modelo-padrao` solto) → exit 0.
  - O cabeçalho da bateria ganha as duas linhas.
mutacao:
  arquivo: `hooks/gate-pergunta-memoria.cjs`
  de: `termosDe(semNomesDeObjeto(p.texto))`
  para: `termosDe(p.texto)`
  bateria: `node hooks/testa-gate-pergunta-memoria.cjs`
  fixture: testa-gate-pergunta-memoria.cjs, caso P25
prova-na-base: verde — P25 e P26 só existem na bateria que esta tarefa escreve; contra o hook da base saem 2 (abacate, modelo, padrao: 3 termos)
pronto quando: com o payload real de `Stop` e a pergunta da #730 (branch citada na pergunta, memória do projeto que só compartilha os termos da branch), provado por `node hooks/testa-gate-pergunta-memoria.cjs` com `ok` em P25, P26 e P1, e `ok: N   falhou: 0`.

### 3. `gate-publicacao-destino`: remoto pela URL de push, e a mensagem o nomeia [tipo: implementar]
atende: D3
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
busca:
- catalogo | repositoriosDoGitHub em hooks/gate-publicacao-destino.cjs:145 | estendo; remotoDeDestino responde outra pergunta (para onde esta branch publica) e não serve
desfecho: estender
O que fazer:
- `function remotosDoGitHub(gitTop)` substitui o corpo de `repositoriosDoGitHub`: para cada remoto, lê `git(gitTop, ["remote", "get-url", "--push", "--all", nome])`, parte por linha, e cada URL que casa a regex de hoje entra num array de `{ ownerRepo, remotos: [nome...] }` sem repetir `ownerRepo`. `repositoriosDoGitHub(gitTop)` passa a ser `remotosDoGitHub(gitTop).map((a) => a.ownerRepo)`. O docblock ganha um parágrafo da #723 (URL de push: remoto com push desligado não está ao alcance de um push).
- `calcularVisibilidade` percorre `remotosDoGitHub(gitTop)` inteiro, sem o `return "publica"` antecipado de hoje (`hooks/gate-publicacao-destino.cjs:167`): o `gh` passa a ser consultado uma vez por repositório mesmo depois de achar um público (só roda quando já houve achado). Para cada repositório que sai `publica`, acrescenta uma entrada `{ nome, ownerRepo }` **por remoto** (`remotos` com dois nomes para o mesmo `dono/repo` dão duas entradas) a uma lista, guardada em `publicosMemorizados` (um `Map` do módulo, chave `gitTop`). Depois do laço: lista não vazia devolve `"publica"`; senão, o veredito de hoje (`"desconhecida"` se algum saiu desconhecido, `"privada"` se todos privados).
- Em `mensagemBloqueio`, com `visibilidade === "publica"` e lista não vazia em `publicosMemorizados.get(gitTop)`, a linha vira `Repositório: visibilidade pública, apurada por 'gh repo view': o remoto '<nome>' (<dono/repo>) é público. `; com mais de uma entrada, cada `o remoto '<nome>' (<dono/repo>) é público` separado por `; `. Emenda do executar: o começo `visibilidade pública` fica, porque o caso (b) da bateria procura `pública`. `mensagemBloqueio` recebe `gitTop` como sexto parâmetro; a única chamada é a de `bloqueia` (`process.stderr.write(mensagemBloqueio(..., repositoriosDoGitHub(gitTop).length > 0, gitTop))`). Sem lista, a linha de hoje.
- `mensagemBloqueioGh` (o caminho de `gh issue|pr|api|...`) não muda: ali o destino é o repositório do comando (`--repo`, URL, `GH_REPO` ou cwd), e a #723 mediu só a escrita de arquivo.
- Parágrafo novo no docblock de `repositoriosDoGitHub`: "#723: conta a URL de PUSH (`get-url --push --all`). Remoto com push desligado (`no_push`) ou apontando para fora do GitHub não está ao alcance de um push, e não conta; o de fetch sozinho não publica."
- Bateria: o dublê `gh` lê `GH_RESPONSES` (JSON `{ "<dono/repo>": "<resposta>" }`) e usa a entrada de `process.argv[4]` quando existe, senão `GH_RESPONSE`. Na chamada, `GH_RESPONSES='{"test/priv723":"{\"isPrivate\":true}","test/pub723":"{\"isPrivate\":false}"}'` (aspas simples no shell). O repositório segue o molde do teste (b), `testa-gate-publicacao-destino.sh:444-449` (`git init`, commit, `remote add`, `PAY_CWD`, `pay Write`). Seção nova `echo "== (#723) remoto público nomeado e push desligado =="` antes de `== resultado:`, num repositório com `origin` `https://github.com/test/priv723.git` (privado) e `upstream` `https://github.com/test/pub723.git` (público), escrevendo um arquivo com `contato: $JID_REAL`:
  - `723 mensagem nomeia o upstream`: exit 2 e o stderr contém `o remoto 'upstream' (test/pub723) é público`.
  - `723 upstream com push no_push passa`: depois de `git remote set-url --push upstream no_push`, exit 0.
  - `723 upstream com push para o público barra`: depois de `git remote set-url --push upstream https://github.com/test/pub723.git`, exit 2.
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `["remote", "get-url", "--push", "--all", nome]`
  para: `["remote", "get-url", "--all", nome]`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: testa-gate-publicacao-destino.sh, seção "(#723) remoto público nomeado e push desligado", caso "723 upstream com push no_push passa"
prova-na-base: verde — os casos 723 só existem na bateria que esta tarefa escreve, com o dublê `GH_RESPONSES`; contra o gate da base o `no_push` sai 2 e a mensagem diz só "visibilidade pública"
pronto quando: com o payload real de `PreToolUse` de `Write` no fork da #723 (`origin` privado, `upstream` público), provado por `bash hooks/testa-gate-publicacao-destino.sh` com `ok` nos três casos `723` e `== resultado: N ok, 0 falha(s) ==`.

### 4. Versão 2.17.2 [tipo: docs]
atende: D4, D5
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3
O que fazer:
- `version` `2.17.2` nas duas `plugin.json` e no selo do `README.md`.
- `## 2.17.2 — 2026-11-24` no topo do `CHANGELOG.md`, com um item por Issue (#731, #730, #723), do ponto de vista de quem usa.
- D4: o corpo do PR (`docs/rainforest/planos/2026-11-24-zerar-issues-16.pr.md`) leva a seção `## Fora desta rodada` com #722 e #724 e o porquê da D4 (furo de cobertura achado em revisão, mecanismo novo e revisão de segurança própria).
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
prova: `grep -q '"version": "2.17.2"' .claude-plugin/plugin.json`
pronto quando: com o plugin instalado pela versão nova, provado por `grep -c '"version": "2.17.2"' .claude-plugin/plugin.json .codex-plugin/plugin.json` imprimindo 1 em cada, e `grep -c '^## 2.17.2' CHANGELOG.md` imprimindo 1.
