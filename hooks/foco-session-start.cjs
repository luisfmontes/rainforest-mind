#!/usr/bin/env node
// SessionStart hook: injeta as regras rainforest-mind + foco declarado em toda sessão.
//
// Este arquivo é o ADAPTADOR: só faz I/O (ler arquivo, sondar porta, imprimir).
// A montagem do texto injetado mora em lib/contexto-sessao.cjs, que é puro e tem
// bateria própria (hooks/testa-contexto-sessao.sh).
const fs = require('fs');
const path = require('path');
const net = require('net');
const { montarContexto, resumirSessoes, sessoesVivas } = require('./lib/contexto-sessao.cjs');
const { resolverRaiz } = require('./lib/raiz.cjs');

// Dados (FOCO/IDEIAS) vivem no repo de trabalho, não na cópia em cache do plugin.
// A cadeia de 5 níveis (RFM_ROOT > projeto > global > plugin > legado) está em
// lib/raiz.cjs, com o porquê de cada nível. `nivel` diz qual respondeu.
// DUAS raizes, e confundi-las apaga as regras da sessao inteira.
//
// CODIGO (skills, scripts, o proprio hook) mora sempre no plugin — e o plugin sabe
// onde ele mesmo esta. DADOS (FOCO.md, ideias.jsonl, sessoes.json) moram na pasta
// do usuario, resolvida pela cadeia.
//
// Em 2026-08-11, ao separar os dados do codigo, este arquivo passou a procurar o
// SKILL.md dentro da pasta de DADOS. Resultado: a injecao caiu de 7.967 B para
// 3.047 B e o fallback disparou — "esta sessao esta SEM o rainforest-mind", em
// TODA sessao. A degradacao barulhenta pegou em voz alta, que e para isso que ela
// existe; sem ela, as sessoes subiriam mudas e sem regra.
const CODIGO_ROOT = path.resolve(__dirname, '..');
const { raiz: RAIZ_RESOLVIDA, nivel: NIVEL_RAIZ } = resolverRaiz({ plugin: CODIGO_ROOT });
const ROOT = RAIZ_RESOLVIDA || CODIGO_ROOT;

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
    // A regra 8 deixou de depender deste plugin em 2026-08-11: a jornada se mede
    // com `scripts/jornada`, que le o transcript e nao depende de nada de fora.
    // O status continua util para quem TEM o plugin (conferencia do apontamento
    // formal), mas a ausencia dele nao degrada regra nenhuma — e dizer que degrada
    // era afirmacao falsa em toda sessao de quem nao o tem.
    apontamento: getStatus('um plugin de apontamento externo', 'opcional: confere o apontamento formal'),
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

const CAMINHO_SKILL = path.join(CODIGO_ROOT, 'skills', 'rainforest-mind', 'SKILL.md');
const foco = readSafe(path.join(ROOT, 'FOCO.md'));
const skill = readSafe(CAMINHO_SKILL);

// Aviso de revisão bimestral a partir da linha "Última revisão: YYYY-MM-DD"
let revisao = '';
const m = skill.match(/Última revisão:\s*(\d{4}-\d{2}-\d{2})/);
if (m) {
  const dias = Math.floor((Date.now() - new Date(m[1]).getTime()) / 86400000);
  if (dias > 60) {
    revisao = `\n⚠ A skill rainforest-mind não é revisada há ${dias} dias (limite: 60). Avise o Luís que está na hora de revisá-la.`;
  }
}

// Sessões paralelas (heartbeat: prompt_ts = o Luís agiu, stop_ts = Claude
// terminou o turno e está esperando)
let sessoes = '';
try {
  const state = JSON.parse(fs.readFileSync(path.join(ROOT, 'sessoes.json'), 'utf8'));
  const agora = Date.now();
  // Vivas = recentes E com processo de pé. Só a idade não bastava: janela fechada
  // não gera evento, e a entrada dela ficava idêntica à de uma sessão ociosa.
  const entradas = sessoesVivas(state, agora, 6 * 3600 * 1000)
    .map(([, s]) => {
      const p = s.prompt_ts || 0, t = s.stop_ts || 0;
      return {
        cwd: s.cwd,
        trabalhando: p > t,
        minutos: Math.round((agora - (p > t ? p : (t || p))) / 60000),
      };
    });
  // Só o estado medido + o parâmetro que o texto da regra não pode ter (a
  // ociosidade é por foco). O que fazer com isso é a regra 17, e reescrevê-la
  // aqui custava ~370 B em toda sessão que tem janela paralela aberta. A dedução
  // por pasta e o teto do bloco moram na lib, onde a bateria os alcança.
  const oci = (foco.match(/Ociosidade máxima:\s*(\d+)\s*min/i) || [])[1] || '45';
  sessoes = resumirSessoes(entradas, oci);
} catch {}

// Checagem de dependências com timeout garantido
let impresso = false;

function doConsoleLog(pluginsStatus, whatsappStatus) {
  if (impresso) return;
  impresso = true;
  // Sem isto o timer de guarda segura o event loop e TODA sessão paga os 700ms,
  // mesmo com o bridge respondendo em 1ms (medido: 82ms → 776ms).
  if (guarda) clearTimeout(guarda);

  // Só o estado medido. A instrução do que fazer com ele é a regra 14, e repeti-la
  // aqui custava ~330 B de duplicação em toda sessão — dentro de um orçamento em
  // que 330 B são uma regra inteira.
  const dependencias = `## Dependências de ambiente (regra 14)
Checado pelo hook: apontamento-horas ${pluginsStatus.apontamento}; bridge WhatsApp ${whatsappStatus.status} (${whatsappStatus.url}); claude-mem ${pluginsStatus.claudeMem}.`;

  const contexto = montarContexto({
    skillText: skill,
    focoText: foco,
    caminhoSkill: CAMINHO_SKILL,
    root: ROOT,
    sessoes,
    revisao,
    dependencias,
  });

  // JSON, não texto cru — e a diferença não é de estilo.
  //
  // Texto cru no stdout É a entrega: passando do limite do harness, ele grava tudo
  // num arquivo, injeta um preview de ~2 KB e sai com exit 0. Foi o que aconteceu
  // em 50 de 50 sessões até 2026-08-10 (medido: `medir-injecao.py --entrega`).
  // Com JSON, o harness lê `additionalContext` e o stdout ao redor não conta: no
  // mesmo transcript, 25 KB de stdout JSON entregaram 9,7 KB de contexto sem
  // truncamento nenhum, enquanto 32 KB de texto cru daqui viraram 2,2 KB.
  // Todos os outros hooks de SessionStart desta máquina já emitiam JSON; este era
  // o único de texto cru, e o único truncado.
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: contexto,
    },
  }));
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
