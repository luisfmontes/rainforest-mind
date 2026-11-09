# Design: o verificar recusa diff que apaga ou pula teste sem declarar

## Objetivo
Hoje nada no fluxo distingue "editei o teste" de "tirei o teste do caminho". O `creep` do
`revisar` só pergunta se o arquivo do diff casa com algum `arquivos:` do plano: uma tarefa que
declara `scripts/testa-x.sh` pode apagar a bateria inteira, ou acrescentar `.skip(` num caso
`*.test.ts`, e passa por todas as travas com a suíte verde (o que não roda não falha). Creep
autoriza tocar; esta trava exige declarar que o toque tira proteção. É a parte 2 da ideia
`regua-que-nao-afrouxa` (affaan-m/ECC `skills/loop-design-check/SKILL.md:121`, a meta sem
mecanismo; addyosmani/agent-skills `skills/constraint-driven-development/references/floor-guard.md`,
o mecanismo, lido em 2026-10-24). Nada é copiado: a forma é reimplementada sobre o estado do
fluxo. Modo autônomo ("pode seguir a vontade", 2026-11-09): as decisões **[sessão]** foram a
recomendada, sem rodada, e ficam para veto no PR.

## Decisões fechadas
- **D1 — Subcomando `conferir-fluxo.cjs afrouxa`, chamado pelo `marcar verificar ok` [sessão]** — porquê: o diff que importa é o que o `revisar` aprovou, e o `revisar ok` já grava `base` e `head` no estado (exigidos desde a trava de creep). O `verificar` lê `estado.revisar.base`/`head`, roda o subcomando logo depois da catraca de mutações e recusa com exit 2 se ele recusar. Sem `base`/`head` gravados (fluxo de antes da trava): avisa em stderr e segue. O `git diff` roda onde o `creep` rodou (a raiz do estado), mesmo com `--raiz`: é ali que `base` e `head` foram aceitos, e é esse o diff que o `revisar` aprovou. Subcomando de `conferir-fluxo.cjs`, e não script novo, porque reaproveita `extrairTarefas`, `extrairArquivos` e `globMatches`, que o `creep` já usa.
- **D2 — Dois sinais, só em arquivo de teste [sessão]** — porquê: os dois são nítidos, e o falso positivo de cada um é ato que vale declarar. (a) Arquivo de teste com status `D` em `git diff --name-status -M <base>...<head>`; renome (`R`) não conta. (b) Linha adicionada, num arquivo de teste, com marcador de pulo ou de foco: `.skip(`, `.only(`, `xit(`, `xdescribe(`, `xtest(`, `@pytest.mark.skip`, `@unittest.skip`, `t.Skip(`, `@Disabled`, `@Ignore`. Custo medido do sinal (a): dos mesmos 821 commits, 9 apagaram bateria (aposentar a peça testada, tirar bateria duplicada, um commit de merge), todos legítimos — cerca de um a cada 90 commits pede a linha `afrouxa:` (D4). Arquivo de teste é o que casa `testa-*.sh`, `testa-*.cjs`, `testa-*.py` (as 223, 80 e 6 baterias daqui), `*.test.*`, `*.spec.*`, `*_test.*` ou `test_*.py`, em qualquer pasta.
- **D3 — Contar asserção fica fora [sessão]** — porquê: medido. O padrão do floor-guard (`expect|assert|should`) não casa as baterias `.sh` daqui, que usam `ok`, `confere`, `esperar`, `checar` — e `ok` aparece também em texto ecoado. Com o padrão local (`ok|confere|esperar|checar|assert*|expect`), dos 821 commits que tocaram `testa-*.sh` desde 2026-09-01, 16 tiram mais linhas casadas do que põem, e todos foram revisados e mergeados (tirar caso duplicado, reescrever caso, aposentar peça). Recusar por isso ensinaria a declarar por hábito, e escape declarado por hábito não trava nada.
- **D4 — O escape é o campo `afrouxa: <motivo>` na tarefa do plano [sessão]** — porquê: é o idioma do `mutacao: n/a` com `motivo:`. O preço de passar é escrever por quê, no plano que o leitor cego e o revisor leem. Um achado passa quando o arquivo casa o `arquivos:` de uma tarefa que declara `afrouxa:` com motivo não vazio; o motivo sai no stdout. `afrouxa:` vazio é recusa da `cobertura`. Sem `--forcar`.
- **D5 — Saídas: 0 limpo, 2 recusa, 69 ambiente [sessão]** — porquê: as mesmas do `creep`. A recusa abre com `RECUSADO:` e lista cada achado (`apagado: <arquivo>` ou `pulo: <arquivo>:<linha> <trecho>`) e diz o remédio (o campo `afrouxa:`). Sem `git` no PATH: `nao-verificavel:` e 69. Outro erro do git (revisão desconhecida): exit 1. O `verificar` recusa em qualquer saída diferente de 0, porque não medir não é aprovar. Nome de teste fora dos padrões do D2 não é visto: falha aberta, sem chave de config nesta versão.
- **D6 — Versão MINOR, 2.10.0** — porquê: campo novo no plano e trava nova no `verificar`. Documentado em `skills/verificar/SKILL.md`, `skills/plano/SKILL.md`, `docs/travas-mecanicas.md`, CHANGELOG e README.

## Avaliado e descartado
- Contar asserções (D3).
- Chave de config com os padrões de arquivo de teste: nenhum repositório em uso pede outro padrão hoje; entra quando um pedir.
- Rodar no `revisar ok`, ao lado do `creep`: a ideia é do `verificar` ("quem verifica não afrouxa a régua") e lá o diff já está congelado pelo backstop do `revisar`.
- Parte 1 da ideia (hook que barra editar config de lint, teste e CI): pede ler `config-protection.js` do ECC, que não há nesta máquina; a ideia continua plantada para ela.

## Fora de escopo
- Marcador de pulo nas baterias `.sh` daqui: não há convenção (`exit 0` cedo, `pulado`), nada nítido para casar.
- Cobertura que cai: não há medidor de cobertura no repositório.

## Varredura
docs/rainforest/varredura/2026-11-09-regua-testes.txt — os termos ("teste apagado", "skip", "afrouxa", "floor-guard") casam só Issues e PRs que citam as palavras de passagem; nenhum trata recusar diff que apaga ou pula teste. A única ideia casada é a própria `regua-que-nao-afrouxa`.

## Em aberto
- Nada bloqueia. D1 a D5 ficam para veto no PR.
