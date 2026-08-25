---
name: plano
description: Use depois que o design de um trabalho está aprovado no fluxo do rainforest-mind, para transformar decisões fechadas em tarefas executáveis — nunca antes da primeira linha de código.
---

# Plano

Segundo estágio do fluxo (design → plano → executar → revisar → verificar
→ fechar). Lê o design aprovado e escreve tarefas **tipadas**, cada uma com
sua dependência declarada — é essa marcação que o estágio `executar` usa
para despachar em paralelo; sem ela o paralelismo vira adivinhação.

## Abrir

```
node scripts/estado.cjs exigir --slug <slug> --estagio plano
```

Sai com exit 2 se `design` não estiver `aprovado` — não insista, volte para
o `brainstorm`. Leia o design inteiro em
`docs/rainforest/design/<slug>.md` antes de escrever a primeira tarefa.

## Template — `docs/rainforest/planos/<slug>.md`

Caminho relativo à **raiz do projeto em que se trabalha**, como o design.

```markdown
# Plano: <título>

Design: docs/rainforest/design/<slug>.md

## O que não pode quebrar
- <invariante 1>
- <invariante 2>

## Tarefas

### 1. <nome da tarefa> [tipo: implementar|configurar|pesquisar|teste|docs]
atende: D1, D2
arquivos: `<padrão ou caminho>`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `<arquivo onde a mutação entra>`
  de: <o padrão exato a inverter>
  para: <o substituto>
  bateria: `<comando que tem de ficar VERMELHO com a mutação aplicada>`
  fixture: <nome-do-caso-de-teste-que-exercita-essa-mutacao>
pronto quando: com `<entrada real do sistema>`, `<efeito verificável>` — provado por `<comando exato>` devolvendo `<saída esperada>`

### 2. <nome da tarefa> [tipo: docs]
atende: D3
arquivos: `<padrão ou caminho>`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: <por que esta tarefa não tem comportamento a inverter>
pronto quando: com `<entrada real do sistema>`, `<efeito verificável>` — provado por `<comando exato>` devolvendo `<saída esperada>`
```

Cada tarefa leva: **tipo**, `atende:` (lista de `D<n>` do design que esta tarefa realiza), `arquivos:` (caminhos ou globs que ela pode tocar), `depende de:` (números das tarefas antecessoras ou "nenhuma"), `paralela: sim|nao` (só "sim" quando `depende de: nenhuma`), `mutacao:` (o alvo da validação por mutação, abaixo) e critério de pronto **falsificável** — comando e saída esperada, nunca "funcionar bem" ou "funcionar corretamente", e nunca "a bateria sai 0" (ver abaixo: o critério nomeia a entrada real do sistema, não o instrumento).

### Campos obrigatórios: `atende:` e `arquivos:`

- **`atende:` vazio é recusa**: tarefa sem `atende:`, ou com `atende:` vazio, não entra no plano — se não atende nenhuma decisão, ela não deveria estar aqui.
- **`arquivos:` sem glob largo**: declare caminhos concretos ou padrões específicos. Glob largo como `hooks/**` não descreve o que você toca — é achado do `revisar`, não atalho. **`arquivos:` nomeia arquivos que a tarefa toca, não pastas**: `skills/executar/SKILL.md`, não `skills/**`; `scripts/conferir-entrega.cjs` e `scripts/conferir-entrega.py`, não `scripts/**`. Arquivo por arquivo.
- **Cobertura nos dois sentidos**: decisão do design sem tarefa barra o plano, e tarefa citando `D<n>` inexistente também barra.

### Campo obrigatório: `mutacao:` — o alvo é declarado, nunca inferido

Toda tarefa declara **qual linha inverter e qual bateria tem de ficar vermelha**
quando ela for invertida. Quem sabe o que inverter é quem escreveu o conserto —
por isso o alvo mora no plano, e não na cabeça de quem executa depois.

```
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: o `process.exit(2)` do ramo de sessão co-locada
  para: `process.exit(0)`
  bateria: `bash hooks/testa-gate-worktree.sh`
  fixture: `testa-gate-worktree.sh, linhas 23-30 (o ramo co-locado que dispara a saída)`
```

- **`de:` é o padrão exato**, não a intenção. Padrão que não casa com o fonte
  não vira "bateria vermelha" — vira recusa, com o veredito certo pelo motivo
  certo.
- **`bateria:` é o comando que tem de FALHAR** com a mutação aplicada. Se
  continuar verde, a bateria não mede o que a tarefa entregou.
- **`fixture:` nomeia qual caso de teste exercita a mutação** — arquivo, função ou
  intervalo de linhas. Não basta a **bateria** ficar vermelha: o ramo mutado tem de
  ser alcançado por um caso específico, senão o vermelho pode vir de outro lugar, e
  veredito certo pelo motivo errado é pior que veredito errado — ninguém volta a
  olhar. **Quem confere isso é a integração, lendo qual linha ficou vermelha.** O
  `conferir-mutacao.cjs` prova só que a bateria virou (`--de`, `--para`, `--bateria`);
  ele não conhece caso de teste, e escrever que conhece mandaria confiar numa trava
  que não existe. Quando a bateria souber rodar um caso sozinho, é o comando dela que
  vai em `bateria:`, e aí o exit code passa a valer pelo caso. **Obrigatória quando
  `resultado` é `vermelho`**, e o `estado.cjs` recusa sem ela; `n/a` não tem
  comportamento a inverter, então não tem caso a nomear.
- **O relato de mutação do agente não fecha a tarefa.** A integração re-roda, e
  só o exit code dela vale.

**`mutacao: n/a` com `motivo:` é resposta aceita.** Tarefa de doc não tem
comportamento a inverter; a falsificação dela é outra (casar com a interface
real, por exemplo). Exigir o impossível cria o hábito do `--forcar`, e trava que
se contorna por hábito não trava mais nada. O que **não** vale é `n/a` sem
motivo: o preço do escape é escrever por que ele cabe.

> 2026-08-21: um agente cumpriu todos os critérios falsificáveis do briefing,
> colou saída de validação por mutação e entregou 49/49 verde — com a trava que
> ele acabara de escrever recusando o caminho feliz **sempre**. Não foi caso
> isolado: 10 de 18 entregas do acervo têm o mesmo formato de defeito
> (`obs-2026-08-17-dez-baterias-que-nao-sabiam-falhar`). O que faltava não era
> rigor de quem executa — era o plano dizer o alvo, para haver o que re-rodar.

**Proibido placeholder.** Tarefa com "TBD", "a definir" ou critério de
pronto vago não entra no plano — falta decisão, e decisão que falta volta
para o `brainstorm`; não se resolve inventando aqui.

### `pronto quando:` nomeia a ENTRADA REAL, não a bateria

**"`bash <bateria>` sai 0" não é critério de pronto.** Essa forma mede o
instrumento, não o sistema — e o instrumento é escrito por quem precisa dele
verde, então enquanto o critério apontar para ele, a saída mais barata sempre
será ajustar o instrumento. **Teste que pula por infraestrutura ausente é
vermelho disfarçado**: quando o próprio teste monta o que precisa, zero `skipped`
é critério de aceite (teste que não precisa de infraestrutura externa pode pular
honestamente). **Tarefa de tipo `docs` não pode ter critério que seja presença de uma string** — qualquer trecho citado é satisfazível digitando o trecho e fim. O critério tem que conferir **coerência com a decisão**: números do texto casa com números do design, prescrições do texto implementam as prescrições decididas, argumentação segue a lógica do design. A forma que vale:

```
pronto quando: com <entrada real do sistema>, <efeito verificável> — provado por `<comando>`
```

Qual payload entra, qual efeito sai. "Entrada real" quer dizer **a que o mundo
manda**, não a que o teste monta: o JSON que o harness realmente envia no
stdin, o registro que o cliente realmente tem na tabela, o arquivo no formato
em que ele realmente chega. A bateria continua existindo e continua rodando —
ela só não é mais o que a tarefa promete.

> 2026-08-19: as 13 tarefas de um plano tinham `pronto quando:` na forma
> "`bash <bateria>` sai 0". A entrega passou por **10 baterias verdes**, por
> validação por mutação feita à mão, e pelo `conferir-entrega.cjs` com exit 0 —
> e o subsistema estava **morto em produção**: o hook lia `evento.project`, um
> campo que o harness nunca envia, e as baterias só passavam porque
> **injetavam esse campo à mão** no JSON de teste. Três formas do mesmo defeito
> num dia só: teste que certifica um no-op (a função tinha um `if` de corpo
> vazio e o teste verificava que nada mudava); payload que a produção nunca
> produz; e fixture com schema inventado — os transcritos de teste ganharam os
> campos `tipo`/`conteudo` que o código esperava, e o transcrito real do Claude
> Code não tem nenhum dos dois. O denominador não é descuido de quem escreveu.
>
> O agravante: a armadilha estava documentada **dentro do próprio repositório**
> (`referencias/2026-08-11-everything-claude-code.md:131`), incluindo o
> mecanismo pelo qual a suíte não pega. O repo documentou e caiu nela.

### Critério de superfície humana

**Quando a tarefa produz algo que uma pessoa lê para decidir**, o plano exige ao menos
um critério cuja pergunta seja sobre a pessoa: *qual informação ela vê no momento de
decidir, e essa informação basta?*

**Gatilho — tarefa TEM superfície humana quando:**
- Devolve uma página web, uma interface de CLI ou prompt
- Produz uma mensagem de erro ou aviso que o usuário vê
- Gera um QR code, código, identificador ou qualquer artefato visual que a pessoa usa para tomar ação
- Emite log, relatório ou resultado pensado para **leitura humana**, não para integração

**A forma continua falsificável.** O que muda é o que se pergunta antes de escrever o
`assert` — não há afrouxamento da exigência. Exemplos para a mesma tarefa:

```
Tarefa: página de pareamento por conta no MCP de WhatsApp

❌ Nível 1 — mede o comando, não a pessoa:
pronto quando: com `curl localhost:3005/qr`, a resposta tem um `<h2>` — provado por
`grep -q 'h2' <(curl -s localhost:3005/qr)`

Problema: um `<h2>` em cada página satisfaz o critério, mas não distingue contas.

⚠️ Nível 2 — PARECE medir a pessoa, mas não mede:
pronto quando: com as duas contas pareadas em portas diferentes (3005 e 3006),
as páginas são diferentes — provado por
`! diff <(curl -s localhost:3005/qr) <(curl -s localhost:3006/qr)` retorna verdadeiro

Problema: o `diff` fica verde com um `<title>` distinto entre as duas contas.
A pessoa com o telefone na mão está olhando o **corpo** da página para escanear
o QR — um `<title>` que ninguém vê não a ajuda. Esse critério passa verde,
o QR fica idêntico na prática, e a pessoa não consegue decidir qual conta.
**É o erro que a regra 12 pegou ao consertar a página real** — o teste passava
porque o `<title>` era único, e nada mais.

✅ Nível 3 — mede a informação que a pessoa precisa:
pronto quando: com as duas contas pareadas em portas diferentes (3005 e 3006),
cada página **no corpo visível** contém um identificador da conta — provado por
`grep -q 'Account: 5551234567' <(curl -s localhost:3005/qr)` E
`grep -q 'Account: 5559876543' <(curl -s localhost:3006/qr)` E
`! diff <(curl -s localhost:3005/qr | grep -oE 'Account: [0-9]+') <(curl -s localhost:3006/qr | grep -oE 'Account: [0-9]+')'`

Prova: a pessoa vê **qual número de conta** é cada QR; nessa informação falha,
o critério falha, ainda que as páginas difiram por qualquer outro motivo.
```

A pergunta está colada no critério **antes** de escrever o `assert`: "qual
informação a pessoa precisa?", "onde ela fica visível?", "e o critério falha
quando essa informação desaparece?" — tudo isso é falsificável por comando, e
tudo isso mede a pessoa, não o instrumento, não o test harness, não uma
diferença qualquer que satisfaz o `diff`.

### Trava de cobertura

A partir de 2026-08-13, `node scripts/estado.cjs marcar --estagio plano --status ok` recusa plano que não tenha cobertura completa: testa se toda decisão `D<n>` do design tem tarefa no plano com `atende: D<n>`, e se toda tarefa do plano cita apenas `D<n>` existentes. Sem cobertura completa, o comando sai com exit 2.

A partir de 2026-08-21 a mesma checagem cobra o bloco `mutacao:`: tarefa sem o bloco é recusada **pelo número**, e `mutacao: n/a` sem `motivo:` também. Rode antes de fechar:

```
node scripts/conferir-fluxo.cjs cobertura --slug <slug>
```

## Fechar

```
node scripts/estado.cjs marcar --slug <slug> --estagio plano --status ok --json '{"arquivo":"docs/rainforest/planos/<slug>.md","tarefas":N,"paralelas":[1,3]}'
```

**Condição de parada: o plano termina antes da primeira linha de código.**
Se a tentação for "só implementar essa parte pra confirmar", isso é uma
tarefa marcada no plano e o `executar` que faz depois — não aqui.

---

Segundo estágio do fluxo rainforest-mind. `exigir`/`marcar` vêm de
`scripts/estado.cjs` — leia-o antes de citar uma flag que ele não tem.
