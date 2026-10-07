#!/usr/bin/env node
// @categoria: bateria
//
// Bateria de idioma-session-start: verifica injeção de idioma na compactação.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const os = require('os');

const SCRIPT = path.join(__dirname, 'idioma-session-start.cjs');

function mktemp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-test-'));
}

function rodaComPayload(payload, configObj) {
  const tmpdir = mktemp();
  try {
    // Cria a estrutura de projeto
    const rainforestDir = path.join(tmpdir, '.rainforest');
    fs.mkdirSync(rainforestDir, { recursive: true });

    // Grava o config se necessário
    if (configObj !== null) {
      fs.writeFileSync(
        path.join(rainforestDir, 'config.json'),
        JSON.stringify(configObj, null, 2)
      );
    }

    // Monta o payload
    const eventPayload = {
      session_id: 'test-session',
      hook_event_name: 'SessionStart',
      cwd: tmpdir,
      ...payload,
    };

    const input = JSON.stringify(eventPayload);
    const result = execSync(`node ${SCRIPT}`, {
      input,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    return { stdout: result, exit: 0 };
  } catch (e) {
    return {
      stdout: e.stdout ? e.stdout.toString() : '',
      exit: e.status || 1,
    };
  } finally {
    try {
      fs.rmSync(tmpdir, { recursive: true, force: true });
    } catch {}
  }
}

const casos = [
  {
    nome: 'source compact com idioma no config emite a linha',
    payload: { source: 'compact' },
    config: { idioma: 'português do Brasil' },
    expectExit: 0,
    expectEmit: true,
    expectText: 'Responda ao usuário em português do Brasil.',
  },
  {
    nome: 'source compact sem idioma no config sai silencioso',
    payload: { source: 'compact' },
    config: {},
    expectExit: 0,
    expectEmit: false,
  },
  {
    nome: 'source diferente de compact sai silencioso',
    payload: { source: 'standard' },
    config: { idioma: 'português do Brasil' },
    expectExit: 0,
    expectEmit: false,
  },
  {
    nome: 'idioma de 500 caracteres é recusado, sai silencioso',
    payload: { source: 'compact' },
    config: { idioma: 'a'.repeat(500) },
    expectExit: 0,
    expectEmit: false,
  },
  {
    nome: 'idioma vazio é recusado, sai silencioso',
    payload: { source: 'compact' },
    config: { idioma: '' },
    expectExit: 0,
    expectEmit: false,
  },
  {
    nome: 'idioma null é aceito como padrão, sai silencioso',
    payload: { source: 'compact' },
    config: { idioma: null },
    expectExit: 0,
    expectEmit: false,
  },
  {
    nome: 'saída com idioma curto nunca passa de 200 B',
    payload: { source: 'compact' },
    config: { idioma: 'en-US' },
    expectExit: 0,
    expectEmit: true,
    checkBytes: true,
  },
];

let ok = 0;
let falhou = 0;

for (const caso of casos) {
  const { stdout, exit } = rodaComPayload(caso.payload, caso.config);

  let passou = exit === caso.expectExit;
  let saida = '';

  if (stdout) {
    try {
      const json = JSON.parse(stdout);
      const emitiu = !!json.hookSpecificOutput?.additionalContext;

      if (emitiu !== caso.expectEmit) {
        passou = false;
        saida += `(emissão: esperado ${caso.expectEmit}, veio ${emitiu}) `;
      }

      // O harness descarta hookSpecificOutput sem hookEventName do evento.
      if (emitiu && json.hookSpecificOutput.hookEventName !== 'SessionStart') {
        passou = false;
        saida += `(hookEventName: esperado SessionStart, veio ${json.hookSpecificOutput.hookEventName}) `;
      }

      if (caso.expectEmit && caso.expectText && emitiu) {
        const texto = json.hookSpecificOutput.additionalContext;
        if (texto !== caso.expectText) {
          passou = false;
          saida += `(texto errado: esperado "${caso.expectText}", veio "${texto}") `;
        }
      }

      if (caso.checkBytes && emitiu) {
        const texto = json.hookSpecificOutput.additionalContext;
        const bytes = Buffer.byteLength(texto, 'utf8');
        if (bytes > 200) {
          passou = false;
          saida += `(${bytes} B > 200 B) `;
        }
      }
    } catch (e) {
      passou = false;
      saida += `(JSON inválido) `;
    }
  } else if (!stdout) {
    // Sem stdout: esperava emissão mas não veio
    if (caso.expectEmit) {
      passou = false;
      saida += `(esperava emissão mas veio silencioso) `;
    }
    // Se expectEmit é false, ok, esperava silêncio e veio
  }

  const statusCaso = passou ? 'ok' : 'FALHA';
  if (passou) {
    ok++;
  } else {
    falhou++;
  }

  console.log(`  ${statusCaso} ${caso.nome} ${saida}`);
  if (!passou && stdout) {
    console.log(`         stdout: ${stdout.slice(0, 100)}`);
  }
}

console.log(`== resultado: ${ok} ok, ${falhou} falha(s) ==`);
process.exit(falhou === 0 ? 0 : 1);
