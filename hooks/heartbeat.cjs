#!/usr/bin/env node
// Heartbeat da sessão para consciência entre janelas paralelas.
// Chamado em três eventos (argv[2]): "prompt" (UserPromptSubmit — o usuario
// agiu), "stop" (Stop — o Claude terminou o turno e está esperando) e "end"
// (SessionEnd — a sessão acabou, a entrada sai do arquivo).
// Ocioso = stop_ts mais novo que prompt_ts e antigo demais; Claude
// trabalhando (prompt_ts > stop_ts) nunca conta como ocioso.
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./lib/raiz.cjs');

// A MESMA cadeia que o hook de abertura usa para LER. Era
// `RFM_ROOT || 'C:\Projetos\rainforest-mind'` — caminho da máquina do usuario
// cravado —, e em 2026-08-11, quando os dados saíram do repo, este arquivo
// continuou gravando no lugar velho enquanto a abertura passou a ler no novo.
// Efeito: o radar multi-janela cegou por completo, sem erro nenhum, porque o
// `sessoes.json` que ele lia simplesmente não recebia mais escrita.
//
// Quem lê e quem escreve o mesmo arquivo resolvem o caminho pela mesma função,
// ou a divergência aparece como ausência silenciosa de dado.

// Nota sobre PID: em 2026-08-13 foi tentado gravar o PID do claude.exe subindo
// a árvore de processos (bash -> bash -> bash -> claude.exe). Isso foi abandonado.
// Causa 1: shell efêmera. O hook roda em uma shell criada para executá-lo, e essa
// shell morre imediatamente. ParentProcessId fica gravado no kernel mas a cadeia
// é quebrada: `bash.exe (pid=2940) tem ppid=46360`, mas 46360 não existe mais.
// Causa 2: elo morto permanente. Sem acesso ao processo que foi, o walk quebra
// antes de chegar a claude.exe, não importa quantas vezes é tentado. Funciona
// em teste isolado (cadeia viva) mas falha em produção (cadeia com elo morto).
// Causa 3: linha de comando sem identidade. `"...\claude.exe" --dangerously-skip-permissions`
// não tem session id, não tem cwd, não tem projeto — impossível casar pela CLI.
//
// Desenho aprovado: podar só por IDADE (24h). SessionEnd cuida do fechamento
// limpo (ação "end"). Custo aceito, nomeado: janela fechada no X ou por crash
// fica no arquivo até o corte de 24 h, pode ser lida como janela do foco ociosa.
// Isso é pior que perder o PID de verdade (cegueira), mas melhor que falhar a
// resolver (ficar travado aguardando resposta). Radar multi-janela depende de
// SessionEnd ser chamado — é o mecanismo real de limpeza.

const CODIGO_ROOT = path.resolve(__dirname, '..');
const ROOT = resolverRaiz({ plugin: CODIGO_ROOT }).raiz || CODIGO_ROOT;
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
  s[evento] = Date.now();
  state[data.session_id] = s;
}

// Poda: sem atividade há 24h+ sai. Idade é a rede embaixo — cobre processamento
// de crash, reboot, janela fechada no X. SessionEnd cobre fechamento limpo.
const corte = Date.now() - 24 * 3600 * 1000;
for (const [id, x] of Object.entries(state)) {
  const ult = Math.max(x.prompt_ts || 0, x.stop_ts || 0);
  if (ult < corte) delete state[id];
}

// ponytail: escrita direta sem lock — última escrita vence, dano máximo é
// perder um heartbeat, que o evento seguinte repõe.
try { fs.writeFileSync(STATE, JSON.stringify(state)); } catch {}
