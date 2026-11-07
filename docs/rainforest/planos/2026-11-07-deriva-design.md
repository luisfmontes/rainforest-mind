# Plano: deriva entre o design fechado e o código atual

Design: docs/rainforest/design/2026-11-07-deriva-design.md

## O que não pode quebrar
- Os subcomandos `design`, `cobertura`, `camadas`, `creep` e `mutacoes` do `conferir-fluxo.cjs` saem como hoje: `bash scripts/testa-conferir-fluxo.sh` segue verde.
- `extrairTarefas`, `extrairDecisoes` e `mascaraDeCerca` não mudam de comportamento: `deriva` só os chama.
- `skills/brainstorm/SKILL.md` fica abaixo de 16 384 bytes e 500 linhas (`bash scripts/testa-teto-skills.sh`).

## Tarefas

### 1. Subcomando `deriva` [tipo: implementar]
atende: D1, D2, D3, D4, D5
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-deriva.sh`
depende de: nenhuma
busca:
- repo | rg -n "function extrairTarefas|mutacao.campos|campos.de" scripts | scripts/conferir-fluxo.cjs:486 extrairTarefas devolve mutacao.campos {arquivo, de, para, bateria}; reaproveitado
- repo | rg -n "git.*log.*-S" scripts hooks | nenhum uso de pickaxe; construir
- livro | vigias/livro-de-repos.md "elephant-goldfish" | triado na rodada salvos-instagram, só README; a ideia vem de lá, o mecanismo é próprio
desfecho: estender
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `const intacta = texto !== null && texto.includes(de);`
  para: `const intacta = texto !== null;`
  bateria: `bash scripts/testa-deriva.sh`
  fixture: `testa-deriva.sh, caso "âncora tirada por um commit sai como sumiu, com o commit"`
prova: `node scripts/conferir-fluxo.cjs deriva --arquivo scripts/conferir-fluxo.cjs`
pronto quando: com o próprio repositório como entrada real, `node scripts/conferir-fluxo.cjs deriva` sai 0, imprime ao menos uma linha `<slug> D<n>[, D<m>]: <arquivo> — sumiu em <hash> <assunto>` cujo `<hash>` é o que `git log -1 --format=%h -S'<de>' -- <arquivo>` devolve para aquela âncora, e termina com a linha `decisões: <n> com âncora (<i> intactas, <p> com âncora perdida), <s> sem âncora medível`; `node scripts/conferir-fluxo.cjs deriva --arquivo scripts/lib/complexidade.cjs` lista `complexidade-por-funcao D1, D2, D3, D4, D5, D6, D8: scripts/lib/complexidade.cjs — intacta`; numa fixture git em mktemp, a bateria confere por linha exata: âncora intacta não aparece sem `--arquivo`; âncora que um commit tirou sai como `sumiu em <hash> <assunto>` com o hash desse commit; arquivo apagado sai como `arquivo sumiu em <hash> <assunto>`; a mesma âncora atendendo duas decisões sai uma vez com `D1, D2`; tarefa com `de:` em prosa e tarefa `mutacao: n/a` deixam a decisão em "sem âncora medível" no placar; `--slug` restringe a um plano e o placar só conta ele; `--arquivo` mostra também as intactas daquele arquivo; `--slug` sem plano sai 1 — provado por `bash scripts/testa-deriva.sh`, nenhum caso afirmando sobre o texto do fonte

Forma prescrita:
- **Raiz.** Tudo (planos, design do `Design:`, arquivos das âncoras, `git`) resolve contra a `RAIZ` do script (`RFM_ESTADO_ROOT || CLAUDE_PROJECT_DIR || cwd`). Os comandos de prova e do critério rodam com `RFM_ESTADO_ROOT="$PWD"` no worktree; a bateria exporta `RFM_ESTADO_ROOT` com a fixture (`cygpath -m`).
- **Entrada.** `deriva` lê os planos de `docs/rainforest/planos/*.md` sob a `RAIZ` (fora os `*.pr.md`), em ordem de nome; `--slug <s>` lê só `docs/rainforest/planos/<s>.md` e sai 1 com `RECUSADO: plano não existe: <caminho>` se ele faltar. O slug de cada plano é o nome do arquivo sem `.md`. Opção que não seja `--slug` ou `--arquivo` sai 1 com `erro: opção desconhecida: <opção>`.
- **Decisões.** As decisões de um plano são as `D<n>` do design apontado pela linha `Design: <caminho>` do plano (`extrairDecisoes`); sem design legível, as `D<n>` citadas nos `atende:` das tarefas.
- **Âncoras.** De cada tarefa de `extrairTarefas`, a âncora é `mutacao.campos.arquivo` e `mutacao.campos.de`, os dois inteiros entre um par de crases (tira as crases); qualquer outra forma não é âncora. A âncora vale para toda `D<n>` do `atende:` da tarefa, extraídas da string com `/D(\d+)/g`. Duas tarefas com a mesma âncora (arquivo e `de:` iguais) somam as decisões numa só.
- **Estado.** Com `texto` = conteúdo atual do arquivo (null se não existe), `const intacta = texto !== null && texto.includes(de);`. Não intacta com arquivo existente: `sumiu em ` + saída de `git log -1 --first-parent -m "--format=%h %s" "-S<de>" -- <arquivo>` (cada par de aspas é um argumento só do `execFileSync`; saída em utf8 com `trim()`). Arquivo inexistente: `arquivo sumiu em ` + saída de `git log -1 --first-parent -m "--format=%h %s" -- <arquivo>`. *Emenda do executar:* `--first-parent -m` entrou porque, sem ele, a remoção feita por commit de merge não aparece e o pickaxe devolvia o commit que pôs o trecho (`.codex-plugin/plugin.json` do `multihost-sobre-1-11`: `070e55b4 sobe para 1.25.0` sem a flag, `c630a3e5 Merge pull request #347` com ela). Saída vazia ou git com erro: `commit não achado`. Todo git roda com `cwd` = `RAIZ`, por `execFileSync` sem shell.
- **Saída.** Linha por âncora perdida: `<slug> <D…>: <arquivo> — sumiu em <hash> <assunto>` (ou `— arquivo sumiu em …`), com as decisões em ordem numérica separadas por `, `. Ordem das linhas: planos em ordem de nome; dentro do plano, âncoras na ordem da primeira tarefa em que aparecem. Com `--arquivo <caminho>` (os dois lados com `\` trocado por `/` antes de comparar), só entram âncoras daquele arquivo e as intactas também saem, como `<slug> <D…>: <arquivo> — intacta`. Última linha: `decisões: <n> com âncora (<i> intactas, <p> com âncora perdida), <s> sem âncora medível`, contando cada `D<n>` de cada plano selecionado uma vez: com âncora perdida se alguma âncora dela se perdeu, intacta se todas estão, sem âncora medível se não tem nenhuma. Com `--arquivo`, só contam as decisões com âncora naquele arquivo. Exit 0.
- `main` ganha `deriva` no despacho e na linha `uso:`.
- **Bateria** `scripts/testa-deriva.sh`, no molde de `scripts/testa-conferir-mutacao-placar.sh`: script do próprio checkout (`RAIZ=$(cd "$(dirname "$0")/.." && pwd)`), fixture em `mktemp -d` fora do worktree com `trap rm -rf`, `git init` com `user.name`/`user.email` locais, design e plano escritos por `node -e` com `Design:`, `atende:` e `mutacao:` com crases; o trecho entra num commit e sai noutro (`git commit -m "tira a âncora"`), e o hash esperado vem de `git log -1 --format=%h` da própria fixture. Um caso por comportamento do critério, com o nome literal `âncora tirada por um commit sai como sumiu, com o commit` para o da mutação, mais o caso da opção desconhecida. Termina com `ok: <n>   falhou: <m>` e sai 1 com falha.

*Emenda da revisão 1:* `--arquivo` vira caminho relativo à `RAIZ` antes de comparar (`./`, absoluto e contrabarra casam), e filtro que não casa nenhuma âncora avisa no stderr `aviso: nenhuma âncora de plano aponta para <filtro>`; opção sem valor sai 1 com `erro: falta valor para <opção>`; a pasta e o sufixo dos planos vêm de `caminhoDoc('planos', ...)`, como no `cobertura` e no `creep`; o caminho do `Design:` é o primeiro token da linha, entre crases ou não. A bateria ganha remoção por merge, commit posterior que toca o arquivo sem a âncora, decisão com âncora intacta e perdida, `--arquivo` com `./` e absoluto, aviso e opção sem valor.

### 2. O brainstorm consulta a deriva dos arquivos que vai tocar [tipo: docs]
atende: D5
arquivos: `skills/brainstorm/SKILL.md`
depende de: 1
mutacao: n/a
  motivo: tarefa só de texto de skill; a falsificação é o comando escrito nela rodar no repositório real e dizer o que o texto promete
pronto quando: com o `skills/brainstorm/SKILL.md` real, a seção `## Abrir` traz, depois do parágrafo da varredura e antes de `## Território`, o parágrafo abaixo; o comando dele, rodado como está escrito com `<arquivo>` = `scripts/lib/complexidade.cjs` no repositório real, sai 0 e lista a linha `complexidade-por-funcao D1, D2, D3, D4, D5, D6, D8: scripts/lib/complexidade.cjs — intacta`, que é o que o parágrafo diz que ele lista — provado por `node scripts/conferir-fluxo.cjs deriva --arquivo scripts/lib/complexidade.cjs` e por `bash scripts/testa-teto-skills.sh`

Parágrafo a inserir:

```
**Pergunte ao repositório que decisões já moram nos arquivos que a demanda vai tocar:**
`node scripts/conferir-fluxo.cjs deriva --arquivo <arquivo>` para cada um. Ele lista, por
design, as decisões cuja âncora de mutação (o `de:` do plano) está naquele arquivo, intacta ou
perdida, com o commit que a tirou. Leia o design de cada decisão listada antes da primeira
rodada: decisão intacta é restrição que o design novo herda; âncora perdida é deriva, e o
design antigo pode estar afirmando o que o código já não faz.
```

### 3. README, CHANGELOG e versão [tipo: docs]
atende: D6
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
mutacao: n/a
  motivo: tarefa só de texto e número de versão; a falsificação é a coerência com o que as tarefas 1 e 2 entregaram, conferida no critério
pronto quando: com o repositório real, depois de `git fetch origin` e `git merge --no-edit origin/main` (conflito para e reporta), e com a versão-base lida por `git show origin/main:.claude-plugin/plugin.json`, a versão é a MINOR seguinte à da `origin/main` (2.8.0 se o #657 estiver mergeado, 2.7.0 se não), igual nos dois `plugin.json`, no selo do README (URL e `alt`) e no topo do `CHANGELOG.md` (`## <versão> — 2026-11-07`, um bullet em negrito que diz: a âncora é o `de:` da mutação; os três estados (intacta, sumiu, arquivo sumiu) com o commit; o `--arquivo`; o uso no `brainstorm`; exit 0, relatório que não trava); o README ganha, logo depois da linha do `conferir-fluxo.cjs mutacoes` na tabela de scripts, uma linha do `deriva` com a forma do comando, a âncora pelo `de:` da mutação, os três estados com o commit e o exit 0 — provado por `grep -c "conferir-fluxo.cjs deriva" README.md` ≥ 1, `bash scripts/testa-versao.sh` e `bash scripts/testa-plugin-codex.sh` verdes, e `node scripts/conferir-versao.cjs` exit 0
