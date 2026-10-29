# Plano: aviso-fluxo deixa passar arquivo ignorado pelo git

Design: docs/rainforest/design/2026-10-29-aviso-fluxo-gitignored.md

## O que não pode quebrar
- Edit de código rastreado sem fluxo aberto nem `leve` continua saindo 2, com a mesma mensagem.
- Os casos já existentes de `hooks/testa-bloqueio-fluxo.cjs` e `hooks/testa-aviso-fluxo.cjs` continuam verdes.

## Tarefas

### 1. aviso-fluxo deixa passar o arquivo que o git ignora [tipo: implementar]
atende: D1, D2, D3, D5
arquivos: `hooks/aviso-fluxo.cjs`, `hooks/testa-bloqueio-fluxo.cjs`
depende de: nenhuma
busca:
- repo | rg "check-ignore" hooks scripts | gate-publicacao-destino.cjs tem estaGitignorado local, não exportado e sem --; conferir-entrega.cjs usa -v
desfecho: compor
prova-na-base: verde — os dois casos novos nascem na própria tarefa dentro da bateria; na base a bateria não os tem e sai 0
mutacao:
  arquivo: `hooks/aviso-fluxo.cjs`
  de: if (ignoradoPeloGit(gitTop, relPath)) {
  para: if (false) {
  bateria: `node hooks/testa-bloqueio-fluxo.cjs`
  fixture: testa-bloqueio-fluxo.cjs, caso "rainforest na main sem fluxo: Edit de .ps1 listado no .gitignore passa (#623)"
pronto quando: com o payload `PreToolUse` de `Edit` que o harness manda, sobre `start-bridge.ps1` listado no `.gitignore` da `main` de um repo com `docs/rainforest/estado/` e sem fluxo, o hook sai 0 sem stderr; sobre um `.ps1` rastreado que casa com o mesmo `.gitignore` (adicionado com `git add -f`), sai 2 com "nenhum está aberto" — provado por `node hooks/testa-bloqueio-fluxo.cjs` devolvendo as linhas `ok:` dos dois casos e `falhou: 0`

### 2. Comentário do hook de shell, README, CHANGELOG e versão 2.1.3 [tipo: docs]
atende: D4, D6
arquivos: `hooks/aviso-fluxo-shell.cjs`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: só texto e número de versão; o comportamento novo é medido pela mutação da tarefa 1
pronto quando: com o repositório no HEAD da tarefa, o comentário do `aviso-fluxo-shell.cjs` não afirma mais que o Edit barra o arquivo ignorado, a linha do `aviso-fluxo.cjs` no README diz que o arquivo ignorado passa, e a versão é a mesma nos três lugares — provado por `grep -c "o Edit já o barra" hooks/aviso-fluxo-shell.cjs` devolvendo `0`, `grep -c "ignorado pelo git" README.md` devolvendo ao menos `1`, e `bash scripts/testa-versao.sh` saindo 0
