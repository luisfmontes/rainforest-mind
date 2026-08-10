#!/usr/bin/env node
// Heartbeat da sessão para consciência entre janelas paralelas.
// Chamado em três eventos (argv[2]): "prompt" (UserPromptSubmit — o Luís
// agiu), "stop" (Stop — o Claude terminou o turno e está esperando) e "end"
// (SessionEnd — a sessão acabou, a entrada sai do arquivo).
// Ocioso = stop_ts mais novo que prompt_ts e antigo demais; Claude
// trabalhando (prompt_ts > stop_ts) nunca conta como ocioso.
const fs = require('fs');
const path = require('path');
const { processoVivo } = require('./lib/contexto-sessao.cjs');

const ROOT = process.env.RFM_ROOT || 'C:\\Projetos\\rainforest-mind';
const STATE = path.join(ROOT, 'sessoes.json');
const acao = process.argv[2];
const evento = acao === 'stop' ? 'stop_ts' : 'prompt_ts';

let input = '';
try { input = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }
let data = {};
try { data = JSON.parse(input); } catch { process.exit(0); }
if (!data.session_id) process.exit(0);

let state = {};
try { state = JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch {}

if (acao === 'end') {
  // Encerramento limpo (/clear, logout, sair do prompt): a entrada sai na hora.
  // Sem isto, a última linha de uma sessão morta fica idêntica à de uma sessão
  // viva e ociosa, e o radar da abertura conta janela fechada como janela aberta.
  delete state[data.session_id];
} else {
  const s = state[data.session_id] || {};
  if (data.cwd) s.cwd = data.cwd;
  // O PID do processo que chamou o hook é o claude.exe desta sessão. É o que
  // permite a varredura da abertura derrubar o que o SessionEnd não alcança:
  // janela fechada no X, crash e reboot não disparam evento nenhum.
  s.pid = process.ppid;
  s[evento] = Date.now();
  state[data.session_id] = s;
}

// Poda: processo morto sai imediatamente; sem atividade há 24h+ também. A idade
// continua sendo a rede embaixo — cobre entrada antiga sem `pid` e PID reciclado
// depois de um reboot.
const corte = Date.now() - 24 * 3600 * 1000;
for (const [id, x] of Object.entries(state)) {
  const ult = Math.max(x.prompt_ts || 0, x.stop_ts || 0);
  if (ult < corte || (x.pid && id !== data.session_id && !processoVivo(x.pid))) delete state[id];
}

// ponytail: escrita direta sem lock — última escrita vence, dano máximo é
// perder um heartbeat, que o evento seguinte repõe.
try { fs.writeFileSync(STATE, JSON.stringify(state)); } catch {}
