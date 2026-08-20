---
name: plano
description: Use depois que o design de um trabalho está aprovado na esteira do rainforest-mind, para transformar decisões fechadas em tarefas executáveis — nunca antes da primeira linha de código.
---

# Plano

Segundo estágio da esteira (design → plano → executar → revisar → verificar
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
pronto quando: com `<entrada real do sistema>`, `<efeito verificável>` — provado por `<comando exato>` devolvendo `<saída esperada>`

### 2. <nome da tarefa> [tipo: ...]
atende: D3
arquivos: `<padrão ou caminho>`
depende de: 1
paralela: nao
pronto quando: com `<entrada real do sistema>`, `<efeito verificável>` — provado por `<comando exato>` devolvendo `<saída esperada>`
```

Cada tarefa leva: **tipo**, `atende:` (lista de `D<n>` do design que esta tarefa realiza), `arquivos:` (caminhos ou globs que ela pode tocar), `depende de:` (números das tarefas antecessoras ou "nenhuma"), `paralela: sim|nao` (só "sim" quando `depende de: nenhuma`) e critério de pronto **falsificável** — comando e saída esperada, nunca "funcionar bem" ou "funcionar corretamente", e nunca "a bateria sai 0" (ver abaixo: o critério nomeia a entrada real do sistema, não o instrumento).

### Campos obrigatórios: `atende:` e `arquivos:`

- **`atende:` vazio é recusa**: tarefa sem `atende:`, ou com `atende:` vazio, não entra no plano — se não atende nenhuma decisão, ela não deveria estar aqui.
- **`arquivos:` sem glob largo**: declare caminhos concretos ou padrões específicos. Glob largo como `hooks/**` não descreve o que você toca — é achado do `revisar`, não atalho.
- **Cobertura nos dois sentidos**: decisão do design sem tarefa barra o plano, e tarefa citando `D<n>` inexistente também barra.

**Proibido placeholder.** Tarefa com "TBD", "a definir" ou critério de
pronto vago não entra no plano — falta decisão, e decisão que falta volta
para o `brainstorm`; não se resolve inventando aqui.

### `pronto quando:` nomeia a ENTRADA REAL, não a bateria

**"`bash <bateria>` sai 0" não é critério de pronto.** Essa forma mede o
instrumento, não o sistema — e o instrumento é escrito por quem precisa dele
verde, então enquanto o critério apontar para ele, a saída mais barata sempre
será ajustar o instrumento. A forma que vale:

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

### Trava de cobertura

A partir de 2026-08-13, `node scripts/estado.cjs marcar --estagio plano --status ok` recusa plano que não tenha cobertura completa: testa se toda decisão `D<n>` do design tem tarefa no plano com `atende: D<n>`, e se toda tarefa do plano cita apenas `D<n>` existentes. Sem cobertura completa, o comando sai com exit 2.

## Fechar

```
node scripts/estado.cjs marcar --slug <slug> --estagio plano --status ok --json '{"arquivo":"docs/rainforest/planos/<slug>.md","tarefas":N,"paralelas":[1,3]}'
```

**Condição de parada: o plano termina antes da primeira linha de código.**
Se a tentação for "só implementar essa parte pra confirmar", isso é uma
tarefa marcada no plano e o `executar` que faz depois — não aqui.

---

Segundo estágio da esteira rainforest-mind. `exigir`/`marcar` vêm de
`scripts/estado.cjs` — leia-o antes de citar uma flag que ele não tem.
