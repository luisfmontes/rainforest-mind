#!/usr/bin/env node
/**
 * Checagem de arme da skill vigiar: verifica se a integração está ligada,
 * se a bridge da conta está acessível, e resolve os caminhos necessários.
 *
 * Uso:
 *   node scripts/vigiar-checar.cjs --conta <alias>
 *
 * Exit:
 *   0  tudo certo → stdout JSON de uma linha
 *   2  algo falta ou está errado → stderr uma linha explicando
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');
const { ligado } = require('../hooks/lib/config.cjs');

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return i >= 0 ? process.argv[i + 1] : null;
}

const projetoDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const conta = arg('conta');

if (!conta) {
  console.error('erro: --conta é obrigatório');
  process.exit(2);
}

// ============================================================================
// 1. Verificar se a integração está ligada
// ============================================================================

if (!ligado('integracao-whatsapp-mcp', { projeto: projetoDir })) {
  console.error('integração WhatsApp não ligada: rode /rainforest-mind:setup --ligar integracao-whatsapp-mcp --escopo usuario');
  process.exit(2);
}

// ============================================================================
// 2. Ler accounts.json
// ============================================================================

const accountsFile = process.env.WHATSAPP_ACCOUNTS_FILE || path.join(os.homedir(), '.whatsapp-mcp', 'accounts.json');

let accounts = null;
try {
  const accountsJson = fs.readFileSync(accountsFile, 'utf8');
  const parsed = JSON.parse(accountsJson);
  // Extrair as contas do formato real: { accounts: { pessoal: {...}, trabalho: {...} } }
  accounts = parsed.accounts || parsed;
} catch (err) {
  console.error(`arquivo de contas não encontrado ou inválido: ${accountsFile}`);
  process.exit(2);
}

if (!accounts || typeof accounts !== 'object' || Object.keys(accounts).length === 0) {
  console.error('nenhuma conta configurada');
  process.exit(2);
}

if (!(conta in accounts)) {
  const contasDisponiveis = Object.keys(accounts).join(', ');
  console.error(`conta "${conta}" não existe; contas disponíveis: ${contasDisponiveis}`);
  process.exit(2);
}

const accountConfig = accounts[conta];
const port = accountConfig.port;
const dir = accountConfig.dir;

// ============================================================================
// 3. Verificar bridge da conta via GET /api/status
// ============================================================================

function verificarBridge() {
  return new Promise((resolve) => {
    const statusUrl = `http://127.0.0.1:${port}/api/status`;
    const req = http.get(statusUrl, { timeout: 3000 }, (res) => {
      let dados = '';
      res.on('data', (chunk) => { dados += chunk; });
      res.on('end', () => {
        try {
          if (res.statusCode === 200) {
            const json = JSON.parse(dados);
            if (json.healthy === true) {
              resolve({ ok: true });
            } else {
              resolve({ ok: false, motivo: 'desconectada' });
            }
          } else {
            resolve({ ok: false, motivo: `status HTTP ${res.statusCode}` });
          }
        } catch {
          resolve({ ok: false, motivo: 'JSON inválido' });
        }
      });
    });

    req.on('error', (err) => {
      if (err.code === 'ECONNREFUSED') {
        resolve({ ok: false, motivo: 'porta recusada' });
      } else {
        resolve({ ok: false, motivo: err.message });
      }
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({ ok: false, motivo: 'timeout' });
    });
  });
}

verificarBridge().then((resultado) => {
  if (!resultado.ok) {
    console.error(`bridge "${conta}" (porta ${port}) fora do ar: ${resultado.motivo}`);
    process.exit(2);
  }

  // ========================================================================
  // 4. Verificar caminhos e arquivo de script
  // ========================================================================

  const whatsappMcpDir = process.env.WHATSAPP_MCP_DIR || 'C:/Projetos/whatsapp-mcp';
  const script = path.join(whatsappMcpDir, 'scripts', 'watch_chat.py');
  const vigiarMd = path.join(whatsappMcpDir, 'commands', 'vigiar.md');

  if (!fs.existsSync(script)) {
    console.error(`script não encontrado: ${script}`);
    process.exit(2);
  }

  // ========================================================================
  // 5. Tudo certo: devolver JSON com a configuração
  // ========================================================================

  const db = path.join(dir, 'store', 'messages.db');
  const statusUrl = `http://127.0.0.1:${port}/api/status`;

  const saida = {
    conta,
    porta: port,
    status_url: statusUrl,
    script,
    vigiar_md: vigiarMd,
    db,
  };

  console.log(JSON.stringify(saida));
  process.exit(0);
});
