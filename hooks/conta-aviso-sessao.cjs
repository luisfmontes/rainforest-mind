#!/usr/bin/env node
// @categoria: guia
// SessionStart e UserPromptSubmit: injeta no contexto os problemas de conta abertos (regra 14), uma
// vez por sessão (D5 e D6 da Issue #693, plano conta-reserva-avisa, tarefa 5). Lê o log de eventos
// e o expiresAt dos logins; nunca lê token e nunca grava fora de <dados>/contas/avisos-vistos/.
// Qualquer falha -> stdout vazio e exit 0: o hook nunca derruba a sessão.
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {
  dadosDir,
  lerEventosArq,
  problemasAbertos,
  montarSecao,
  JANELA_DIAS,
} = require(path.join(__dirname, '..', 'scripts', 'lib', 'conta-avisos.cjs'));

const EVENTOS = new Set(['SessionStart', 'UserPromptSubmit']);
const RE_SESSAO = /^[A-Za-z0-9_-]+$/;
const DIA_MS = 24 * 60 * 60 * 1000;

// mtime em ms, ou null se o arquivo não existe.
function mtimeOuNulo(arq) {
  try {
    return fs.statSync(arq).mtimeMs;
  } catch {
    return null;
  }
}

// expiresAt do login (ms), ou null em qualquer erro. Só esse campo sai do arquivo.
function expiraEmDe(arq) {
  try {
    const exp = JSON.parse(fs.readFileSync(arq, 'utf8')).claudeAiOauth.expiresAt;
    return Number.isFinite(exp) ? exp : null;
  } catch {
    return null;
  }
}

// Chaves já mostradas nesta sessão. Ausente ou fora do formato = nenhuma.
function lerVistos(arq) {
  try {
    const dado = JSON.parse(fs.readFileSync(arq, 'utf8'));
    return Array.isArray(dado) ? dado.filter((c) => typeof c === 'string') : [];
  } catch {
    return [];
  }
}

// Apaga, na leitura, os arquivos de sessão com mais de 7 dias.
function limparVistos(dir, agora) {
  let nomes;
  try {
    nomes = fs.readdirSync(dir);
  } catch {
    return;
  }
  for (const nome of nomes) {
    const arq = path.join(dir, nome);
    try {
      if (agora - fs.statSync(arq).mtimeMs > JANELA_DIAS * DIA_MS) fs.unlinkSync(arq);
    } catch {
      /* arquivo sumiu ou sem permissão: segue */
    }
  }
}

function saidaDoHook(entrada, agora = Date.now()) {
  const evento = String(entrada.hook_event_name || '');
  const sessao = String(entrada.session_id || '');
  if (!EVENTOS.has(evento) || !RE_SESSAO.test(sessao)) return '';

  const dados = dadosDir({ env: process.env, home: os.homedir(), plugin: path.resolve(__dirname, '..') });
  if (!dados) return '';
  const contas = path.join(dados, 'contas');

  const eventos = lerEventosArq(path.join(contas, 'eventos.jsonl'));
  if (!eventos.length) return '';

  const vigiaOkEm = mtimeOuNulo(path.join(contas, 'vigia-ok'));
  const expiraEm = (nome) => expiraEmDe(path.join(contas, `${nome}.json`));
  const abertos = problemasAbertos(eventos, { agora, expiraEm, vigiaOkEm });

  const dirVistos = path.join(contas, 'avisos-vistos');
  const arqVistos = path.join(dirVistos, `${sessao}.json`);
  limparVistos(dirVistos, agora);
  const vistos = new Set(lerVistos(arqVistos));
  const novos = abertos.filter((p) => !vistos.has(p.chave)); // D5 (conta-reserva-avisa)
  if (!novos.length) return '';

  // Grava todas as chaves mostradas, inclusive as do "e mais N" (senão a linha voltaria a cada turno).
  // Falha de gravação não cala o aviso: só significa que ele pode voltar na próxima mensagem.
  try {
    fs.mkdirSync(dirVistos, { recursive: true });
    fs.writeFileSync(arqVistos, JSON.stringify([...vistos, ...novos.map((p) => p.chave)]));
  } catch {
    /* melhor esforço */
  }

  return JSON.stringify({ hookSpecificOutput: { hookEventName: evento, additionalContext: montarSecao(novos) } });
}

try {
  const entrada = JSON.parse(fs.readFileSync(0, 'utf8'));
  const saida = saidaDoHook(entrada);
  if (saida) process.stdout.write(saida + '\n');
} catch {
  /* stdin vazio, não JSON ou erro de leitura: sai mudo */
}
process.exitCode = 0;
