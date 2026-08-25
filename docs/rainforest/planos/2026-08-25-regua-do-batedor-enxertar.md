# Plano: Régua do batedor por trilha — instalar, enxertar, ler

Design: docs/rainforest/design/2026-08-25-regua-do-batedor-enxertar.md

## O que não pode quebrar

- **As 40 linhas já escritas do `livro-de-repos.md` não mudam** — nem o veredito, nem a
  data, nem a coluna "Reprovou em". É D8, e é o precedente que o próprio livro documenta
  na seção "Por que a pergunta 4 aceita código".
- **As seis perguntas de Instalar continuam com a redação de hoje** (D12), inclusive a
  emenda de 2026-08-12 que fez a pergunta 4 aceitar prova de código-fonte.
- **O gatilho duplo de revisita continua duplo** — 60+ dias **E** push posterior ao
  registrado. D11 muda a pergunta, nunca o gatilho.
- **O default nunca vira silencioso.** Âncora sem trilha recusa (D5); em nenhum caminho o
  código escolhe `Instalar` por omissão.
- **Nada é escrito fora do repositório.** A fila e o livro moram em `vigias/`; o
  `ideias.jsonl` do usuário é lido, nunca escrito por este trabalho (regra 15).
- **`node scripts/orcamento.cjs` continua exit 0.** Script novo não entra na injeção, mas
  a `description` de qualquer skill ou comando tocado entraria.

## Tarefas

### 1. `vigias/fila-de-repos.jsonl`: âncora com trilha declarada, e recusa sem ela [tipo: implementar]
atende: D4, D5
arquivos: `vigias/fila-de-repos.jsonl`, `vigias/dados-batedor-repos.js`, `scripts/testa-fila-de-repos.sh`
depende de: nenhuma
paralela: sim

Nasce `vigias/fila-de-repos.jsonl`, uma entrada por linha, com `candidato`, `ancora`
(o problema que motivou), `trilha` (`instalar` | `enxertar` | `ler`) e `plantada_em`. O
`dados-batedor-repos.js` passa a ler a fila junto do resto e a entregar a trilha ao vigia.

Entrada **sem** `trilha`, ou com trilha fora das três, faz a leitura **recusar aquele
candidato** com mensagem nomeando o que falta — nunca assumir `instalar`, nunca corrigir
por baixo. Os outros candidatos da fila seguem: recusa é por entrada, não por rodada.

mutacao:
  arquivo: `vigias/dados-batedor-repos.js`
  de: a recusa de entrada sem `trilha`
  para: a atribuição do default `instalar`
  bateria: `bash scripts/testa-fila-de-repos.sh`
  fixture: `scripts/testa-fila-de-repos.sh`, o caso "entrada sem trilha é recusada e não vira instalar"
pronto quando: uma fila com três entradas — uma `instalar`, uma sem `trilha` e uma com `trilha: "comprar"` — produz exatamente uma entrada utilizável e duas recusas nomeadas, e a saída **não contém** a string `instalar` para nenhuma das duas recusadas; provado rodando `node vigias/dados-batedor-repos.js` contra essa fila em `mktemp -d` e colando a saída

### 2. `livro-de-repos.md`: três trilhas, cascata freada e vocabulário fechado [tipo: implementar]
atende: D1, D2, D3, D6, D9, D10, D11, D12
arquivos: `vigias/livro-de-repos.md`
depende de: nenhuma
paralela: sim

O cabeçalho do livro ganha, **acima** da tabela das seis perguntas: a escolha de trilha
pela âncora antes da busca (D1); a cascata `Instalar → Enxertar → Ler` com o freio da
pergunta 1 e o fundo de poço em `não vale voltar` (D2, D3); as perguntas de Enxertar e de
Ler como estão no design, com a licença na forma "o que exatamente ela proíbe?" e a nota
de que licença é fato, nunca veredito (D9); o vocabulário fechado de sete strings, com a
frase que explica por que o meio-termo sumiu (D6); o formato da linha carregando o
**caminho** da cascata e a leitura da coluna "Reprovou em" junto da trilha (D10); e a
tabela de revisita por trilha final, com `Ler` fora dela (D11).

A tabela das seis perguntas de Instalar fica **intocada** (D12), e nenhuma das 40 linhas
existentes é editada (D8) — inclusive as seis de veredito inventado.

mutacao: n/a
  motivo: a tarefa reescreve o cabeçalho de um documento; o comportamento que se pode inverter é o do checador, e ele é a tarefa 3
pronto quando: `grep -c '^| ' vigias/livro-de-repos.md` devolve o **mesmo número** de antes da tarefa, e `git diff --stat` mostra zero linha removida na região da tabela "Avaliados" — provado colando o `git diff -U0 vigias/livro-de-repos.md | grep '^-' | grep -v '^---'`, que tem de sair **vazio**

### 3. `scripts/conferir-livro-de-repos.cjs`: a catraca do vocabulário, com data de corte [tipo: implementar]
atende: D7, D8
arquivos: `scripts/conferir-livro-de-repos.cjs`, `scripts/testa-conferir-livro-de-repos.sh`
depende de: 2
paralela: nao

Checador na família `conferir-*`: lê a tabela "Avaliados" do livro e **recusa** linha cuja
data seja posterior ao corte e cujo veredito não esteja no vocabulário fechado da trilha
declarada. Linha com data anterior ao corte passa sem ser olhada (D8). Exit codes
distintos para veredito fora do vocabulário, trilha ausente e caminho de cascata
malformado — a família não faz o chamador ler mensagem para saber o que houve.

mutacao:
  arquivo: `scripts/conferir-livro-de-repos.cjs`
  de: a comparação do veredito contra a lista fechada
  para: uma comparação que aceita qualquer string não vazia
  bateria: `bash scripts/testa-conferir-livro-de-repos.sh`
  fixture: `scripts/testa-conferir-livro-de-repos.sh`, o caso "veredito inventado depois do corte é recusado"
pronto quando: uma fixture com quatro linhas — veredito válido pós-corte, veredito inventado pós-corte, veredito inventado **pré**-corte e trilha ausente pós-corte — devolve exatamente uma recusa por veredito, uma por trilha ausente, e **nenhuma** para a linha pré-corte; provado colando a saída e os exit codes, sem pipe

### 4. `vigias/batedor-repos.md`: o procedimento passa a ler a trilha da fila [tipo: implementar]
atende: D1, D5
arquivos: `vigias/batedor-repos.md`
depende de: 1, 2
paralela: nao

O passo 1 (Âncora) passa a dizer que a trilha vem declarada na fila e que candidato sem
trilha é **recusado**, não avaliado por default. O passo 3 (Avaliação) deixa de mandar
"responda as seis perguntas do livro" e passa a mandar responder as perguntas **da trilha
da âncora**, com a cascata e o freio. O passo 4 (Registro) passa a escrever o caminho da
cascata na linha. O passo 5 (Revisita) aponta para a tabela de revisita por trilha.

mutacao: n/a
  motivo: procedimento em prosa lido por um vigia; a trava do que ele produz é o checador da tarefa 3
pronto quando: `grep -c 'seis perguntas' vigias/batedor-repos.md` devolve `0` e o arquivo cita as três trilhas pelo nome — provado colando o `grep -n 'instalar\|enxertar\|ler' vigias/batedor-repos.md` com as três presentes
