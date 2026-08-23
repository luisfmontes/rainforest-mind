# Plano: Divergir como workflow — grafo em código, não em prosa

Design: docs/rainforest/design/divergir-como-workflow.md

Fato apurado no `plano`, que fechou o item "Em aberto" sobre a prova de
isolamento: o `journal.jsonl` do workflow **não serve** — ele só grava linhas
`started` (`type,key,agentId`) e `result` (`type,key,agentId,result`), sem o
prompt. O prompt está na **primeira linha de cada `agent-<id>.jsonl`** do mesmo
diretório (`type=user`, `role=user`), e o `agent-<id>.meta.json` ao lado traz
`agentType`. A prova é feita ali, não no journal.

## O que não pode quebrar

- As 39 baterias existentes continuam verdes.
- **Node continua sendo a única dependência.** O conferidor e o registrador são
  `.cjs`; nada de Python novo — o gêmeo `ideias.py` está sendo aposentado em
  paralelo justamente por isso.
- **O critério de "quando NÃO usar" continua sendo lido antes do gasto.** Ele
  vive na `SKILL.md` (D1) e não pode virar comentário dentro do script, onde
  seria lido depois dos sete despachos.
- Nada escreve em `ideias.jsonl`. O registro de divergência é arquivo próprio.
- A pasta `workflows/` nova não pode quebrar o carregamento do plugin em
  nenhum dos dois perfis.
- O `divergir` continua **não decidindo**: quem monta a decisão numerada para o
  usuário é a janela principal.

## Tarefas

### 1. Escrever o script do grafo [tipo: implementar]
atende: D2, D3, D5, D6, D8, D10
arquivos: `workflows/divergir-frames.js`
depende de: nenhuma
paralela: sim
pronto quando: com o enunciado de um problema real passado em `args`, a invocação de `rainforest-mind:divergir-frames` devolve objeto com as quatro chaves `shortlist`, `escolha_nao_obvia`, `critico_bateu_na_primeira_da_rodada` e `refutacao`, e `escolha_nao_obvia` não vem vazio — provado por gravar o retorno em `div.json` e `node -e "const o=require('./div.json'); const f=['shortlist','escolha_nao_obvia','critico_bateu_na_primeira_da_rodada','refutacao'].filter(k=>!(k in o)); if(f.length||!o.escolha_nao_obvia){console.error('faltou:',f);process.exit(1)} console.log('ok')"` devolvendo `ok` e exit 0
nota: o nome do quarto campo era `bate_com_a_primeira_ideia` quando esta tarefa foi escrita, e a tarefa 8 o renomeou pela **D11**. O critério ficou apontando para o nome velho e só foi pego pelo segundo `revisar` — rodado literalmente, ele reprovaria código correto no `verificar`. Renomear campo exige varrer os critérios de pronto que o citam, não só o código.
mutacao:
  arquivo: `workflows/divergir-frames.js`
  de: cada um dos seis `agent()` da fase 1 recebe só o enunciado vindo de `args`
  para: o segundo frame em diante recebe `enunciado + JSON.stringify(resultado do primeiro frame)`, quebrando o isolamento sem quebrar o formato de saída
  bateria: `scripts/conferir-divergencia.cjs` sobre o transcript da rodada — tem que sair diferente de 0 apontando qual agente recebeu prompt divergente

### 2. Escrever o conferidor de isolamento e sua bateria [tipo: teste]
atende: D2, D3
arquivos: `scripts/conferir-divergencia.cjs`, `scripts/testa-conferir-divergencia.sh`
depende de: nenhuma
paralela: sim
pronto quando: apontado para o diretório de transcript de uma rodada real (`.../subagents/workflows/wf_<id>/`), o conferidor lê a primeira linha `type=user` de cada `agent-*.jsonl`, afirma que há exatamente 6 prompts de frame idênticos byte a byte entre si e 1 prompt de crítico distinto deles, e sai 0; e com um diretório de fixture em que um dos seis prompts teve um caractere trocado, sai diferente de 0 nomeando o agente divergente — provado por `bash scripts/testa-conferir-divergencia.sh` devolvendo exit 0 com as duas asserções verdes
mutacao:
  arquivo: `scripts/conferir-divergencia.cjs`
  de: a comparação que exige os seis prompts de frame idênticos entre si
  para: a comparação sempre verdadeira (`return true`), aceitando qualquer conjunto de prompts
  bateria: `scripts/testa-conferir-divergencia.sh` — tem que reprovar, porque o caso negativo da fixture passaria a ser aceito

### 3. Escrever o enunciado-isca do teste de isolamento [tipo: docs]
atende: D2
arquivos: `docs/rainforest/design/divergir-como-workflow.md`
depende de: nenhuma
paralela: sim
pronto quando: o design ganha uma seção `### Enunciado-isca` com um problema concreto e curto que tenha uma solução óbvia sedutora e ao menos duas não-óbvias defensáveis, mais a resposta esperada de cada um dos seis frames em uma linha — provado por `grep -c "^### Enunciado-isca" docs/rainforest/design/divergir-como-workflow.md` devolvendo `1` e `grep -A40 "^### Enunciado-isca" docs/rainforest/design/divergir-como-workflow.md | grep -cE "^- .(restricao-dura|inversao|incentivo|ja-existe|modo-de-falha|premissa)."` devolvendo `6`
mutacao: n/a
motivo: tarefa de documentação sem comportamento a inverter — o artefato é texto lido por humano e por agente, e não há código que possa ser mutado para provar que a bateria discrimina. O critério de pronto já é falsificável por grep contando os seis frames.

### 4. Escrever o registrador de rodadas, com bateria e prova de mutação [tipo: implementar]
atende: D4, D7, D9
arquivos: `scripts/divergencias.cjs`, `scripts/testa-divergencias.sh`
depende de: nenhuma
paralela: sim
pronto quando: num `$RAINFOREST_DIR` temporário com 3 linhas pré-existentes, `node scripts/divergencias.cjs abrir < rodada.json` acrescenta uma linha com `status:"aberta"` e data carimbada pelo relógio local, e `node scripts/divergencias.cjs fechar --id <id> < escolha.json` reescreve aquela linha com `status:"fechado"`, a escolha do usuário e o booleano `bate_com_a_primeira_ideia`, com as 3 linhas não-alvo byte a byte idênticas ao original — provado por `bash scripts/testa-divergencias.sh` devolvendo exit 0
mutacao:
  arquivo: `scripts/divergencias.cjs`
  de: a conferência byte a byte das linhas não-alvo antes de confirmar a gravação
  para: a conferência removida, deixando a gravação confirmar sem provar que só a linha alvo mudou
  bateria: `scripts/testa-divergencias.sh` — tem que reprovar na seção que corrompe uma linha não-alvo e espera reversão

### 5. Fazer a SKILL.md invocar o workflow [tipo: docs]
atende: D1, D5
arquivos: `skills/divergir/SKILL.md`
depende de: 1
paralela: nao
pronto quando: a `SKILL.md` deixa de instruir despacho manual de `Agent` e passa a mandar invocar `rainforest-mind:divergir-frames`, mantendo intactas as três seções de julgamento — provado por `grep -c "divergir-frames" skills/divergir/SKILL.md` devolvendo ao menos `1`, e `grep -c "Antes de qualquer coisa" skills/divergir/SKILL.md` e `grep -c "O que falsificaria" skills/divergir/SKILL.md` devolvendo `1` cada
mutacao: n/a
motivo: tarefa de documentação — a mudança é de texto de instrução, sem comportamento próprio a inverter. O comportamento que ela aciona é o do script da tarefa 1, cuja mutação já está declarada lá. Mutar esta SKILL.md provaria a bateria da tarefa 1, não uma bateria desta.

### 6. Rodada ponta a ponta contra o enunciado-isca [tipo: teste]
atende: D1, D2, D3, D5, D6, D8, D9, D10
arquivos: `docs/rainforest/estado/divergir-como-workflow.json`
depende de: 1, 2, 3, 4, 5
paralela: nao
pronto quando: invocando a skill `divergir` com o enunciado-isca da tarefa 3, o grafo roda com sete despachos, o conferidor da tarefa 2 aprova o isolamento daquela rodada e o registrador da tarefa 4 grava a linha `aberta` — provado por `node scripts/conferir-divergencia.cjs <dir-da-rodada>` devolvendo exit 0 e por `node -e "const fs=require('fs');const l=fs.readFileSync(process.env.RAINFOREST_DIR+'/divergencias.jsonl','utf8').trim().split('\n');const u=JSON.parse(l[l.length-1]);if(u.status!=='aberta')process.exit(1);console.log('ok')"` devolvendo `ok`
mutacao: n/a
motivo: tarefa de integração — ela não entrega artefato próprio, exercita os das tarefas 1, 2 e 4 juntos, e as mutações desses três já estão declaradas em cada uma. Uma mutação aqui seria mutação de um deles, contada duas vezes.

### 7. Allowlist na entrada do `fechar` [tipo: implementar]
atende: D7, D9
arquivos: `scripts/divergencias.cjs`, `scripts/testa-divergencias.sh`
depende de: nenhuma
paralela: sim
pronto quando: com o stdin `{"escolha":"y","bate_com_a_primeira_ideia":true,"id":"FORJADO","shortlist":["sequestrada"]}` mandado para `fechar --id <rodada existente>`, o comando **recusa com exit != 0** nomeando os campos não permitidos, e a linha no `.jsonl` continua com o `id` e a `shortlist` originais byte a byte — provado por `bash scripts/testa-divergencias.sh` devolvendo exit 0 com a asserção nova verde
mutacao:
  arquivo: `scripts/divergencias.cjs`
  de: a allowlist de campos aceitos no `fechar`
  para: removida, voltando ao `Object.assign(obj, entrada)` cru
  bateria: `scripts/testa-divergencias.sh` — tem que reprovar na asserção do payload forjado

### 8. Desdobrar as duas medidas de ancoragem [tipo: implementar]
atende: D11, D4, D8, D10
arquivos: `workflows/divergir-frames.js`, `scripts/divergencias.cjs`, `scripts/testa-divergencias.sh`, `skills/divergir/SKILL.md`
depende de: 7
paralela: nao
pronto quando: `abrir` passa a **exigir e persistir** `critico_bateu_na_primeira_da_rodada` (booleano) e `ideias` (lista das ideias cruas), o schema do crítico no workflow devolve o campo com o nome novo, e `fechar` continua exigindo `bate_com_a_primeira_ideia` — provado por, num `$RFM_ROOT` temporário, `abrir` seguido de `fechar` produzir uma linha que contém **os dois** campos com valores distintos e a lista `ideias` não vazia, conferido por `node -e` lendo o `.jsonl`; e por `bash scripts/testa-divergencias.sh` exit 0
mutacao:
  arquivo: `scripts/divergencias.cjs`
  de: a persistência da lista `ideias` no `abrir`
  para: o campo descartado silenciosamente, como hoje
  bateria: `scripts/testa-divergencias.sh` — tem que reprovar na asserção que exige `ideias` não vazia na linha gravada

### 9. O `fechar` valida o registro inteiro, não só o diff [tipo: implementar]
atende: D12, D4, D7
arquivos: `scripts/divergencias.cjs`, `scripts/testa-divergencias.sh`
depende de: nenhuma
paralela: sim
pronto quando: com um `.jsonl` contendo uma linha anterior à D11 (sem `ideias`, sem `critico_bateu_na_primeira_da_rodada`, com os campos `critico_viu_ancoragem` e `origem`), `fechar --id <ela>` **recusa com exit != 0** nomeando o que está fora do schema, e a linha continua `status: "aberta"` byte a byte — provado por `bash scripts/testa-divergencias.sh` exit 0 com a asserção nova verde
mutacao:
  arquivo: `scripts/divergencias.cjs`
  de: a validação do registro completo depois da fusão, no `fechar`
  para: removida, voltando a validar só o diff da entrada
  bateria: `scripts/testa-divergencias.sh` — tem que reprovar na asserção da linha legada

### 10. Subcomando de reparo para linha legada [tipo: implementar]
atende: D12
arquivos: `scripts/divergencias.cjs`, `scripts/testa-divergencias.sh`
depende de: 9
paralela: nao
pronto quando: com a mesma linha legada da tarefa 9 e um stdin trazendo `ideias` e `critico_bateu_na_primeira_da_rodada`, o subcomando de reparo produz uma linha que passa na validação da tarefa 9 — com `critico_viu_ancoragem` **renomeado** (valor preservado, não recriado), `origem` **mantido**, e as demais linhas do arquivo byte a byte idênticas; e `fechar` naquela linha passa a sair 0 — provado por `bash scripts/testa-divergencias.sh` exit 0 com as asserções novas verdes
mutacao:
  arquivo: `scripts/divergencias.cjs`
  de: o renomeio de `critico_viu_ancoragem` para `critico_bateu_na_primeira_da_rodada` no reparo
  para: o campo apenas descartado, e o novo criado com valor padrão
  bateria: `scripts/testa-divergencias.sh` — tem que reprovar na asserção que exige o VALOR original preservado, não um padrão

### 11. O reparo não sobrescreve valor novo já válido [tipo: implementar]
atende: D12
arquivos: `scripts/divergencias.cjs`, `scripts/testa-divergencias.sh`
depende de: nenhuma
paralela: sim
pronto quando: com uma linha carregando **os dois** nomes — `critico_bateu_na_primeira_da_rodada: true` (já correto) e `critico_viu_ancoragem: false` (residual) — o reparo **preserva o `true`** e apaga só o campo velho, espelhando a guarda que a migração de `ideias` já tem — provado por `bash scripts/testa-divergencias.sh` exit 0 com a asserção nova verde
mutacao:
  arquivo: `scripts/divergencias.cjs`
  de: a guarda que só renomeia quando o campo novo ainda não é booleano
  para: removida, voltando a deixar o campo velho vencer sempre
  bateria: `scripts/testa-divergencias.sh` — tem que reprovar na asserção da linha com nome duplo

### 12. A asserção do payload forjado para de passar por vacuidade [tipo: teste]
atende: D7, D9
arquivos: `scripts/testa-divergencias.sh`
depende de: 11
paralela: nao
nota: declarada `paralela: sim` no primeiro rascunho desta emenda, junto com a 11 — as duas tocam `scripts/testa-divergencias.sh`. É **o mesmo erro** que a nota da rodada 2 já tinha diagnosticado e corrigido para as tarefas 7/8, repetido duas rodadas depois. Pego pela quarta revisão. Que a regra estivesse escrita no próprio arquivo, a poucas linhas de distância, não impediu a reincidência — o que sugere que ela precisa virar checagem do conferidor de plano, não parágrafo.
pronto quando: a asserção deixa de varrer a mensagem de erro com `grep -q "id"` e passa a conferir os campos efetivamente recusados — hoje ela casa incondicionalmente, porque `id` é substring de `permitidos`, que está no texto fixo da mensagem — provado por, com a lista de campos permitidos do `fechar` invertida, a bateria **reprovar** nessa asserção
mutacao:
  arquivo: `scripts/divergencias.cjs`
  de: `CAMPOS_PERMITIDOS_FECHAR` com `escolha` e `bate_com_a_primeira_ideia`
  para: invertida para `id` e `shortlist`, fazendo o comando recusar os campos legítimos e aceitar os forjados
  bateria: `scripts/testa-divergencias.sh` — tem que reprovar; hoje a sub-asserção do grep sobreviveria

## Notas de execução

- **Tarefas 1, 2, 3 e 4 são paralelas** — nenhuma depende de outra e tocam
  arquivos disjuntos. As 5 e 6 são seriais.
- A tarefa 6 é a única que gasta os sete despachos de verdade. As outras cinco
  não invocam o grafo.
- O subcomando `conferir` do `divergencias.cjs` (item que ficou "Em aberto" no
  design) **não entra neste plano**: só faz sentido com arquivo que já tenha
  linha suficiente para conferir, e depois da tarefa 6 haverá uma. Volta como
  ideia plantada, não como tarefa com placeholder.

### Rodada 2 — tarefas 7 e 8, acrescentadas em 2026-08-23

Vieram do `revisar`, que reprovou a primeira rodada com três achados: a 7
conserta a porta de escrita, a 8 conserta a semântica do campo de ancoragem.

As duas são **seriais, não paralelas** — e isso foi correção de um erro do
primeiro rascunho desta emenda, que as declarava paralelas. Ambas tocam
`scripts/divergencias.cjs` e `scripts/testa-divergencias.sh`; dois worktrees
editando os mesmos dois arquivos é conflito na integração, não paralelismo. A
regra que o plano já tinha — `paralela: sim` só quando `depende de: nenhuma` —
não basta sozinha: independência de **ordem** não implica disjunção de
**arquivos**, e é a segunda que decide se dá para paralelizar.

O **terceiro achado fica de fora deste plano, de propósito**. Ele é real e a
raiz está localizada — `scripts/estado.cjs:671` faz
`{ ...estado[estagio], ...extra, status }`, então o `pendentes` gravado num
`parcial` sobrevive à transição para `ok` e produz um registro que se
contradiz (`tarefas_ok: 6` de `6` com pendência listada). Mas isso é defeito da
**maquinaria do fluxo**, não desta entrega: vale para qualquer trabalho que
passe por `parcial`, e nenhuma das onze decisões deste design fala de estado.
Bundlá-lo aqui seria o creep que o próprio `revisar` existe para pegar. Sai como
trabalho próprio, com branch e PR separados.
