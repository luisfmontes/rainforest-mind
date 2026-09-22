/**
 * Chave de grupo de origem de uma observação, para a consolidação (D7).
 *
 * Por que existe: a consolidação agrupa por sessão de origem — sessão já é
 * unidade de assunto, e um resumo por sessão não mistura temas sem relação
 * como o lote cronológico antigo misturava. Mas sessão só existe para 12% do
 * acervo (`origem` na forma `sessao:<id>:offset:<n>`); as 88% importadas do
 * claude-mem têm `origem` na forma `claude-mem:<seq>:<hash>`, com `<seq>` um
 * contador de importação distinto em TODA linha — não é sessão nenhuma.
 * Agrupar só por sessão deixaria 88% do acervo sem síntese para sempre.
 *
 * Emenda de 2026-09-18 ao D7 (decisão do usuário): para quem não tem sessão,
 * agrupa por (projeto, dia de criada_em) — medido em 98 grupos, média 103,
 * maior 521, só 3 grupos de 1; a importação é cronológica por projeto, e um
 * dia dentro de um projeto é o mais perto de "um assunto" que o dado permite.
 *
 * Exported: sqlGrupoDeOrigem()
 *   - devolve a EXPRESSÃO SQL (string), não um valor — para ser colada tanto
 *     no GROUP BY de `cmdConsolidar` (scripts/memoria.cjs) quanto numa
 *     consulta externa de conferência (o critério 1 da tarefa 4 a importa e
 *     usa contra o banco real).
 *   - a expressão referencia as colunas de `observacoes` SEM alias de tabela
 *     (`origem`, `projeto`, `criada_em`) — quem a usa com uma tabela aliased
 *     precisa colar a expressão numa subquery ou usar o mesmo nome de tabela.
 */

// `sessao:` tem 7 caracteres — substr(origem, 8) é tudo depois do prefixo.
// O id da sessão termina no primeiro ':' que sobra (o de ':offset:<n>').
function sqlGrupoDeOrigem() {
  return (
    "CASE " +
    "WHEN origem LIKE 'sessao:%' " +
    "THEN substr(origem, 8, instr(substr(origem, 8), ':') - 1) " +
    "ELSE projeto || ':' || substr(criada_em, 1, 10) " +
    'END'
  );
}

module.exports = { sqlGrupoDeOrigem };
