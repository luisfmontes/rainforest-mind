#!/usr/bin/env node
// UserPromptSubmit hook (async): heartbeat da sessão para consciência
// entre janelas paralelas. Grava sessao → { cwd, ts } em sessoes.json.
const fs = require('fs');
const path = require('path');

const STATE = 'C:\\Projetos\\rainforest-mind\\sessoes.json';

let input = '';
try { input = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }
let data = {};
try { data = JSON.parse(input); } catch { process.exit(0); }
if (!data.session_id) process.exit(0);

let state = {};
try { state = JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch {}

state[data.session_id] = { cwd: data.cwd || '', ts: Date.now() };

// poda sessões sem atividade há 24h+
const corte = Date.now() - 24 * 3600 * 1000;
for (const [id, s] of Object.entries(state)) {
  if (!s.ts || s.ts < corte) delete state[id];
}

// ponytail: escrita direta sem lock — última escrita vence, dano máximo é
// perder um heartbeat, que o prompt seguinte repõe.
try { fs.writeFileSync(STATE, JSON.stringify(state)); } catch {}
