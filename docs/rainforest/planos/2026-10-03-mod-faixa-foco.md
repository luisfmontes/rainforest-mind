# Plano: faixa acima do prompt com foco, fluxos e Q abertas (mod, AbovePrompt)

Design: docs/rainforest/design/2026-10-03-mod-faixa-foco.md

Base: worktree `fluxo/mod-faixa-foco`, HEAD `197a147a`, versao publicada 1.37.0. Destino: 1.38.0 (MINOR).

## Achados que ajustam o briefing

Medidos pelo planejador num plugin descartavel em `$TEMP` (ja apagado), contra o Claude Code 2.1.288.

1. **A faixa nao mora no `register.ts`.** JSX exige `.tsx`; `hooks/testa-mod-abertura.cjs:205-208` exige que `register.ts` registre exatamente `session.end`, `prompt.compose` e `classic.SessionStart`. Entrada nova `hooks/mod.tsx` (o `hooks.json` aponta para ela) que chama a abertura como funcao (`import { register as abertura } from './register.ts'`). Import de `.ts` dentro de `.tsx` passou em `claude plugin validate` e `claude plugin test`.
2. **`claude plugin validate .` na raiz valida so o `marketplace.json`.** O sensor e `claude plugin validate .claude-plugin/plugin.json`.
3. **`$.state` exige contrato de tipos no manifesto** (`"types": "./types/index.d.ts"`): sem `export {}`, so `type` exportado, `PluginState` dentro de `declare module 'claude-code'`.
4. **`claude plugin test` monta `AbovePrompt` nos surfaces terminal e desktop** (`$.ui.mount`, `find`, `press`, `drawn`); o teste precisa de fundo para cada evento chamado; props exigidas: `hasSurvey`, `isWorking`, `maxRows`, `bodyColumns`, `scroll: { offset, bodyRows }`, `view: {}`. Exit 1 quando um caso cai.
5. **`$.state` vale para a sessao de teste inteira:** um `test(...)` por surface.
6. **`claude plugin test .` serve de bateria para `conferir-mutacao.cjs`** (medido: vermelho com a mutacao da abertura, fonte restaurado).
7. **`estado.cjs listar` nao tem `--json` nem `tarefas_ok`/`em_voo`;** `estado.cjs` exporta `proximo`; `hooks/lib/contexto-sessao.cjs` exporta `tituloDoFocoAtivo` (devolveu o titulo do foco ativo do `FOCO.md` real); `hooks/lib/raiz.cjs` exporta `resolverRaiz`. Um script fino reusa os tres (0,23 s medidos com `git worktree list`).
8. **Marcador `**Q<n>.**`:** nao documentado no repo, mas usado nas respostas reais (medido no transcrito de 2026-10-03). O parser aceita as duas formas.

## Decisões do usuário

Respondidas em 2026-10-03:
- **A. Fonte das Q: `e.answer` do `turn.complete`** (emenda da D7 no design), em vez de `$.session.messages()`.
- **B. Gatilhos: so os tres da D11** (`session.start`, `turn.complete`, ao pressionar); `em_voo` atualiza no fim do turno. A tarefa 5 mede se o atraso incomoda; se incomodar, vira tarefa nova.

## O que não pode quebrar

- **A abertura do mod (1.37.0) fica identica.** `hooks/register.ts`, `hooks/abertura-mod-puro.mjs`, `hooks/testa-mod-abertura.cjs` e `hooks/mod-abertura.test.ts` nao mudam um byte (`git diff --quiet 197a147a -- <os quatro>`); `node hooks/testa-mod-abertura.cjs` segue `28 ok, 0 falha(s), 0 skipped`; `claude plugin test .` segue com os 2 casos da abertura passando.
- **A chave `hooks` do `hooks/hooks.json` fica intacta;** so `modules` muda de `./register.ts` para `./mod.tsx`. Base extraida com `MSYS_NO_PATHCONV=1 git cat-file -p 197a147a:hooks/hooks.json` (conferir saida nao vazia).
- **Falha de leitura nunca quebra a sessao, a abertura nem o prompt:** script com exit != 0, JSON invalido ou timeout apaga foco e fluxo; Q vem de `e.answer`; excecao no `ui.render` devolve `next(e)`.
- **Sem fluxo em curso e sem Q aberta, `ui.render` devolve `next(e)`;** o foco sozinho nao acende (D2); `hasSurvey` verdadeiro devolve `next(e)`.
- **O script de dados e somente leitura** (nada em `docs/rainforest/estado`, `FOCO.md`, `ideias.jsonl`; sem `gh`).
- **A statusline nao e tocada** (`statusline/` fora do diff); a faixa nao mostra jornada, prazo nem versao (D10).
- **Codex nao muda:** `.codex-plugin/plugin.json` so muda de versao; `node scripts/contrato-plugin-codex.cjs` passa.
- **`varrer-baterias` nao depende do binario `claude`:** logica em `.mjs`/`.cjs` testada em Node; provas de engine em `*.test.tsx` e comandos `claude`, sem prefixo `testa-`.
- **O ambiente do usuario nao muda;** `tsconfig.json` na raiz e `.claude-plugin/types/` gerados pelo engine nunca vao para o commit.
- **`node scripts/conferir-categoria.cjs` segue exit 0.**
- **`claude plugin validate .claude-plugin/plugin.json` sai 0** depois de cada tarefa que toca `hooks/hooks.json`, `hooks/*.mjs|ts|tsx`, `types/` ou `plugin.json`.

## Contrato dos dados

**Saida de `node scripts/faixa-dados.cjs --cwd <dir>`:** JSON em uma linha, exit 0:
`{"foco": "<titulo>"|null, "fluxos": [{"slug","titulo","etapa","tarefas_ok": n|null,"tarefas": n|null,"em_voo": ["<agente>",...],"criado_em","worktree"}]}`
- `etapa` = `proximo(estado)`; so entra fluxo com `etapa !== null`. `tarefas_ok`/`tarefas` do bloco `executar` quando numeros; `em_voo` do bloco da etapa ativa, filtrando entradas sem `agente` (como `hooks/gate-agente-em-voo.cjs:173-175`).
- Fluxos de todos os worktrees (`git worktree list --porcelain`, caindo para `[cwd]` se o git falhar), mais recente primeiro (`criado_em` desc, depois `slug` desc). Mesmo slug em varios worktrees: vale a copia mais avancada (indice de `etapa` em design, plano, executar, revisar, verificar, fechar, completo; empate pelo `mtime`).
- Estado ilegivel e ignorado com aviso no stderr; so excecao nao tratada sai 1.
- Foco: `tituloDoFocoAtivo` sobre o `FOCO.md` da raiz de `resolverRaiz({ cwd, plugin })`, como `hooks/foco-session-start.cjs:27`; vazio vira `null`.

**Estado do mod** (`$.state`, plugin `rainforest-mind`, contrato em `types/index.d.ts`): `faixaDados` (o JSON acima), `faixaQ` (`{ n, titulo }[]`), `faixaOculta` (`string | null`, a assinatura vista ao apertar "esconder").

**Linhas** (rotulos ASCII): `foco  <titulo>` · `fluxo <slug sem data>: <etapa>[ <ok>/<total>][ | <n> em voo][ | +<k>]` · `Q <k> aberta(s): Q1 <titulo> | Q2 <titulo> ...`. Cada linha cortada em `bodyColumns` celulas com `…`; emoji e CJK contam 2.

## Ordem e paradas

Cadeia: 1 → 2 → 3 → 4 → 5 → 6 → 7, todas `paralela: nao`.
- **PARADA 1, depois da tarefa 5:** a janela principal (e o usuario) roda o REPL real com `--plugin-dir` e cola a leitura de tela; `claude -p` nao desenha UI. Falhou, volta ao usuario.
- **Pendente pos-merge:** depois do `claude plugin update`, repetir a leitura da tarefa 5 numa sessao pelo marketplace.

## Tarefas

### 1. Script de dados: foco e fluxos em curso de todos os worktrees [tipo: implementar]
atende: D1, D4, D8, D9
arquivos: `scripts/faixa-dados.cjs`, `scripts/testa-faixa-dados.sh`
depende de: nenhuma
paralela: nao
prova: `bash scripts/testa-faixa-dados.sh`
mutacao:
  arquivo: `scripts/faixa-dados.cjs`
  de: `if (etapa === null) continue;`
  para: `if (false) continue;`
  bateria: `bash scripts/testa-faixa-dados.sh`
  fixture: `testa-faixa-dados.sh, caso "fluxo completo nao entra na lista"`
pronto quando: com o checkout principal real `C:/Projetos/rainforest-mind` como `--cwd`, `node scripts/faixa-dados.cjs --cwd C:/Projetos/rainforest-mind` devolve `fluxos` com `2026-10-03-mod-faixa-foco` (que so existe no worktree, o caso da D4), sem `2026-10-02-mod-regras-inteiras` (completo) e `foco` igual ao `tituloDoFocoAtivo` do `FOCO.md` da raiz resolvida — provado por um `node -e` que roda o script, faz `JSON.parse` e sai 1 se alguma das tres condicoes falhar; a bateria monta repo temporario com `git init` + `git worktree add` + JSON de estado nos dois e cobre copia velha no principal contra copia avancada no worktree (vale a avancada), fluxo completo fora, estado ilegivel ignorado, sem `FOCO.md` dando `foco: null` e diretorio que nao e repo caindo para `[cwd]`.

Nota: o `de:` e texto que a tarefa escreve, uma vez so, com `etapa` = `proximo(estado)` importado de `scripts/estado.cjs`. Reusar `proximo` e `tituloDoFocoAtivo`, nunca copiar. Git por `spawnSync('git', [...], { cwd })` conferindo `status === 0` (um `git -C` num diretorio que nao e repo sobe para o pai em silencio). Zero `skipped`; a bateria nunca le o `~/.rainforest` vivo.

### 2. Logica pura da faixa: Q, linhas, assinatura e esconder [tipo: implementar]
atende: D1, D2, D3, D5, D7, D10
arquivos: `hooks/faixa-puro.mjs`, `hooks/testa-mod-faixa.cjs`
depende de: 1
paralela: nao
prova: `node hooks/testa-mod-faixa.cjs`
mutacao:
  arquivo: `hooks/faixa-puro.mjs`
  de: `return oculto !== null && oculto === assinatura;`
  para: `return false;`
  bateria: `node hooks/testa-mod-faixa.cjs`
  fixture: `testa-mod-faixa.cjs, caso "esconder vale ate a assinatura mudar"`
pronto quando: com as linhas 49 a 52 do `README.md` real como texto de resposta, `extrairQs` devolve `[{n:1,titulo:"Onde o token vive"},{n:2,titulo:"Expiração"}]`; com o `❓ **Q1 — ...**` de `skills/brainstorm/SKILL.md:22` (em blockquote ou fora) devolve a Q1; com `**Q1.** texto` devolve a Q1; com a saida real do script da tarefa 1 sobre repo temporario, `montarLinhas(dados, qs, 40, 3)` devolve no maximo 3 linhas, nenhuma acima de 40 celulas (emoji contando 2), nenhuma com prazo, jornada ou versao mesmo que a entrada traga esses campos, e `[]` sem fluxo e sem Q — provado por `node hooks/testa-mod-faixa.cjs`, que importa o `.mjs` e cobre tambem Q dentro de bloco de codigo ignorada, numero de Q repetido contado uma vez, `+k` dos fluxos, `maxLinhas` menor que 3, assinatura que muda com nova Q, nova etapa e agente novo em `em_voo` e nao muda com `tarefas_ok`, e `escondida(oculto, assinatura)` verdadeira so com assinatura igual.

Nota: `escondida` termina com exatamente `return oculto !== null && oculto === assinatura;`, uma vez so. Exporta `MAX_LINHAS` (3), `MARCADORES_Q`, `extrairQs`, `montarLinhas`, `assinatura`, `largura`. ES module sem Node e sem `$`, no molde de `hooks/abertura-mod-puro.mjs`. Superficie humana: a linha da Q traz numero e titulo de cada Q, a do fluxo traz slug, etapa e progresso; a bateria falha se qualquer um sumir.

### 3. Fiacao do mod: `mod.tsx`, contrato de estado e `hooks.json` [tipo: implementar]
atende: D2, D5, D6, D7, D11
arquivos: `hooks/mod.tsx`, `types/index.d.ts`, `hooks/hooks.json`, `.claude-plugin/plugin.json`
depende de: 2
paralela: nao
prova: `claude plugin validate .claude-plugin/plugin.json 2>&1 | grep -q AbovePrompt`
mutacao:
  arquivo: `hooks/hooks.json`
  de: `"modules": ["./mod.tsx"]`
  para: `"modules": ["./register.ts"]`
  bateria: `claude plugin validate .claude-plugin/plugin.json 2>&1 | grep -q AbovePrompt`
  fixture: `validate lista ui.render{component=AbovePrompt}: o grep casa so com mod.tsx como entrada`
pronto quando: com o `hooks/hooks.json` e o `.claude-plugin/plugin.json` reais, `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista os hooks `session.start`, `turn.complete`, `ui.render{component=AbovePrompt}` da faixa e `session.end`, `prompt.compose`, `classic.SessionStart` da abertura, as chamadas `$.process.run`, `$.state.get`, `$.state.set` e `$.ui.resolve`, e `declares state:` com `rainforest-mind.faixaDados`, `faixaQ` e `faixaOculta`; a secao `hooks` do `hooks.json` e `deepStrictEqual` a de `197a147a`; `git diff --quiet 197a147a` sobre `hooks/register.ts`, `hooks/abertura-mod-puro.mjs`, `hooks/testa-mod-abertura.cjs` e `hooks/mod-abertura.test.ts` sai 0; `node hooks/testa-mod-abertura.cjs` imprime `28 ok, 0 falha(s), 0 skipped`; `claude plugin test .` mantem os 2 casos de `mod-abertura.test.ts`; `bash scripts/testa-versao.sh` e `node scripts/conferir-categoria.cjs` saem 0 — provado por esses comandos.

Nota:
- `mod.tsx` exporta `register = (on, options) => { abertura(on, options); ...hooks da faixa }`, importa `./faixa-puro.mjs` estaticamente (sem `import()`), atomos com `atom({ plugin: 'rainforest-mind', key } as const, ...)`, leitura `read($, ...)`, escrita `update($, ...)`.
- O engine recusa `$` passado como argumento a funcao propria: o refresh (rodar o script e gravar `faixaDados`) e closure dentro de `register`; ao `.mjs` vao so valores. O validate e o sensor.
- `session.start`: aguarda o refresh com `timeoutMs: 5000`; argv `['node', '<raiz do plugin>/scripts/faixa-dados.cjs', '--cwd', cwd]`, `env: { CLAUDE_PROJECT_DIR: cwd }` como `hooks/abertura-mod-puro.mjs:84`.
- `turn.complete`: ignora `e.agentId !== undefined` (subagente); so atualiza a Q com `e.reason === 'answer'`, extraindo de `e.answer` (decisao A); atualiza tambem `faixaDados`.
- `ui.render` em `{ component: 'AbovePrompt' }`: a linha `if (e.props.hasSurvey) return next(e)` uma unica vez (e o `de:` da tarefa 4); `isWorking` NAO esconde (D6); `montarLinhas(..., e.props.bodyColumns, Math.min(MAX_LINHAS, e.props.maxRows - 1))`; cada linha um `Text` com `key` e `wrap="truncate-end"`; `Button` `key="esconder"` `label="esconder"`; tudo em `try/catch` devolvendo `next(e)`.
- `onPress`: grava em `faixaOculta` a assinatura do que esta nos atomos agora e depois refaz o refresh de `faixaDados` em segundo plano; se algo mudou, a assinatura difere e a faixa volta (D5, D11).
- `types/index.d.ts`: so `type` exportado (sem `export {}`), `PluginState` em `declare module 'claude-code'`, nomes com prefixo `RainforestMind`; `plugin.json` ganha `"types": "./types/index.d.ts"`; versao nao sobe aqui.

### 4. Prova de engine: a faixa desenha em terminal e desktop, com os dados reais [tipo: teste]
atende: D1, D2, D3, D5, D6, D7, D11
arquivos: `hooks/mod-faixa.test.tsx`, `hooks/testa-mod-faixa.cjs`
depende de: 3
paralela: nao
prova: `claude plugin test . 2>&1 | grep -q mod-faixa.test.tsx`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `if (e.props.hasSurvey) return next(e)`
  para: `if (false) return next(e)`
  bateria: `claude plugin test .`
  fixture: `mod-faixa.test.tsx, caso "cede a vaga quando hasSurvey"`
pronto quando: com a saida REAL do script da tarefa 1 sobre repo temporario (colada como `FIXTURE_DADOS`, servida por `on('process.run')`) e o texto REAL de `README.md:49-52` como `answer` do `turn.complete`, `claude plugin test .` sai 0 com `(pass)` e 0 fail para cada caso abaixo, um `test(...)` por surface (`terminal` e `desktop`), mais os 2 casos de `mod-abertura.test.ts` — provado por `claude plugin test .`.

Casos por surface (montando `AbovePrompt` com `hasSurvey`, `isWorking`, `maxRows`, `bodyColumns`, `scroll: { offset: 0, bodyRows }`, `view: {}`): quieta sem fluxo e sem Q; depois de `session.start` e `turn.complete`, `find` acha o titulo do foco, o slug com a etapa e `Q1 Onde o token vive`; `cede a vaga quando hasSurvey`; `isWorking: true` ainda desenha; `press esconder` deixa quieta, a mesma Q no turno seguinte mantem escondida, e Q nova ou agente novo em voo a traz de volta; `process.run` com exit 1 apaga foco e fluxo e a linha da Q fica, sem excecao; `turn.complete` com `agentId` nao mexe na Q, nem com `reason: 'aborted'`, nem com `answer` vazio ou ausente quebrando; com `bodyColumns` 30 cada `Text` cabe em 30 celulas (`largura` de `faixa-puro.mjs`).

Nota: `hooks/testa-mod-faixa.cjs` ganha um caso que le `hooks/mod-faixa.test.tsx` como texto e confere que as chaves do `FIXTURE_DADOS` sao exatamente as da saida real do script (fecha o desvio fixture x producao; nunca pula). Superficie humana: os `find` falham se numero ou titulo da Q, slug ou etapa sumirem da tela.

### 5. Medicao no REPL real: a faixa aparece, esconde e volta [tipo: pesquisar]
atende: D2, D6
arquivos: nenhum
depende de: 4
paralela: nao
mutacao: n/a
  motivo: tarefa de medicao em sessao interativa real; a falsificacao e o controle (faixa quieta sem fluxo e sem Q) e o relato do que apareceu na tela.
pronto quando: com um REPL interativo aberto por `claude --plugin-dir C:\Projetos\rainforest-mind\.claude\worktrees\mod-faixa-foco` onde o fluxo `2026-10-03-mod-faixa-foco` esta em curso, a janela principal cola o texto das linhas que a faixa desenhou mostrando `foco`, `fluxo mod-faixa-foco: <etapa> <ok>/<total>` e, depois de uma resposta com `❓ **Q1 — ...**`, `Q 1 aberta(s)`; a faixa continua visivel durante um turno longo (D6); `esconder` a retira e uma Q nova a traz de volta; num diretorio sem fluxo e sem Q ela nao aparece; e `node scripts/faixa-dados.cjs --cwd C:/Projetos/rainforest-mind` medido com tempo real <= 1,5 s, e `git status --short` sem `tsconfig.json` nem `.claude-plugin/types/` a commitar — provado pelas saidas coladas na evidencia e no PR.

Nota: PARADA 1. Cole tambem o atraso percebido no `session.start` e se o `em_voo` atrasado ate o fim do turno incomoda (decisao B). Script acima de 1,5 s devolve o fluxo ao estagio `plano`.

### 6. Documentacao da faixa [tipo: docs]
atende: D3, D5, D7, D10, D11
arquivos: `CONTRIBUTING.md`, `README.md`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: tarefa de documentacao, sem comportamento a inverter; a falsificacao e a coerencia com o design e com o codigo entregue.
pronto quando: a secao nova "A faixa do mod" em `CONTRIBUTING.md` (depois do paragrafo "Sem mod, o hook entrega o núcleo") diz que a faixa tem no maximo `MAX_LINHAS` linhas (foco, fluxo, Q) cortadas em `bodyColumns`, que so aparece com fluxo em curso ou Q aberta, que o fluxo vem de todos os worktrees por `scripts/faixa-dados.cjs`, que as Q saem do texto final do turno pelos marcadores de `MARCADORES_Q`, que "esconder" vale ate a assinatura mudar, que atualiza em `session.start`, `turn.complete` e ao pressionar, que falha de leitura apaga so a linha afetada e que nao repete a statusline; e o `README.md` acrescenta o requisito (Claude Code 2.1.287+, terminal e desktop, sem mod nada muda) junto do requisito da abertura — provado por um `node -e` que importa `hooks/faixa-puro.mjs`, le `MAX_LINHAS` e `MARCADORES_Q`, extrai do texto os numeros e as formas de marcador, le os eventos de `hooks/mod.tsx` e sai 1 se numero de linhas, marcadores ou os tres gatilhos divergirem do codigo.

Nota: numeros do texto vem do codigo. Nada que a tarefa 5 nao tenha medido. Nao toca o badge de versao.

### 7. Versao 1.38.0, CHANGELOG e fim de lote [tipo: configurar]
atende: D1, D2
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`, `.gitignore`
depende de: 6
paralela: nao
mutacao: n/a
  motivo: tarefa de configuracao de versao; quem prova o efeito e o sensor de versao e a medicao em sessao instalada pelo marketplace, pendente pos-merge.
pronto quando: com a versao 1.38.0 em `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` e no badge do `README.md`, e a nota `## 1.38.0` no topo do `CHANGELOG.md` no commit `Versao 1.38.0: ...` (ultimo do lote), `node scripts/conferir-versao.cjs` sai 0, `node scripts/contrato-plugin-codex.cjs` sai 0 e o diff de `.codex-plugin/plugin.json` contra `197a147a` e so a linha `version` — provado por esses tres comandos.

Nota (emenda pos-tarefa 5): o `.gitignore` ganha `/tsconfig.json` — medido na tarefa 5, `claude --plugin-dir` deixa na raiz um `tsconfig.json` (`extends ./.claude-plugin/types/tsconfig.json`) que nenhuma regra ignora (a pasta `types/` se ignora sozinha); `git check-ignore tsconfig.json` sai 0.

Nota: a nota diz o que o usuario passa a ver (a faixa, o que a acende, o "esconder", o requisito 2.1.287+ e o que acontece sem ele) e que vale na sessao seguinte a atualizacao.

## Cobertura

D1 → 1, 2, 4, 7. D2 → 2, 3, 4, 5, 7. D3 → 2, 4, 6. D4 → 1. D5 → 2, 3, 4, 6. D6 → 3, 4, 5. D7 → 2, 3, 4, 6. D8 → 1. D9 → 1. D10 → 2, 6. D11 → 3, 4, 6.

## Lacunas conhecidas

- O desenho real em REPL (terminal e desktop): `claude plugin test` mostra a arvore e as regras de cada surface, nunca a pintura; so a tarefa 5 le a tela.
- Se `--plugin-dir` deixa `tsconfig.json` e `.claude-plugin/types/` na arvore: a tarefa 5 confere.
- O atraso do `session.start` com o refresh aguardado: estimado em ~0,25 s, medido na tarefa 5.
- Regra de nomes exportados do contrato de tipos: o spike passou com o nome do plugin em PascalCase; `RainforestMind*` e assumido e o validate da tarefa 3 e o sensor.
