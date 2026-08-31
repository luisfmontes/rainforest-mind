---
name: ponte
description: >-
  Gera a ponte para outro agente (CLAUDE.md, AGENTS.md, GEMINI.md) a partir das
  regras do rainforest-mind. Ou conduz a entrevista que captura contexto de um
  repositório antes de gerar a ponte — varredura de fatos, depois responde 4
  perguntas, depois grava bloco em docs/rainforest/projeto.md.
---

# Ponte e entrevista

A ponte leva as regras para um repositório que outra pessoa usa com Claude Code
(sem o plugin), Codex ou Gemini CLI. Usa o mesmo SKILL.md que o hook de abertura
injeta — **nunca escreva esses arquivos à mão**.

Há duas jornadas aqui: a clássica (gerar a ponte), e a que captura contexto
antes (a entrevista).

## Jornada clássica: gerar a ponte

**Entrada:** configuração do `/setup` (quais agentes esta máquina usa).

**Saída:** arquivo gerado no repositório alvo (CLAUDE.md, AGENTS.md ou GEMINI.md),
com um bloco derivado que contém as regras. Se o arquivo já existe, substitui só
o bloco; texto antes e depois sobrevive. Sem arquivo, o bloco entra no fim.

```bash
# Ensaio: mostra e não grava
node scripts/ponte.cjs --alvo <dir>

# Aplica: grava no alvo
node scripts/ponte.cjs --alvo <dir> --aplicar

# Escolhe agente pontualmente (sobrescreve o setup)
node scripts/ponte.cjs --alvo <dir> --agente codex --aplicar
```

O bloco gerado contém um **hash curto do SKILL.md** (16 caracteres), que permite
detectar se alguém editou à mão depois. Use `node scripts/conferir-ponte.cjs`
para verificar.

**Quem escolhe o agente é o `/setup`, não este comando.** As chaves `ponte-claude`,
`ponte-codex` e `ponte-gemini` (todas desligadas por padrão) dizem o que esta
máquina usa. Sem nenhuma ligada, o comando recusa — gerar arquivo em repositório
de terceiro sem intenção declarada não é um bom padrão.

## Jornada com entrevista: capturar contexto antes

**O que diferencia:** a varredura roda **antes** de qualquer pergunta. Você não
inventou o contexto — descobriu no repositório real.

### Passo 1: varredura pura (fatos do repositório)

```bash
# Detecta stack (Node, Python, Go, ou desconhecida), scripts de test/build,
# workflows (.github/workflows/*.yml), e layout de 1º nível.
# JSON no stdout. Nada gravado.
node scripts/ponte.cjs --entrevistar --varredura --alvo <dir>
```

**Saída:** JSON com `stack`, `scripts`, `workflows`, `layout`. Use para entender
antes de perguntar — você vai perguntar sobre o que o repositório realmente é,
não sobre o que acha que é.

### Passo 2: responda 4 perguntas (arquivo JSON)

Crie um arquivo JSON com 4 chaves — as 4 perguntas da entrevista:

```json
{
  "pronto": "O que significa 'pronto' neste repositório?",
  "nao_toca": "O que não deve ser tocado aqui?",
  "convencao": "Que convenção não está escrita?",
  "revisao": "Qual é a política de revisão?"
}
```

Cada chave é uma resposta breve em prosa — o que o bloco `projeto.md` vai guardar.

### Passo 3: gera o bloco (ensaio ou aplicação)

```bash
# Ensaio: markdown no stdout, nada criado
node scripts/ponte.cjs --entrevistar --gravar \
    --respostas <arquivo.json> \
    --alvo <dir>

# Aplica: grava atomicamente em docs/rainforest/projeto.md
node scripts/ponte.cjs --entrevistar --gravar \
    --respostas <arquivo.json> \
    --alvo <dir> \
    --aplicar
```

**O que ele faz:**
1. Roda a varredura automaticamente (stack, scripts, workflows, layout).
2. Lê as 4 respostas do JSON.
3. Combina fatos + respostas num markdown estruturado.
4. Com `--aplicar`, grava em `docs/rainforest/projeto.md` do alvo, atomicamente.

**O arquivo gerado:**
- Título: "Bloco do projeto".
- Seção "Fatos da varredura": stack, scripts de test/build, workflows, layout.
- Seção "Entrevista": as 4 perguntas + respostas.

Se o arquivo já existe, o conteúdo é substituído (não duplica). Rodar a entrevista
duas vezes grava a segunda resposta, não acumula.

## A ponte não desaparece sem entrevista

O comportamento clássico segue funcionando:

```bash
# Sem --entrevistar, gera a ponte a partir das regras do SKILL.md
# (como antes)
node scripts/ponte.cjs --alvo <dir> --aplicar
```

Entrevista é **opcional** — use-a quando quiser capturar o contexto de um
repositório novo, antes de gerar a ponte. Repositório que já tem `docs/rainforest/projeto.md`
aparece no bloco gerado também (marca que há projeto aqui).

## Ensaio sempre

Antes de usar `--aplicar`, rode sem ele:

```bash
node scripts/ponte.cjs --alvo <dir>
```

O stdout mostra o que seria criado/modificado — tamanho do arquivo, quantos bytes,
qual ação (criar, substituir bloco, ou acrescentar no fim). Leia tudo antes de
aplicar.

## Execução dos exemplos acima

Os comandos abaixo exemplificam a jornada de entrevista. Cada linha é executável:

```shell-node-ponte-exemplos
# Varredura pura
node scripts/ponte.cjs --entrevistar --varredura --alvo /tmp/repo-exemplo

# Entrevista completa (ensaio + aplicação)
# (criar /tmp/respostas.json com as 4 chaves antes)
node scripts/ponte.cjs --entrevistar --gravar --respostas /tmp/respostas.json --alvo /tmp/repo-exemplo
node scripts/ponte.cjs --entrevistar --gravar --respostas /tmp/respostas.json --alvo /tmp/repo-exemplo --aplicar
```

Quando a bateria `bash scripts/testa-ponte-entrevista.sh` executa o bloco acima,
substitui `/tmp/repo-exemplo` por um fixture real com package.json e a chave JSON
por um arquivo de respostas real, e verifica que cada linha completa com exit 0.
