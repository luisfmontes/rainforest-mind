#!/usr/bin/env node
// @categoria: guia
// PreToolUse (Agent): acrescenta ao prompt do subagente as memorias de QUALQUER projeto que tratam
// do assunto dele (design 2026-10-08-memoria-por-assunto, D5/D6). Ramo updatedInput: o harness
// aceita updatedInput sem permissionDecision (tarefa 1), entao este hook nao decide permissao —
// a portaria segue sendo a unica que decide. Somente leitura no banco; o unico arquivo escrito e
// <raiz>/memoria-assunto/<session_id>.json (so ids, D10), compartilhado com o hook do prompt.
// D6: qualquer falha -> stdout vazio e exit 0. O despacho do agente nunca espera nem quebra por isto.
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { buscarPorAssunto, montarBlocoAssunto } = require('./lib/memoria-assunto.cjs');
const { abrirBancoSomenteLeitura, resolverCaminhos } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { extrairSessao, acharAlvo } = require(path.join(__dirname, '..', 'scripts', 'lib', 'utilidade.cjs'));

function lerIds(arquivo) {
  const dado = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  if (!Array.isArray(dado)) throw new Error('arquivo de sessao invalido');
  return dado.filter((n) => Number.isInteger(n));
}

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
    const arquivo = path.join(raiz, 'memoria-assunto', sessao + '.json');
    let servidos;
    if (fs.existsSync(arquivo)) {
      servidos = new Set(lerIds(arquivo));
    } else {
      // Primeiro uso na sessao: semeia com o que a abertura ja serviu (transcrito).
      servidos = new Set();
      const apelidos = projetos.length > 1 ? { [projetos[0]]: projetos[projetos.length - 1] } : null;
      for (const linha of extrairSessao(String(payload.transcript_path || '')).servidas) {
        const alvo = acharAlvo(conexao, linha, apelidos);
        if (alvo && alvo.origem === 'observacao') servidos.add(alvo.id);
      }
    }

    const achadas = buscarPorAssunto(conexao, original.prompt, { projetoAtual: projetos[0], jaServidos: servidos, max: 3 });
    const bloco = montarBlocoAssunto(achadas);
    if (!bloco) return '';

    for (const a of achadas) servidos.add(a.id);
    fs.mkdirSync(path.dirname(arquivo), { recursive: true });
    fs.writeFileSync(arquivo, JSON.stringify(Array.from(servidos)));
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
