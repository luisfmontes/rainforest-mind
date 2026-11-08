## Resumo
O `gate-fechar-issue` tem cinco recusas sobre o corpo de `gh pr create` e `gh pr edit`, e cada uma sugeria uma saída diferente. Algumas sugeriam justamente o que a recusa seguinte barra. Numa medição sobre os 300 maiores transcritos dos últimos 30 dias, este gate foi a maior fonte de turnos em que a mesma falha se repetiu 3 vezes ou mais: 13 de 48 turnos, com 42 negações. Lendo esses turnos, o agente não repetia o comando. Ele seguia a sugestão da mensagem e caía na recusa seguinte:

```
--body "... `x` ..."            → "use --body texto-plano ou --body-file"
--body-file "$S/pr.md"          → "variável que o gate não resolve; escreva o caminho literal"
--body-file C:/.../pr.md        → "não consegui ler" (o comando que o criaria foi barrado)
--body-file /tmp/pr.md          → "não consegui ler" (o node do gate não enxerga o /tmp do Git Bash)
```

Agora todas as recusas do corpo dizem a razão e terminam na mesma receita:

```
Receita que passa:
  1. Grave o corpo antes, com a ferramenta de escrita (Write), num caminho absoluto literal do Windows, por exemplo o scratchpad da sessão;
  2. num comando que só tem o gh: gh pr create --title "<título>" --body-file "<caminho literal>" (ou gh pr edit <n> --body-file "<caminho literal>").
Comando barrado não roda nenhuma parte: o arquivo que ele criaria não existe.
```

Quando o arquivo não é lido, a recusa também diz por quê:
- o arquivo não existe, com o caminho resolvido se ele era relativo;
- é caminho do Git Bash (só no Windows);
- o corpo vem do stdin (`-`);
- o caminho veio vazio;
- o código do erro.

O heredoc ilegível ganha razão própria. Antes ele dizia "nada neste comando o cria por heredoc", o que era falso. Sobe a versão para 2.8.2 (PATCH).

## Evidência
- **Antes:** a bateria nova roda contra o gate da base e sai `ok: 16 falhou: 18` (rodada pelo revisor na rodada 2).
  **Depois:** `bash hooks/testa-gate-receita-corpo.sh` sai `ok: 39   falhou: 0`. São 14 casos com o payload real de `PreToolUse` e um `gh` falso no PATH.
- O exit de toda recusa ficou igual. O revisor rodou 35 comandos pelo gate da base e pelo do HEAD, e o exit deu igual em todos. `bash hooks/testa-gate-fechar-issue.sh` continua com `420 ok, 0 falha(s)`, sem edição.
- `node hooks/testa-gate-subagente-sem-gh.cjs` sai `ok: 102 falhou: 0`. O caso (13) da bateria nova garante que um subagente ainda pode rodar `node hooks/gate-fechar-issue.cjs`: a primeira versão da receita, com `gh pr create` por extenso no fonte, fazia o `gate-subagente-sem-gh` barrar isso.
- **Mutação:** `const receita = RECEITA_CORPO_PR;` → `const receita = "";` e `if (codigo === "ENOENT") return` → `if (false) return` deixam a bateria vermelha nas duas rodadas.

## Perigo de merge
**Porta:** mão dupla. Só muda o texto das recusas, e se desfaz com um revert.
**Raio de impacto:** pequeno. A mensagem de recusa de `gh pr create`/`gh pr edit` muda, e o que é barrado continua igual.

## Deixado para depois
- revisar: [baixa] caso (13) passa sem testar em checkout sob /tmp do Git Bash → descartada: CI (windows-latest, /d/a/...) e worktrees reais ficam em caminho de drive, onde o (13) foi visto vermelho com a mutação; checkout sob /tmp não é uso do repo
- revisar: [baixa] motivo cita /tmp para qualquer raiz POSIX → descartada: a orientação final (caminho absoluto do Windows) está certa para toda raiz POSIX; só a palavra /tmp é específica demais

O `-F` (atalho de `--body-file`), que o gate não reconhece, ficou na Issue #664. Corrigi-lo muda o que o gate recusa, e este PR só muda texto.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
