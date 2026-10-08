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

(O limiar -16 desta primeira calibração, sem teto de frequência, foi substituído pela recalibração abaixo.)

## Recalibração (teto de frequência)

Motivo: sem teto, as palavras comuns do pedido (df alto) somavam bm25 até o limiar sem serem assunto. Agora
`construirQueryAssunto` descarta termo com df > `TETO_DF_FRACAO` × (observações vivas e não consolidadas) e a consulta
da calibração é montada por essa mesma função (teto como parâmetro opcional). Mesma cópia do banco, mesmos
transcritos, mesmo filtro temporal e mesma nota (sem o pedido) da primeira calibração.

Comando rodado:

```
node scripts/calibrar-limiar-assunto.cjs --db <copia-do-rainforest.db> --tetos 0.005,0.01,0.02 --limiares -1,-2,-3,-4,-5,-6,-8,-10,-12,-14,-16,-20
```

```
teto | limiar | injecoes | fracao_util(nota>=0.5) | media_por_pedido | fracao_pedidos_sem_injecao
0.005 | -1 | 5360 | 0.099 | 2.577 | 0.119
0.005 | -2 | 5350 | 0.099 | 2.572 | 0.119
0.005 | -3 | 5214 | 0.101 | 2.507 | 0.119
0.005 | -4 | 5009 | 0.105 | 2.408 | 0.120
0.005 | -5 | 4905 | 0.106 | 2.358 | 0.129
0.005 | -6 | 4665 | 0.107 | 2.243 | 0.144
0.005 | -8 | 1723 | 0.189 | 0.828 | 0.585
0.005 | -10 | 628 | 0.252 | 0.302 | 0.823
0.005 | -12 | 286 | 0.311 | 0.138 | 0.912
0.005 | -14 | 125 | 0.304 | 0.060 | 0.958
0.005 | -16 | 80 | 0.350 | 0.038 | 0.971
0.005 | -20 | 30 | 0.200 | 0.014 | 0.990
0.01 | -1 | 5668 | 0.107 | 2.725 | 0.079
0.01 | -2 | 5665 | 0.107 | 2.724 | 0.079
0.01 | -3 | 5548 | 0.109 | 2.667 | 0.079
0.01 | -4 | 5377 | 0.113 | 2.585 | 0.080
0.01 | -5 | 5314 | 0.113 | 2.555 | 0.082
0.01 | -6 | 4981 | 0.111 | 2.395 | 0.103
0.01 | -8 | 2242 | 0.179 | 1.078 | 0.512
0.01 | -10 | 1119 | 0.217 | 0.538 | 0.716
0.01 | -12 | 508 | 0.262 | 0.244 | 0.856
0.01 | -14 | 235 | 0.234 | 0.113 | 0.926
0.01 | -16 | 137 | 0.270 | 0.066 | 0.952
0.01 | -20 | 50 | 0.140 | 0.024 | 0.985
0.02 | -1 | 5974 | 0.116 | 2.872 | 0.036
0.02 | -2 | 5972 | 0.116 | 2.871 | 0.036
0.02 | -3 | 5856 | 0.118 | 2.815 | 0.036
0.02 | -4 | 5700 | 0.121 | 2.740 | 0.036
0.02 | -5 | 5681 | 0.121 | 2.731 | 0.037
0.02 | -6 | 5162 | 0.116 | 2.482 | 0.083
0.02 | -8 | 2757 | 0.175 | 1.325 | 0.430
0.02 | -10 | 1655 | 0.190 | 0.796 | 0.619
0.02 | -12 | 806 | 0.203 | 0.388 | 0.798
0.02 | -14 | 397 | 0.207 | 0.191 | 0.887
0.02 | -16 | 217 | 0.212 | 0.104 | 0.933
0.02 | -20 | 83 | 0.108 | 0.040 | 0.975
sessoes=535 pedidos=2080 transcritos_ausentes=386
```

Critério (o mesmo da primeira calibração): maior fração útil com pelo menos 30% dos pedidos com alguma injeção
(fração sem injeção <= 0.70). Dentre os pares que cumprem, o maior é teto 0.02 com limiar -10 (fração útil 0.190,
61,9% dos pedidos sem injeção, 0.796 por pedido); o segundo é teto 0.005 com limiar -8 (0.189, 58,5% sem injeção). A
diferença entre os dois é de 0.001, dentro do ruído; vale o critério mecânico. Os pares com fração útil maior
(por exemplo teto 0.005 com limiar -16, 0.350) deixam 82% ou mais dos pedidos sem memória e ficam fora do critério.

Ressalvas: o teto sobe a fração útil de 0.140 (sem teto, limiar -16) para 0.190, ganho real mas modesto; a contagem de
vivas do teto é a da cópia inteira, não a do instante do pedido; 386 de 535 transcritos não existem na máquina.

LIMIAR_BM25 = -10
TETO_DF_FRACAO = 0.02
