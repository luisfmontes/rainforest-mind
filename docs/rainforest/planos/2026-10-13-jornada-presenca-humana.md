# Plano: Jornada: prompt de máquina não conta como presença humana (#485)

Design: docs/rainforest/design/2026-10-13-jornada-presenca-humana.md

## O que não pode quebrar
- `mensagensHumanas(caminho)` segue exportada e devolvendo a lista `[Date, caminho]` de presença humana: o relógio do mod (`hooks/testa-mod-relogio.cjs`) e `--json` dependem dela.
- O filtro atual (`toolUseResult`, `isMeta`, `isCompactSummary`, `type !== "user"`) continua valendo antes do critério novo; o corte de 55 min e a lógica de `medir()` não mudam.
- As três baterias que já constroem transcript sintético (`scripts/testa-jornada.sh`, `scripts/testa-jornada-filtro.cjs`, `hooks/testa-mod-relogio.cjs`) seguem verdes. Elas montam entradas sem `origin` nem `entrypoint`, que o D1 passa a recusar: as fixtures ganham o formato real em `origin: { kind: "human" }` e `entrypoint: "cli"`, no mesmo commit do filtro. Nenhum caso de teste lê o texto do fonte.

## Tarefas

### 1. Filtro de presença humana por origem, com a bateria nova [tipo: implementar]
atende: D1, D2, D4
arquivos: `scripts/jornada.cjs`, `scripts/testa-jornada-origem.cjs`, `scripts/testa-jornada.sh`, `scripts/testa-jornada-filtro.cjs`, `hooks/testa-mod-relogio.cjs`
depende de: nenhuma
paralela: sim
prova: `node scripts/testa-jornada-origem.cjs`
mutacao:
  arquivo: `scripts/jornada.cjs`
  de: `if (ehPresencaHumana(d)) {`
  para: `if (true) {`
  bateria: `node scripts/testa-jornada-origem.cjs`
  fixture: `testa-jornada-origem.cjs, casos "task-notification nao conta", "headless sdk-cli nao conta", "sdk-py nao conta" e "plugin nao conta"`
pronto quando: com um transcript de formato real (campos `type`, `timestamp`, `entrypoint`, `origin.kind`, `isSidechain`, `message` copiados do que o Claude Code grava: `origin.kind` = `human`, `task-notification`, `plugin`; `entrypoint` = `cli`, `sdk-cli`, `sdk-py`; uma entrada sem `origin` com `entrypoint: "cli"`; uma `[Request interrupted by user]` sem `origin` com `entrypoint: "cli"`; uma sem `origin` com `entrypoint: "sdk-cli"`; uma com `isSidechain: true`), `node scripts/jornada.cjs --json --transcript <arquivo>` devolve `mensagens` igual ao número de entradas humanas (`origin.kind: human`, a sem `origin` do `cli`, e a interrupção) e zero das outras — provado por `node scripts/testa-jornada-origem.cjs` saindo 0 com zero `skipped`, e por `bash scripts/testa-jornada.sh`, `node scripts/testa-jornada-filtro.cjs` e `node hooks/testa-mod-relogio.cjs` saindo 0.

Forma do código: o critério mora numa função pura `ehPresencaHumana(d)`, uma expressão de decisão sem `print`, chamada na linha exata do alvo da mutação (`if (ehPresencaHumana(d)) {`, o ramo que separa humano de máquina na função que classifica o transcript), depois dos filtros atuais. A bateria roda `jornada.cjs` como subprocesso e afirma sobre a saída; nenhum caso lê o texto do fonte. As fixtures das três baterias existentes passam a trazer `entrypoint: "cli"` e `origin: { kind: "human" }` em toda entrada que representa o usuário.

### 2. Contagem de sinais de máquina descartados [tipo: implementar]
atende: D3, D5
arquivos: `scripts/jornada.cjs`, `scripts/testa-jornada-origem.cjs`, `hooks/mod-relogio.test.tsx`, `hooks/mod-painel.test.tsx`
depende de: 1
paralela: nao
prova: `node scripts/testa-jornada-origem.cjs`
mutacao:
  arquivo: `scripts/jornada.cjs`
  de: `console.log("sinais de maquina descartados ..... " + maquina);`
  para: `console.log("sinais de maquina descartados ..... " + 0);`
  bateria: `node scripts/testa-jornada-origem.cjs`
  fixture: `testa-jornada-origem.cjs, caso "linha de descartados mostra a contagem de entradas de maquina"`
pronto quando: com o transcript da tarefa 1 (N entradas de máquina e M humanas no dia), `node scripts/jornada.cjs --transcript <arquivo>` imprime a linha `sinais de maquina descartados ..... N` e `--json` traz `maquina_descartadas: N`, contando só entradas que passaram os filtros antigos e foram recusadas pelo D1 (`toolUseResult`, `isMeta` e `isCompactSummary` não contam); e com os transcripts reais do usuário, a contagem do script antigo (`git show origin/main:scripts/jornada.cjs`) e a do novo, ambos com `--dia 2026-10-10 --json`, fecham a conta: `mensagens` antigo = `mensagens` novo + `maquina_descartadas`, com `maquina_descartadas` > 0 e `efetiva_min` novo < antigo — provado por `node scripts/testa-jornada-origem.cjs` saindo 0 e por `git show origin/main:scripts/jornada.cjs > "$TEMP/jornada-antiga.cjs" && node "$TEMP/jornada-antiga.cjs" --dia 2026-10-10 --json` mais `node scripts/jornada.cjs --dia 2026-10-10 --json`, cujas saídas satisfazem a igualdade (medido em 2026-10-13: 613 = 142 + 471; efetiva 1055 min → 612 min).

Forma do código: `mensagensHumanas()` mantém a assinatura e o retorno; a contagem sai de uma função irmã que classifica o mesmo transcript (um percurso só, sem reler o arquivo duas vezes), e `main()` soma só as entradas do dia medido. A linha impressa fica na posição logo depois de "mensagens do usuario", só no modo texto.

### 3. Versão 1.65.1, nota de atualização e README [tipo: docs]
atende: D1, D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação e versão, sem comportamento a inverter; a falsificação é a coerência entre a nota, a versão e a saída real do script.
pronto quando: com o `jornada.cjs` da tarefa 2, a versão dos dois `plugin.json` é `1.65.1`, o badge do `README.md` mostra `1.65.1`, a primeira seção de versão do `CHANGELOG.md` é `## 1.65.1 — 2026-10-13`, e essa seção cita a #485, diz que só prompt digitado conta como presença (origem `human`) e reproduz literalmente o rótulo da linha que o script imprime — provado por `node -e "const fs=require('fs');const v=s=>JSON.parse(fs.readFileSync(s,'utf8')).version;const out=require('child_process').execFileSync(process.execPath,['scripts/jornada.cjs','--dia','2026-10-10'],{encoding:'utf8'});const rot=/(sinais de maquina descartados)/.exec(out);const cl=fs.readFileSync('CHANGELOG.md','utf8');const sec=cl.split(/^## /m)[1];const rd=fs.readFileSync('README.md','utf8');const bad=[v('.claude-plugin/plugin.json')!=='1.65.1',v('.codex-plugin/plugin.json')!=='1.65.1',!rd.includes('vers%C3%A3o-1.65.1'),!sec.startsWith('1.65.1 — 2026-10-13'),!sec.includes('#485'),!rot||!sec.includes(rot[1])];if(bad.some(Boolean)){console.log('FALHA',bad);process.exit(1)}console.log('ok')"` imprimindo `ok`.
