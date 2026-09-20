# Critério — fluxo 13, parte 2: o loop, keep/discard e as paradas

O diff altera `skills/regua/SKILL.md`. Julgue **só** se as sete afirmações abaixo
são verdadeiras sobre o texto que o diff deixa no arquivo. Cada uma é
falsificável: se o texto disser o contrário, ou não disser nada, a afirmação é
falsa. Responda `concordo` só se as sete forem verdadeiras; qualquer uma falsa →
`discordo`, nomeando o número.

1. **Dois críticos por rodada, em despachos separados.** O texto prescreve dois
   `Agent` novos e cegos a cada rodada — um contra a régua, outro contra o nosso
   melhor guardado — e dá o motivo de não serem o mesmo: um crítico só, vendo as
   três peças, identifica pelo parentesco quais duas são nossas e o anonimato cai.

2. **Os dois recebem o mesmo manifesto, da mesma origem.** O texto diz que o
   crítico interno também recebe os mecanismos, pelo mesmo comando `conferir-regua.cjs
   mostrar`, e dá o motivo (crítico sem critério devolve "o B está mais polido").

3. **A lacuna única sai da comparação contra a régua.** O texto afirma que a lacuna
   que alimenta o builder da rodada seguinte vem do crítico da régua, nunca do
   crítico interno, e dá o motivo (senão o loop passa a se perseguir).

4. **Keep/discard vem da comparação interna, e o melhor guardado é um SHA.** O
   texto diz que nosso-novo contra nosso-melhor decide guardar ou descartar, que o
   melhor guardado é um commit registrado no log de rodadas e materializado por
   `git show`, e declara o limite: artefato que só existe renderizado precisa ter o
   render commitado junto, senão a comparação interna fica cega.

5. **Discard não apaga commit.** O texto afirma que o commit da rodada descartada
   permanece no histórico e que o que não avança é o ponteiro do melhor, com o
   motivo (a regra 11 proíbe git destrutivo em agente, e o commit por rodada existe
   para poder voltar). Texto que prescreva `git reset` ou equivalente reprova.

6. **São quatro condições de parada, não três.** Venceu, teto, régua errada e
   **estagnação** — três rodadas seguidas sem `keep`. O texto distingue estagnação
   de teto em vez de tratá-las como a mesma saída.

7. **O log existe, é versionado, e o teste de falsificação cobre o enxerto.** O
   texto nomeia `docs/rainforest/reguas/<slug>-rodadas.tsv` com as colunas
   `rodada`, `commit`, `venceu_regua`, `venceu_interno`, `status` e `lacuna`, com
   `status` em `keep|discard|abortado`, e diz que ele é versionado. E a seção "O
   que falsificaria esta skill" ganhou o caso do crítico interno: se em três usos
   toda rodada der `keep`, ele não discrimina e o remédio é cortá-lo.
