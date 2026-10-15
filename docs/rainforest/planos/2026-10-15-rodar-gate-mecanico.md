# Plano: Flake gravado pela integração, sem depender da janela (#498)

Design: docs/rainforest/design/2026-10-15-rodar-gate-mecanico.md

## O que não pode quebrar
- `bash scripts/testa-conferir-fluxo.sh`, `bash scripts/testa-integrar-tarefa.sh` e `bash scripts/testa-conferir-mutacao-flaky.sh` seguem verdes.
- O `verificar` (`estado.cjs`, chamada de `conferir-fluxo.cjs mutacoes` sem `--gravar-flake`) não grava flake: o estado do fluxo não ganha `executar.flakes` quando a catraca roda pelo `verificar`.
- `bash scripts/varrer-baterias.sh --listar` sai 0 (a lista de obrigatórias não cita bateria que não existe).

## Tarefas

### 1. A integração pede o repasse de `--slug`/`--tarefa` à catraca [tipo: implementar]
atende: D1
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/integrar-tarefa.cjs`, `scripts/testa-conferir-fluxo.sh`, `scripts/conferir-mutacao.cjs`, `scripts/testa-integrar-tarefa.sh`
depende de: nenhuma
prova-na-base: verde — o caso novo usa a flag `--gravar-flake`, que só passa a existir nesta tarefa; na base o `mutacoes` não a conhece
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: if (gravaFlake) argumentos.push('--slug', slug, '--tarefa', String(numero));
  para: if (false) argumentos.push('--slug', slug, '--tarefa', String(numero));
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: testa-conferir-fluxo.sh, caso novo "#498: mutacoes com --gravar-flake grava o flake do baseline"
pronto quando: com um estado de fluxo real (criado por `node scripts/estado.cjs iniciar` numa caixa) e um plano cuja tarefa 1 declara uma bateria de exit variável por chamada (contador FORA da cópia que a catraca faz, sequência `1 0 1 1`: baseline vermelho, nova tentativa verde, pós-mutação vermelho nas duas), (a) `node scripts/conferir-fluxo.cjs mutacoes --slug <s> --tarefa 1 --plano <p> --gravar-flake` sai 0 com `tarefa 1: vermelho` e o JSON do estado passa a ter `executar.flakes` com `{"tarefa":1,"gate":"catraca: <bateria>"}`; (b) o mesmo comando SEM `--gravar-flake`, com o contador zerado, sai 0 e o estado não ganha `executar.flakes`; (c) `scripts/integrar-tarefa.cjs` passa `--gravar-flake` na chamada de `mutacoes` (o caso existente de integração em `testa-integrar-tarefa.sh` segue verde); (d) a chamada de `mutacoes` do `verificar` em `scripts/estado.cjs` não muda — provado por `bash scripts/testa-conferir-fluxo.sh` e `bash scripts/testa-integrar-tarefa.sh` com zero falha e por `git diff <base> -- scripts/estado.cjs` vazio.

Emenda depois da 1ª revisão (achados 1 e 2): (e) a raiz do estado onde o flake é gravado é a do `conferir-fluxo` (`RAIZ`), não a `--raiz` da tarefa: o `conferir-mutacao.cjs` ganha `--raiz-estado <pasta>` (opcional, padrão a `--raiz`, como hoje), e o `gravarFlake` roda o `estado.cjs registrar-flake` com `RFM_ESTADO_ROOT` igual a ela, só nesse processo filho (a bateria não herda); o `conferir-fluxo` passa `--raiz-estado RAIZ` junto com `--slug`/`--tarefa`. Provado por um caso em `testa-conferir-fluxo.sh` SEM `RFM_ESTADO_ROOT` no ambiente, com `cwd` no topo da caixa, tarefa com `raiz: app` e `--raiz-codigo <topo>`: o estado do topo ganha `executar.flakes`. (f) `testa-integrar-tarefa.sh` ganha um caso que roda o `integrar-tarefa.cjs` de verdade com uma tarefa cuja bateria é de exit variável (`1 0 1 1`) e exige `executar.flakes` no estado depois da integração; esse caso cai se o `'--gravar-flake'` sair do `integrar-tarefa.cjs`.

Forma do código: em `cmdMutacoes`, `const gravaFlake = process.argv.includes('--gravar-flake') && Boolean(slug);` lido uma vez; dentro do laço, logo depois de montar `argumentos` (e do `--timeout`), a linha exata `if (gravaFlake) argumentos.push('--slug', slug, '--tarefa', String(numero));`. O uso do `conferir-fluxo.cjs` (mensagem de uso e comentário do cabeçalho de `mutacoes`) cita a flag. Em `integrar-tarefa.cjs`, a lista de `rodar('conferir-fluxo.cjs', [...])` ganha `'--gravar-flake'`. Nenhum caso de teste lê o texto do fonte.

### 2. `rodar-gate.cjs` sai, e a doc diz quem grava o flake [tipo: docs]
atende: D2
arquivos: `scripts/rodar-gate.cjs`, `scripts/testa-rodar-gate.sh`, `scripts/baterias-obrigatorias.txt`, `skills/revisar/references/laco.md`, `README.md`, `docs/travas-mecanicas.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: remoção de script sem chamador e documentação; não há comportamento a inverter
pronto quando: com o repositório depois da tarefa 1, (a) `scripts/rodar-gate.cjs` e `scripts/testa-rodar-gate.sh` não existem e `scripts/baterias-obrigatorias.txt` não cita `testa-rodar-gate.sh`; (b) `grep -rn "rodar-gate" --include=*.md --include=*.cjs --include=*.sh --include=*.txt --include=*.json . ` fora de `CHANGELOG.md`, `docs/rainforest/` e `relatorios/` não devolve linha; (c) a seção `Flaky` do `laco.md` diz que a integração (`scripts/integrar-tarefa.cjs`) roda a catraca com o flake gravado (`--gravar-flake`), que a janela não roda bateria nem catraca à mão, e mantém o `FLAKY TERMINAL` e o `--status flaky` como estão; (d) entrada nova no CHANGELOG (PATCH sobre a versão da `origin/main` no despacho) descreve D1 e D2 sem prometer mais do que o código faz, com as duas `plugin.json` e o selo do README batendo — provado por `node scripts/conferir-versao.cjs` saindo 0, `bash scripts/varrer-baterias.sh --listar` saindo 0, `node scripts/conferir-indice-referencias.cjs` saindo 0, `bash scripts/testa-conferir-categoria.sh` com zero falha e pela leitura do revisor confrontando o `laco.md` e o CHANGELOG com D1–D2.
