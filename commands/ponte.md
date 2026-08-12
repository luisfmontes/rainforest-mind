---
description: Leva as regras para um repositório que outra pessoa usa com Codex ou Gemini CLI
argument-hint: [caminho do repo — vazio para o repo atual]
---

Gera a **ponte** para outros agentes: `AGENTS.md` (Codex) e `GEMINI.md` (Gemini
CLI), a partir do mesmo `skills/rainforest-mind/SKILL.md` que o hook de abertura
injeta no Claude Code.

```
node scripts/ponte.cjs --alvo <dir>                      # ensaio: mostra e não grava
node scripts/ponte.cjs --alvo <dir> --aplicar
node scripts/ponte.cjs --alvo <dir> --agente codex --aplicar
```

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
`conferir-entrega.cjs`, `conferir-relatorio.cjs` —, e o arquivo gerado já traz a
tabela.

Bateria: `bash scripts/testa-ponte.sh` (inclui mutação: SKILL.md sabotado tem que
fazer o script recusar).
