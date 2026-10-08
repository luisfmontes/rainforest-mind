#!/usr/bin/env node
// @categoria: guia
// PreToolUse (Agent): acrescenta ao prompt do subagente as memorias de QUALQUER projeto que tratam
// do assunto dele (design 2026-10-08-memoria-por-assunto, D5/D6). Ramo updatedInput: o harness
// aceita updatedInput sem permissionDecision (tarefa 1), entao este hook nao decide permissao —
// a portaria segue sendo a unica que decide. Somente leitura no banco; nao escreve arquivo nenhum
// (o arquivo da sessao e so do hook do prompt: cada subagente e contexto novo).
// D6: qualquer falha -> stdout vazio e exit 0. O despacho do agente nunca espera nem quebra por isto.
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { buscarPorAssunto, montarBlocoAssunto } = require('./lib/memoria-assunto.cjs');
const { abrirBancoSomenteLeitura, resolverCaminhos } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));

// Devolve o JSON a imprimir, ou '' quando nao ha o que injetar. Lanca em qualquer falha.
function executar() {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8'));
  if (payload.tool_name !== 'Agent' && payload.tool_name !== 'Task') return '';
  const original = payload.tool_input;
  if (!original || typeof original !== 'object' || typeof original.prompt !== 'string' || !original.prompt.trim()) return '';
  const sessao = String(payload.session_id || '');
  if (!/^[A-Za-z0-9_-]+$/.test(sessao)) throw new Error('session_id invalido');

  const cwd = payload.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const { raiz } = resolverRaiz({ cwd, plugin: path.resolve(__dirname, '..') });
  if (!raiz) throw new Error('sem raiz de dados');
  const { caminhoDb, projetos } = resolverCaminhos(cwd);
  if (!fs.existsSync(caminhoDb)) throw new Error('banco ausente');
  const conexao = abrirBancoSomenteLeitura(caminhoDb);
  if (!conexao) throw new Error('banco indisponivel');

  try {
    // Subagente e contexto isolado: nao recebeu o que o pai recebeu, entao nao ha dedupe da sessao
    // (nao le nem grava o arquivo da sessao; o pedido seguinte nao perde nada por causa dele).
    const achadas = buscarPorAssunto(conexao, original.prompt, { projetoAtual: projetos[0], jaServidos: new Set(), max: 3 });
    const bloco = montarBlocoAssunto(achadas);
    if (!bloco) return '';

    const novoPrompt = original.prompt + '\n\n' + bloco;
    const entrada = { ...original, prompt: novoPrompt };
    return JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', updatedInput: entrada } });
  } finally {
    try { conexao.close(); } catch (e) { /* melhor esforco */ }
  }
}

try {
  const saida = executar();
  if (saida) process.stdout.write(saida + '\n');
} catch (e) {
  process.exitCode = 0;
}
