#!/usr/bin/env node
// Heartbeat da sessão para consciência entre janelas paralelas.
// Chamado em dois eventos (argv[2]): "prompt" (UserPromptSubmit — o Luís
// agiu) e "stop" (Stop — o Claude terminou o turno e está esperando).
// Ocioso = stop_ts mais novo que prompt_ts e antigo demais; Claude
// trabalhando (prompt_ts > stop_ts) nunca conta como ocioso.
const fs = require('fs');
const path = require('path');

const ROOT = process.env.RFM_ROOT || 'C:\\Projetos\\rainforest-mind';
const STATE = path.join(ROOT, 'sessoes.json');
const evento = process.argv[2] === 'stop' ? 'stop_ts' : 'prompt_ts';

let input = '';
try { input = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }
let data = {};
try { data = JSON.parse(input); } catch { process.exit(0); }
if (!data.session_id) process.exit(0);

let state = {};
try { state = JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch {}

const s = state[data.session_id] || {};
if (data.cwd) s.cwd = data.cwd;
s[evento] = Date.now();
state[data.session_id] = s;

// poda sessões sem atividade há 24h+
const corte = Date.now() - 24 * 3600 * 1000;
for (const [id, x] of Object.entries(state)) {
  const ult = Math.max(x.prompt_ts || 0, x.stop_ts || 0);
  if (ult < corte) delete state[id];
}

// ponytail: escrita direta sem lock — última escrita vence, dano máximo é
// perder um heartbeat, que o evento seguinte repõe.
try { fs.writeFileSync(STATE, JSON.stringify(state)); } catch {}
