# Plano: Orçamento — medida estável e folga declarada

Design: docs/rainforest/design/2026-08-24-orcamento-medida-estavel-e-folga.md

## O que não pode quebrar

- **O veredito de qualquer bateria não pode depender da raiz de dados da máquina.**
  É o defeito que esta entrega conserta; reintroduzi-lo em outro ponto anula tudo.
- **Nenhum valor de teto muda** (D6): `NUCLEOS_MAX_BYTES: 5600`, `ORCAMENTO_BYTES: 8000`,
  `FOCO_MAX_BYTES: 2600`, `FOCO_MIN_BYTES: 700` e o `|| 14000` de `scripts/orcamento.cjs:164`
  ficam nos valores de hoje.
- **A perna vermelha continua vermelha.** `scripts/testa-orcamento.sh` seção 2
  (`--teto 1000` estoura e sai 1) e a seção 5 (mutante) provam que o gate acusa. Aviso
  novo não pode transformar estouro em aviso: acima do teto continua sendo exit 1.
- **A regressão de 2026-08-13 continua coberta.** Frontmatter em CRLF não pode medir
  0 B (`scripts/testa-orcamento.sh:63-96`); nenhuma fonte pode sair como `: 0 B`.
- **D8 de `skills-finas-com-references` continua valendo**: `references/` fora do
  agregado (`scripts/testa-orcamento.sh:98-131`) — o total não muda quando a pasta aparece.
- **A bateria não escreve na raiz de dados do usuário.** Toda fixture nasce em
  `mktemp -d` e morre no `trap` (regra 15).

## Tarefas

### 1. Lib da banda de folga e da mensagem que enuncia a decisão [tipo: implementar]
atende: D4, D5
arquivos: `hooks/lib/folga.cjs`, `scripts/testa-folga.sh`
depende de: nenhuma
paralela: sim

Cria `avaliarFolga(valor, teto, { banda = 0.05, nome, alternativas })` devolvendo
`{ estado: 'ok'|'aviso'|'estouro', folga, limiar, pct, mensagem }`. `limiar` é
`Math.round(teto * banda)`; `folga < 0` é `estouro`, `folga < limiar` é `aviso`, o resto
é `ok`. A `mensagem` de `aviso` e de `estouro` nomeia o trade-off recebido em
`alternativas` — de onde sai o byte — e **nunca** prescreve o conserto (D5). É o único
lugar onde a banda existe: as tarefas 2 e 4 consomem esta função, não recalculam.

mutacao:
  arquivo: `hooks/lib/folga.cjs`
  de: `folga < limiar`
  para: `folga < 0`
  bateria: `bash scripts/testa-folga.sh`
  fixture: `scripts/testa-folga.sh`, seção "2. dentro da banda avisa sem reprovar" — o caso `avaliarFolga(5589, 5600)`, que é o dos núcleos hoje
pronto quando: com os três pares reais medidos em 2026-08-24 — `(5589, 5600)`, `(7924, 8000)` e `(13096, 14000)` — `avaliarFolga` devolve `aviso`, `aviso` e `ok` nessa ordem, e a mensagem dos dois primeiros contém as alternativas passadas e não contém a string `reduz` — provado por `node -e "const {avaliarFolga}=require('./hooks/lib/folga.cjs'); console.log([[5589,5600],[7924,8000],[13096,14000]].map(([v,t])=>avaliarFolga(v,t).estado).join(' '))"` devolvendo `aviso aviso ok`

### 2. `orcamento.cjs` ganha a banda; `testa-orcamento.sh` passa a medir o repo, não a mesa [tipo: implementar]
atende: D1, D2, D3, D4, D6, D7
arquivos: `scripts/orcamento.cjs`, `scripts/testa-orcamento.sh`
depende de: 1
paralela: nao

Em `scripts/orcamento.cjs`: consome `avaliarFolga` para o teto do hook e para o
agregado, imprimindo o aviso em `stderr` **sem mudar o exit code** — `ok` e `aviso`
saem 0, `estouro` continua saindo 1. Nenhuma constante muda (D6, D7).

Em `scripts/testa-orcamento.sh`: a seção 1 passa a rodar com `RFM_ROOT="$RAIZ_VAZIA"`
(`mktemp -d`, sem marcador) — é ela que reprova (D1, D2). Nasce uma seção nova que roda
com a raiz real da máquina e **apenas informa** o número, sem contar para `ok`/`falhou`
(D1). Nasce outra seção que planta `$RAIZ_GORDA` (`mktemp -d` com um `FOCO.md` de
~2.500 B) e afirma que a medição neutra **não se move** com ela plantada — é o que prova
a neutralização de verdade, e roda igual no CI e na máquina do dono. E nasce a trava dos
valores congelados (D6): `grep` sobre `hooks/lib/contexto-sessao.cjs` e
`scripts/orcamento.cjs` afirmando `5600`, `8000`, `2600`, `700` e `14000`, com o motivo
da D6 escrito na mensagem de falha.

mutacao:
  arquivo: `scripts/testa-orcamento.sh`
  de: `RAIZ_VAZIA="$(mktemp -d)"`
  para: `RAIZ_VAZIA="$RAIZ_GORDA"`
  bateria: `bash scripts/testa-orcamento.sh`
  fixture: `scripts/testa-orcamento.sh`, seção "1. caminho verde — raiz neutra" — com a raiz gorda de ~2.500 B o payload do hook passa de `ORCAMENTO_BYTES`, o `orcamento.cjs` sai 1 e a asserção `igual "sai 0"` cai
pronto quando: com um `FOCO.md` de ~2.500 B plantado na raiz de dados, `node scripts/orcamento.cjs` e `bash scripts/testa-orcamento.sh` divergem de propósito — o primeiro sai 1 acusando o estouro real da mesa e o segundo sai 0, porque mede o repositório — provado por `RFM_ROOT=<raiz gorda> node scripts/orcamento.cjs; echo $?` devolvendo `1` e `RFM_ROOT=<raiz gorda> bash scripts/testa-orcamento.sh; echo $?` devolvendo `0` na mesma execução

### 3. Neutraliza os dois pontos contaminados fora do `testa-orcamento.sh` [tipo: teste]
atende: D3
arquivos: `hooks/testa-memoria-session-start.sh`, `scripts/testa-medir-injecao.sh`
depende de: nenhuma
paralela: sim

`hooks/testa-memoria-session-start.sh:137` roda `scripts/orcamento.cjs` contra a raiz
real e afirma `Hook <= 8000 B` — hoje com 76 B de folga, quebra sozinho. Passa a rodar
com raiz `mktemp -d`. `scripts/testa-medir-injecao.sh:161` executa
`hooks/foco-session-start.cjs` cru, herdando o ambiente — mesma correção.

mutacao:
  arquivo: `hooks/testa-memoria-session-start.sh`
  de: `RAIZ_NEUTRA="$(mktemp -d)"`
  para: `RAIZ_NEUTRA="$RAIZ_GORDA"`
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: `hooks/testa-memoria-session-start.sh`, seção "5. Orcamento do foco não aumentou (D10)" — a asserção `hook de foco continua <= 8000 B`, que com a raiz gorda mede acima de 8.000 e cai
pronto quando: com um `FOCO.md` de ~2.500 B plantado na raiz de dados da máquina, as duas baterias saem 0 — provado por `RFM_ROOT=<raiz gorda> bash hooks/testa-memoria-session-start.sh; echo $?` e `RFM_ROOT=<raiz gorda> bash scripts/testa-medir-injecao.sh; echo $?` devolvendo `0` nas duas

### 4. `testa-contexto-sessao.sh`: raiz de sandbox e banda no teto de núcleos [tipo: teste]
atende: D3, D4, D5
arquivos: `hooks/testa-contexto-sessao.sh`
depende de: 1
paralela: nao

As linhas 326, 1259 e 1268 usam `RFM_ROOT="$SRC_WIN"` — a raiz é o próprio repositório,
que contém `sessoes.json` gitignored (`.gitignore:2`), logo difere entre a máquina e o
runner. Passam a usar uma raiz `mktemp -d` (D3). E a catraca dos núcleos em `:397-403`
passa a consumir `avaliarFolga` (D4): abaixo da banda imprime aviso e continua verde;
a mensagem de falha em `:401-402` deixa de dizer "pague por subtração noutro núcleo, ou
suba `NUCLEOS_MAX_BYTES`" e passa a enunciar o trade-off medido — núcleo, FOCO ou
agregado, com os três números do dia (D5).

mutacao:
  arquivo: `hooks/testa-contexto-sessao.sh`
  de: `RAIZ_NEUTRA="$(mktemp -d)"`
  para: `RAIZ_NEUTRA="$RAIZ_GORDA"`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: `hooks/testa-contexto-sessao.sh`, seção 7 (orçamento de entrega, a partir de `:325`) — com a raiz gorda o payload passa de `ORCAMENTO_BYTES` e a asserção de tamanho da seção 7 cai
pronto quando: com um `FOCO.md` de ~2.500 B plantado na raiz de dados, a bateria sai 0 e a linha da catraca de núcleos imprime aviso (folga 11 B contra banda de 280 B) sem contar como falha — provado por `RFM_ROOT=<raiz gorda> bash hooks/testa-contexto-sessao.sh; echo $?` devolvendo `0` e a saída contendo a linha de aviso da catraca com `11` e `280`

### 5. Corpo da issue #81 ampliado para os cinco pontos [tipo: docs]
atende: D8
arquivos: `docs/rainforest/design/2026-08-24-orcamento-medida-estavel-e-folga.md` (fonte da tabela; não editar)
depende de: nenhuma
paralela: sim

O corpo da #81 descreve dois pontos de contaminação e a entrega conserta cinco. Ampliar
com a tabela da D3 — cada linha com `arquivo:linha`, o que mede e o risco medido em
2026-08-24 — mais a nota de que a #79 fecha junto pelo segundo ramo do critério dela.
Não fechar a issue aqui: isso é o estágio `fechar`.

mutacao: n/a
  motivo: editar o corpo de uma Issue não altera comportamento do repositório — não há
  ramo de código a inverter. A falsificação desta tarefa é a coerência: cada
  `arquivo:linha` citado tem de existir e conter o que a tabela afirma, e é isso que o
  critério de pronto executa.
pronto quando: todo par `arquivo:linha` citado no corpo da #81 existe no repositório e a linha contém o padrão que a tabela atribui a ela — provado por script que extrai os pares de `gh issue view 81 --json body` e roda `sed -n '<linha>p' <arquivo>` em cada um, imprimindo `5/5 conferem` e saindo 0

---

## Emenda de 2026-08-24 — as duas tarefas dos consertos laterais

Estas duas tarefas não estavam no plano original. Entraram durante o `executar`,
por decisão do dono, quando os defeitos apareceram na frente do trabalho em
andamento. Estão registradas aqui — e não justificadas em prosa — porque é a
emenda do plano que torna o crescimento de escopo auditável: sem ela, os arquivos
apareceriam no diff da revisão sem tarefa correspondente, que é a definição de
creep.

### 6. `conferir-mutacao.cjs` recusa pós-mutação desproporcionalmente curta [tipo: implementar]
atende: D9
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`, `skills/executar/SKILL.md`
depende de: nenhuma
paralela: nao

Exit 5 novo, disparado quando a bateria pós-mutação sai != 0 **e** dura menos de
10% do baseline, com piso absoluto de 1.000 ms para não acusar ruído. A ordem
importa e é parte da tarefa: o ramo do exit 2 (bateria VERDE) decide **antes**,
porque bateria que aprovou o fonte invertido já tem veredito próprio e a duração
não muda isso. A tabela de exits do cabeçalho e a da skill `executar` ganham a
linha do 5.

mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `baselineDuracao >= PISO_ABSOLUTO_MS && posDuracao < baselineDuracao * 0.1`
  para: `false`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: `scripts/testa-conferir-mutacao.sh`, caso 10 ("suspeita de corte de shell: pós-mutação desproporcionalmente curta") — com a heurística desligada o caso espera 5 e recebe 0
pronto quando: com uma bateria que roda ~2 s no fonte íntegro e morre em milissegundos com `unbound variable` no fonte invertido, o `conferir-mutacao.cjs` recusa em vez de aprovar — provado por `bash scripts/testa-conferir-mutacao.sh` cobrindo os casos 10 (exit 5), 12 (baseline abaixo do piso não dispara) e 13 (bateria verde e rápida sai 2, não 5) e devolvendo `falhou: 0`

### 7. `avisoFocoNaoCoube` distingue as duas causas [tipo: implementar]
atende: D10
arquivos: `hooks/lib/contexto-sessao.cjs`
depende de: nenhuma
paralela: nao

O ramo do piso (`:1041`) e o ramo `focoSoTemPonteiro` (`:1055`) compartilhavam uma
frase, e para o segundo os números da mensagem negavam a conclusão dela. Cada
causa passa a dizer o que de fato aconteceu, e as duas continuam terminando com a
instrução de ler o FOCO.md, porque em ambos os casos o bloco está incompleto e a
regra 3 depende dele. Nenhuma constante muda. As asserções novas moram em
`hooks/testa-contexto-sessao.sh`, já coberto pela tarefa 4.

mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: `avisoFocoNaoCoube(tetoFoco, 'ponteiro')`
  para: `avisoFocoNaoCoube(tetoFoco, 'piso')`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: `hooks/testa-contexto-sessao.sh` — as asserções de distinção, que exigem que a frase de uma causa NÃO apareça quando é a outra; com o ramo pointer-only devolvido à frase do piso, 3 asserções caem (239 ok, 3 falhou), baseline 32.141 ms contra pós-mutação 35.494 ms
pronto quando: com uma raiz de dados contendo `FOCO.md` de ~2.000 B, o bloco `## Foco declarado` do payload descreve priorização sem conteúdo e não afirma falta de espaço com um número maior que o piso — provado por `RFM_ROOT=<raiz> node hooks/foco-session-start.cjs` e lendo o bloco, que hoje devolve "saiu com só ponteiros nesta injeção (1546 B, removido pela priorização)"
