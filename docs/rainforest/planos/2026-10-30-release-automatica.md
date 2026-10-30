# Plano: release no GitHub a cada versão nova, sem depender da sessão

Design: docs/rainforest/design/2026-10-30-release-automatica.md

## O que não pode quebrar
- `.github/workflows/baterias.yml` não muda, e os workflows que alcançam PR continuam sendo só ele (`publicar-branch.cjs` conta os workflows de PR).
- `scripts/conferir-versao.cjs` e a regra de quando subir a versão não mudam (D7).
- Release que já existe nunca é recriada nem editada (D3).

## Tarefas

### 1. Script que publica a release da versão do manifesto, com bateria [tipo: implementar]
atende: D2, D3, D5
arquivos: `scripts/release-da-versao.cjs`, `scripts/testa-release-da-versao.sh`
depende de: nenhuma
busca:
- repo | rg -l "CHANGELOG" scripts | só testa-estado-reabrir.sh cita o arquivo, nenhum script extrai seção do CHANGELOG
- repo | rg "gh release" scripts hooks | só o caso de teste do gate-subagente-sem-gh; nenhum script publica release
- livro | pulado: mecanismo de algumas dezenas de linhas; ação de terceiro descartada no design
desfecho: construir
prova: `bash scripts/testa-release-da-versao.sh`
mutacao:
  arquivo: `scripts/release-da-versao.cjs`
  de: if (jaExiste) {
  para: if (false) {
  bateria: `bash scripts/testa-release-da-versao.sh`
  fixture: testa-release-da-versao.sh, caso "release existente: nenhum create"
pronto quando: com um repositório falso de `plugin.json` na versão `9.8.7` e um `CHANGELOG.md` com as seções `## 9.8.7 — ...` e `## 9.8.6 — ...`, e um `gh` de mentira que registra cada chamada, os quatro casos do D5 saem `ok`: (a) release inexistente registra um `release create v9.8.7` com `--target`, `--title "rainforest-mind 9.8.7"` e notas iguais à seção 9.8.7; (b) release existente não registra `create`; (c) seção ausente sai 1 sem `create`; (d) as notas não contêm o texto da seção 9.8.6 — provado por `bash scripts/testa-release-da-versao.sh` saindo 0 com `falhou: 0` na última linha de placar, e pela catraca `node scripts/conferir-mutacao.cjs` com o bloco `mutacao:` acima saindo 0 (vermelho com o `if (false) {`)

Forma prescrita: `node scripts/release-da-versao.cjs --sha <sha> [--seco] [--raiz <dir>]`. Lê `<raiz>/.claude-plugin/plugin.json` e `<raiz>/CHANGELOG.md` (raiz padrão: o diretório pai de `scripts/`). Consulta `gh release view v<versão>`: exit 0 → `const jaExiste = true`. A linha `if (jaExiste) {` imprime `release v<versão> já existe — nada a fazer` e sai 0. Seção: da linha que começa com `## <versão> ` até antes da próxima linha que começa com `## `, sem a linha do título, aparada; vazia ou ausente → stderr `CHANGELOG sem a seção <versão>` e exit 1. Notas gravadas num arquivo temporário (`fs.mkdtempSync(os.tmpdir())`) e passadas por `--notes-file`. `--seco` imprime o comando e as notas e não chama o `create`. O `gh` é chamado pelo nome `gh` via `spawnSync` sem shell, e o PATH decide qual roda (a bateria põe o stub na frente). Exit do `create` ≠ 0 → o script sai com o mesmo código.

Emenda do executar (2026-10-30): no Windows o `spawnSync('gh')` ignora um stub bash sem extensão e roda o `gh.exe` real (o executor mediu e parou antes de escrever). O `gh` passa a ser chamado por `executar('gh', args, opts)` de `hooks/lib/resolver-executavel.cjs`, como em `scripts/publicar-branch.cjs`; a bateria monta o stub no padrão de `scripts/testa-publicar-branch.sh` (`gh` + `gh.cmd` + `gh-stub.js`) e prova, antes dos casos, que o PATH sem o stub não acha `gh`.

### 2. Workflow que chama o script no push do bump à main [tipo: configurar]
atende: D1, D4
arquivos: `.github/workflows/release.yml`
depende de: 1
mutacao: n/a
  motivo: YAML de workflow não roda localmente; o comportamento está no script da tarefa 1, e o primeiro run real é o merge do bump 2.3.0 (D8)
pronto quando: com o arquivo no HEAD da tarefa, ele dispara em `push` à `main` com `paths: ['.claude-plugin/plugin.json']` e em `workflow_dispatch`, roda em `ubuntu-latest` com `permissions: contents: write`, passa `GH_TOKEN: ${{ github.token }}` e chama `node scripts/release-da-versao.cjs --sha "$GITHUB_SHA"`, e não tem gatilho `pull_request` — provado por `grep -c "pull_request" .github/workflows/release.yml` devolvendo `0` e por `node -e` que lê o arquivo e confere as seis substrings `branches: [main]`, `.claude-plugin/plugin.json`, `workflow_dispatch`, `ubuntu-latest`, `contents: write`, `release-da-versao.cjs --sha "$GITHUB_SHA"` imprimindo `6/6`

### 3. Docs, CHANGELOG e versão 2.3.0 [tipo: docs]
atende: D6, D7, D8
arquivos: `CONTRIBUTING.md`, `skills/fechar/SKILL.md`, `scripts/contrato-plugin-codex.cjs`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
mutacao: n/a
  motivo: só texto e número de versão; o comportamento é medido pela mutação da tarefa 1
pronto quando: com o repositório no HEAD da tarefa, a versão é `2.3.0` nos dois `plugin.json` e no badge do README, o CHANGELOG tem a seção `## 2.3.0` citando `release.yml`, e `CONTRIBUTING.md`, `skills/fechar/SKILL.md` e `README.md` citam `release.yml` — provado por `bash scripts/testa-versao.sh`, `bash scripts/testa-teto-skills.sh`, `bash scripts/testa-plugin-codex.sh` e `bash scripts/testa-conferir-invariantes.sh` saindo 0, `grep -l "release.yml" CONTRIBUTING.md skills/fechar/SKILL.md README.md CHANGELOG.md | wc -l` devolvendo `4`, e `node scripts/release-da-versao.cjs --sha HEAD --seco` imprimindo as notas da seção 2.3.0
