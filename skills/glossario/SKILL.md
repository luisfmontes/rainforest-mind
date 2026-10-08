---
name: glossario
description: Propõe, migra ou lista verbetes do GLOSSARIO.md; grava só com aprovação do Luís
---

# Glossário

O `GLOSSARIO.md` é o vocabulário de domínio do repo: o que cada termo é, onde
ele mora e um cenário real. Ele é versionado e lido pelo agente de quem trabalha
ali. Esta skill escreve nele com a aprovação do Luís. Nada grava sozinho: o
verbete entra por commit e PR, no `fechar` (D8).

Formato de cada verbete (D7). Um cabeçalho `## <termo>` e as linhas de campo,
cada rótulo no começo da linha, com este texto exato:

```
## <termo>
Definição: uma a duas frases.
Onde mora: arquivo, rotina, tabela ou campo.
Cenário: um caso real, concreto.
Evite: sinônimo errado; outro sinônimo errado
```

`Evite` é opcional. Definição, Onde mora e Cenário são obrigatórios.

Exemplo de verbete completo, verdadeiro sobre este repo:

```markdown verbete-exemplo
## fluxo
Definição: sequência de estágios por que passa um trabalho do rainforest-mind, na ordem arqueologia (opcional), design, plano, executar, revisar, verificar e fechar.
Onde mora: `scripts/estado.cjs` (a tabela PRE_REQUISITOS) e `docs/rainforest/estado/<slug>.json`, o estado de cada trabalho.
Cenário: `node scripts/estado.cjs exigir --slug <slug> --estagio fechar` recusa enquanto `verificar` não estiver ok, porque fechar só começa depois dele.
Evite: esteira; pipeline
```

## propor

Use quando a conversa trouxer um termo de domínio que ainda não está no glossário.

1. Escolha o termo. Ele tem de ser conhecimento de domínio do repo. Pegadinha de
   ferramenta e vocabulário pessoal do Luís ficam fora (D3, D12).
2. Confira no repo antes de escrever. Nunca escreva "Onde mora" ou "Cenário" de
   memória: rode `grep -rn` ou `ls` e cole o caminho e a linha que sustentam o
   verbete. Só cite em crase caminho que exista.
3. Monte o rascunho no formato D7 e mostre ao Luís, com as provas do passo 2.
4. PARE. Não edite nenhum arquivo antes da aprovação.
5. Com a aprovação, edite o `GLOSSARIO.md` do worktree (crie se faltar) e rode
   `node "$CLAUDE_PLUGIN_ROOT/scripts/conferir-glossario.cjs" --caminhos`. Cole a
   saída. Não faça commit aqui: o commit e o PR são do `fechar`.

## migrar

Use para levar uma memória pessoal de domínio para o glossário do repo (D4).

1. Leia a memória que o Luís indicar, uma por vez.
2. Classifique. Se for pegadinha de ferramenta (comportamento de compilador,
   build, lint ou CI, com contorno) ou vocabulário pessoal (preferência de
   linguagem, "diga X, não Y" sem relação com o domínio), RECUSE, diga o motivo
   em uma linha e deixe a memória como está (D3, D12).
3. Se for termo de domínio, faça o passo 2 e o passo 3 de `propor`: verbete no
   formato D7, com Onde mora e Cenário conferidos no repo, e PARE.
4. Com a aprovação, grave o verbete no `GLOSSARIO.md` e rode o conferidor com
   `--caminhos`, como em `propor`.
5. Troque o corpo da memória por um ponteiro de uma linha que cita o termo e o
   repo, por exemplo `fluxo: ver GLOSSARIO.md do rainforest-mind`. Não copie o
   texto do verbete para a memória: duas fontes do mesmo fato divergem em silêncio
   (D4). Faça a troca arquivo por arquivo, só com a palavra do Luís.

## listar

Mostre os verbetes válidos do glossário do repo:

```
node "$CLAUDE_PLUGIN_ROOT/scripts/conferir-glossario.cjs" --listar
```

Se não houver `GLOSSARIO.md`, diga que não há verbetes para listar.
