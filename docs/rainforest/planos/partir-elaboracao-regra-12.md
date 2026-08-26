# Plano: partir a elaboração da regra 12 sem revogar o critério D9

Design: docs/rainforest/design/partir-elaboracao-regra-12.md

Fato apurado no `plano`, que corrige uma premissa que atravessou o design e um
commit já empurrado: `hooks/testa-contexto-sessao.sh` está **verde** na `main`
(`ok: 273 falhou: 0`, `exit 0`). As 5 linhas `FALHA` da seção **17.1** são o
vermelho **esperado** de sabotagens deliberadas, impressas dentro de um
`( subshell )` que não vaza o incremento para o placar — documentado no próprio
arquivo, linhas 1940-1942. A Issue #120 foi aberta sobre essa leitura errada e
está fechada. Consequência para este plano: **todo `pronto quando:` daqui lê o
exit code e a linha de placar, nunca um grep por `FALHA`.**

Segundo fato apurado: a varredura de H1/número em `testa-contexto-sessao.sh`
filtra `/^regra-\d+\.md$/` (linha ~640 do bloco de títulos), enquanto o
`medir-skill.cjs` conta **qualquer** `.md` da pasta para o teto de bytes. É o
buraco que a D4 fecha.

## O que não pode quebrar

- **As 273 asserções continuam verdes.** O placar final é o veredito.
- **A fórmula `references/regra-<n>.md`** continua valendo sem mudança — ela está
  chumbada na injeção de abertura (`contexto-sessao.cjs`), no `ponte.cjs` e no
  `conferir-ponte.cjs`. Nenhuma tarefa aqui toca os três.
- **Nenhum incidente perdido.** Os 10 blocos `>` datados existentes têm que
  aparecer no destino, texto igual, nada reescrito "de passagem".
- **O núcleo do `SKILL.md` não cresce um byte.** A folga é de 11 B (5589 de
  5600), e tudo que este plano escreve fica abaixo do `<!-- detalhe -->`.
- **Cada arquivo da regra 12 sob 10500 B**, separadamente — o ponto do trabalho é
  não tocar a catraca, e dois arquivos que somados estouram não resolvem nada.
- Node continua a única dependência; nada de script novo em outra linguagem.
- A branch `fix/edicoes-de-regra` já carrega a edição da mutação na
  `regra-12.md`. As tarefas partem desse estado, não do `origin/main` cru.

## Tarefas

### 1. Criar o acervo e mover os 10 incidentes [tipo: implementar]
atende: D1, D3, D5, D6
arquivos: `skills/rainforest-mind/references/regra-12-acervo.md`, `skills/rainforest-mind/references/regra-12.md`
depende de: nenhuma
paralela: não
pronto quando: `node -e "const fs=require('fs');const d='skills/rainforest-mind/references/';const c=f=>(fs.readFileSync(d+f,'utf8').match(/^> \d{4}-\d{2}-\d{2}/gm)||[]).length;const B=f=>Buffer.byteLength(fs.readFileSync(d+f,'utf8'),'utf8');const a=c('regra-12.md'),b=c('regra-12-acervo.md');const ok=a===0&&b>=10&&B('regra-12.md')<10500&&B('regra-12-acervo.md')<10500;console.log(JSON.stringify({regra:a,acervo:b,bytes_regra:B('regra-12.md'),bytes_acervo:B('regra-12-acervo.md')}));process.exit(ok?0:1)"` sai **exit 0** com `regra: 0` (nenhum incidente datado sobrou na regra) e `acervo` ≥ 10; a primeira linha do acervo é exatamente `# Regra 12 — acervo`; e `grep -c "regra-12-acervo" skills/rainforest-mind/references/regra-12.md` devolve ≥ 1 (o ponteiro da D5 existe)
nota: a D6 pede a linha `(acervo: <datas>)` no fim de cada parágrafo que perdeu incidente. Isso não é verificável por contagem — vai no `revisar`, comparando parágrafo por parágrafo contra o texto anterior.
mutacao:
  arquivo: `skills/rainforest-mind/references/regra-12.md`
  de: sem nenhum bloco `> AAAA-MM-DD:` (todos movidos para o acervo)
  para: devolver **um** dos blocos datados para dentro da `regra-12.md`, mantendo o arquivo válido e legível
  bateria: o comando do `pronto quando:` acima — tem que sair **exit 1**, com `regra: 1` no JSON, provando que a checagem mede o que afirma medir e não é vacuidade

### 2. Alargar a varredura de H1/número para enxergar o acervo [tipo: implementar]
atende: D4
arquivos: `hooks/testa-contexto-sessao.sh`
depende de: nenhuma
paralela: sim
pronto quando: `bash hooks/testa-contexto-sessao.sh` sai **exit 0** com a linha final `ok: N falhou: 0` (N ≥ 273), **e** o arquivo passa a validar o acervo — provado por `grep -n 'regra-\\\\d+(-acervo)\\?' hooks/testa-contexto-sessao.sh` achando o padrão novo
nota: o filtro velho é `/^regra-\d+\.md$/`. Alargar só o filtro não basta: o parser que extrai o número do nome usa `f.match(/^regra-(\d+)\.md$/)[1]` e devolve `null` para o nome novo, o que estoura. Os dois lugares mudam juntos, senão a tarefa troca um buraco por um crash.
mutacao:
  arquivo: `skills/rainforest-mind/references/regra-12-acervo.md`
  de: H1 `# Regra 12 — acervo`
  para: H1 `# Regra 13 — acervo` (número do título divergindo do número do nome do arquivo)
  bateria: `bash hooks/testa-contexto-sessao.sh` — tem que sair **exit 1** e o placar final acusar, com o caso `NUMERO` nomeando `regra-12-acervo.md`. Antes da D4 esse mutante passaria verde, porque o arquivo era invisível para a checagem — é essa diferença que a tarefa entrega

### 3. Entrar as 4 edições restantes do cacho na regra 12 [tipo: implementar]
atende: D1
arquivos: `skills/rainforest-mind/references/regra-12.md`, `skills/rainforest-mind/references/regra-12-acervo.md`
depende de: 1
paralela: não
pronto quando: as quatro edições estão no arquivo — provado por `node -e "const t=require('fs').readFileSync('skills/rainforest-mind/references/regra-12.md','utf8');const m=['medidor também pode estar quebrado','Critério que nomeia um arquivo leva o caminho conferido','vale para a própria janela editando configuração','duas citações\\" é o mínimo, não o teto','Recomendação é entrega'].filter(s=>!t.includes(s));console.log(m.length?'faltou: '+m.join(' | '):'as cinco presentes');process.exit(m.length?1:0)"` saindo **exit 0**; e `Buffer.byteLength` dos dois arquivos continuando cada um sob 10500 B (mesmo comando da tarefa 1, exit 0)
nota: os incidentes dessas quatro edições vão para o **acervo**, não para a regra — é o mesmo corte da D3, aplicado ao texto novo. Os textos já estão escritos e guardados no patch da sessão; não reescrever de cabeça.
mutacao:
  arquivo: `skills/rainforest-mind/references/regra-12.md`
  de: as cinco edições presentes
  para: apagar a frase-âncora de **uma** delas, mantendo o resto do arquivo intacto
  bateria: o comando do `pronto quando:` acima — tem que sair **exit 1** nomeando qual faltou

### 4. Registrar a convenção do acervo no SKILL.md [tipo: documentar]
atende: D2
arquivos: `skills/rainforest-mind/SKILL.md`
depende de: nenhuma
paralela: sim
pronto quando: `node scripts/medir-skill.cjs` mostra `skill-bytes` **abaixo de 11000** e o `nucleo` **inalterado em 5589** — provado por rodar antes e depois e colar as duas linhas; e a frase nova está abaixo do `<!-- detalhe -->` do bloco que descreve a convenção de `references/`, provado por `node -e "const t=require('fs').readFileSync('skills/rainforest-mind/SKILL.md','utf8');const i=t.indexOf('acervo');const d=t.indexOf('<!-- detalhe -->');process.exit(i>d&&i>0?0:1)"` com exit 0
nota: o que a frase precisa dizer é o critério, não o caso: elaboração que encostar na catraca parte em `regra-<n>.md` (o que fazer) mais `regra-<n>-acervo.md` (o que aconteceu), com o corte no bloco `>` datado.
mutacao:
  arquivo: `skills/rainforest-mind/SKILL.md`
  de: a frase do acervo abaixo do `<!-- detalhe -->`
  para: mover a mesma frase para **acima** do `<!-- detalhe -->`, dentro do núcleo
  bateria: o `node -e` do `pronto quando:` acima — tem que sair **exit 1**; e `node scripts/medir-skill.cjs` tem que mostrar `nucleo` maior que 5589, provando que a posição é o que protege o orçamento de injeção

## Ordem

Tarefas **2** e **4** saem em paralelo, agora. A **1** roda sozinha (é ela que
cria o espaço). A **3** só depois da **1**, no mesmo arquivo. A mutação da
tarefa 2 depende do acervo existir, então ela se prova **depois** da 1 — o
conserto do filtro é independente, a prova não é.
