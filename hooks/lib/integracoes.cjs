/**
 * Registro de integrações opcionais do rainforest.
 *
 * Cada integração é um repositório próprio do usuário, com ciclo de release
 * próprio. Declarável via `--ligar integracao-<nome>` no setup, desligada por
 * padrão. O `/saude` confere só o que foi declarado, uma linha cada.
 */

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { ler: lerProjetos } = require('./projetos.cjs');
const { resolverRaiz } = require('./raiz.cjs');

function checarWhatsAppMcp(env = process.env) {
  return new Promise((resolve) => {
    let url = env.WHATSAPP_API_BASE_URL || 'http://127.0.0.1:3005/api';

    try {
      const urlObj = new URL(url);
      const protocol = urlObj.protocol === 'https:' ? https : http;
      const timeoutMs = 2000;

      const req = protocol.get(url, { timeout: timeoutMs }, (res) => {
        // Qualquer resposta HTTP = ok
        resolve({ ok: true, detalhe: `respondeu com status ${res.statusCode}` });
        req.abort();
      });

      req.on('timeout', () => {
        req.destroy();
        resolve({
          ok: false,
          acao: 'suba a bridge no repositório local do whatsapp-mcp (binário Go de whatsapp-bridge/, ou o serviço configurado)',
        });
      });

      req.on('error', () => {
        resolve({
          ok: false,
          acao: 'suba a bridge no repositório local do whatsapp-mcp (binário Go de whatsapp-bridge/, ou o serviço configurado)',
        });
      });
    } catch (e) {
      resolve({
        ok: false,
        acao: 'suba a bridge no repositório local do whatsapp-mcp (binário Go de whatsapp-bridge/, ou o serviço configurado)',
      });
    }
  });
}

function checarSabia(env = process.env) {
  let raiz;
  try {
    raiz = resolverRaiz({ env }).raiz;
  } catch {
    raiz = null;
  }

  const mapa = raiz ? lerProjetos(raiz) : null;

  if (!mapa || !mapa.sabia) {
    return {
      ok: false,
      acao: 'registre o projeto: node scripts/ideias.cjs projetos --registrar sabia --caminho <dir>',
    };
  }

  const caminho = mapa.sabia.caminho;
  if (!caminho) {
    return {
      ok: false,
      acao: 'registre o projeto: node scripts/ideias.cjs projetos --registrar sabia --caminho <dir>',
    };
  }

  // Verifica se sabia.py e .venv/ existem
  const sabiaFile = path.join(caminho, 'sabia.py');
  const venvDir = path.join(caminho, '.venv');

  try {
    const sabiaExists = fs.existsSync(sabiaFile);
    const venvExists = fs.existsSync(venvDir);

    if (sabiaExists && venvExists) {
      return { ok: true, detalhe: 'presente' };
    }

    if (!venvExists) {
      return {
        ok: false,
        acao: 'python -m venv .venv && .venv/Scripts/pip install -r requirements.txt (e rode sabia.py doutor)',
      };
    }

    return {
      ok: false,
      acao: 'sabia.py ou .venv não encontrados no caminho registrado',
    };
  } catch {
    return {
      ok: false,
      acao: 'python -m venv .venv && .venv/Scripts/pip install -r requirements.txt (e rode sabia.py doutor)',
    };
  }
}

const INTEGRACOES = {
  'whatsapp-mcp': {
    descricao: 'MCP para bridge WhatsApp local (127.0.0.1:3005)',
    checar: checarWhatsAppMcp,
  },
  sabia: {
    descricao: 'Sabiá: transcrição local de reunião com diarização (quem falou), CLI Python',
    checar: checarSabia,
  },
};

module.exports = { INTEGRACOES };
