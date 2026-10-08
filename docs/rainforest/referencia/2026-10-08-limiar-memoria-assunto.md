# Limiar bm25 da memória escolhida pelo assunto

Calibração do fluxo `2026-10-08-memoria-por-assunto`. Instrumento: `scripts/calibrar-limiar-assunto.cjs`.
Este documento tem só números: nenhum conteúdo de observação, nome de projeto ou pedido.

## Método

- Sessões: as de `uso_memoria_sessoes` de uma cópia do banco (somente-leitura). Transcrito = `<id>.jsonl` em `~/.claude-personal/projects/*/` ou `~/.claude/projects/*/`.
- Pedido: entrada `user` digitada (sem `tool_result`, sem `isMeta`, sem `isSidechain`, sem começar por `/`, `<` ou `[Request interrupted`).
- Candidatas: `observacoes_fts MATCH construirQueryFts5DoTexto(pedido, 30)`, `ORDER BY bm25()`, até 3 por pedido, vivas (`filtroVivas`), `consolidada_em IS NULL`, `criada_em` anterior ao pedido.
- Nota: `calcularNota(conexao, conteudo, textoPosterior)`, com `textoPosterior` = pedidos do usuário e `input` de `tool_use` DEPOIS do pedido (o pedido não entra). Útil = nota >= 0.5.
- Limiar L: a candidata entra se `bm25 <= L` (bm25 do SQLite é negativo; mais negativo = mais relevante).

## Comando rodado

```
node scripts/calibrar-limiar-assunto.cjs --db <copia-do-rainforest.db> --limiares -2,-4,-6,-8,-10,-12,-14,-16,-20,-25,-30
```

## Tabela (com filtro temporal)

```
limiar | injecoes | fracao_util(nota>=0.5) | media_por_pedido | fracao_pedidos_sem_injecao
-2 | 6192 | 0.104 | 2.950 | 0.015
-4 | 5909 | 0.109 | 2.815 | 0.018
-6 | 5570 | 0.106 | 2.654 | 0.054
-8 | 4033 | 0.133 | 1.921 | 0.290
-10 | 3303 | 0.137 | 1.574 | 0.410
-12 | 2678 | 0.140 | 1.276 | 0.525
-14 | 2207 | 0.136 | 1.051 | 0.605
-16 | 1796 | 0.140 | 0.856 | 0.664
-20 | 964 | 0.157 | 0.459 | 0.801
-25 | 245 | 0.155 | 0.117 | 0.934
-30 | 66 | 0.167 | 0.031 | 0.980
sessoes=535 pedidos=2099 transcritos_ausentes=384
```

## Controle: sem o filtro temporal (`--sem-filtro-temporal`)

Memória que ainda não existia no pedido infla a fração útil (0.124 a 0.267 contra 0.104 a 0.167), porque o pedido
e a memória gravada depois dele falam do mesmo trabalho. É por isso que o filtro temporal fica.

```
limiar | injecoes | fracao_util(nota>=0.5) | media_por_pedido | fracao_pedidos_sem_injecao
-2 | 6200 | 0.124 | 2.954 | 0.014
-4 | 6173 | 0.125 | 2.941 | 0.017
-6 | 5924 | 0.125 | 2.822 | 0.049
-8 | 4273 | 0.148 | 2.036 | 0.274
-10 | 3581 | 0.155 | 1.706 | 0.351
-12 | 2991 | 0.162 | 1.425 | 0.459
-14 | 2529 | 0.161 | 1.205 | 0.534
-16 | 2144 | 0.162 | 1.021 | 0.583
-20 | 1253 | 0.196 | 0.597 | 0.746
-25 | 476 | 0.233 | 0.227 | 0.877
-30 | 176 | 0.267 | 0.084 | 0.944
sessoes=535 pedidos=2099 transcritos_ausentes=384
```

## Critério e escolha

Maximizar a fração útil mantendo pelo menos ~30% dos pedidos com alguma injeção (fração sem injeção <= 0.70).
Entre os limiares que cumprem isso (-2 a -16), a fração útil máxima é 0.140, em -12 e -16 (empate); fico com -16,
que injeta menos (0.856 por pedido) pelo mesmo ganho e deixa 33,6% dos pedidos com injeção.

## Ressalva honesta

O sinal é fraco: a fração útil sobe só de 0.104 (-2) para 0.140 (-16), e a nota mede apenas termos raros do
conteúdo reaparecendo depois do pedido, um piso conservador de utilidade. O bm25 sozinho separa pouco o que serve
do que não serve; o limiar corta volume mais do que melhora precisão. Mais rigoroso que -16 (-20 em diante) deixa
80% ou mais dos pedidos sem memória, abaixo do mínimo de cobertura. A decisão de usar bm25 como único critério fica
com quem decide o desenho.

LIMIAR_BM25 = -16
