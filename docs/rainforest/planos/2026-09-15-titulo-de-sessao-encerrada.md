# Plano: título da sessão marca se o fluxo fechou ou onde parou

Design: docs/rainforest/design/2026-09-15-titulo-de-sessao-encerrada.md

## O que não pode quebrar

- **O contrato do `heartbeat.cjs` fica intacto.** Ele continua fazendo
  `delete state[session_id]` no `SessionEnd` (linha 59) e gravando o
  `sessoes.json` sem lock. O ledger novo é **outro arquivo**; nenhuma tarefa
  aqui altera `hooks/heartbeat.cjs`.
- **O `estado.cjs` mantém os exit codes de hoje.** `iniciar` sai 1 em slug
  repetido, `exigir` sai 2 em pré-requisito aberto, `marcar` sai 2 na trava de
  formato e na trava de cobertura. O carimbo é efeito colateral; falha ao gravar
  o ledger **não** pode mudar exit code nem abortar o verbo.
- **Nada escreve fora da raiz de dados do plugin** (`hooks/lib/raiz.cjs`,
  `resolverRaiz`) e fora do transcript da própria sessão.
- **O transcript nunca é corrompido.** A única escrita permitida é o append de
  **uma** linha JSON válida terminada em `\n`. Nada de reescrever, truncar ou
  reordenar linha existente.
- **Sessão sem fluxo carimbado sai sem título.** Repo sem `docs/rainforest/estado/`
  (o `inovacao`, por exemplo) e sessão que não rodou verbo nenhum não recebem
  escrita — silêncio, não `[ok]`.
- **Nenhuma sessão já existente é reescrita** (D2): o hook só toca o transcript
  cujo `session_id` está no ledger.

## Emendas ao plano

Registradas antes do `revisar`, porque creep se destrava emendando o plano —
justificar em prosa não destrava.

- **2026-09-15, tarefa 1 — `.gitignore` entrou no `arquivos:`.** O executor
  descobriu que `fluxos-sessao.json` não estava ignorado, enquanto o
  `sessoes.json` (mesma raiz de dados) estava. Sem a linha, numa instalação
  auto-hospedada do plugin o ledger cairia na raiz do repo e sujaria o
  `git status` de todo dev.
- **2026-09-15, tarefa 2 — a Parte A entrou no `arquivos:`.** O plano original
  mandava o ledger gravar `{slug, estagio}`, e isso **não distingue**
  `exigir --estagio fechar` (fluxo aberto) de `marcar --estagio fechar --status ok`
  (fluxo completo) — sem a distinção o D8 não tem como decidir `[ok]`. O campo
  `aberto` (próximo estágio não-fechado, `null` quando completou) corrige o furo,
  e mexer nele obriga a tocar `hooks/lib/ledger-fluxos.cjs`, `scripts/estado.cjs`
  e `hooks/testa-ledger-fluxos.sh`, que eram da tarefa 1.

## Tarefas

### 1. Ledger de fluxos por sessão, escrito pelos três verbos [tipo: implementar]
atende: D5, D12
arquivos: `hooks/lib/ledger-fluxos.cjs`, `scripts/estado.cjs`, `hooks/testa-ledger-fluxos.sh`, `.gitignore`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/ledger-fluxos.cjs`
  de: a escrita que faz merge de `{slug, estagio}` na entrada de `session_id` antes do `fs.writeFileSync` do ledger
  para: `return;` imediatamente antes dessa escrita
  bateria: `bash hooks/testa-ledger-fluxos.sh`
  fixture: `testa-ledger-fluxos.sh, caso "iniciar carimba slug e estagio sob o CLAUDE_SESSION_ID do ambiente"`
pronto quando: com `CLAUDE_SESSION_ID=11111111-1111-1111-1111-111111111111 RFM_ESTADO_ROOT=<sandbox> node scripts/estado.cjs iniciar --slug teste-carimbo --titulo "t"`, o `fluxos-sessao.json` da raiz de dados passa a ter a chave desse UUID com `[{slug:"teste-carimbo", estagio:"design"}]` — provado por `node -e "const l=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const f=l['11111111-1111-1111-1111-111111111111'];console.log(f[0].slug, f[0].estagio)" <ledger>` imprimindo `teste-carimbo design`, e pelo mesmo comando depois de `exigir --estagio plano` e `marcar --estagio plano --status ok` imprimindo `teste-carimbo plano` (último estágio conhecido, entrada única por slug)

### 2. Hook de título no SessionEnd [tipo: implementar]
atende: D1, D3, D4, D6, D7, D8, D9, D10, D11
arquivos: `hooks/titulo-sessao-end.cjs`, `hooks/testa-titulo-sessao-end.sh`, `hooks/lib/ledger-fluxos.cjs`, `scripts/estado.cjs`, `hooks/testa-ledger-fluxos.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/titulo-sessao-end.cjs`
  de: a guarda `if (data.reason !== 'prompt_input_exit') process.exit(0)`
  para: remover a guarda, deixando qualquer `reason` seguir
  bateria: `bash hooks/testa-titulo-sessao-end.sh`
  fixture: `testa-titulo-sessao-end.sh, caso "reason=clear nao escreve nada no transcript"`
pronto quando: com o payload real de 6 campos medido em 2026-09-15
  (`{"cwd","hook_event_name":"SessionEnd","prompt_id","reason":"prompt_input_exit","session_id","transcript_path"}`)
  no stdin e um transcript-fixture **copiado de sessão real** (contendo uma linha
  `{"type":"ai-title","aiTitle":"Confirmação simples",...}`) com o `session_id`
  carimbado no ledger no estágio `design`, a última linha do transcript passa a ser
  `{"type":"custom-title","customTitle":"[aberto: design] Confirmação simples","sessionId":"<id>"}`
  — provado por `tail -1 <fixture> | node -e "const o=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(o.type, o.customTitle)"` imprimindo
  `custom-title [aberto: design] Confirmação simples`; e, com o mesmo fixture e o
  ledger marcando `fechar` fechado, imprimindo `custom-title [ok] Confirmação simples`

### 3. Registrar o hook no `hooks.json`, síncrono [tipo: configurar]
atende: D13
arquivos: `hooks/hooks.json`, `hooks/testa-titulo-sessao-registro.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/hooks.json`
  de: a entrada nova de `SessionEnd` que chama `titulo-sessao-end.cjs` sem `async`
  para: acrescentar `"async": true` nessa entrada
  bateria: `bash hooks/testa-titulo-sessao-registro.sh`
  fixture: `testa-titulo-sessao-registro.sh, caso "a entrada de titulo-sessao-end e sincrona"`
pronto quando: com o `hooks/hooks.json` que o Claude Code realmente carrega, existe
  exatamente uma entrada de `SessionEnd` apontando para `titulo-sessao-end.cjs`, ela
  **não** tem `async: true`, e está num grupo separado do `heartbeat.cjs` — provado por
  `node -e "const h=require('./hooks/hooks.json').hooks.SessionEnd;const e=h.flatMap(g=>g.hooks).filter(x=>x.command.includes('titulo-sessao-end'));console.log(e.length, e[0].async===undefined)"`
  imprimindo `1 true`

### 4. Teste: sem carimbo no ledger, o hook não escreve [tipo: teste]
atende: D2
arquivos: `hooks/testa-titulo-sessao-sem-carimbo.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `hooks/titulo-sessao-end.cjs`
  de: a guarda que sai quando o ledger não tem entrada para o `session_id` recebido
  para: seguir adiante e escrever o título com o marcador padrão
  bateria: `bash hooks/testa-titulo-sessao-sem-carimbo.sh`
  fixture: `testa-titulo-sessao-sem-carimbo.sh, caso "session_id ausente do ledger deixa o transcript byte-a-byte igual"`
pronto quando: com o payload real de `reason: "prompt_input_exit"` e um `session_id`
  **ausente** do ledger, o transcript-fixture fica byte-a-byte idêntico — provado por
  `sha256sum` antes e depois devolvendo o mesmo hash, e pelo mesmo teste com um
  fixture que **já tem** `custom-title` de `/rename` confirmando que a linha antiga
  continua sendo a última

### 5. Documentar o marcador e o filtro do `/resume` [tipo: docs]
atende: D6, D7
arquivos: `README.md`, `skills/fechar/SKILL.md`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: doc não tem comportamento a inverter; a falsificação dela é casar com os literais que o hook realmente escreve e com a decisão do design.
pronto quando: os dois marcadores literais que o hook escreve (`[ok] ` e
  `[aberto: `) aparecem no `README.md` extraídos **do fonte do hook**, não digitados
  — provado por `node -e "const s=require('fs').readFileSync('hooks/titulo-sessao-end.cjs','utf8');const m=[...new Set([...s.matchAll(/[\`']\[(ok|aberto: )/g)].map(x=>x[1]))];if(m.length!==2)throw new Error('esperava 2 marcadores no fonte, achei '+m.length);const r=require('fs').readFileSync('README.md','utf8');console.log(m.join(','), m.every(x=>r.includes('['+x)))"`
  imprimindo `ok,aberto:  true` — a asserção de **dois** marcadores é obrigatória:
  a versão anterior deste comando casava só aspas simples, e `[aberto: ` é template
  string no fonte, então o `every` passava trivialmente sobre um array de um
  elemento (achado 2 da revisão de 2026-09-15); e a nota acrescentada em `skills/fechar/SKILL.md` registra que a
  recusa da linha 168 (pendurar o `concluido` no `SessionEnd`) segue valendo para
  **aviso falado** e não cobre título escrito em sessão já encerrada — provado por
  `rg -c "aviso falado" skills/fechar/SKILL.md` devolvendo `1` e pela leitura do
  `revisar` conferindo que o texto não contradiz a decisão "Fora de escopo" do design

### 6. Consertar o nome da variável de sessão, e provar contra o ambiente real [tipo: implementar]
atende: D5, D12
arquivos: `hooks/lib/ledger-fluxos.cjs`, `scripts/estado.cjs`, `hooks/testa-ledger-fluxos.sh`
depende de: 1, 2
paralela: nao
mutacao:
  arquivo: `hooks/lib/ledger-fluxos.cjs`
  de: a leitura de `process.env.CLAUDE_CODE_SESSION_ID`
  para: `process.env.CLAUDE_SESSION_ID` — o nome errado, que é exatamente o defeito que esta tarefa conserta
  bateria: `bash hooks/testa-ledger-fluxos.sh`
  fixture: `testa-ledger-fluxos.sh, o caso novo "carimba com o nome REAL da variavel, sem injetar CLAUDE_SESSION_ID"`
pronto quando: com **apenas** `CLAUDE_CODE_SESSION_ID` no ambiente e
  `CLAUDE_SESSION_ID` explicitamente ausente (`env -u CLAUDE_SESSION_ID`), rodar
  `node scripts/estado.cjs iniciar --slug prova-var --titulo "t"` cria o
  `fluxos-sessao.json` com a entrada daquele id — provado por
  `node -e "const l=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const k=Object.keys(l);console.log(k.length, k[0]===process.env.CLAUDE_CODE_SESSION_ID)" <ledger>`
  imprimindo `1 true`

**Por que esta tarefa existe** (achado 1 da revisão de 2026-09-15, bloqueante):
`CLAUDE_SESSION_ID` **não existe** no ambiente do Claude Code — `printenv
CLAUDE_SESSION_ID` sai 1, e a variável real é `CLAUDE_CODE_SESSION_ID`. Medido
nesta máquina: o ledger de `C:\Users\Luis\.rainforest\fluxos-sessao.json` **não
foi criado** apesar de esta sessão ter rodado `iniciar`, quatro `exigir` e vários
`marcar` no mesmo dia. As 41 asserções das quatro baterias passavam porque
**todas injetavam `CLAUDE_SESSION_ID` à mão** — nenhuma rodava contra o nome que
o harness realmente exporta. É o defeito de 2026-08-19 outra vez: payload que a
produção nunca produz.

O `scripts/estado.cjs` tem a mesma leitura errada numa linha **pré-existente**
(o carimbo `sessao` de `processarCarimbos`), e é dela que o D12 tirou a conclusão
"a peça já existe". A prova de que estava errada está nos próprios arquivos de
estado do repo: todo carimbo gravado tem `"sessao": "desconhecida"`. Conserte as
duas leituras.

**Compatibilidade:** aceite `CLAUDE_CODE_SESSION_ID` e, só como reserva,
`CLAUDE_SESSION_ID` — nesta ordem. A reserva não custa nada e cobre host que
exporte o nome antigo.

**Limitação a registrar em comentário, não a resolver aqui:** não existe
`CLAUDE_CODE_PARENT_SESSION_ID`. Subagente que rode um verbo do `estado.cjs`
carimba o **próprio** id, e o hook roda no `SessionEnd` da sessão-mãe, então
aquele carimbo não será visto. Na prática os verbos são rodados pela janela
principal (as skills do fluxo mandam assim). `CLAUDE_CODE_CHILD_SESSION=1` não
serve para distinguir: ele está presente também no shell da janela principal —
medido em 2026-09-15.

### 7. Fechar os três achados da segunda revisão [tipo: implementar]
atende: D4, D5
arquivos: `hooks/lib/ledger-fluxos.cjs`, `hooks/testa-ledger-fluxos.sh`, `hooks/testa-titulo-sessao-end.sh`
depende de: 6
paralela: nao
mutacao:
  arquivo: `hooks/titulo-sessao-end.cjs`
  de: `fs.appendFileSync(caminho, linha)`
  para: `fs.writeFileSync(caminho, linha)` — trunca o transcript, que é exatamente o que o D4 promete nunca acontecer
  bateria: `bash hooks/testa-titulo-sessao-end.sh`
  fixture: `testa-titulo-sessao-end.sh, a asserção nova de contagem de linhas do TESTE 1`
pronto quando: com a mutação `appendFileSync` -> `writeFileSync` aplicada no
  `hooks/titulo-sessao-end.cjs`, `bash hooks/testa-titulo-sessao-end.sh` sai **1** e a
  falha aponta a contagem de linhas — provado pelo `conferir-mutacao.cjs` com esse
  `--de`/`--para` saindo 0; e, com o fonte íntegro, um transcript de 3 linhas vira 4
  com as 3 primeiras byte-a-byte iguais — provado por `head -n -1 <depois> | sha256sum`
  batendo com `sha256sum <antes>`

**Achado 1 — corrida de escrita no ledger.** `carimbarFluxo` faz
leitura-modificação-escrita sem lock e sem escrita atômica. Reproduzido na revisão
de 2026-09-15: 80 processos simultâneos contra o mesmo `RFM_ROOT` e **9 de 80
chaves sobreviveram**. Duas janelas do usuário chamando um verbo quase junto
perdem carimbo — e pode ressuscitar `aberto: "design"` sobre um `aberto: null`
mais recente, que é título **errado**, pior que título ausente (o D2 existe para
evitar justamente isso). Conserto: lockfile exclusivo (`fs.openSync` com flag
`wx`) em volta do ciclo inteiro, com poucas tentativas e desistência **silenciosa**
se não conseguir, mais escrita atômica (arquivo temporário + `fs.renameSync`). A
invariante do "O que não pode quebrar" continua valendo: nunca lança, nunca muda
exit code.

**Achado 2 — a poda de 24 h apaga carimbo de sessão viva.** O `ts` do ledger só
se atualiza quando **aquela** sessão chama um verbo, não a cada interação — ao
contrário do `heartbeat.cjs`, que atualiza a cada prompt. Sessão que roda
`iniciar` na sexta e fica aberta num `executar` longo perde o carimbo quando outra
sessão dispara a poda na segunda, e fecha sem título. Isso contraria a premissa do
D5 ("a entrada só precisa viver até o `SessionEnd` da própria sessão"). Conserto:
janela de poda de **30 dias** em vez de 24 h, mais teto de **500 entradas** (as
mais recentes ficam) para o arquivo não crescer sem limite. Corrija também o
comentário do D5 no design.

**Achado 3 — a bateria é cega a truncamento.** Todas as asserções de escrita de
`testa-titulo-sessao-end.sh` usam `tail -1`. Trocar `appendFileSync` por
`writeFileSync` destrói o transcript (3 linhas viram 1) e as seis asserções
continuam **verdes**. Conserto: em cada caso que escreve, afirmar que o arquivo
cresceu **exatamente uma linha** e que `head -n -1` do resultado é byte-a-byte
igual ao conteúdo de antes.
