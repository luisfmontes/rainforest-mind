# Plano: Estado flaky e teto de despachos no executar

Design: docs/rainforest/design/2026-10-10-flaky-teto.md

## Achados que contradizem o briefing (lidos no fonte, na base 27478d33)
- O resolvedor do fluxo ativo não mora em `hooks/portaria.cjs`: é `resolver({cwd})` de `hooks/lib/estagio-ativo.cjs`. `raizDeDados` é função local da portaria e `portaria.cjs` não tem `module.exports` (um `require` dele executaria o `main()`). O hook novo usa `estagio-ativo.cjs` e `hooks/lib/raiz.cjs` direto, repete as cinco linhas de `raizDeDados` e a portaria fica com **zero diff**.
- `skills/executar/SKILL.md` tem 16376 B (8 B de folga, não 1) e `skills/plano/SKILL.md` tem 16380 B (4 B). O ponteiro do `executar` cabe trocando a linha `Reaberto pelo ...` por uma de 75 B (total 16381 B). O `plano/SKILL.md` não ganha nem um ponteiro: o cabeçalho `teto-despachos:` mora em `skills/plano/references/teto-despachos.md`, alcançado por `recusas-da-cobertura.md`.
- `hooks/hooks.json` tem **dois** grupos com matcher `Task|Agent`: o da `portaria.cjs` e o da `memoria-assunto-agente.cjs`. O hook novo entra no grupo da portaria.
- Em `scripts/conferir-mutacao.cjs` o `limpar()` da fase 5 (linha 771) apaga a cópia **antes** do veredito, e `limpar();` aparece três vezes. A confirmação do vermelho (D7) e a nova tentativa do exit 2 (D8) precisam da cópia viva; a âncora única é `const posRes = rodaBateria(bateria, raizExecucao, timeout, 'pós-mutação');` (uma ocorrência).
- O `liberar` do `estado.cjs` mora na linha 2334 (`if (cmd === 'liberar') {`); a linha ~2700 que o briefing cita é o `delete blocoNovo.liberado_em` do `marcar`.
- `bash scripts/testa-estado.sh` e `bash scripts/testa-conferir-mutacao.sh` já saem 0 na base (medido: exit 0 com 324 ok, e exit 0 com 171 ok), então não servem de `prova:`: cada tarefa de código cria a bateria nova dela.
- Três baterias contam peças e quebram quando o hook entra: `hooks/testa-titulo-sessao-registro.sh` (`PreToolUse` 16 passa a 17) e `scripts/testa-conferir-categoria.sh` (57 peças e 23 guia passam a 58 e 24; o `rodar-gate.cjs` não conta, só `conferir-*.cjs` e os hooks do `hooks.json`).

## O que não pode quebrar
- `bash scripts/testa-teto-skills.sh` verde: `skills/executar/SKILL.md` fica em 16381 B (teto 16384) e `skills/plano/SKILL.md` fica byte a byte igual. Texto novo de skill vai em `references/`.
- A decisão da portaria não muda: `hooks/portaria.cjs` sem diff e as baterias `hooks/testa-portaria-*.cjs` verdes. O teto é hook separado, porque a portaria só registra desde a #264.
- O significado dos exits da catraca (0, 2, 3, 4, 5, 6, 1, 69) e `bash scripts/testa-conferir-mutacao.sh` verde; só os exits 2 e 4 passam a valer depois de uma nova tentativa.
- `TETO_TENTATIVAS = 3`, o `liberar --estagio revisar --rodada-extra`, o `reaberto_por` (só ganha o campo irmão `reaberturas`) e `bash scripts/testa-estado.sh` intactos. `flaky` não consome tentativa.
- Hook de `PreToolUse` nunca sai 1: exit 1 não barra. Falha interna do teto sai 2.
- Nenhuma `description` de skill, comando ou agente muda: `node scripts/orcamento.cjs` continua em 15099 B (teto 15600).

## Decisões assumidas pelo plano (técnicas; o design não fixa, e cada uma está no pronto quando da tarefa)
- Catraca, rodadas pós-mutação: só vermelho nas duas dá exit 0. Verde e verde dá 2. Qualquer sequência mista (verde e vermelho, ou vermelho e verde) dá 2 **e** grava flake. Rodada que estoura tempo ou morre por sinal dá exit 1, como a primeira.
- Catraca, baseline: só o ramo `baselineExit !== 0` com exit numérico ganha nova tentativa. Estouro de tempo, sinal, 126/127, `--de` ambíguo e exit 69 saem como hoje.
- Flake gravado: `estado.executar.flakes` é uma lista de `{tarefa, gate, voltas}`. `volta` é `executar.reaberturas`, um contador novo que `rebaixarUpstream` soma 1 a cada reabertura do `executar` (reprovação de `revisar` ou de `verificar`) e que **nenhum `ok` apaga**; `revisar.tentativas + verificar.tentativas` não serve porque o `marcar ... ok` apaga `tentativas` (linhas 2728 a 2730 do `estado.cjs`) e a volta voltaria a 0; registrar duas vezes na mesma volta não duplica. É terminal o item que tem a volta atual **e** a anterior. Gate da catraca: `catraca: <bateria>`. Gate do critério: `criterio: <comando>`.
- Quem grava: `catraca` e `rodar-gate` ganham `--slug` e `--tarefa` (os dois ou nenhum) e chamam `node scripts/estado.cjs registrar-flake`. Falha ao gravar vira aviso no stderr e **nunca** muda o exit. O `conferir-fluxo.cjs mutacoes` (estágio `verificar`) não passa os dois: o laço do D2 é `executar` e `revisar`.
- `flaky` só existe para `executar`; sai dele com `liberar --estagio executar` (já existe). O `registrar-flake` que detecta terminal apaga `executar.liberado_em`, e por isso o `liberar` vale uma rodada.
- Forma do `liberar` do teto: subcomando `liberar-teto --slug --motivo`, gravando `teto_despachos.liberacoes[]` no estado versionado. Teto efetivo = declarado (ou 40) + 10 por liberação.
- Hook: lê o cabeçalho `teto-despachos: N` das linhas do plano antes do primeiro `## `; plano ausente vale 40 (fluxo ainda em `design`); cabeçalho ilegível nega. Resolver que estoura **antes** de achar o fluxo passa com aviso (a portaria já nega esse caso); depois de achar o fluxo, qualquer falha nega com exit 2. Trava ocupada por mais de 10 s nega.
- Despacho que a portaria vai negar no mesmo `PreToolUse` também conta (os dois hooks rodam juntos e o teto não sabe a decisão da portaria).

## Em aberto
- Nada. Os quatro pontos que o plano levantou foram fechados pelo usuário em 2026-10-10 como D14 a D17 do design.

## Tarefas

### 1. `estado.cjs registrar-flake`: grava o flake e acha o terminal [tipo: implementar]
atende: D4, D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-flaky.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-estado-flaky.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `f.voltas.includes(volta - 1)`
  para: `f.voltas.includes(volta)`
  bateria: `bash scripts/testa-estado-flaky.sh`
  fixture: `testa-estado-flaky.sh, secao "flake de uma volta so nao e terminal"`
pronto quando: com o estado real de um fluxo aberto por `estado.cjs iniciar` num repo-caixa (`RFM_ESTADO_ROOT` na caixa), `node scripts/estado.cjs registrar-flake --slug <s> --tarefa 2 --gate "bash x.sh"` sai 0 e imprime `flake registrado: tarefa 2, volta 0`, o JSON passa a ter `executar.flakes` igual a `[{"tarefa":2,"gate":"bash x.sh","voltas":[0]}]`, repetir o comando na mesma volta não duplica, e `marcar --estagio executar --status ok` com a evidência de sempre ainda fecha (flake de uma volta só segue); depois de `marcar --estagio verificar --status reprovado` (`executar.reaberturas` vira 1 e a volta passa a ser 1) o mesmo comando grava `voltas:[0,1]` e imprime uma linha `FLAKY TERMINAL` que nomeia a tarefa, o gate e o comando `marcar --estagio executar --status flaky`; não são terminais gate diferente na volta 1, tarefa diferente na volta 1, voltas 0 e 2, e voltas 0 e 3 com um `ok` do `revisar` (que apaga `revisar.tentativas`) e um `ok` do `executar` no meio, porque a volta só cresce; sai 1 sem `--gate`, com `--tarefa` igual a `abc`, `0`, `-1` ou `1.5`, com slug inexistente e com flag desconhecida; 6 chamadas lançadas juntas com tarefas 1 a 6 gravam as 6 entradas — provado por `bash scripts/testa-estado-flaky.sh` saindo 0 com a última linha de placar `falhou: 0`

Nota: código a nascer, e nenhum caso de teste afirma sobre o texto do fonte; só a catraca lê o `de:`. A forma prescrita é a função `flakyTerminal(estado)`, uma expressão de retorno sem ramo e sem print: `return flakes.find((f) => f.voltas.includes(volta) && f.voltas.includes(volta - 1)) || null;`, uma única ocorrência, com `volta` igual a `estado.executar.reaberturas || 0`; `rebaixarUpstream` ganha `reaberturas: (bloco_upstream.reaberturas || 0) + 1` no bloco que monta (campo fora de `CAMPOS_EFEMEROS` e fora do `delete` do `ok`), e `bash scripts/testa-estado.sh` continua verde (nenhuma asserção dele compara o bloco `executar` inteiro; as de `reaberto_por` olham `estagio` e `data`). O subcomando entra em `FLAGS_POR_SUBCOMANDO` como `'registrar-flake': ['slug', 'tarefa', 'gate']`, fica antes do `const estado = ler(slug)` como o `veredito`, grava sob `comTrava` num `.<slug>.flake.lock` dentro de `DIR_ESTADO` relendo o estado dentro da trava, e a linha de uso do `main()` o lista. A bateria nova imprime o placar no formato `ok: N   falhou: M`, que a catraca sabe ler.

### 2. Hook `gate-teto-despachos.cjs`: conta despachos e nega no teto [tipo: implementar]
atende: D5, D9, D10, D11, D12, D15, D16, D17
arquivos: `hooks/gate-teto-despachos.cjs`, `hooks/testa-gate-teto-despachos.cjs`, `hooks/hooks.json`, `hooks/testa-titulo-sessao-registro.sh`, `scripts/testa-conferir-categoria.sh`, `.gitignore`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-gate-teto-despachos.cjs`
mutacao:
  arquivo: `hooks/gate-teto-despachos.cjs`
  de: `obj.total >= 0 ? obj.total : null`
  para: `obj.total >= 0 ? obj.total : 0`
  bateria: `node hooks/testa-gate-teto-despachos.cjs`
  fixture: `testa-gate-teto-despachos.cjs, caso "contador com total invalido nega"`
pronto quando: com o JSON que o harness manda no stdin do `PreToolUse` de `Agent` (o `hooks/fixtures/portaria-folha/payload-da-janela.json`, capturado ao vivo, com `cwd` trocado pela raiz de um repo-caixa na branch `fluxo/x` com o estado aberto `AAAA-MM-DD-x.json` criado por `estado.cjs iniciar`, e `RFM_ROOT` na caixa), cada chamada de `node hooks/gate-teto-despachos.cjs` até a 40ª sai 0 e deixa `<RFM_ROOT>/fluxos/<slug>/despachos.json` com `total` igual ao número da chamada, a 41ª sai 2 citando o slug, o 40 e o contador, e o total continua 40; conta com o estágio `design` aberto e com `executar` aberto; passam sem contar e sem criar a pasta `fluxos/` a branch sem fluxo, o repo sem `docs/rainforest/estado/`, dois estados abertos que casam com a mesma branch, o fluxo com todos os estágios fechados, `tool_name` igual a `Bash`, stdin vazio e stdin com JSON inválido; dois repos-caixa com slugs diferentes mantêm contadores separados (o mesmo slug em dois repos que dividem a raiz de dados divide o contador, aceito por D16); o payload com `agent_id` (`payload-de-subagente.json`) conta igual, e só a negação dada à janela cita `liberar-teto`; nega com exit 2 (nunca 1) sem reescrever o arquivo o contador vazio, `{`, `[]`, `null`, `{}`, `{"total":"7"}`, `{"total":-1}`, `{"total":1.5}` e `{"total":1e400}`, e também `RFM_ROOT` apontando para um arquivo em vez de pasta; 12 processos lançados juntos terminam com `total` 12 e, com o contador em 36, exatamente 4 saem 0 e 8 saem 2 com total 40; `hooks/hooks.json` registra o hook uma vez, no grupo `Task|Agent` da portaria, e `git diff --quiet <hash da base do briefing> -- hooks/portaria.cjs` sai 0 — provado por `node hooks/testa-gate-teto-despachos.cjs` com `falhou: 0`, e por `bash hooks/testa-titulo-sessao-registro.sh` (17 em `PreToolUse`) e `bash scripts/testa-conferir-categoria.sh` (58 peças, 24 guia) saindo 0

Nota: o contorno que importa é o contador lido como zero quando está ruim (o defeito do `ceiling-check.sh` do plugin de origem), e por isso o `de:` é a linha que decide isso. Código a nascer: nenhum caso de teste afirma sobre o texto do fonte. A linha prescrita é `const total = Number.isSafeInteger(obj.total) && obj.total >= 0 ? obj.total : null;`, uma ocorrência, e `null` leva ao ramo que nega. Resto da forma: `// @categoria: guia` na linha 2; `const TETO_PADRAO = 40;`; nega quando `total >= teto` (o teto vale o número de despachos admitidos); lê e grava dentro de `comTrava` de `hooks/lib/trava-jsonl.cjs` (espera máxima 10 s, e estouro nega); grava por arquivo temporário e `rename`; `uncaughtException`/`unhandledRejection` e o `main()` envoltos numa rede que sai 2, como a portaria, exceto stdin ilegível, vazio ou JSON inválido, que sai 0; raiz do projeto é o toplevel git de `payload.cwd`; fluxo vem de `require('./lib/estagio-ativo.cjs').resolver({ cwd: raiz })`; raiz de dados vem de `resolverRaiz({ cwd: raiz })` de `hooks/lib/raiz.cjs`, com `path.join(raiz, '.rainforest')` quando ela falha; a mensagem para quem tem `agent_id` omite o comando do `liberar-teto` (decisão do usuário não vai para a mão do subagente). Sem toggle e sem `RAINFOREST_GATE_OFF` (D15): a saída é o `liberar-teto` (tarefa 4); a bateria tem o caso "sem escape": com `RAINFOREST_GATE_OFF=1` e com a chave `teto-despachos` desligada por `setup.cjs`, a 41ª chamada continua saindo 2. Despacho que a portaria nega conta igual (D17): o hook não lê a decisão da portaria, e a bateria tem o caso "agente fora do manifesto conta". Parada: este hook decide só sobre contagem; não reimplementa gramática de shell nem lê o prompt do despacho.

Emenda (revisar volta 1, decidida pelo usuário em 2026-10-11): sem raiz de dados resolvida, o fallback `path.join(raiz, '.rainforest')` grava o contador dentro do repo, e D11 o quer fora do diff. O `.gitignore` passa a ignorar `.rainforest/fluxos/`, no mesmo padrão de `.rainforest/portaria/despachos.jsonl`. Pronto quando: num repo-caixa sem `RFM_ROOT` e sem marcador de raiz, depois de uma chamada do hook, `git status --porcelain -uall` não lista `.rainforest/fluxos/` e `git check-ignore -q .rainforest/fluxos/<slug>/despachos.json` sai 0 — caso novo na `hooks/testa-gate-teto-despachos.cjs`.

### 3. Status `flaky` do `executar` [tipo: implementar]
atende: D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-flaky-status.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-estado-flaky-status.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (status === 'reprovado') {`
  para: `if (status === 'reprovado' || status === 'flaky') {`
  bateria: `bash scripts/testa-estado-flaky-status.sh`
  fixture: `testa-estado-flaky-status.sh, secao "flaky nao consome tentativas"`
pronto quando: com o estado real da tarefa 1 já em volta 1 com o terminal gravado (`voltas:[0,1]`), `marcar --estagio executar --status ok` com a evidência que fecharia normalmente sai 2 citando `flaky`; `marcar --estagio executar --status flaky` sai 0 e o JSON fica com `executar.status` igual a `flaky`, sem `executar.tentativas`, `verificar.tentativas` ainda 1 e `executar.flakes` preservado; daí `exigir --estagio executar` sai 2 apontando `liberar --slug <s> --estagio executar`, `marcar --estagio executar --status parcial` sai 2, `proximo` imprime `executar` e `exigir --estagio revisar` sai 2; `liberar --estagio executar` sai 0, depois `exigir --estagio executar` sai 0 e `marcar --estagio executar --status parcial` sai 0; repetir o `registrar-flake` do mesmo gate na volta 1 volta a imprimir `FLAKY TERMINAL`, apaga `executar.liberado_em`, e `marcar --estagio executar --status ok` sai 2 de novo (o `liberar` vale uma rodada); `marcar --status flaky` com `--estagio revisar`, `verificar` e `fechar` sai 1 (status inválido); `marcar --estagio executar --status flaky` sem flake nenhum, ou com flakes de gates diferentes em voltas seguidas, sai 2; a mensagem de status inválido para `executar` lista `flaky` — provado por `bash scripts/testa-estado-flaky-status.sh` saindo 0 com `falhou: 0` e por `bash scripts/testa-estado.sh` saindo 0

Nota: o `de:` é a linha existente que abre o ramo que incrementa `tentativas`, reabre o upstream e apaga `liberado_em`; `flaky` tem de ficar fora dele (D6: não consome `TETO_TENTATIVAS`). Casa uma vez em `scripts/estado.cjs`. A permissão do status vem de uma linha a mais junto de `const permitidos = DECISAO[estagio] || STATUS_EXECUCAO;` que acrescenta `flaky` só quando o estágio é `executar`; `STATUS_EXECUCAO` não muda porque serve aos quatro estágios. As três recusas novas (fechar `flaky` sem terminal, sair de `flaky` sem `liberar`, fechar `ok` com terminal sem `liberar`) valem só para `executar`. O `registrar-flake` passa a apagar `executar.liberado_em` ao detectar terminal.

### 4. `estado.cjs liberar-teto`: +10 despachos com o motivo [tipo: implementar]
atende: D13
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-teto.sh`
depende de: 3
paralela: nao
prova: `bash scripts/testa-estado-teto.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `[...anteriores, { motivo, em: hoje() }]`
  para: `[{ motivo, em: hoje() }]`
  bateria: `bash scripts/testa-estado-teto.sh`
  fixture: `testa-estado-teto.sh, secao "segunda liberacao acumula"`
pronto quando: com o estado real de um fluxo (`estado.cjs iniciar`), `node scripts/estado.cjs liberar-teto --slug <s> --motivo "Luis: fluxo grande, segue"` sai 0 e o JSON ganha `teto_despachos.liberacoes` com um item `{"motivo":"Luis: fluxo grande, segue","em":"<AAAA-MM-DD>"}`; a segunda chamada deixa dois itens, na ordem; todo o resto do JSON fica igual; `--motivo ""` e `--motivo "   "` saem 2 com o arquivo byte a byte igual ao de antes; sem `--motivo` sai 1; slug inexistente sai 1; `--estagio executar` sai 1 (flag desconhecida: o teto não é estágio); `liberar --estagio revisar` sem `--rodada-extra` continua saindo 2 e `liberar --estagio executar` continua gravando `liberado_em` — provado por `bash scripts/testa-estado-teto.sh` saindo 0 com `falhou: 0` e por `bash scripts/testa-estado.sh` saindo 0

Nota: código a nascer, e nenhum caso de teste afirma sobre o texto do fonte. Forma prescrita: `const liberacoes = [...anteriores, { motivo, em: hoje() }];` uma ocorrência, sem ramo, depois de validar o motivo; `anteriores` vale `[]` quando `teto_despachos.liberacoes` não é lista. O subcomando entra em `FLAGS_POR_SUBCOMANDO` como `'liberar-teto': ['slug', 'motivo']` e na linha de uso. Não calcula o teto: quem soma o +10 é o hook (tarefa 7).

### 5. Catraca: confirma o vermelho e repete o que o acaso pode ter produzido [tipo: implementar]
atende: D4, D7, D8
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-flaky.sh`, `scripts/testa-conferir-mutacao.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-conferir-mutacao-flaky.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `confRes.r.status !== 0`
  para: `confRes.r.status === 0`
  bateria: `bash scripts/testa-conferir-mutacao-flaky.sh`
  fixture: `testa-conferir-mutacao-flaky.sh, secao "vermelho e depois verde nao confirma"`
pronto quando: com uma bateria de caixa cujo exit varia entre chamadas consecutivas (um arquivo-contador e uma sequência de exits por chamada, a forma real da bateria instável), rodada por `node scripts/conferir-mutacao.cjs --arquivo fonte.cjs --de <trecho> --para <trecho> --bateria 'bash bat.sh' --raiz <caixa>`: baseline `1 0` e pós-mutação `1 1` sai 0, o contador termina em 4 e o stdout traz `FLAKE: baseline`; baseline `1 1` sai 4 com o contador em 2; pós-mutação `0 0` sai 2 com o contador em 3; `0 1` sai 2 com `FLAKE: pos-mutacao`; `1 1` sai 0 com o contador em 3; `1 0` sai 2 com `FLAKE: pos-mutacao`; `--de` que não casa sai 3 com o contador em 1; `--de` que casa duas vezes sai 4 com o contador em 1; bateria que colapsa (placar `ok: 0   falhou: 0` na pós-mutação, como o caso 14 de `testa-conferir-mutacao.sh`) sai 6 sem terceira rodada; comando de bateria inexistente sai 69; `--slug` sem `--tarefa` (e o inverso) sai 1; com `--slug <s> --tarefa 3` num estado real e pós-mutação `0 1`, o JSON ganha `executar.flakes` com `{"tarefa":3,"gate":"catraca: bash bat.sh","voltas":[0]}`, sem `--slug` o estado não é tocado, e com slug inexistente o aviso sai no stderr e o exit é o mesmo — provado por `bash scripts/testa-conferir-mutacao-flaky.sh` saindo 0 com `falhou: 0` e por `bash scripts/testa-conferir-mutacao.sh` saindo 0

Nota: código a nascer, e nenhum caso de teste afirma sobre o texto do fonte. Forma prescrita do alvo: uma expressão booleana de uma linha, sem ramo e sem print, `const confirmouVermelho = !confRes.r.error && confRes.r.status !== null && confRes.r.status !== 0;`, em que `confRes` é o resultado da segunda rodada pós-mutação; a subexpressão `confRes.r.status !== 0` ocorre uma vez. As rodadas extras acontecem dentro da mesma cópia, antes do `limpar()` da fase 5 (âncora única `const posRes = rodaBateria(bateria, raizExecucao, timeout, 'pós-mutação');`); o `limpar();` literal não serve de âncora, aparece três vezes. A nova tentativa do baseline vive no ramo `if (baselineExit !== 0) {` (uma ocorrência) e só para exit numérico; os exits 1, 3, 5, 6 e 69 nunca repetem. O exit 5 não tem caso de teste porque depende de cronômetro (Issue #121, comentário sobre `PISO_ABSOLUTO_MS`): fica coberto só por leitura. A ordem depois da primeira rodada pós-mutação é: exit 0 da bateria (verde) repete uma vez (D8) e sai 2 em qualquer resultado; senão colapso, 6; senão corte de shell, 5; só então a confirmação do vermelho (D7). Os casos 10, 13 e 14 de `testa-conferir-mutacao.sh` dependem dessa ordem. A segunda rodada que estoura tempo ou morre por sinal sai 1 (`BATERIA SEM VEREDITO`). `--slug` e `--tarefa` vão com `spawnSync(process.execPath, [estado.cjs, 'registrar-flake', ...])`; falhar ao gravar é aviso. O módulo passa a exportar `rodaBateria`, que a tarefa 6 reaproveita. O cabeçalho, o `USO` e a tabela de exits do arquivo dizem que 2 e 4 só saem depois da nova tentativa. A suíte `testa-conferir-mutacao.sh` pode ficar mais lenta (rodadas extras nos casos 2 e 4); ajuste de tempo nela é permitido, de comportamento não.

Emenda (revisar volta 1, 2026-10-11): a rodada de confirmação passa pela mesma checagem de colapso da primeira (`bateriaColapsou` contra o placar do baseline); crash sem placar na confirmação não é vermelho confirmado. Pronto quando a sequência de exits `0 1 c` (íntegro verde, 1ª pós-mutação vermelha com placar, confirmação que colapsa) sai 6, e não 0 — caso novo na `scripts/testa-conferir-mutacao-flaky.sh`.

### 6. `rodar-gate.cjs`: a bateria do critério com uma nova tentativa [tipo: implementar]
atende: D4, D8
arquivos: `scripts/rodar-gate.cjs`, `scripts/testa-rodar-gate.sh`
depende de: 1, 5
paralela: nao
prova: `bash scripts/testa-rodar-gate.sh`
mutacao:
  arquivo: `scripts/rodar-gate.cjs`
  de: `primeira.r.status !== 0`
  para: `primeira.r.status === 0`
  bateria: `bash scripts/testa-rodar-gate.sh`
  fixture: `testa-rodar-gate.sh, secao "vermelho na primeira rodada repete uma vez"`
pronto quando: com a mesma bateria de caixa de exit variável da tarefa 5, `node scripts/rodar-gate.cjs --comando 'bash bat.sh' --raiz <caixa>` com sequência `0` sai 0 com o contador em 1 e sem `FLAKE`; com `1 0` sai 0, o contador termina em 2 e o stdout traz `FLAKE: passou so na nova tentativa`; com `1 1` sai 2 com o contador em 2 (nunca 3) e o stderr traz o exit das duas rodadas; comando inexistente sai 69; `--timeout 300` com uma bateria que dorme 5 s sai 1 com o contador em 1 (estouro não se repete); sem `--comando` sai 1; `--slug` sem `--tarefa` sai 1; com `--slug <s> --tarefa 2` num estado real e sequência `1 0`, o JSON ganha `{"tarefa":2,"gate":"criterio: bash bat.sh","voltas":[0]}`; repetido na volta seguinte (depois de `marcar --estagio verificar --status reprovado`) o stdout repassa a linha `FLAKY TERMINAL` e `marcar --estagio executar --status ok` passa a sair 2 — provado por `bash scripts/testa-rodar-gate.sh` saindo 0 com `falhou: 0`

Nota: código a nascer, e nenhum caso de teste afirma sobre o texto do fonte. Forma prescrita: `const repetir = !primeira.r.error && primeira.r.status !== null && primeira.r.status !== 0;`, uma linha, sem ramo, uma ocorrência de `primeira.r.status !== 0`; `primeira` é o retorno de `rodaBateria`, importada de `scripts/conferir-mutacao.cjs` (stdin fechado, teto de tempo e bash do Git, sem copiar a resolução de shell). Exits: 0 verde, de primeira ou só na nova tentativa; 2 vermelho nas duas; 1 uso ou sem veredito; 69 ambiente (inclui 126 e 127). Gate gravado: `criterio: <comando>`. O arquivo não conta como peça no `conferir-categoria` (o nome não é `conferir-*`).

### 7. Teto declarado no plano e liberações lidas pelo hook [tipo: implementar]
atende: D9, D12, D13
arquivos: `hooks/gate-teto-despachos.cjs`, `hooks/lib/teto-despachos.cjs`, `hooks/testa-gate-teto-declarado.cjs`
depende de: 2, 4
paralela: nao
prova: `node hooks/testa-gate-teto-declarado.cjs`
mutacao:
  arquivo: `hooks/gate-teto-despachos.cjs`
  de: `DESPACHOS_POR_LIBERACAO * liberacoes.length`
  para: `0 * liberacoes.length`
  bateria: `node hooks/testa-gate-teto-declarado.cjs`
  fixture: `testa-gate-teto-declarado.cjs, caso "liberar-teto soma 10 e a segunda soma mais 10"`
pronto quando: com o mesmo payload real da tarefa 2 num repo-caixa e o plano real em `docs/rainforest/planos/<slug>.md`: sem plano o teto é 40 (40ª passa, 41ª nega); com a linha `teto-despachos: 5` entre o título e o primeiro `## ` a 5ª passa e a 6ª nega; com `teto-despachos: abc`, `0`, `-1`, `1.5`, `5 despachos`, `10000`, valor vazio ou duas linhas `teto-despachos:` o hook sai 2 citando o caminho do plano e o texto lido, mesmo com o contador em zero; a mesma linha depois do primeiro `## ` é ignorada (teto 40); plano que existe mas não é arquivo legível nega; depois de `node scripts/estado.cjs liberar-teto --slug <s> --motivo "..."` a 50ª passa e a 51ª nega, depois de uma segunda liberação a 60ª passa e a 61ª nega, e a liberação de outro slug não vale para este; `teto_despachos.liberacoes` malformado (`"x"`, `[{}]`, `[{"motivo":""}]`) nega com exit 2 — provado por `node hooks/testa-gate-teto-declarado.cjs` saindo 0 com `falhou: 0` e por `node hooks/testa-gate-teto-despachos.cjs` saindo 0

Nota: código a nascer, e nenhum caso de teste afirma sobre o texto do fonte. Forma prescrita: `const DESPACHOS_POR_LIBERACAO = 10;` e, sem ramo, `const teto = declarado + DESPACHOS_POR_LIBERACAO * liberacoes.length;`, cada uma uma ocorrência. O caminho do plano vem de `caminhoDoc('planos', slug, { raiz })` de `hooks/lib/pastas-docs.cjs` e as liberações do estado em `docs/rainforest/estado/<slug>.json` (versionado, D11). Cabeçalho = linhas antes do primeiro `## `; valor válido casa `^[1-9][0-9]{0,3}$`. O leitor do cabeçalho mora em `hooks/lib/teto-despachos.cjs`, exportando `lerTetoDeclarado(textoDoPlano)` que devolve `{ teto }` (40 sem a linha) ou `{ erro }`, sem ler disco; o hook só lê o arquivo e chama. É o mesmo leitor que a `cobertura` usa na tarefa 12 (D14). A negação diz como destravar: declarar `teto-despachos: N` no plano ou rodar `liberar-teto` (só na mensagem da janela).

### 8. Registro das oito baterias novas como obrigatórias [tipo: configurar]
atende: D4, D5, D14
arquivos: `scripts/baterias-obrigatorias.txt`
depende de: 1, 2, 3, 4, 5, 6, 7, 12
paralela: nao
mutacao: n/a
  motivo: arquivo de lista; o comportamento (recusar varredura sem obrigatória) é do `varrer-baterias.sh` e já tem `testa-varrer-baterias.sh`
pronto quando: com a lista real do repositório, cada uma das oito baterias novas (`scripts/testa-cobertura-teto.sh`, `scripts/testa-estado-flaky.sh`, `scripts/testa-estado-flaky-status.sh`, `scripts/testa-estado-teto.sh`, `scripts/testa-conferir-mutacao-flaky.sh`, `scripts/testa-rodar-gate.sh`, `hooks/testa-gate-teto-despachos.cjs`, `hooks/testa-gate-teto-declarado.cjs`) aparece uma vez como linha de `scripts/baterias-obrigatorias.txt` e existe em disco, e a conferência de obrigatórias da varredura aceita a lista — provado por `node -e "const fs=require('fs');const l=fs.readFileSync('scripts/baterias-obrigatorias.txt','utf8').split(/\r?\n/).map(x=>x.trim());const n=['scripts/testa-cobertura-teto.sh','scripts/testa-estado-flaky.sh','scripts/testa-estado-flaky-status.sh','scripts/testa-estado-teto.sh','scripts/testa-conferir-mutacao-flaky.sh','scripts/testa-rodar-gate.sh','hooks/testa-gate-teto-despachos.cjs','hooks/testa-gate-teto-declarado.cjs'];process.exit(n.every(b=>l.filter(x=>x===b).length===1&&fs.existsSync(b))?0:1)"` saindo 0 e por `bash scripts/varrer-baterias.sh --listar` saindo 0 com as oito na saída

### 9. O laço escrito: flaky, teto, o que o plano declara [tipo: docs]
atende: D2, D3, D6, D9, D13, D16
arquivos: `skills/revisar/references/laco.md`, `skills/executar/SKILL.md`, `skills/plano/references/teto-despachos.md`, `skills/plano/references/recusas-da-cobertura.md`, `skills/limpar/SKILL.md`
depende de: 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: texto normativo; o comportamento executável está nas tarefas 1 a 7
pronto quando: com o `laco.md` como a janela o lê no laço do `revisar`, duas seções novas (`Flaky` e `Teto de despachos`) prescrevem: na integração rodar `rodar-gate.cjs` para o critério e `conferir-mutacao.cjs` com `--slug` e `--tarefa`; o exit de cada um vale depois da nova tentativa; `FLAKY TERMINAL` manda fechar o `executar` com `--status flaky` e subir ao usuário, sem consumir `TETO_TENTATIVAS` (D6); o hook nega no teto padrão do código e o `liberar-teto` soma o número do código por liberação, com o motivo que o usuário disse (D13); e dizem o que o teto não protege, na ordem do D3 (bateria determinística que mede a coisa errada fica com a catraca; agente despachado fora de fluxo fica com a portaria); o `executar/SKILL.md` troca só a linha `Reaberto pelo ...` por uma que aponta `flaky` e teto para o `laco.md` e fica com 16384 B ou menos; `skills/plano/references/teto-despachos.md` descreve o cabeçalho `teto-despachos: N` (onde fica, o valor aceito, o que acontece com valor ilegível) e `recusas-da-cobertura.md` ganha uma linha que aponta para ele; o item **Arquivo temporário** de `skills/limpar/SKILL.md` ganha o contador `<dados>/fluxos/<slug>/` de fluxo que o `estado.cjs listar` mostra `(completo)` como removível (D16); `skills/plano/SKILL.md` não muda — provado por `node -e "const fs=require('fs');const d=fs.readFileSync('skills/revisar/references/laco.md','utf8');const h=fs.readFileSync('hooks/gate-teto-despachos.cjs','utf8');const e=fs.readFileSync('scripts/estado.cjs','utf8');const p=h.match(/const TETO_PADRAO = (\d+);/)[1];const l=h.match(/const DESPACHOS_POR_LIBERACAO = (\d+);/)[1];const ok=d.includes('teto padrão de '+p+' despachos')&&d.includes('+'+l+' despachos')&&d.includes('scripts/rodar-gate.cjs')&&['registrar-flake','liberar-teto'].every(s=>d.includes('estado.cjs '+s)&&e.includes(\"'\"+s+\"':\"));process.exit(ok&&fs.readFileSync('skills/limpar/SKILL.md','utf8').includes('fluxos/<slug>/')?0:1)"` saindo 0 (o texto cita os números e os subcomandos que o código tem, e o limpar cita o contador), `bash scripts/testa-teto-skills.sh` saindo 0, `git diff --quiet <hash da base do briefing> -- skills/plano/SKILL.md` saindo 0 e `node scripts/conferir-indice-referencias.cjs` saindo 0

Nota: o D3 não tem como ser conferido por máquina além disso; é o `revisar` que lê as duas exclusões contra o design. `laco.md` fica abaixo de 100 linhas e não precisa de índice. A linha nova do `executar/SKILL.md` deve ser ``Reaberto (`revisar`), `flaky` ou teto: `skills/revisar/references/laco.md`.``, com 75 B contra 70 B da antiga, e leva o arquivo de 16376 B a 16381 B.

### 10. Tabela de travas e README [tipo: docs]
atende: D5
arquivos: `docs/travas-mecanicas.md`, `README.md`
depende de: 6, 7
paralela: nao
mutacao: n/a
  motivo: documentação; o comportamento do hook é provado pela bateria da tarefa 2
pronto quando: com a tabela de hooks do `docs/travas-mecanicas.md` e a do `README.md` como o leitor as vê, cada uma ganha uma linha para `gate-teto-despachos.cjs` que diz o que barra (despacho de agente do fluxo ativo acima do teto), o teto padrão, que o contador mora fora do repo, que fora de fluxo não conta, e que a saída é o `liberar-teto`, sem prometer toggle; a tabela de scripts ganha `rodar-gate.cjs`; a linha da `portaria.cjs` continua dizendo que ela só registra; a soma de casos de gates do README não muda — provado por `node -e "const fs=require('fs');const h=fs.readFileSync('hooks/gate-teto-despachos.cjs','utf8');const p=h.match(/const TETO_PADRAO = (\d+);/)[1];const j=fs.readFileSync('hooks/hooks.json','utf8');const ok=['README.md','docs/travas-mecanicas.md'].every(f=>{const t=fs.readFileSync(f,'utf8');return t.includes('gate-teto-despachos.cjs')&&t.includes('liberar-teto')&&t.includes(' '+p+' ')&&t.includes('rodar-gate.cjs')})&&j.includes('gate-teto-despachos.cjs');process.exit(ok?0:1)"` saindo 0 (o número no texto é o do código e o hook está no `hooks.json`) e `git diff <hash da base do briefing> -- README.md | grep -c "849 casos"` devolvendo 0

### 11. Versão 1.61.0 e nota de atualização [tipo: docs]
atende: D1
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`
depende de: 8, 9, 10
paralela: nao
mutacao: n/a
  motivo: nota de versão
pronto quando: com a entrada nova do topo do `CHANGELOG.md` (`## 1.61.0`), ela descreve do ponto de vista de quem usa o plugin as duas partes do fluxo (a nova tentativa que decide o `flaky`, e o teto de despachos com o `liberar-teto`), cita o teto padrão do código e o +10 do código, e a versão é a mesma nos dois `plugin.json` e no badge do README — provado por `node -e "const fs=require('fs');const c=fs.readFileSync('CHANGELOG.md','utf8').split(/^## /m)[1];const h=fs.readFileSync('hooks/gate-teto-despachos.cjs','utf8');const p=h.match(/const TETO_PADRAO = (\d+);/)[1];const l=h.match(/const DESPACHOS_POR_LIBERACAO = (\d+);/)[1];const a=JSON.parse(fs.readFileSync('.claude-plugin/plugin.json','utf8')).version;const b=JSON.parse(fs.readFileSync('.codex-plugin/plugin.json','utf8')).version;const r=fs.readFileSync('README.md','utf8');process.exit(c.startsWith('1.61.0')&&a==='1.61.0'&&b==='1.61.0'&&r.includes('vers%C3%A3o-1.61.0')&&c.includes('flaky')&&c.includes('liberar-teto')&&c.includes(p)&&c.includes(l)?0:1)"` saindo 0

Nota: minor porque é recurso novo (hook, subcomandos e status), não correção. A 1.60.0 já saiu na `main` (#492, recarga das janelas); se a `main` tiver passado da 1.60.x quando esta tarefa rodar, o executor usa a próxima minor livre e troca o número no critério, sem mudar o resto.

### 12. A `cobertura` recusa `teto-despachos:` ilegível [tipo: implementar]
atende: D14
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-cobertura-teto.sh`, `scripts/testa-estado.sh`, `scripts/testa-conferir-fluxo.sh`
depende de: 7
paralela: nao
prova: `bash scripts/testa-cobertura-teto.sh`
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `if (tetoDeclarado.erro) erros.push(`
  para: `if (false) erros.push(`
  bateria: `bash scripts/testa-cobertura-teto.sh`
  fixture: `testa-cobertura-teto.sh, caso "teto-despachos: abc recusa na cobertura"`
pronto quando: com um design e um plano reais num repo-caixa (copiados de `docs/rainforest/design/2026-10-10-flaky-teto.md` e deste plano, só o cabeçalho variando), `node scripts/conferir-fluxo.cjs cobertura --slug <s>` sai 2 citando o texto lido e o caminho do plano para `teto-despachos: abc`, `0`, `-1`, `1.5`, `10000`, valor vazio e duas linhas `teto-despachos:` no cabeçalho; sai 0 sem a linha, com `teto-despachos: 5` e com a linha depois do primeiro `## ` (ignorada, como no hook); e o mesmo texto de plano dá a mesma resposta (aceita/recusa) no hook da tarefa 7 e na `cobertura`, porque os dois chamam `lerTetoDeclarado` de `hooks/lib/teto-despachos.cjs` — provado por `bash scripts/testa-cobertura-teto.sh` com `falhou: 0` e por `node scripts/conferir-fluxo.cjs cobertura --slug 2026-10-10-flaky-teto` saindo 0 neste repositório

Nota: código a nascer, e nenhum caso de teste afirma sobre o texto do fonte. Forma prescrita: em `cmdCobertura`, depois de ler o plano, `const tetoDeclarado = lerTetoDeclarado(conteudo_plano);` e, numa linha só, `if (tetoDeclarado.erro) erros.push(` com a mensagem — uma ocorrência. O erro entra na mesma lista `erros` que já recusa com exit 2; nenhum leitor de cabeçalho próprio no `conferir-fluxo.cjs`.

Emenda (revisar, 2026-10-11): `testa-estado.sh` e `testa-conferir-fluxo.sh` montam caixas com uma lista fixa de libs de `hooks/lib/`; com o `require` de `teto-despachos.cjs` desta tarefa, as duas quebraram (`Cannot find module`) e a lib entrou nas listas. Pronto quando as duas saem com zero falhas: `bash scripts/testa-estado.sh` e `bash scripts/testa-conferir-fluxo.sh`.
