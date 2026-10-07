# Plano: enxertar o terminal-desk no mod (barra de sessão, pane `/painel`, mapa e "deixado para depois")

Design: docs/rainforest/design/2026-10-07-desk-no-mod.md

Base: branch `fluxo/desk-no-mod`, HEAD `6e339d12` (só adiciona o design em cima de `99c5e5b7`); `origin/main` = `99c5e5b7`, versão publicada 1.43.0. Destino: a próxima MINOR depois da que estiver em `origin/main` no momento do `fechar` (hoje 1.44.0; se a sessão paralela `regras-inteiras-conta-org` mesclar a 1.44.0 antes, 1.45.0). Claude Code medido: 2.1.292.

## Achados que ajustam o briefing

Medidos pelo planejador em 2026-10-07 num plugin descartável em `$TEMP` (já apagado) e nos tipos que o engine escreve; comandos e saídas na lista de medição entregue junto. `CONFIRMADO` = rodei e colei; `LACUNA` = não foi possível medir daqui.

1. **O `claude` rodado por subagente neste worktree é barrado pelo `hooks/gate-worktree.cjs` do próprio plugin** (rodado do worktree e de `$TEMP` citando o caminho do worktree: `BLOQUEADO ... CLI que escreve (claude) com cd nao resolvido`). `claude plugin validate` e `claude plugin test` só rodaram sobre o plugin descartável em `$TEMP`; `claude -p` e `claude plugin test .` sobre o repo real não rodaram. Consequência: **a forma de toda a API do desk está CONFIRMADA; o comportamento em sessão real (`$.session.usage` devolve breakdown de verdade? o Haiku responde? o sec-default da conta de trabalho barra o quê?) é LACUNA** e só a tarefa 11 mede. As tarefas 6 a 10 rodam `claude plugin test .`, então o `executar` precisa de worktree isolado próprio (regra 11), senão o gate as barra.
2. **A API que o desk usa existe no 2.1.292 com a forma do desk** (CONFIRMADO por `claude plugin validate` no plugin descartável: `./mod.tsx hooks: session.start, command.run{command=sonda}, agent.spawn, turn.step, session.compact, tool.call, turn.complete, ui.render{component=Pane, requestId=sonda}, ui.render{component=AbovePrompt}` e `calls: $.clock.every, $.command.register, $.model.complete, $.prompt.fill, $.session.usage, $.ui.open, $.ui.resolve, $.ui.toast`; e por `claude plugin test` com `(pass)` nos dois surfaces para `command.register`, `command.run`, `session.usage({breakdown:'summary'})`, `model.complete`, `ui.open`, `prompt.fill`, `ui.toast`, `clock.every`, `Pane` com `requestId` e `e.props.view?.agentId` em `Pane` e `AbovePrompt`). `turn.step` como gerador (`async function*` com `return yield* next(e)`), `agent.spawn` (resultado traz `agentId` e `model`), `session.compact` (resultado traz `tokensBefore`/`tokensAfter`) e `tool.call` (resultado traz `deny`/`isError`) foram aceitos pelo `validate` e conferidos nos tipos, mas **não exercitados** no engine de teste: a tarefa 6 os exercita.
3. **O `validate` lista `gating hook without .catch:` para `agent.spawn`, `session.compact` e `tool.call`.** É fato do engine ("um hook que falha ali é pulado"), não aviso: já é a falha aberta da D10. O `verificar` não lê essa linha como erro.
4. **O titular do copyright é `ClariSortAi`, não "GraniteAI" como a D1 escreve.** `LICENSE` do terminal-desk 0.2.1: `Copyright (c) 2026 ClariSortAi`; `.claude-plugin/plugin.json` dele: `"author": { "name": "ClariSortAi" }`; "GraniteAI" é só o site de distribuição (`graniteai.co/tools/terminal-desk`, `README.md` do zip). A tarefa 12 grava o `NOTICE` com o texto do `LICENSE` byte a byte (sha256 normalizado `935f4a47a3df62864088b2d47dd626de09352c9e700792fbf69c6b25536436e9`) e cita o site como origem.
5. **O modelo do checker vai por alias, não por id fixo.** Os tipos do engine (`$.model.complete({ model: "haiku", prompt, effort })`, `claude-code.d.ts:2579`) usam o alias; o id `claude-haiku-4-5-20251001` do desk morre com a próxima geração. O alias aceito em runtime é LACUNA até a tarefa 11 (decisão técnica: `model: 'haiku'`).
6. **`TODO` em maiúscula é palavra portuguesa neste repo.** `hooks/gate-git-verificacao.cjs:67` ("corpo de TODO heredoc"), `hooks/lib/estagio-ativo.cjs:112`, `hooks/testa-config.sh:230`, `hooks/testa-estagio-ativo.cjs:215` e `scripts/conferir-cobertura-fixtures.cjs:34` têm `TODO` como "todo". A regex do desk (`\b(?:TODO|FIXME|XXX)\b`) acusaria as cinco. A tarefa 2 exige o marcador seguido de `:` ou `(`, e essas cinco linhas reais são os controles. Marcador positivo real no repo: nenhum (grep `(TODO|FIXME)\s*[:(]` vazio), então o positivo da bateria é sintético e dito assim.
7. **A comparação do desvio (D14) já existe no repo e tem isentos que o desk não conhece.** `scripts/conferir-fluxo.cjs` exporta `globMatches`, `extrairTarefas` (cada tarefa já traz `arquivos[]`) e `lerMarkdown`; o `cmdCreep` monta, sem exportar, a lista de isentos (design, plano e estado do próprio fluxo, `relatorios/`, `docs/rainforest/reguas/`, varredura, e `skills/<s>/references/` quando o `SKILL.md` está declarado). Sem esses isentos, escrever o próprio design ou plano acenderia a linha vermelha da D15. A tarefa 3 extrai a lista para uma função exportada (`globsIsentos`) usada pelo `cmdCreep` e pelo mod: reuso, nunca cópia.
8. **A tensão do glob (decisão técnica, assumida):** o casamento de glob mora em CJS e o mod roda sem Node. Opções: (a) o mod chama um script Node a cada escrita, em segundo plano; (b) o mod casa só literal em `.mjs`. Escolhida a (a): `scripts/desvio-do-plano.cjs` recebe `--cwd` e `--arquivo` e devolve o veredito; só Edit, Write e NotebookEdit disparam (poucos por turno), sem `await` no `tool.call`; o custo (~0,25 s medido em plano anterior para `faixa-dados.cjs`, que lê os mesmos estados) é medido de novo na tarefa 11. A (b) copiaria `globMatches` para `.mjs`, o que é proibido.
9. **Escrita em worktree de subagente tem de ser relativizada contra a raiz certa.** `git worktree list` mostra 15 worktrees `agent-*` ao lado dos de fluxo (CONFIRMADO), e o `executar` despacha escrita para eles. O script do desvio relativiza o caminho contra a raiz de worktree mais longa que o contém; caminho fora de qualquer worktree do repositório (`~/.claude`, `$TEMP`) vira veredito `fora-da-raiz` e não acusa (decisão técnica: escrever fora do repositório não é desvio de plano).
10. **Mais um evento serve ao desk:** `session.measure` (`claude-code.d.ts:11012`) dispara quando contexto, custo ou limites mexem. Não entra: a D5 cobre o que o desk mede com `turn.complete` mais `session.usage({breakdown:'summary'})`, e adicionar evento é escopo novo. Fica como alternativa para a tarefa 11 se o `turn.complete` medir tarde.
11. **`skill.prompt` e `tool.call{tool:'Skill'}` existem** (`e.skill` na entrada da ferramenta, `claude-code.d.ts:16520`). A D13 usa `tool.call`; skill chamada por barra (`/skill`) pode não passar por ele: INFERIDO, a tarefa 11 confere.
12. **`MultiEdit` não existe no 2.1.292** (zero ocorrências nos tipos): "escrever" da D16 são mesmo `Edit`, `Write` e `NotebookEdit` (entradas `file_path` e `notebook_path`).
13. **Entrada real de `usage` colhida** do transcript desta máquina (`~/.claude-personal/projects/C--Projetos-rainforest-mind/42fa8a5e-dc19-4a78-b86e-05d10364fd47.jsonl`, 1º `assistant` com `usage`): `model: claude-opus-5-5`, `input_tokens: 2`, `cache_creation_input_tokens: 45815`, `cache_read_input_tokens: 30782`, `output_tokens: 273`, cache de 1 h (`ephemeral_1h_input_tokens: 45815`). Casa com a linha `opus-5-5` da tabela de preços do desk. O `usage` de `$.session.usage` não tem fonte real aqui (achado 1): as fixtures dele nascem da forma dos tipos (`SessionContextUsage`, `ContextBreakdownDetail`) e são rotuladas INFERIDO até a tarefa 11 colar o real.
14. **Base verde medida** (sem `claude`, por causa do achado 1): `bash scripts/testa-conferir-fluxo.sh` 102 ok, 0 falhou; `bash scripts/testa-faixa-dados.sh` 14 ok; `node hooks/testa-mod-faixa.cjs` 23 ok; `node hooks/testa-mod-faixa-relogio.cjs` 9 ok; `node hooks/testa-mod-relogio.cjs` 27 ok; `node hooks/testa-mod-abertura.cjs` 28 ok, todos 0 falha(s), 0 skipped. A contagem de base de `claude plugin test .` e o `validate` do repo real foram medidos pela janela principal em 2026-10-07: `claude plugin test .` sai 0 com `24 pass, 0 fail` (2 abertura, 2 faixa, 20 relógio) e o `validate` sai 0 declarando os 7 átomos de estado de hoje.
15. **`scripts/tempos-baterias.json` e `repartir-baterias.cjs` toleram bateria nova sem peso (mediana) e entrada órfã**: nenhuma tarefa mexe nele.

## Decisões técnicas assumidas (sem impacto de produto)

- `session.usage` sempre com `breakdown: 'summary'` (estimativa local); `full` chama a API de contagem a cada turno.
- O relógio é a última figura a cair quando a barra aperta (o usuário só manteve ele), logo depois do estado; as demais caem da direita como no desk.
- O foco sai do JSON de `scripts/faixa-dados.cjs` na tarefa 6, junto com o consumidor, para a base não ficar vermelha entre tarefas.
- `faixa-puro.mjs` continua existindo só como biblioteca de largura em células (`largura`, `cortar`, `semControle`); renomear é escopo à parte.
- Falha de leitura grava uma linha de debug (`painel: <peça>: <erro>`) por `$.ui.log(..., { to: 'debug' })`, que a tarefa 11 lê com `--debug-file`.

## O que não pode quebrar

- **A abertura do mod fica idêntica (D11):** `git diff --quiet 99c5e5b7 -- hooks/register.ts hooks/abertura-mod-puro.mjs hooks/testa-mod-abertura.cjs hooks/mod-abertura.test.ts` sai 0; `node hooks/testa-mod-abertura.cjs` segue `28 ok, 0 falha(s), 0 skipped`; os 2 casos de `mod-abertura.test.ts` seguem passando.
- **`hooks/hooks.json` e `.claude-plugin/plugin.json` não mudam** (a entrada já é `./mod.tsx`, o `types` já está declarado); só a versão do `plugin.json` na tarefa 14. `git diff --quiet 99c5e5b7 -- hooks/hooks.json` sai 0 até lá. Base com `MSYS_NO_PATHCONV=1 git cat-file -p 99c5e5b7:hooks/hooks.json` (conferir saída não vazia).
- **Relógio e nota da regra 8 com o mesmo comportamento (D3):** `hooks/relogio-puro.mjs`, `scripts/relogio-sessoes.cjs` e `scripts/jornada.cjs` não mudam (`git diff --quiet 99c5e5b7 -- <os três>`); `node hooks/testa-mod-relogio.cjs` segue `27 ok`; `hooks/mod-relogio.test.tsx` muda só na parte que lia a faixa (os textos agora saem da barra) e todos os casos dele seguem passando, inclusive a nota por dia, `esconder` que não volta com os minutos (agora por `/painel esconder`), `isInteractive: false` sem timer e `session.end` que cancela.
- **Falha aberta em toda leitura (D10):** `$.session.usage`, `$.model.complete`, `$.ui.open`, `$.process.run` e `$.prompt.fill` recusados, rejeitados ou lentos apagam só a peça afetada; exceção no `ui.render` devolve `next(e)`; `hasSurvey` devolve `next(e)`; o pane e a barra nunca derrubam a sessão.
- **Nenhuma escrita em disco pelo mod:** `grep -cE '\$\.fs|\$\.store' hooks/mod.tsx` devolve 0. O desvio lê estado e plano; o checker não grava; o `$.state` é da sessão.
- **`note_assumption` e `prompt.compose` novo ausentes (D6):** `grep -c "note_assumption" hooks/mod.tsx` devolve 0; `grep -c "prompt.compose" hooks/mod.tsx` devolve 0 (o `prompt.compose` que o `validate` lista vem de `hooks/register.ts`, intacto); `grep -c '\$\.tool\.register' hooks/mod.tsx` devolve 0.
- **Uma faixa só, um dono do slot (D1):** `grep -c "component: 'AbovePrompt'" hooks/mod.tsx` devolve 1.
- **O ambiente do usuário não muda:** nada instalado; `tsconfig.json` na raiz e `.claude-plugin/types/` gerados pelo engine nunca vão para o commit (`git status --short` ao fim de cada tarefa que roda `claude`; `/tsconfig.json` já está no `.gitignore`).
- **Codex não muda:** `.codex-plugin/plugin.json` só muda de versão; `node scripts/contrato-plugin-codex.cjs` passa.
- **`varrer-baterias` não depende do binário `claude`:** lógica em `.mjs`/`.cjs` testada em Node; provas de engine em `*.test.tsx`, sem prefixo `testa-`.
- **`creep` do próprio fluxo continua igual:** `bash scripts/testa-conferir-fluxo.sh` segue `ok: 102   falhou: 0` (mais os casos novos da tarefa 3).
- **`node scripts/conferir-categoria.cjs` segue exit 0:** arquivo novo leva `@categoria` (`bateria` nas baterias, `guia` nos scripts de dados).
- **`claude plugin validate .claude-plugin/plugin.json` sai 0** depois de cada tarefa que toca `hooks/*.mjs|tsx` ou `types/`.

## Contrato dos dados

**Estado do mod** (`$.state`, plugin `rainforest-mind`, contrato em `types/index.d.ts`, só `type` exportado, prefixo `RainforestMind`):
- ficam: `faixaDados` (agora `{ fluxos }`), `relogioJornada`, `relogioSessoes`, `relogioNotaPendente`, `relogioNotaEntregue`;
- saem: `faixaQ`, `faixaOculta` (D2, D9);
- entram: `painelStats` (contadores da sessão: turnos, ferramentas, falhas, tokens novos/lidos do cache/escritos no cache/saída, custo, contexto %, tokens e janela, fatias, carimbos das ferramentas, subagentes, última requisição, modelo, TTL do cache, medir de novo), `painelOculto` (`boolean`, D9), `painelMapa` (arquivos escritos, skills, serviços, subagentes, desvios), `painelDeixado` (itens abertos, `checando`, `checar` ligado, último pedido, ferramentas do turno).

**`node scripts/desvio-do-plano.cjs --cwd <dir> --arquivo <caminho>`** (tarefa 4) → JSON em uma linha, exit 0: `{"veredito":"dentro"|"fora"|"isento"|"sem-fluxo"|"sem-plano"|"fora-da-raiz","rel":"<caminho relativo>"|null,"slug":"<slug>"|null}`. Exit 2 sem `--cwd` ou sem `--arquivo`; exit 1 em erro inesperado (o mod lê qualquer exit ≠ 0 como "sem informação").
- `sem-fluxo`: nenhum fluxo em curso (`etapa !== null`) cujo `worktree` seja a raiz do worktree de `--cwd`; `sem-plano`: fluxo sem `docs/rainforest/planos/<slug>.md`; ambos significam "só lista" (D14).
- `dentro` = `rel` casa por `globMatches` com algum `arquivos:` de alguma tarefa do plano; `isento` = casa com `globsIsentos`; `fora` = nenhum dos dois.

**Linha da barra** (rótulos em português; figuras que não cabem caem da direita, o ⏰ por último): `● trabalhando | ○ pronto`, `Tokens 76.9K`, `Custo $0.42`, `Contexto 0 ━━●──── 100 38%`, `Cache ● quente 50:00 · reenvio $0.02 ($0.61 se esfriar)` ou `Cache ○ frio · reenvio $0.61`, `Deixado 2`, `Ferram./min 3`, `Subagentes 1`, `Turnos 4`, `Erros 0`, `⏰ jornada 9h12 · 20h40`.

## Ordem e paradas

Cadeia: 1 ∥ 2 ∥ 3 ∥ 5 → 4 (depende da 3) → 6 (depende da 1) → 7 → 8 (depende de 4, 5 e 7) → 9 (depende de 2 e 7) → 10 → 11 → 12 → 13 → 14. As tarefas 1, 2, 3 e 5 têm `arquivos:` disjuntos e `depende de: nenhuma`; as demais são `paralela: nao`.
- **PARADA 1, depois da tarefa 10:** a tarefa 11 é medição em REPL real nas duas contas; a bola é do usuário (`claude -p` não desenha UI). Falhou numa conta, volta ao usuário; não se contorna.
- **Pendente pós-merge:** repetir a leitura da tarefa 11 numa sessão instalada pelo marketplace.

## Tarefas

### 1. Lógica pura do painel: cache e preço, fatias, ritmo, formatação e figuras da barra [tipo: implementar]
atende: D3, D5, D12
arquivos: `hooks/painel-puro.mjs`, `hooks/testa-mod-painel.cjs`, `hooks/faixa-puro.mjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-painel.cjs`
mutacao:
  arquivo: `hooks/painel-puro.mjs`
  de: `const quente = restanteMs > 0;`
  para: `const quente = restanteMs >= 0;`
  bateria: `node hooks/testa-mod-painel.cjs`
  fixture: `testa-mod-painel.cjs, caso "cache frio quando o TTL acabou no instante exato e quando nada foi medido"`
pronto quando: com o `usage` real do 1º turno do transcript desta máquina (achado 13: contexto 2+45815+30782 = 76599 tokens, modelo `claude-opus-5-5`, TTL 1 h) `cacheDe({ modelo: "claude-opus-5-5", ctxTokens: 76599, ultimaRequisicaoMs: 1000000, agora: 1600000, ttlMs: 3600000 })` devolve quente com 3000000 ms restantes, reenvio quente `$0.02` e frio `$0.61` (76599 tokens a US$ 4/M, leitura de cache a 5 % e escrita a 2x), com `ultimaRequisicaoMs: 0` devolve frio, e `fatias` reparte 7 células entre 50/30/20 tokens em `[4,2,1]` (maior resto) e soma sempre a largura pedida — provado por `node --input-type=module -e 'import("./hooks/painel-puro.mjs").then(m=>{const c=m.cacheDe({modelo:"claude-opus-5-5",ctxTokens:76599,ultimaRequisicaoMs:1000000,agora:1600000,ttlMs:3600000});const f=m.cacheDe({modelo:"claude-opus-5-5",ctxTokens:76599,ultimaRequisicaoMs:0,agora:1600000,ttlMs:3600000});console.log(JSON.stringify([c.quente,c.restanteMs,m.dinheiro(c.custoQuente),m.dinheiro(c.custoFrio),f.quente,m.fatias([{nome:"a",tokens:50},{nome:"b",tokens:30},{nome:"c",tokens:20}],7)]))})'` imprimindo `[true,3000000,"$0.02","$0.61",false,[4,2,1]]`; e a linha real que `linhaRelogio` (`hooks/relogio-puro.mjs`) devolve para 552 min às 20h40, `⏰ jornada 9h12 · 20h40`, entra em `figurasDaBarra` como figura `relogio`: com 40 colunas a soma de `largura` das figuras mantidas é <= 40 e o relógio é a última a cair, com 200 colunas todas as figuras cabem, e o `⏰` conta 2 células — provado por `node hooks/testa-mod-painel.cjs`, que importa os dois `.mjs` reais e cobre ritmo por minuto (só carimbos de até 60 s), `dinheiro` (`<$0.01`, `$1.23`, `--`), `compacto` (`999`, `76.9K`, `1.20M`), preço pela primeira linha que casa (`fable-5-1` antes de `fable`, `opus-5-5` antes de `opus`, modelo desconhecido sem preço), TTL de 5 min com escrita a 1,25x, e `semControle` aplicado ao nome de subagente.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, dentro de `cacheDe` (`restanteMs` = `ultimaRequisicaoMs === 0 ? 0 : Math.max(0, ultimaRequisicaoMs + ttlMs - agora)`); nenhum caso de teste afirma sobre o texto do fonte. Reaproveita a tabela de preços e as fórmulas do desk (`register.tsx:30-42`, `226-263`) com o crédito da tarefa 12; as cotações são as do desk de 2026-09-25 e não foram conferidas (Lacuna). `faixa-puro.mjs` só ganha `export` em `cortar` e `semControle` (aditivo: `painel-puro.mjs` importa `largura`, `cortar` e `semControle` de lá, nunca copia). Sem `$`, sem Node, sem `Date.now()` (`agora` por argumento). Superfície humana: a barra é o que a pessoa lê para decidir se segue ou compacta; a bateria falha se estado, custo, contexto %, estado do cache ou o relógio sumirem da lista de figuras. `// @categoria: bateria` na bateria nova.

### 2. Lógica pura do "deixado para depois": frases em português e inglês, marcadores e prompt do checker [tipo: implementar]
atende: D7, D12
arquivos: `hooks/deixado-puro.mjs`, `hooks/testa-mod-deixado.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-deixado.cjs`
mutacao:
  arquivo: `hooks/deixado-puro.mjs`
  de: `.filter(parte => parte.length > 12 && DITO.test(semCitacao(parte)))`
  para: `.filter(parte => parte.length > 12 && DITO.test(parte))`
  bateria: `node hooks/testa-mod-deixado.cjs`
  fixture: `testa-mod-deixado.cjs, caso "frase entre aspas ou crase nao conta como adiamento"`
pronto quando: com as linhas reais do repo como texto de resposta, `deferimentos` acha 1 adiamento em `docs/rainforest/design/LEIA-PRIMEIRO-CONSOLIDADO-v2.md:111` ("9. **Fluxo 4 (território)** fica para depois do núcleo estável —") e 1 em `referencias/advpl-graph/HANDOVER-advpl-graph.md:60` ("... sem HTML bonito por enquanto; INDEX.md + graph.json bastam"), 0 nas linhas 33 e 34 de `docs/rainforest/design/2026-10-07-desk-no-mod.md` (as mesmas frases, mas entre aspas: `("por enquanto", "não rodei", "fica para depois", "próxima fase", "placeholder"…)`), e `marcadoresEmArquivo` acha 0 em `hooks/gate-git-verificacao.cjs:67` ("corpo de TODO heredoc", `TODO` como palavra portuguesa, achado 6) — provado por `node --input-type=module -e 'import("./hooks/deixado-puro.mjs").then(async m=>{const fs=await import("node:fs");const l=(f,n)=>fs.readFileSync(f,"utf8").split(/\r?\n/)[n-1];const d="docs/rainforest/design/2026-10-07-desk-no-mod.md";console.log(JSON.stringify([m.deferimentos(l("docs/rainforest/design/LEIA-PRIMEIRO-CONSOLIDADO-v2.md",111)).length,m.deferimentos(l("referencias/advpl-graph/HANDOVER-advpl-graph.md",60)).length,m.deferimentos(l(d,33)+" "+l(d,34)).length,m.marcadoresEmArquivo(l("hooks/gate-git-verificacao.cjs",67)).length]))})'` imprimindo `[1,1,0,0]`; e a bateria cobre, além disso, o positivo em inglês ("I haven't run the tests yet"), "não rodei" com e sem acento, bloco de código ignorado, no máximo 3 por resposta, `marcadoresEmArquivo` com `// TODO: tratar timeout` (sintético: não existe marcador positivo real no repo), `FIXME(ana)`, `.skip(`, e o prompt do checker (`montarPromptChecker`) que leva o pedido, o fim do relato (últimos 6000 caracteres) **e a lista de ferramentas do turno com as falhas** (`Bash x12 (2 erros)`, `Edit x3`, `Write x1 (1 negada)`), em português, pedindo no máximo 3 linhas começando por verbo e a palavra `NENHUM` quando não houver nada, e `lerRespostaChecker("NENHUM")` vazio.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, na pipeline de `deferimentos`; `semCitacao` tira o que está entre aspas retas, aspas curvas e crases e normaliza acento e caixa. Exporta `CHECAR_MIN_FERRAMENTAS` (5), `deferimentos`, `marcadoresEmArquivo`, `resumirFerramentas`, `montarPromptChecker`, `lerRespostaChecker`, `rascunhoFazAgora` (rascunho em português, nunca enviado sozinho). Frases e marcadores partem das regex do desk (`register.tsx:87-101`) com o crédito da tarefa 12. Superfície humana: o item que a pessoa lê traz a frase (até 200 caracteres) e a origem (`Claude disse`, `em arquivo`, `segundo modelo`); a bateria falha se a frase sumir. Zero `skipped`; `// @categoria: bateria`.

### 3. Isentos do fluxo exportados e `lerFluxos` reutilizável [tipo: implementar]
atende: D4, D14, D15
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/faixa-dados.cjs`, `scripts/testa-conferir-fluxo.sh`, `scripts/testa-faixa-dados.sh`
depende de: nenhuma
paralela: sim
prova: `node -e "process.exit(typeof require('./scripts/conferir-fluxo.cjs').globsIsentos==='function'?0:1)"`
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `docs/rainforest/estado/${slug}.json`,
  para: `docs/rainforest/estado/nunca-${slug}.json`,
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: `testa-conferir-fluxo.sh, caso "globsIsentos inclui o estado do proprio fluxo"`
pronto quando: com o slug real `2026-10-07-desk-no-mod` e o `SKILL.md` real `skills/limpar/SKILL.md` como glob de tarefa, `globsIsentos` devolve a lista com o estado do fluxo, `relatorios/` e `skills/limpar/references/`; com `require('./scripts/faixa-dados.cjs')` o módulo exporta `lerFluxos` e `worktrees` e **não imprime nada**, e `node scripts/faixa-dados.cjs --cwd .` continua imprimindo o JSON de antes — provado por `node -e 'const g=require("./scripts/conferir-fluxo.cjs").globsIsentos({slug:"2026-10-07-desk-no-mod",design:null,plano:null,globsDoPlano:["skills/limpar/SKILL.md"]});console.log(JSON.stringify([g.includes("docs/rainforest/estado/2026-10-07-desk-no-mod.json"),g.includes("relatorios/"),g.includes("skills/limpar/references/")]))'` imprimindo `[true,true,true]`, por `node -e 'const d=require("./scripts/faixa-dados.cjs");console.log(typeof d.lerFluxos,typeof d.worktrees)'` imprimindo exatamente `function function`, e por `bash scripts/testa-conferir-fluxo.sh` terminando em `ok: 102   falhou: 0` mais os casos novos (o `creep` do repo real continua igual: refatoração sem mudar comportamento).

Nota: o `de:` já existe em `scripts/conferir-fluxo.cjs` (uma ocorrência) e passa a morar em `globsIsentos`; o `cmdCreep` chama a função nova, e a lista de isentos continua a mesma, em ordem e conteúdo. Contrato de `globsIsentos({ slug, design, plano, globsDoPlano })`: `design` e `plano` são caminhos relativos reais quando vieram por `--design`/`--plano` (como hoje, `rel(...)`), `null` cai nos nomes derivados do slug. `faixa-dados.cjs` ganha `if (require.main === module) main();` e `module.exports = { lerFluxos, worktrees }` (hoje `main()` roda no `require`, sem guarda); `foco` **fica** no JSON até a tarefa 6. A bateria nova de `testa-faixa-dados.sh` confere o `require` mudo.

### 4. Script do desvio: arquivo escrito contra os `arquivos:` do plano do fluxo [tipo: implementar]
atende: D14, D15, D16
arquivos: `scripts/desvio-do-plano.cjs`, `scripts/testa-desvio-do-plano.sh`
depende de: 3
paralela: nao
prova: `bash scripts/testa-desvio-do-plano.sh`
mutacao:
  arquivo: `scripts/desvio-do-plano.cjs`
  de: `return !permitidos.some((glob) => globMatches(rel, glob));`
  para: `return false;`
  bateria: `bash scripts/testa-desvio-do-plano.sh`
  fixture: `testa-desvio-do-plano.sh, caso "arquivo fora dos arquivos do plano e acusado"`
pronto quando: com o plano real `docs/rainforest/planos/2026-10-03-mod-faixa-foco.md` (copiado por `git show` para um repo temporário com `git init`, um `git worktree add` e um estado em `executar`, a fonte de `arquivos:`: `hooks/faixa-puro.mjs`, `hooks/mod.tsx`, `README.md`, `.gitignore` e `scripts/faixa-dados.cjs` entre as declaradas) o script devolve `dentro` para `hooks/faixa-puro.mjs` e `README.md`, `fora` para `scripts/estado.cjs` e `tsconfig.json`, `isento` para o design e o plano do próprio slug, `fora-da-raiz` para um arquivo em `$TEMP`, `sem-fluxo` num diretório sem fluxo em curso e `sem-plano` num fluxo sem arquivo de plano, e relativiza um `file_path` absoluto de Windows (barras invertidas, drive em caixa diferente) e um caminho dentro de um worktree `agent-*` contra a raiz certa; e neste worktree real, depois de o plano estar gravado, `node scripts/desvio-do-plano.cjs --cwd C:/Projetos/rainforest-mind/.claude/worktrees/desk-no-mod --arquivo C:/Projetos/rainforest-mind/.claude/worktrees/desk-no-mod/hooks/painel-puro.mjs` imprime `"veredito":"dentro"`, com `.../scripts/conferir-prova.cjs` imprime `"veredito":"fora"` e com `.../docs/rainforest/design/2026-10-07-desk-no-mod.md` imprime `"veredito":"isento"` — provado por esses três comandos mais `bash scripts/testa-desvio-do-plano.sh` com os casos acima (zero `skipped`, a bateria nunca lê o `~/.rainforest` vivo: `HOME`, `USERPROFILE` e `RFM_ROOT` em caixas).

Nota: o `de:` é a forma de `foraDoPlano` (uma função, uma expressão final, sem print e sem ramo); a tarefa o escreve uma vez só e nenhum caso afirma sobre o texto do fonte. Reusa, nunca copia: `lerFluxos` e `worktrees` (tarefa 3), `extrairTarefas`, `lerMarkdown` e `globMatches` (já exportados), `globsIsentos` (tarefa 3). A raiz do worktree de `--cwd` sai de `git rev-parse --show-toplevel` por `spawnSync` com `cwd` e `status === 0` conferido (um `git -C` fora de repo sobe para o pai em silêncio). `arquivos: nenhum` de uma tarefa contribui com lista vazia. Somente leitura, sem `gh`; `// @categoria: guia`.

### 5. Lógica pura do mapa da sessão: escrita, skill, serviço MCP e subagente [tipo: implementar]
atende: D12, D13, D16
arquivos: `hooks/mapa-puro.mjs`, `hooks/testa-mod-mapa.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-mapa.cjs`
mutacao:
  arquivo: `hooks/mapa-puro.mjs`
  de: `if (!ESCRITORAS.has(e.tool)) return null;`
  para: `if (false) return null;`
  bateria: `node hooks/testa-mod-mapa.cjs`
  fixture: `testa-mod-mapa.cjs, caso "ler nao entra em arquivos escritos: Read e Bash devolvem nulo"`
pronto quando: com chamadas de ferramenta no formato do `tool.call` do engine (`tool` mais os argumentos ao lado, achado 12) `escritaDe` devolve `null` para `{ tool: "Read", file_path: "hooks/mod.tsx" }` e para `{ tool: "Bash", command: "echo oi > x.txt" }` (D16: escrita por Bash fica fora e o painel diz isso), devolve o caminho de `{ tool: "Write", file_path: "hooks/mod.tsx", content: "x" }`, de `Edit` e o `notebook_path` de `NotebookEdit`, e `servidorDe("mcp__claude_ai_Claude_Docs__guide")` (nome real de uma ferramenta MCP desta sessão) devolve `claude_ai_Claude_Docs` e `null` para `Bash` — provado por `node --input-type=module -e 'import("./hooks/mapa-puro.mjs").then(m=>console.log(JSON.stringify([m.escritaDe({tool:"Read",file_path:"hooks/mod.tsx"}),m.escritaDe({tool:"Write",file_path:"hooks/mod.tsx",content:"x"}),m.servidorDe("mcp__claude_ai_Claude_Docs__guide"),m.servidorDe("Bash")])))'` imprimindo `[null,"hooks/mod.tsx","claude_ai_Claude_Docs",null]`; e `node hooks/testa-mod-mapa.cjs` cobre `registrar` (arquivo repetido conta uma vez e devolve `novo: false` na 2ª escrita, skill pelo campo `skill`, subagente pelo `description` do `agent.spawn`, teto de entradas por categoria, lista que não perde o desvio já marcado) e `semControle` no que vem de caminho.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, na 1ª linha de `escritaDe`; `ESCRITORAS` é `Set(['Edit','Write','NotebookEdit'])`. Sem `$`, sem Node, sem `Date.now()`. `registrar(mapa, evento)` é puro e devolve `{ mapa, novo }`; quem marca desvio é o mod (tarefa 8). Superfície humana: o painel precisa mostrar o caminho completo ou o fim dele, o servidor e o nome da skill; a bateria falha se qualquer um sumir. `// @categoria: bateria`.

### 6. Fiação da barra: ela substitui a faixa, `/painel esconder|mostrar|cache`, foco e Q fora [tipo: implementar]
atende: D1, D2, D3, D5, D6, D8, D9, D10, D11
arquivos: `hooks/mod.tsx`, `types/index.d.ts`, `hooks/faixa-puro.mjs`, `hooks/testa-mod-faixa.cjs`, `hooks/testa-mod-faixa-relogio.cjs`, `hooks/mod-faixa.test.tsx`, `hooks/mod-painel.test.tsx`, `hooks/mod-relogio.test.tsx`, `hooks/testa-mod-painel.cjs`, `scripts/faixa-dados.cjs`, `scripts/testa-faixa-dados.sh`
depende de: 1
paralela: nao
prova: `grep -q "painelStats" types/index.d.ts`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `await update($, painelOculto, () => palavra === 'esconder')`
  para: `await update($, painelOculto, () => palavra !== 'esconder')`
  bateria: `claude plugin test .`
  fixture: `mod-painel.test.tsx, caso "barra (<surface>): esconder e mostrar"`
pronto quando: com o `usage` real do achado 13 entregue em `turn.complete` (`input_tokens` 2, `cache_creation_input_tokens` 45815, `cache_read_input_tokens` 30782, `output_tokens` 273, `model` `claude-opus-5-5`), o `session.usage` respondido por `on('session.usage')` com a forma dos tipos (INFERIDO: 76599 tokens, janela 200000, 38 %, custo US$ 0,42, rótulo da fixture no código) e `mock.clock(on, { now })` 10 min depois, `claude plugin test .` sai 0 com `(pass)` e 0 fail, um `test(...)` por surface (`terminal` e `desktop`): a barra desenha `Tokens` com `76.9K`, `Custo` com `$0.42`, `38%`, `Cache` com `quente 50:00` e `$0.02`/`$0.61`, `● trabalhando` com `isWorking: true` e `○ pronto` sem ele, `Erros` 1 depois de um `tool.call` com `isError`, `Subagentes` 1 depois de um `agent.spawn` e 0 depois do `turn.complete` do `agentId`; com `view: { agentId }` desenha a barra do subagente (nome, status, ferramentas, tokens) e o contexto da sessão principal; o relógio aparece como figura `⏰ jornada 9h12 · 20h40` (os casos de `mod-relogio.test.tsx` seguem passando, lendo agora a barra); `/painel esconder` deixa a barra quieta e `/painel mostrar` a traz de volta, e a mesma Q numa resposta não acende nada (D2: nenhuma linha de foco, fluxo ou Q); `/painel cache 5m` muda o TTL e a estimativa de reenvio (escrita a 1,25x); `hasSurvey` devolve `next(e)`; `process.run` e `session.usage` falhando apagam só a figura afetada; `session.compact` com `tokensAfter` mostra o contexto novo na hora e pede medição nova; com 40 colunas cada `Text` cabe e o `⏰` é o último a cair — provado por `claude plugin test .`; `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista `turn.step`, `tool.call`, `agent.spawn`, `session.compact`, `$.clock.every`, `$.session.usage`, `$.command.register` e `declares state:` com `painelStats` e `painelOculto` e **sem** `faixaQ` nem `faixaOculta`; `grep -c "note_assumption" hooks/mod.tsx` e `grep -c "prompt.compose" hooks/mod.tsx` devolvem 0; `node hooks/testa-mod-painel.cjs`, `node hooks/testa-mod-relogio.cjs` (27 ok) e `bash scripts/testa-faixa-dados.sh` (sem o caso do foco) seguem verdes, `git diff --quiet 99c5e5b7 -- hooks/register.ts hooks/abertura-mod-puro.mjs hooks/testa-mod-abertura.cjs hooks/mod-abertura.test.ts hooks/hooks.json` sai 0 e `git status --short` não mostra `tsconfig.json` nem `.claude-plugin/types/`.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, no ramo de `esconder` e `mostrar` do `command.run` (`palavra` = `` `${e.args ?? ''}`.trim().toLowerCase() ``). O mod chama as funções puras só com valores (o engine recusa `$` como argumento de função própria; `buscar`, `medir` e `registrar` seguem o molde de `buscar(io)` com `io = { rodar, cwd, raiz }` montado no ponto de chamada). Sai (D2, D9): `extrairQs`, `MARCADORES_Q`, `montarLinhas`, `MAX_LINHAS`, `assinatura`, `escondida`, o campo foco do desenho, o botão "esconder", `faixaQ` e `faixaOculta`, a limpeza das Q no `prompt.submit` (a nota da regra 8 desse hook fica byte a byte) e `hooks/testa-mod-faixa-relogio.cjs` (o objeto dele, `montarLinhas` com relógio, deixou de existir; os casos do relógio na barra migram para `testa-mod-painel.cjs`); `hooks/testa-mod-faixa.cjs` perde os casos das funções removidas e fica com `largura`, `cortar` e `semControle`; `hooks/mod-faixa.test.tsx` é renomeado `hooks/mod-painel.test.tsx` e reescrito. `scripts/faixa-dados.cjs` deixa de ler o foco (`lerFoco`, `resolverRaiz` e `tituloDoFocoAtivo` saem do script, a chave `foco` sai do JSON) e o caso 4 da bateria muda junto; um caso novo em `testa-mod-painel.cjs` confere que as chaves da `FIXTURE_DADOS` de `mod-painel.test.tsx` são exatamente as da saída real do script (fecha o desvio fixture x produção, nunca pula). O `/painel` registra o comando em `session.start`, responde com `{ text }` e usa o `command.run` com matcher. `assinaturaRelogio` fica sem chamador no mod, só nas baterias do relógio (Lacuna). Medição: `breakdown: 'summary'`, no `turn.complete` da sessão principal e quando `precisaMedir` (depois de `session.compact`). Hook que falha apaga só a peça e grava `painel: <peça>: <erro>` no debug. Superfície humana: o que a pessoa vê na barra para decidir compactar ou esperar é contexto %, cache quente ou frio com o custo de reenvio, custo e erros, e os `find` falham se qualquer um sumir.

### 7. Fiação do pane `/painel`: contexto por fatia, cache, subagentes, custo e fluxos em curso [tipo: implementar]
atende: D4, D5, D8, D10
arquivos: `hooks/mod.tsx`, `types/index.d.ts`, `hooks/mod-painel.test.tsx`
depende de: 6
paralela: nao
prova: `grep -q "id: 'painel'" hooks/mod.tsx`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `const celulas = fatias(desenhadas, interior);`
  para: `const celulas = fatias(desenhadas, interior + 1);`
  bateria: `claude plugin test .`
  fixture: `mod-painel.test.tsx, caso "pane (<surface>): a barra de contexto soma exatamente a largura interna"`
pronto quando: com o `/painel` sem argumento respondido por `command.run` (abre `$.ui.open({ id: 'painel', title: 'Esta sessão' })`, mede o contexto e devolve `{ text }`), o `session.usage` com três categorias `used` (50/30/20 em tokens, nomes de fixture) mais `free` e `buffer` no formato do `get_context_usage` dos tipos (INFERIDO até a tarefa 11), a saída REAL de `scripts/faixa-dados.cjs` sobre repo temporário (um fluxo em `executar` 1/3 com um agente em voo) servida por `on('process.run')`, e `Pane` montado em cada surface (`requestId: 'painel'`, `placement`, `bodyColumns` 80): `claude plugin test .` sai 0 com 0 fail e o pane mostra os painéis "Fluxos em curso" (slug sem data, etapa, `1/3`, `1 em voo`), "Onde foi o contexto" (uma barra cujas células somam a largura interna, a legenda com nome, `compacto` e %, `+ N em ferramentas sob demanda`), "Cache de prompt" (quente ou frio, custo da próxima mensagem quente e fria, e a frase `Estimativa: reenvio da conversa a preço de lista, cache de 5m|1h`), "Subagentes" e "Custo e tokens" (custo, lidos, % servida do cache, escritos, turnos); com `view: { agentId }` o pane é o do subagente e diz que contexto e cache são da sessão principal; `ui.open` recusado (`{ value: { isPlaced: false } }`) ou `session.usage` rejeitado ainda devolvem `{ text }` do comando e o pane diz "Medição indisponível" em vez de ficar em branco; um subcomando desconhecido (`/painel xyz`) devolve `{ text }` com a lista de subcomandos (`esconder`, `mostrar`, `cache 5m|1h`, `checar ligar|desligar`) — provado por `claude plugin test .`; `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista `$.ui.open` e `ui.render{component=Pane, requestId=painel}`.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, no painel de contexto, com `interior = Math.max(16, e.props.bodyColumns - 4)`. Reaproveita `fatias` (tarefa 1). O painel "Fluxos em curso" lê `faixaDados` (atualizado em `session.start`, `turn.complete` e ao abrir o pane). Os painéis "Mapa da sessão" e "Deixado para depois" entram nas tarefas 8 e 9. Superfície humana: a pessoa abre o pane para entender onde foi o contexto e quanto custa esperar; os `find` falham se o nome de uma fatia, o % ou o custo do reenvio sumirem.

### 8. Mapa da sessão e desvio do plano no pane: linha vermelha e um toast por arquivo [tipo: implementar]
atende: D13, D14, D15, D16, D10
arquivos: `hooks/mod.tsx`, `types/index.d.ts`, `hooks/mod-painel.test.tsx`
depende de: 4, 5, 7
paralela: nao
prova: `grep -q "desvio-do-plano.cjs" hooks/mod.tsx`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `if (desvio.veredito === 'fora' && marcado.novo) {`
  para: `if (desvio.veredito === 'fora') {`
  bateria: `claude plugin test .`
  fixture: `mod-painel.test.tsx, caso "mapa (<surface>): um toast por arquivo, nao por escrita"`
pronto quando: com o plano real `docs/rainforest/planos/2026-10-03-mod-faixa-foco.md` como fonte dos `arquivos:` (servido pela saída REAL de `scripts/desvio-do-plano.cjs` sobre repo temporário, colada como fixture e servida por `on('process.run')` conforme o `argv`), `tool.call` de `Write` em `hooks/faixa-puro.mjs` (veredito `dentro`), de `Edit` em `scripts/estado.cjs` duas vezes (veredito `fora`), de `Read` em `hooks/mod.tsx`, de `Bash`, de `mcp__claude_ai_Claude_Docs__guide` e de `Skill` com `skill: "plano"`, e um `agent.spawn` com `description` "revisar o diff", `claude plugin test .` sai 0 com 0 fail nos dois surfaces e o pane "Mapa da sessão" lista os dois arquivos escritos (o fora do plano em vermelho, `scripts/estado.cjs` aparecendo uma vez), a skill `plano`, o serviço `claude_ai_Claude_Docs` e o subagente, **não lista** o `Read` nem o `Bash`, e diz na própria tela que escrita por Bash não é detectada (D16); `$.ui.toast` é chamado uma única vez para `scripts/estado.cjs` mesmo com as duas escritas (D15), nenhum `prompt.submit` nem `context` sai do desvio (nada vai ao modelo); fora de fluxo (veredito `sem-fluxo`) o mapa lista e nada fica vermelho nem gera toast; script com exit 1, JSON inválido ou `process.run` rejeitado não acusam nada e não quebram o `tool.call` — provado por `claude plugin test .`; o `tool.call` devolve o resultado de `next(e)` sem esperar o script (o teste faz o `process.run` do desvio demorar com `relogio.sleep` e confere que o resultado da ferramenta chega antes); `grep -c "desvio-do-plano" hooks/mod.tsx` devolve pelo menos 1 e `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista `$.ui.toast` e `tool.call`.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, no tratamento da resposta do script; `marcado` é o retorno de `registrar` (tarefa 5), `desvio` o JSON lido. Disparo só para escrita (`escritaDe` não nulo e sem `deny`/`isError`), em segundo plano: `$.process.run(['node', raiz + '/scripts/desvio-do-plano.cjs', '--cwd', cwd, '--arquivo', caminho], ...)` com `timeoutMs` 5000 e `.catch` que grava `painel: desvio: <erro>` no debug. O desvio nunca vai ao modelo (D15). Superfície humana: o pane mostra o caminho relativo, o veredito e, em vermelho, o motivo "fora dos arquivos do plano"; os `find` falham se o caminho ou a marca vermelha sumirem.

### 9. "Deixado para depois" com checker Haiku que vê as ferramentas do turno [tipo: implementar]
atende: D7, D8, D10
arquivos: `hooks/mod.tsx`, `types/index.d.ts`, `hooks/mod-painel.test.tsx`
depende de: 2, 7
paralela: nao
prova: `grep -q "deixado-puro.mjs" hooks/mod.tsx`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `const deveChecar = ligado && ferramentas.length >= CHECAR_MIN_FERRAMENTAS && pedido !== '';`
  para: `const deveChecar = ligado && pedido !== '';`
  bateria: `claude plugin test .`
  fixture: `mod-painel.test.tsx, caso "checker (<surface>): so com 5 ou mais ferramentas"`
pronto quando: com o texto REAL de `docs/rainforest/design/LEIA-PRIMEIRO-CONSOLIDADO-v2.md:111` ("9. **Fluxo 4 (território)** fica para depois do núcleo estável —") como `answer` de um `turn.complete` com `reason: 'answer'` depois de um `prompt.submit` do composer com o pedido "me diga o status do fluxo 4", `claude plugin test .` sai 0 com 0 fail nos dois surfaces: a varredura acha 1 item, o pane "Deixado para depois" mostra a frase com a origem `Claude disse` e o botão "Faz agora" preenche o prompt com o rascunho em português (`$.prompt.fill`, modo `append`, o teste confere o texto e que nada é enviado); com 4 ferramentas no turno `model.complete` **não** é chamado, com 5 é chamado uma vez, com `model: 'haiku'`, o pedido, o fim do relato e a lista de ferramentas com as falhas (`Bash x3 (1 erro)`, `Edit x2`) no `prompt`, e uma resposta `Rodar a bateria da tarefa 2` vira um item com origem `segundo modelo` e um toast `Deixado para depois: ...`, enquanto `NENHUM` não gera nada; um `Write` cujo `content` traz `// TODO: tratar timeout` vira item `em arquivo` e o mesmo `Write` com `TODO heredoc` (palavra portuguesa, achado 6) não; `/painel checar desligar` impede a chamada e `/painel checar ligar` a restaura; `model.complete` com `{ isAnswered: false }` não gera item nem toast e grava `painel: checker: ...` no debug; a mensagem do turno de subagente (`agentId`) não dispara varredura nem checker — provado por `claude plugin test .`; `claude plugin validate .claude-plugin/plugin.json` sai 0 e lista `$.model.complete` e `$.prompt.fill`.

Nota: o `de:` é texto que a tarefa escreve, uma vez só, na decisão de checar; `ferramentas` é a lista que o `tool.call` acumula no turno da sessão principal (nome e `deny`/`isError`, sem entrada da ferramenta), zerada no `turn.complete`. A chamada ao modelo não é aguardada (`.catch` registra no debug), com `timeoutMs` 30000 e `maxTokens` 300; `checando` sobe antes e desce no `finally` por uma linha só (alvo da mutação da tarefa 10). O `prompt.submit` guarda o pedido (até 4000 caracteres) só para `origin` ausente ou `composer`/`bridge`/`sdk`, sem mexer na nota da regra 8. Sem `prompt.compose` e sem `$.tool.register` (D6). Superfície humana: o item traz a frase e a origem, e o botão diz o que vai acontecer ("Faz agora" só preenche o prompt).

### 10. Prova de engine transversal: falha aberta, subagente, duas surfaces e negativos da D6 e D11 [tipo: teste]
atende: D1, D3, D6, D10, D11
arquivos: `hooks/mod-painel.test.tsx`, `hooks/mod-relogio.test.tsx`
depende de: 8, 9
paralela: nao
prova: `grep -q "falha aberta" hooks/mod-painel.test.tsx`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `await update($, painelDeixado, (d) => ({ ...d, checando: false }));`
  para: `await update($, painelDeixado, (d) => ({ ...d }));`
  bateria: `claude plugin test .`
  fixture: `mod-painel.test.tsx, caso "falha aberta (<surface>): model.complete rejeita e o pane para de dizer checando"`
pronto quando: com os dados REAIS dos casos anteriores (a saída real de `faixa-dados.cjs`, a do `desvio-do-plano.cjs`, o `usage` real do achado 13) e o mundo por baixo recusando uma peça de cada vez, `claude plugin test .` sai 0 com 0 fail e um `test(...)` por surface cobrindo: `process.run` com exit 1 (apaga fluxos e desvio, barra segue), `session.usage` rejeitando (a figura de contexto some, o resto da barra fica, o pane diz "Medição indisponível"), `model.complete` rejeitando como faria o sec-default (nenhum toast, nenhuma exceção, `checando` volta a falso), `ui.open` recusando (o comando ainda devolve `{ text }`), `prompt.fill` recusando (o botão "Faz agora" não derruba o pane), `ui.render` do `AbovePrompt` lançando (devolve `next(e)`), subagente em tela (`view.agentId`) na barra e no pane, `isInteractive: false` sem timer do relógio e sem `process.run` do painel, `session.end` cancelando os timers, `bodyColumns` 30 com cada `Text` em 30 células, e os dois surfaces com os mesmos resultados; os 20 casos de `mod-relogio.test.tsx` (10 por surface) e os 2 de `mod-abertura.test.ts` seguem passando — provado por `claude plugin test .`; negativos: `grep -c "note_assumption" hooks/mod.tsx`, `grep -c "prompt.compose" hooks/mod.tsx`, `grep -c '\$\.tool\.register' hooks/mod.tsx` e `grep -cE '\$\.fs|\$\.store' hooks/mod.tsx` devolvem 0, `grep -c "component: 'AbovePrompt'" hooks/mod.tsx` devolve 1, o `claude plugin validate .claude-plugin/plugin.json` lista `prompt.compose` exatamente uma vez (o de `register.ts`) e não lista `tool.register` nem chamada a `$.fs`, e `git diff --quiet 99c5e5b7 -- hooks/register.ts hooks/abertura-mod-puro.mjs hooks/testa-mod-abertura.cjs hooks/mod-abertura.test.ts hooks/hooks.json` sai 0.

Nota: o `de:` é a linha que a tarefa 9 escreve (uma vez só); esta tarefa só acrescenta o caso que a deixa vermelha, e `mod-relogio.test.tsx` só é editado se o caso transversal precisar do mesmo mundo. O engine de teste exige fundo para cada evento chamado (medido no plugin descartável): `command.register` responde `{ value: { command } }`, `ui.open` e `session.usage` e `model.complete` respondem `{ value: ... }`, `prompt.fill` responde `{ isFilled: true }` **sem** `value`, `clock.every` só existe com `mock.clock(on, { now })`, e as props do `Pane` são `title`, `isFocused`, `bodyColumns`, `placement: 'dock' | 'inline'`, `scroll` e `view`. Um `test(...)` por surface porque `$.state` dura a sessão de teste inteira.

### 11. Medição no REPL real nas duas contas: a barra desenha, o `/painel` abre, o Haiku responde, o `usage` responde [tipo: pesquisar]
atende: D5, D7, D10, D13, D14
arquivos: nenhum
depende de: 10
paralela: nao
mutacao: n/a
  motivo: tarefa de medição em sessão interativa real, nas duas contas; a falsificação é o controle (a barra some com `/painel esconder`, o mapa vazio fora de fluxo, sem toast) e o relato do que apareceu na tela e no log de debug.
pronto quando: com REPLs interativos abertos por `claude --plugin-dir C:\Projetos\rainforest-mind\.claude\worktrees\desk-no-mod --debug-file <log>` uma vez com `CLAUDE_CONFIG_DIR=C:\Users\Luis\.claude-personal` e outra com `CLAUDE_CONFIG_DIR=C:\Users\Luis\.claude`, o usuário cola, para cada conta, o texto da barra depois de um turno com 5 ou mais ferramentas (estado, `Tokens`, `Custo`, `Contexto`, `Cache`, `Erros` e o `⏰` quando aceso), o pane do `/painel` com as fatias de contexto e o painel "Fluxos em curso", o resultado de `/painel cache 5m` e de `/painel esconder`, uma resposta que diga "fica para depois" (ou a pergunta "me diga o que fica para depois do núcleo estável") com o item aparecendo, a decisão do Haiku (item `segundo modelo` ou o `painel: checker: ...` do log), um `Edit` num arquivo fora dos `arquivos:` do plano com a linha vermelha e um único toast, uma escrita num arquivo dentro do plano sem acusação, e um `Skill` chamado pelo modelo e outro chamado por `/skill` (acha se a segunda aparece no mapa, achado 11); mais as linhas `painel:` do log de debug (`grep -a "painel:" <log>`) e, em cada conta, a resposta de `$.session.usage` observável na tela (se falhar, a linha de debug com o erro); e `time node scripts/desvio-do-plano.cjs --cwd <worktree> --arquivo <arquivo>` com tempo real <= 1,5 s, `time node scripts/faixa-dados.cjs --cwd <worktree>` <= 1,5 s, `git status --short` sem `tsconfig.json` nem `.claude-plugin/types/` a commitar — provado pelas saídas coladas na evidência e no PR; **cada peça que a conta de trabalho (sec-default) barrar vira linha da tabela "o que a conta de trabalho barra", não vira falha do fluxo (D10)**.

Nota: PARADA 1 (a bola é do usuário). Cole também o atraso percebido ao abrir o `/painel`, o atraso do toast depois da escrita, e se o `claude --plugin-dir` deixou `tsconfig.json` ou `.claude-plugin/types/` na árvore. Com o `breakdown` real em mãos, rode `node --input-type=module -e` com `fatias(<categorias reais lidas da tela>, 40)` e confira que a soma das células é 40 (troca o INFERIDO das fixtures das tarefas 6 e 7 pelo real). Barra que não desenha na conta pessoal, ou `/painel` que não abre, devolve o fluxo à tarefa 6 ou 7; o que só a conta de trabalho barra é registrado e segue. O `~/.rainforest` real não é tocado.

### 12. Crédito MIT: `NOTICE` e cabeçalho nos arquivos enxertados [tipo: docs]
atende: D1
arquivos: `NOTICE`, `hooks/painel-puro.mjs`, `hooks/deixado-puro.mjs`, `hooks/mod.tsx`
depende de: 11
paralela: nao
mutacao: n/a
  motivo: tarefa de texto legal; a falsificação é a igualdade com o LICENSE de origem, byte a byte depois de normalizar a quebra de linha.
pronto quando: com o `LICENSE` real do terminal-desk 0.2.1 (titular `ClariSortAi`, achado 4) o `NOTICE` na raiz diz que o painel é adaptado do terminal-desk (origem `graniteai.co/tools/terminal-desk`), traz o texto da licença como última seção e `hooks/painel-puro.mjs`, `hooks/deixado-puro.mjs` e `hooks/mod.tsx` abrem com um comentário que cita terminal-desk 0.2.1, `ClariSortAi`, MIT e a remissão ao `NOTICE` — provado por `node -e 'const t=require("fs").readFileSync("NOTICE","utf8").replace(/\r\n/g,"\n");const i=t.indexOf("MIT License");const h=require("crypto").createHash("sha256").update(t.slice(i).trimEnd()+"\n").digest("hex");const c=["hooks/painel-puro.mjs","hooks/deixado-puro.mjs","hooks/mod.tsx"].every(f=>/terminal-desk 0\.2\.1/.test(require("fs").readFileSync(f,"utf8").slice(0,800))&&/ClariSortAi/.test(require("fs").readFileSync(f,"utf8").slice(0,800)));process.exit(h==="935f4a47a3df62864088b2d47dd626de09352c9e700792fbf69c6b25536436e9"&&c?0:1)'` saindo 0; e `node scripts/contrato-plugin-codex.cjs` e `node scripts/conferir-categoria.cjs` seguem saindo 0.

Nota: o design escreve "GraniteAI" como titular; o `LICENSE` e o `plugin.json` do desk dizem `ClariSortAi` e o texto legal segue o `LICENSE`, não o design (achado 4); o `NOTICE` nomeia "GraniteAI" só como site de distribuição. O `LICENSE` do repo (do Luís Montes) não muda. Só comentários mudam nos três arquivos de código: as baterias seguem como estavam.

### 13. Documentação do painel [tipo: docs]
atende: D2, D3, D5, D7, D8, D9, D13, D14, D16
arquivos: `CONTRIBUTING.md`, `README.md`
depende de: 12
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação, sem comportamento a inverter; a falsificação é a coerência com o design e com o código entregue.
pronto quando: a seção "A faixa do mod" do `CONTRIBUTING.md` vira "A barra e o painel do mod": diz que a barra substitui a faixa de foco, fluxo e Q (D2) e que o relógio ⏰ é uma figura dela (D3, com os números de `LIMITE_EFETIVA_MIN`, `HORA_NOITE`, `HORA_FIM_MADRUGADA`, `JANELA_MSG_MIN` e `OCIOSIDADE_PADRAO_MIN` iguais às constantes de `hooks/relogio-puro.mjs`, e o parágrafo do relógio já não fala em "faixa" nem em esconder pela assinatura); lista as figuras da barra e que as que não cabem caem da direita com o ⏰ por último; descreve os subcomandos de `/painel` exatamente como o `command.run` os aceita (`esconder`, `mostrar`, `cache 5m|1h`, `checar ligar|desligar`) e que esconder é alternância explícita (D9); descreve o pane (fluxos em curso, mapa da sessão, deixado para depois, contexto por fatia, cache, subagentes, custo); diz que o desvio compara só escrita por `Edit`, `Write` e `NotebookEdit` e que escrita por Bash não é detectada (D16), que o aviso vai só ao usuário (D15) e que fora de fluxo o mapa só lista (D14); diz que o checker roda em turno com `CHECAR_MIN_FERRAMENTAS` ou mais ferramentas, vê a lista e as falhas do turno (D7), usa o alias `haiku` e que o preço do cache é estimativa a preço de lista (cotações do desk de 2026-09-25); diz que falha de qualquer leitura apaga só a peça (D10) e que o mod não grava em disco; aponta o `NOTICE`; e o `README.md` acrescenta, junto do requisito da abertura, que o painel precisa do Claude Code 2.1.292+ medido (o piso de versão é o da tarefa 11) em terminal e desktop e que sem o mod nada muda — provado por um `node -e` que importa `hooks/painel-puro.mjs`, `hooks/deixado-puro.mjs` e `hooks/relogio-puro.mjs`, extrai do `CONTRIBUTING.md` os números e os subcomandos, lê os eventos e os subcomandos de `hooks/mod.tsx` e sai 1 se algum número, subcomando ou evento divergir do código, e também sai 1 se o `CONTRIBUTING.md` ainda citar `MAX_LINHAS` ou `esconder pela assinatura`.

Nota: números e nomes do texto vêm do código; nada que a tarefa 11 não tenha medido. O requisito de versão sobe só para o que a tarefa 11 confirmou. Não toca o badge de versão.

### 14. Versão, CHANGELOG e fim de lote [tipo: configurar]
atende: D1, D11
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 13
paralela: nao
mutacao: n/a
  motivo: tarefa de configuração de versão; quem prova o efeito é o sensor de versão e a medição em sessão instalada pelo marketplace, pendente pós-merge.
pronto quando: depois de `git fetch origin main`, com a versão nova em `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` e no badge do `README.md` igual à **próxima MINOR depois da que está em `origin/main` naquele momento** (não um número fixo: hoje 1.43.0 na `main`, 1.44.0 na branch da sessão paralela), a nota `## <versão>` no topo do `CHANGELOG.md` no commit `Versao <versão>: ...` (último do lote) — provado por `node -e 'const {execFileSync:x}=require("child_process");const b=JSON.parse(x("git",["show","origin/main:.claude-plugin/plugin.json"],{encoding:"utf8",env:{...process.env,MSYS_NO_PATHCONV:"1"}})).version.split(".").map(Number);const m=require("./.claude-plugin/plugin.json").version.split(".").map(Number);process.exit(m[0]===b[0]&&m[1]===b[1]+1&&m[2]===0?0:1)'` saindo 0, `node scripts/conferir-versao.cjs` saindo 0, `node scripts/contrato-plugin-codex.cjs` saindo 0 e o diff de `.codex-plugin/plugin.json` contra `99c5e5b7` sendo só a linha `version`; e o `CHANGELOG.md` diz, nesta ordem, a barra no lugar da faixa (foco, fluxo e Q saem; o relógio ⏰ fica), o `/painel` com os subcomandos, o mapa e o aviso de desvio, o "deixado para depois" com o checker que vê as ferramentas, o crédito ao terminal-desk (MIT), a falha aberta nas duas contas e o que a conta de trabalho barra (da tarefa 11), o requisito de versão e que vale a partir da sessão seguinte à atualização — provado por um `node -e` que lê a nota do topo e sai 1 se faltar qualquer um desses oito itens.

Nota: se a 1.44.0 mesclar antes, a versão é 1.45.0 e o CHANGELOG deste lote entra acima do dela; se a main ainda estiver em 1.43.0 quando este lote fechar primeiro, é a sessão paralela que renumera (conflito restrito a CHANGELOG e versão, D11). A decisão de quem mescla primeiro é da janela principal no `fechar`.

## Cobertura

D1 → 6, 10, 12, 14. D2 → 6, 13. D3 → 1, 6, 10, 13. D4 → 3, 7. D5 → 1, 6, 7, 11, 13. D6 → 6, 10. D7 → 2, 9, 11, 13. D8 → 6, 7, 9, 13. D9 → 6, 13. D10 → 6, 7, 8, 9, 10, 11. D11 → 6, 10, 14. D12 → 1, 2, 5. D13 → 5, 8, 11, 13. D14 → 3, 4, 8, 11, 13. D15 → 3, 4, 8. D16 → 4, 5, 8, 13.

## Lacunas conhecidas

- **Comportamento em sessão real** de `$.session.usage`, `$.model.complete` (alias `haiku`), `$.ui.open` e `ui.render` nas duas contas: só a tarefa 11 mede; nesta fase só a forma está CONFIRMADA.
- **`conferir-prova.cjs plano` não foi rodado** (cria e remove um worktree descartável no `.git`); a janela principal roda `node scripts/conferir-prova.cjs plano --slug 2026-10-07-desk-no-mod --plano docs/rainforest/planos/2026-10-07-desk-no-mod.md` antes de marcar o plano `ok`.
- **Cotações de preço** (tabela do desk de 2026-09-25) e a **escrita a 2x para cache de 1 h**: copiadas do desk, não conferidas contra a tabela oficial. A estimativa vem rotulada "estimativa" no pane.
- **Skill chamada por `/skill`** pode não passar por `tool.call` (INFERIDO); o mapa só lista o que passou. A tarefa 11 confere.
- **O que o sec-default barra na conta de trabalho** (`ui.render`, `$.model.complete`, `$.session.usage`) é medido na tarefa 11, não decidido; a falha aberta da D10 cobre o caso.
- **`assinaturaRelogio` fica sem chamador no mod** depois da tarefa 6 (só as baterias do relógio a usam); removê-la mexe nas baterias que a D3 manda preservar. Candidata ao `enxugar` depois deste fluxo.
- **`faixa-puro.mjs` mantém o nome** mas vira biblioteca de largura em células; renomear é escopo à parte.
- **Atraso de 0,25 s por escrita** (spawn do `desvio-do-plano.cjs`) estimado a partir do `faixa-dados.cjs`; medido na tarefa 11. Se incomodar, o desvio passa a rodar em lote no `turn.complete` (tarefa nova).
- **Escrita por Bash** não é detectada (D16), dito na tela; escrita por servidor MCP também não.
- **Desktop**: a pintura real só se lê no terminal; `claude plugin test` mostra a árvore e as regras de cada surface.
- **Barra de subagente**: o `Subagentes` do desk usa o fim do silêncio (2 min) para decidir "ainda rodando" quando ninguém viu o fim; vale como veio, a tarefa 11 observa.
