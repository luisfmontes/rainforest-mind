#!/usr/bin/env node
// SessionStart hook: injeta as regras rainforest-mind + foco declarado em toda sessão.
const fs = require('fs');
const path = require('path');
const net = require('net');

// Dados (FOCO/IDEIAS) vivem no repo de trabalho, não na cópia em cache do plugin.
const DATA_ROOT = process.env.RFM_ROOT || 'C:\\Projetos\\rainforest-mind';
const ROOT = fs.existsSync(DATA_ROOT) ? DATA_ROOT : path.resolve(__dirname, '..');

function readSafe(p) {
  try { return fs.readFileSync(p, 'utf8').trim(); } catch { return ''; }
}

// Checagem de dependências de ambiente
function readPlugins() {
  // A raiz da config sai do CLAUDE_CONFIG_DIR da sessão, nunca escrita à mão:
  // em 2026-08-08 ela virou .claude-personal e o caminho fixo aqui passou a ler
  // o settings.json antigo — reportando "apontamento-horas ausente" com o plugin
  // instalado e habilitado. Regra 14.
  const configDir = process.env.CLAUDE_CONFIG_DIR
    || path.join(process.env.USERPROFILE || process.env.HOME || '', '.claude');
  const userSettingsPath = process.env.RFM_SETTINGS_PATH || path.join(configDir, 'settings.json');
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const projectSettingsPath = path.join(projectDir, '.claude', 'settings.json');
  const projectLocalSettingsPath = path.join(projectDir, '.claude', 'settings.local.json');

  let allPlugins = {};
  let filesRead = 0;

  // Ordem: usuário, projeto, projeto local (último vence)
  for (const filePath of [userSettingsPath, projectSettingsPath, projectLocalSettingsPath]) {
    try {
      const settings = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const plugins = settings.enabledPlugins || {};
      allPlugins = { ...allPlugins, ...plugins };
      filesRead++;
    } catch {
      // Arquivo ausente ou JSON inválido, ignorar
    }
  }

  // Determinar status para cada plugin
  const getStatus = (pluginKey, defaultMessage) => {
    if (allPlugins[pluginKey] === true) {
      return 'ok';
    } else if (filesRead > 0) {
      // Pelo menos um arquivo foi lido
      return `ausente neste projeto (${defaultMessage})`;
    } else {
      // Nenhum arquivo pôde ser lido
      return '?';
    }
  };

  return {
    apontamento: getStatus('um plugin de apontamento externo', 'regra 8 no fallback de relógio'),
    claudeMem: getStatus('claude-mem@thedotmack', 'revisão bimestral sem dados'),
  };
}

function testTcpConnection(host, port, timeout = 400) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host, port, timeout });
    let done = false;

    const onConnect = () => {
      if (!done) {
        done = true;
        socket.destroy();
        resolve(true);
      }
    };

    const onError = () => {
      if (!done) {
        done = true;
        socket.destroy();
        resolve(false);
      }
    };

    const onTimeout = () => {
      if (!done) {
        done = true;
        socket.destroy();
        resolve(false);
      }
    };

    socket.on('connect', onConnect);
    socket.on('error', onError);
    socket.on('timeout', onTimeout);
  });
}

async function checkWhatsAppBridge() {
  const url = process.env.WHATSAPP_API_BASE_URL || 'http://localhost:3005';
  let host = 'localhost';
  let port = 3005;

  try {
    const urlObj = new URL(url);
    host = urlObj.hostname;
    port = urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80);
  } catch {
    // Se URL for inválida, usa default
  }

  const isConnected = await testTcpConnection(host, parseInt(port, 10));
  return {
    status: isConnected ? 'ok' : 'FORA',
    url: url,
  };
}

const foco = readSafe(path.join(ROOT, 'FOCO.md'));
const skill = readSafe(path.join(ROOT, 'skills', 'rainforest-mind', 'SKILL.md'));

// Aviso de revisão bimestral a partir da linha "Última revisão: YYYY-MM-DD"
let revisao = '';
const m = skill.match(/Última revisão:\s*(\d{4}-\d{2}-\d{2})/);
if (m) {
  const dias = Math.floor((Date.now() - new Date(m[1]).getTime()) / 86400000);
  if (dias > 60) {
    revisao = `\n⚠ A skill rainforest-mind não é revisada há ${dias} dias (limite: 60). Avise o Luís que está na hora de revisá-la.`;
  }
}

// O bloco de regras e 94% do SKILL.md, e e injetado em TODA sessao. O que
// pesa dentro dele nao e a regra: e o incidente datado que a justifica.
//
// Incidente citado em blockquote (`> ...`) sai da injecao e continua no
// arquivo, ao lado da regra que ele fundamenta. Isso separa duas funcoes que
// estavam pagando o mesmo preco: a regra precisa estar residente para valer
// em toda resposta; o incidente precisa estar LEGIVEL para o Luis manter a
// regra (regra 13) e para o corpo da skill quando ela e aberta sob demanda.
// A doc do Claude Code e explicita: "a skill's body loads only when it's
// used" — este hook contornava isso injetando o corpo inteiro.
//
// Regra pratica ao marcar: vai pro blockquote a NARRATIVA (o que aconteceu,
// quando, quem corrigiu). Nunca a instrucao — se a frase diz o que fazer,
// ela fica fora do blockquote, sempre residente.
const CITACAO = /^>.*(?:\r?\n|$)/gm;
const regras = (skill.split('## As regras')[1]?.split('## Comando')[0] || '')
  .replace(CITACAO, '')
  .replace(/\n{3,}/g, '\n\n')
  .trim();

// Sessões paralelas (heartbeat: prompt_ts = o Luís agiu, stop_ts = Claude
// terminou o turno e está esperando)
let sessoes = '';
try {
  const state = JSON.parse(fs.readFileSync(path.join(ROOT, 'sessoes.json'), 'utf8'));
  const agora = Date.now();
  const linhas = Object.entries(state)
    .filter(([, s]) => agora - Math.max(s.prompt_ts || 0, s.stop_ts || 0) < 6 * 3600 * 1000)
    .map(([id, s]) => {
      const p = s.prompt_ts || 0, t = s.stop_ts || 0;
      const min = (x) => Math.round((agora - x) / 60000);
      const status = p > t
        ? `Claude trabalhando (turno em curso há ${min(p)} min)`
        : `esperando o Luís há ${min(t || p)} min`;
      return `- ${s.cwd || '(pasta desconhecida)'} — ${status}`;
    });
  if (linhas.length) {
    const oci = (foco.match(/Ociosidade máxima:\s*(\d+)\s*min/i) || [])[1] || '45';
    sessoes = `\n## Outras sessões recentes (radar multi-janela)\n${linhas.join('\n')}\n` +
      `Se alguma dessas sessões está no projeto do foco ativo, o radar DESTA sessão fica leve (trabalho paralelo é normal). ` +
      `Ocioso = "esperando o Luís" — Claude trabalhando nunca conta. ` +
      `O alerta que importa: sessão do projeto do foco esperando o Luís há ${oci}+ min enquanto as demais trabalham — avisar uma vez ("a janela do foco esfriou").\n`;
  }
} catch {}

// Checagem de dependências com timeout garantido
let impresso = false;

function doConsoleLog(pluginsStatus, whatsappStatus) {
  if (impresso) return;
  impresso = true;
  // Sem isto o timer de guarda segura o event loop e TODA sessão paga os 700ms,
  // mesmo com o bridge respondendo em 1ms (medido: 82ms → 776ms).
  if (guarda) clearTimeout(guarda);

  const dependencias = `## Dependências de ambiente (regra 14)
Checado pelo hook: apontamento-horas ${pluginsStatus.apontamento}; bridge WhatsApp ${whatsappStatus.status} (${whatsappStatus.url}); claude-mem ${pluginsStatus.claudeMem}.
Nenhum script enxerga o prompt DESTA sessão: se ela proibir o Agent (regra 10), um MCP ou qualquer outra regra, diga em UMA linha na primeira vez que a regra seria aplicada, nomeando o efeito prático — silêncio faz o Luís acreditar que a regra rodou.`;

  console.log(`RAINFOREST MIND ATIVO — memória de trabalho externa e radar de escopo do Luís (perfil 2e).

## Regras (aplicar em toda resposta)
${regras}

## Foco declarado
${foco || '(nenhum foco declarado — sugira /foco <texto> se o Luís disser no que precisa entregar)'}
${sessoes}${revisao}${dependencias}

Arquivos de apoio: ${ROOT}\\FOCO.md e ${ROOT}\\ideias.jsonl (uma ideia por linha)`);
}

// Força impressão após 700ms se não terminar (cancelado assim que imprime)
const guarda = setTimeout(() => {
  if (!impresso) {
    const pluginsStatus = readPlugins();
    doConsoleLog(pluginsStatus, { status: '?', url: process.env.WHATSAPP_API_BASE_URL || 'http://localhost:3005' });
  }
}, 700);

// Executa checagem de dependências e imprime quando pronto
(async () => {
  try {
    const pluginsStatus = readPlugins();
    const whatsappStatus = await checkWhatsAppBridge();
    doConsoleLog(pluginsStatus, whatsappStatus);
  } catch {
    if (!impresso) {
      const pluginsStatus = readPlugins();
      doConsoleLog(pluginsStatus, { status: '?', url: process.env.WHATSAPP_API_BASE_URL || 'http://localhost:3005' });
    }
  }
})();
