# Impasse: gate-worktree-brechas (#530, #533)

**Data:** 2026-10-16. O estágio `revisar` reprovou 3 vezes, e o teto é 3.

## Por que reprovou
- **1ª revisão:** 6 achados, entre regressões (o gate barrava leitura legítima no worktree) e grafias que contornavam o conserto. Viraram o D5.
- **2ª revisão:** 9 achados. Eram grafias dentro do escopo que a lista não cobria, falsos positivos e um CHANGELOG que prometia mais do que o gate fazia. O achado de design foi para a #552.
- **3ª revisão:** os critérios (a) e (b) ficaram limpos: as grafias do plano e as afirmações do CHANGELOG batem, e não há creep. Reprovou por regressão (c): `Copy-Item`, `Move-Item` e `New-Item` com continuação de linha por crase eram barrados no worktree. Vieram ainda três achados menores: `<#` entre aspas, prefixo de parâmetro resolvido pela união dos cmdlets, e bateria com casos que já barravam por outro ramo.

## O que foi feito depois da 3ª revisão
Commit `af646e9e`: a crase de continuação junta as linhas, o `<#` só conta fora de aspas, o prefixo de parâmetro é resolvido pelo conjunto de cada cmdlet, e `FileInfo`/`DirectoryInfo` saem da isenção de construtor (achado da revisão de segurança). Os casos que já barravam por outro ramo ganharam rótulo de regressão. `testa-gate-worktree.sh` tem 422 ok e nenhuma falha. Os 16 casos novos ficam vermelhos sem o conserto.

## Causa do impasse
O gate reconhece a escrita por uma lista de formas conhecidas, e cada revisão com olhar de atacante acha mais formas. A #552 registra isso e propõe outra abordagem. A 3ª revisão foi a primeira com critério de reprovação fixado (plano, CHANGELOG, regressão, defeito no diff), e o que ela achou já está consertado.

## Decisão pedida
Liberar uma 4ª rodada de revisão, só do delta `08af6033..af646e9e` mais a regressão, com o mesmo critério da 3ª.

## 4ª rodada (liberada por Luís em 2026-10-16)
- Reprovou com 1 achado (d): a continuação de linha juntava a linha seguinte quando o `#` vinha depois de aspa fechada, de membro ou de índice (`'x'#c`, `$a.b#c`, `$a[0]#c`), e o `Set-Content` da linha seguinte escapava. Saía 2 em `08af6033` e passou a sair 0.
- Os outros três pontos do delta (`<#`, prefixo por cmdlet, `FileInfo`/`DirectoryInfo` em `::new`) passaram, sem creep e sem afirmação do CHANGELOG contradita.
- Conserto `8ed64b58`: continuação de linha com qualquer `#` fora de aspas vira alvo incerto (falha fechada). A bateria tem 436 ok e nenhuma falha; os 6 casos novos ficam vermelhos sem o conserto.
- Decisão pedida: uma 5ª rodada, só do delta `45be540f..8ed64b58`.
