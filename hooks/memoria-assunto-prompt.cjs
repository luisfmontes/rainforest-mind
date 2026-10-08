#!/usr/bin/env node
// @categoria: guia
// UserPromptSubmit: injeta memorias de QUALQUER projeto que tratam do assunto do pedido
// (design 2026-10-08-memoria-por-assunto, D1/D2/D3/D6/D10). Somente leitura no banco;
// o unico arquivo escrito e <raiz>/memoria-assunto/<session_id>.json, que guarda SO ids (D10).
// D6: qualquer falha -> stdout vazio e exit 0. O pedido do usuario nunca espera nem quebra por isto.
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { buscarPorAssunto, montarBlocoAssunto } = require('./lib/memoria-assunto.cjs');
const { abrirBancoSomenteLeitura, resolverCaminhos } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { extrairLinhasServidas, acharAlvo } = require(path.join(__dirname, '..', 'scripts', 'lib', 'utilidade.cjs'));
const CAB_ABERTURA = '## Memória (corpus residentes)';

const MIN_TERMOS = 3;
const MIN_TAMANHO_TERMO = 3;

function termosUteis(texto) {
  const brutos = String(texto || '').match(/[\p{L}\p{N}]+/gu) || [];
  return new Set(brutos.map((t) => t.toLowerCase()).filter((t) => t.length >= MIN_TAMANHO_TERMO)).size;
}

function lerIds(arquivo) {
  const dado = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  if (!Array.isArray(dado)) throw new Error('arquivo de sessao invalido');
  return dado.filter((n) => Number.isInteger(n));
}

function persistirServidos(arquivo, ids) {
  fs.mkdirSync(path.dirname(arquivo), { recursive: true });
  fs.writeFileSync(arquivo, JSON.stringify(Array.from(ids)));
}

// O attachment de SessionStart vem no comeco do transcrito: le so os primeiros 2 MiB
// (transcrito real chega a 95 MB; extrairSessao inteiro leva 12 s contra o timeout de 5 s).
// A ultima linha pode vir cortada: JSON invalido e ignorado.
const BYTES_SEMEADURA = 2 * 1024 * 1024;
function lerServidasDoInicio(caminhoTranscrito) {
  const fd = fs.openSync(caminhoTranscrito, 'r');
  let texto;
  try {
    const buf = Buffer.alloc(BYTES_SEMEADURA);
    const lidos = fs.readSync(fd, buf, 0, BYTES_SEMEADURA, 0);
    texto = buf.toString('utf8', 0, lidos);
  } finally { fs.closeSync(fd); }
  const servidas = [];
  for (const l of texto.split('\n')) {
    if (!l.includes('SessionStart')) continue;
    let e;
    try { e = JSON.parse(l); } catch (err) { continue; }
    if (e.type !== 'attachment' || !e.attachment || e.attachment.hookEvent !== 'SessionStart') continue;
    let ctx = null;
    try { ctx = JSON.parse(e.attachment.stdout).hookSpecificOutput.additionalContext; } catch (err) { ctx = null; }
    if (ctx) for (const linha of extrairLinhasServidas(ctx, [CAB_ABERTURA])) servidas.push(linha);
  }
  return servidas;
}

// Devolve o JSON a imprimir, ou '' quando nao ha o que injetar. Lanca em qualquer falha.
function executar() {
  const entrada = JSON.parse(fs.readFileSync(0, 'utf8'));
  const prompt = typeof entrada.prompt === 'string' ? entrada.prompt : '';
  const sessao = String(entrada.session_id || '');
  if (!/^[A-Za-z0-9_-]+$/.test(sessao)) throw new Error('session_id invalido');
  if (prompt.trimStart().startsWith('/') || termosUteis(prompt) < MIN_TERMOS) return '';

  const cwd = entrada.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
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
      // Primeiro pedido da sessao: semeia com o que a abertura ja serviu (transcrito).
      servidos = new Set();
      const apelidos = projetos.length > 1 ? { [projetos[0]]: projetos[projetos.length - 1] } : null;
      for (const linha of lerServidasDoInicio(String(entrada.transcript_path || ''))) {
        const alvo = acharAlvo(conexao, linha, apelidos);
        if (alvo && alvo.origem === 'observacao') servidos.add(alvo.id);
      }
      // A semeadura roda uma vez por sessao: grava ja, com ou sem acerto, para o proximo
      // pedido nao reparsear o transcrito.
      persistirServidos(arquivo, servidos);
    }

    const achadas = buscarPorAssunto(conexao, prompt, { projetoAtual: projetos[0], jaServidos: servidos, max: 3 });
    const bloco = montarBlocoAssunto(achadas);
    if (!bloco) return '';

    for (const a of achadas) servidos.add(a.id);
    persistirServidos(arquivo, Array.from(servidos));
    return JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: bloco } });
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
