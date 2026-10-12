# Impasse: 2026-10-12-pasta-unica

Três reprovações seguidas no `revisar`, com achados decrescendo em quantidade e gravidade:

| Rodada | Achados | O que sobrou |
|---|---|---|
| 1 | 8 (2 graves) | credencial em dois arquivos; retomada bloqueada por `.pessoal.*` |
| 2 | 6 | retomada: vigia desagendado, pasta fora de casa, flags do perfil, índice, `--profile`, rollback |
| 3 | 3 (2 médios, 1 baixo) | ver abaixo |

## Achados da rodada 3

1. **[médio] Índice de memória na retomada com conflito** — `scripts/lib/conta-unificar.cjs:69` e `:152`: o `<nome>.pessoal.md` já gravado volta como `igual` e conta como "copiado", e a retomada acrescenta ao `MEMORY.md` uma linha pessoal que aponta para o `a.md` da pasta de trabalho. Variante baixa: `a.md` idêntico nas duas pastas também acrescenta a linha numa rodada limpa.
2. **[médio, a confirmar] `<pasta>/.claude.json` da pasta padrão** — `scripts/conta.cjs:107` e `scripts/lib/conta-mover.cjs:79,82` leem `~/.claude/.claude.json`; o Claude Code usa `~/.claude.json` para a pasta padrão. Medido em 2026-10-12: os dois existem nesta máquina (o de dentro da pasta foi escrito pelo vigia em 2026-10-10), os dois com `oauthAccount`. Então o vigia não quebra aqui, mas grava o `oauthAccount` no arquivo que a pasta padrão não lê. É comportamento da 1.62.0, anterior a este fluxo.
3. **[baixo] `.bak-pasta-unica` de uma gravação de perfil que falhou bloqueia a retomada** — `scripts/conta.cjs` (`migrar`, `perfilSo`).

## Decisão pedida ao Luís

Liberar a 4ª rodada para consertar 1 e 3 (pequenos, no mesmo arquivo), e levar o 2 para uma Issue própria (anterior a este fluxo e não quebra a migração nesta máquina) — ou outra saída.
