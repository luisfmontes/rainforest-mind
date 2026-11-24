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
- grep | maxBuffer em scripts/*.cjs | uso a mesma forma de opção do spawnSync; não há helper comum de git com buffer grande
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
prova-na-base: vermelho — na base, o caso novo sai 2 com `RECUSADO: diff` (o mesmo da Issue)
pronto quando: com um commit de agente que traz arquivo de mais de 1 MiB no escopo da tarefa (a entrada da Issue: o `.glb` de 2 MB), provado por `bash scripts/testa-integrar-tarefa.sh` com `ok` nos três casos da seção #731 e placar de 0 falhas.

### 2. `gate-pergunta-memoria`: nome de objeto sai da pergunta [tipo: implementar]
atende: D2
arquivos: `hooks/gate-pergunta-memoria.cjs`, `hooks/testa-gate-pergunta-memoria.cjs`
depende de: nenhuma
busca:
- catalogo | termosDe em hooks/gate-pergunta-memoria.cjs:59 | estendo antes de termosDe; nenhuma lib tira código inline de texto
desfecho: estender
O que fazer:
- Função `function semNomesDeObjeto(texto)` logo depois de `termosDe`, com comentário citando a #730 e a D2: troca cada `` `...` `` (sem quebra de linha dentro) por espaço; depois parte por espaço em branco e descarta a palavra que casa `/[\p{L}\p{N}]\/[\p{L}\p{N}]/u` (caminho, branch) ou `/[\p{L}\p{N}]-[\p{L}\p{N}]+-[\p{L}\p{N}]/u` (dois hífens ou mais); junta com espaço.
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
prova-na-base: vermelho — na base, P25 e P26 saem 2 (abacate, modelo, padrao: 3 termos)
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
- `calcularVisibilidade` percorre `remotosDoGitHub` e guarda em `publicosMemorizados` (um `Map` do módulo, chave `gitTop`) a lista `{ nome, ownerRepo }` de cada repositório que saiu `publica`; continua devolvendo `"publica"` quando há ao menos um, e a ordem de veredito de hoje para o resto.
- Em `mensagemBloqueio`, com `visibilidade === "publica"` e lista não vazia em `publicosMemorizados.get(gitTop)`, a linha vira `Repositório: o remoto '<nome>' (<dono/repo>) é público, apurado por 'gh repo view'. ` (vários: separados por `; `). `mensagemBloqueio` recebe `gitTop` como sexto parâmetro; sem lista, a linha de hoje.
- Bateria: o dublê `gh` lê `GH_RESPONSES` (JSON `{ "<dono/repo>": "<resposta>" }`) e usa a entrada de `process.argv[4]` quando existe, senão `GH_RESPONSE`. Seção nova `echo "== (#723) remoto público nomeado e push desligado =="` antes de `== resultado:`, num repositório com `origin` `https://github.com/test/priv723.git` (privado) e `upstream` `https://github.com/test/pub723.git` (público), escrevendo um arquivo com `contato: $JID_REAL`:
  - `723 mensagem nomeia o upstream`: exit 2 e o stderr contém `o remoto 'upstream' (test/pub723) é público`.
  - `723 upstream com push no_push passa`: depois de `git remote set-url --push upstream no_push`, exit 0.
  - `723 upstream com push para o público barra`: depois de `git remote set-url --push upstream https://github.com/test/pub723.git`, exit 2.
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `["remote", "get-url", "--push", "--all", nome]`
  para: `["remote", "get-url", "--all", nome]`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: testa-gate-publicacao-destino.sh, seção "(#723) remoto público nomeado e push desligado", caso "723 upstream com push no_push passa"
prova-na-base: vermelho — na base, o caso `723 upstream com push no_push passa` sai 2 e a mensagem diz só "visibilidade pública"
pronto quando: com o payload real de `PreToolUse` de `Write` no fork da #723 (`origin` privado, `upstream` público), provado por `bash hooks/testa-gate-publicacao-destino.sh` com `ok` nos três casos `723` e `== resultado: N ok, 0 falha(s) ==`.

### 4. Versão 2.17.2 [tipo: docs]
atende: D5
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3
O que fazer:
- `version` `2.17.2` nas duas `plugin.json` e no selo do `README.md`.
- `## 2.17.2 — 2026-11-24` no topo do `CHANGELOG.md`, com um item por Issue (#731, #730, #723), do ponto de vista de quem usa.
mutacao: n/a — troca de versão e texto de changelog
prova-na-base: vermelho — na base, `grep -c '"version": "2.17.2"' .claude-plugin/plugin.json` imprime 0
pronto quando: com o plugin instalado pela versão nova, provado por `grep -c '"version": "2.17.2"' .claude-plugin/plugin.json .codex-plugin/plugin.json` imprimindo 1 em cada, e `grep -c '^## 2.17.2' CHANGELOG.md` imprimindo 1.
