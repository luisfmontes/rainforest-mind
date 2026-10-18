# Impasse: gate-worktree-552, teto de 3 reprovações no `revisar`

## Onde está

- **Aprovados:** o diff `038de7d8...130491d1` (rodada 3) e o delta `...84d055a2`.
- **Depois deles:** cada revisão de segurança automática (plugin `security-guidance`) trouxe uma variante nova de contorno na isenção dos worktrees: chave que monta `..`, `$` no caminho, aspas, `$HOME` no meio, prefixo de opção.
- **Reprovações seguidas:** os três consertos seguintes (`0e111e0a`, `6ed2beb6` e `5c66e7d3`) foram reprovados.

## Achados que reprovaram `5c66e7d3`

1. **`\\` + quebra de linha no Bash.** A remoção de continuação de linha (`comando.replace(/\\\r?\n/g, "")`) cola duas linhas quando o número de contrabarras é par. Exemplo: em `ls \\⏎rm <P>/f`, o `rm` some, e o gate devolve 0, quando antes devolvia 2. É regressão introduzida pelo delta.
2. **`HOME`/`USERPROFILE` em maiúsculas em qualquer lugar da linha.** A isenção cai para o próprio cwd do worktree. Assim, `git commit -m "ajusta HOME"` e `HOME=/tmp/h npm test` dentro do worktree passam a barrar. É falso positivo largo, e o CHANGELOG não o declara.

## Conserto proposto (pequeno, já mapeado)

- **Continuação de linha:** linha com `\`+quebra vira não confiável, isto é, um segmento só, sem leitura. A palavra já trata `\`+quebra.
- **`homeRedefinido`:** tira a isenção só da palavra que chega ao worktree por atalho de home. Não vale mais para a linha inteira, nem para o cwd.
- **Mais dois ajustes:** o nome da variável é testado também sem aspas nem escape, e no Bash o atalho de home tem caixa exata e exige chave fechada.

## Por que o laço não converge sozinho

Cada revisão de segurança automática acha uma grafia nova de contorno da isenção. O design (D3 e "Fora de escopo") já deixa de fora a variável sem o literal do caminho. A cauda longa de grafias é o que alimenta o laço.

## Decisão pedida

Liberar uma 4ª rodada para o conserto acima, com corte de escopo: variante nova vinda da revisão automática vira Issue de continuação e não reabre este PR, salvo se for regressão (algo que o head anterior barrava).

## Rodada extra 2 (2026-10-18)

A rodada extra fechou o caso `\`+quebra, mas reprovou na redefinição de HOME. Os contornos foram `${HOME:-x}`, `export {HOME,X}=` e `$HOMEDRIVE$HOMEPATH`, que o head anterior barrava. Todos são variável sem o literal do caminho, que o design deixou fora de escopo.

Decisão do Luís: tirar do PR a detecção de HOME redefinido, declará-la fora de escopo no CHANGELOG e abrir Issue de continuação. Uma rodada curta confere essa remoção e o caso `\`+quebra.
