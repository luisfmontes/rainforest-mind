---
description: Leva as regras para um repositório que outra pessoa usa com Codex ou Gemini CLI
argument-hint: [caminho do repo — vazio para o repo atual]
---

Gera a **ponte** para outro agente — `CLAUDE.md` (Claude Code sem o plugin),
`AGENTS.md` (Codex) ou `GEMINI.md` (Gemini CLI) —, a partir do mesmo
`skills/rainforest-mind/SKILL.md` que o hook de abertura injeta no Claude Code.

```
node scripts/ponte.cjs --alvo <dir>                      # ensaio: mostra e não grava
node scripts/ponte.cjs --alvo <dir> --aplicar
node scripts/ponte.cjs --alvo <dir> --agente claude|codex|gemini|todos --aplicar
```

**Quem escolhe o agente é o `/setup`, não este comando.** As chaves
`ponte-claude`, `ponte-codex` e `ponte-gemini` (todas desligadas por padrão) dizem
o que esta máquina usa, e é isso que vale quando ninguém passa `--agente`. Sem
nenhuma ligada, o comando **recusa** e ensina a ligar — gerar arquivo em
repositório de terceiro não é coisa que se faça por omissão. `--agente` continua
existindo como escolha pontual.

A divisão é essa, e ela tem razão: **qual agente você usa é configuração** (mora
no `/setup`); **qual repositório recebe o arquivo não é** — é alvo explícito, com
ensaio, porque o arquivo gerado vai ser commitado no repo de outra pessoa.

**Três alvos, e o terceiro não é redundante.** `ponte-claude` gera `CLAUDE.md`
para quem usa **Claude Code sem o plugin instalado** — que não tem regra nenhuma.
É o caminho de quem vai receber o convite antes de instalar, e o único caminho num
repo compartilhado onde não dá para exigir plugin. O texto do gerado muda com o
alvo: no `CLAUDE.md` a falta das travas se explica pelo **plugin ausente** (e
instalar resolve); no `AGENTS.md`/`GEMINI.md`, pelo **host não ter `PreToolUse`**.

Alvo = `$ARGUMENTS` quando vier, senão o repositório da sessão. **Rode o ensaio
primeiro e mostre ao usuario o tamanho e a ação de cada arquivo** (criar,
substituir o bloco, ou acrescentar no fim) antes de aplicar — o alvo costuma ser
repositório de outra pessoa.

**Nunca escreva esses arquivos à mão, nem edite o bloco gerado.** Eles são
derivados: mudança de regra vai no SKILL.md e a ponte se regera. Um `AGENTS.md`
editado à mão é uma segunda versão das regras, e ela diverge em silêncio — foi o
que aconteceu com as duas `CLAUDE.md` de escopo usuario desta máquina em
2026-08-10.

Três coisas que o script já garante, e que você não precisa checar de novo:

- **não apaga o que é de outra pessoa** — sem marcador, o bloco entra no fim;
  com marcador, só o bloco é substituído; texto antes e depois sobrevive;
- **não chumba caminho de home** no arquivo gerado (ele vai ser commitado no repo
  de terceiro), e ensina a descobrir a pasta de dados com `ideias.cjs conferir`;
- **recusa** gerar se não achar as regras no SKILL.md, em vez de escrever meia
  ponte — meia regra parece regra completa.

Ao terminar, diga em uma linha o que a ponte **não** leva: os dois gates de git
usam o `PreToolUse` do Claude Code e viram texto nesses hosts. O que continua
mecânico é o que tem exit code por comando de shell — `estado.cjs exigir`,
`conferir-entrega.cjs`, `conferir-publicacao.cjs` —, e o arquivo gerado já traz a
tabela.

Bateria: `bash scripts/testa-ponte.sh` (inclui mutação: SKILL.md sabotado tem que
fazer o script recusar).
