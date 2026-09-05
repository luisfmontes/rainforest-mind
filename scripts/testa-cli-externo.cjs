#!/usr/bin/env node
/**
 * Bateria para cli-externo.cjs — transporte de CLI externo
 * Testa rodarCli e extrairJson contra fixtures.
 */

const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const { rodarCli, extrairJson } = require('../hooks/lib/cli-externo.cjs');

const SRC = path.join(__dirname, '..');
const FIXTURES = path.join(SRC, 'scripts', 'fixtures', 'cli-externo');
const FIXTURES_SEGUNDA_OPINIAO = path.join(SRC, 'scripts', 'fixtures', 'segunda-opiniao');
const CLI_EXTERNO_PATH = require.resolve('../hooks/lib/cli-externo.cjs');

let ok = 0;
let falhou = 0;

function testa(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`  ok   ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`  FALHA ${nome}`);
    console.log(`         ${e.message}`);
  }
}

console.log('==== Bateria: cli-externo ====\n');

// ---- Teste 1: rodarCli recusa sem timeoutMs ----
console.log('Teste 1: timeout obrigatório');
testa('recusa sem timeoutMs', () => {
  try {
    rodarCli({ cmd: 'echo ok', entrada: '' });
    throw new Error('Deveria ter lançado erro');
  } catch (e) {
    if (!e.message.includes('timeoutMs')) {
      throw new Error(`Mensagem de erro incorreta: ${e.message}`);
    }
  }
});

console.log('');

// ---- Teste 2: prompt-com-aspas-e-quebra-de-linha ----
console.log('Teste 2: prompt-com-aspas-e-quebra-de-linha');
const TEMP_DIR = fs.mkdtempSync(path.join(require('os').tmpdir(), 'test-'));
const PROMPT_FILE = path.join(TEMP_DIR, 'prompt.txt');
const EXPECTED = 'Olá, mundo!\nE uma "aspas" aqui.';
fs.writeFileSync(PROMPT_FILE, EXPECTED, 'utf8');

testa('eco exato do stdin', () => {
  const cmd = `node "${path.join(FIXTURES, 'prompt-com-aspas-e-quebra-de-linha.cjs')}"`;
  const resultado = rodarCli({
    cmd,
    entrada: EXPECTED,
    timeoutMs: 2000
  });

  if (resultado.stdout !== EXPECTED) {
    throw new Error(
      `Mismatch: entrada e stdout não batem\n` +
      `  Entrada: ${JSON.stringify(EXPECTED)}\n` +
      `  Stdout:  ${JSON.stringify(resultado.stdout)}`
    );
  }
  if (resultado.status !== 0) {
    throw new Error(`Exit code: ${resultado.status}`);
  }
});

console.log('');

// ---- Teste 3: cli-que-trava-e-cortado ----
console.log('Teste 3: cli-que-trava-e-cortado (timeout)');
testa('cortado por timeout', () => {
  const cmd = `node "${path.join(FIXTURES, 'cli-que-trava-e-cortado.cjs')}"`;
  const inicio = Date.now();
  const resultado = rodarCli({
    cmd,
    entrada: '',
    timeoutMs: 1500
  });
  const duracao = Date.now() - inicio;

  // Deve ter sido cortado (status é null quando killed ou saída vazia).
  // Teto folgado: rodarCli agora paga matarDescendencia no ramo de timeout,
  // que no Windows soma 1-2 chamadas a powershell.exe (~1-1.5s cada) para
  // consultar e matar a descendência. O teto de 8s ainda distingue "cortado"
  // de "dormiu a fixture inteira" — a fixture dorme 60s, não 10s: subiu junto
  // com este teto, porque 8s contra 10s deixava só 2s de margem.
  if (duracao >= 8000) {
    throw new Error(`Não foi cortado: duração ${duracao}ms >= 8000ms`);
  }
});

console.log('');

// ---- Teste 4: json-cercado-por-crase ----
console.log('Teste 4: json-cercado-por-crase');
testa('extrai JSON dentro de crases', () => {
  const cmd = `node "${path.join(FIXTURES, 'json-cercado-por-crase.cjs')}"`;
  const resultado = rodarCli({
    cmd,
    entrada: 'prompt qualquer',
    timeoutMs: 2000
  });

  if (resultado.status !== 0) {
    throw new Error(`Exit code ${resultado.status}, stdout: ${resultado.stdout}`);
  }

  const obj = extrairJson(resultado.stdout);
  if (!obj || obj.opinion !== 'válida' || obj.detalhes !== 'JSON cercado por crase') {
    throw new Error(
      `JSON não extraído ou inválido\n` +
      `  Stdout: ${JSON.stringify(resultado.stdout)}\n` +
      `  Objeto: ${JSON.stringify(obj)}`
    );
  }
});

console.log('');

// ---- Teste 5: extrairJson retorna null em JSON inválido ----
console.log('Teste 5: extrairJson com JSON inválido');
testa('retorna null em JSON inválido', () => {
  const result = extrairJson('isso não é json {{{');
  if (result !== null) {
    throw new Error(`Esperava null, recebeu: ${JSON.stringify(result)}`);
  }
});

console.log('');

// ---- Teste 6: extrairJson com stdout vazio ----
console.log('Teste 6: extrairJson com stdout vazio');
testa('retorna null com stdout vazio', () => {
  const result = extrairJson('');
  if (result !== null) {
    throw new Error(`Esperava null, recebeu: ${JSON.stringify(result)}`);
  }
});

console.log('');

// ---- Teste 7: rodarCli propaga exit code ----
console.log('Teste 7: rodarCli propaga exit code');
testa('propagando exit ≠ 0', () => {
  const resultado = rodarCli({
    cmd: 'exit 42',
    entrada: '',
    timeoutMs: 1000
  });

  if (resultado.status !== 42) {
    throw new Error(`Status esperado 42, recebido: ${resultado.status}`);
  }
});

console.log('');

// ---- Teste 8: extrairJson com JSON simples {...} ----
console.log('Teste 8: extrairJson com JSON simples {...}');
testa('extrai JSON simples {...}', () => {
  const stdout = 'Texto com {"key": "value"} no meio';
  const obj = extrairJson(stdout);
  if (!obj || obj.key !== 'value') {
    throw new Error(`JSON simples não extraído: ${JSON.stringify(obj)}`);
  }
});

console.log('');

// ---- Teste 9: fallback-array-toplevel (exercita fallback do extrairJson) ----
console.log('Teste 9: extrairJson com array top-level (fallback)');
testa('extrai array JSON válido (exercita fallback)', () => {
  // Array top-level puro: não tem "{" (segunda regex não casa)
  // e não tem ```json``` (primeira regex não casa)
  // Portanto só o fallback (const json = match ? match[1] : stdout) consegue parseá-lo
  const stdout = '[1, 2, 3, 4, 5]';
  const obj = extrairJson(stdout);
  if (!Array.isArray(obj) || obj.length !== 5 || obj[0] !== 1) {
    throw new Error(
      `Array JSON não extraído via fallback: ${JSON.stringify(obj)}\n` +
      `  Esperava: [1, 2, 3, 4, 5]`
    );
  }
});

console.log('');

// ---- Teste 10: timeout nao deixa descendente vivo ----
// O timeout do spawnSync mata só o filho direto (cmd.exe/sh) — nunca o neto
// que executa de verdade. Prova que matarDescendencia (chamada dentro de
// rodarCli, no ramo de timeout) limpa a árvore inteira.
//
// Descobre o PID do filho direto interceptando child_process.spawnSync (o
// mesmo mecanismo interno de rodarCli) e recarregando o módulo com o cache
// limpo, para capturar o .pid que o spawnSync devolveu — sem alterar a
// assinatura pública de rodarCli. A consulta de descendência é por
// ParentProcessId desse PID; nunca por nome de executável ou string de
// comando (o utilitário ps do Git Bash com a flag de listagem estendida do
// Windows não imprime a coluna de comando — filtrar por ali daria falso-negativo).
console.log('Teste 10: timeout nao deixa descendente vivo');

/**
 * Lista, recursivamente, todo PID descendente vivo de `pidRaiz` — só por
 * ParentProcessId, nunca por nome de executável ou linha de comando.
 */
function listarDescendentesVivos(pidRaiz) {
  const filhosDiretos = (pid) => {
    if (process.platform === 'win32') {
      const r = cp.spawnSync(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          `Get-CimInstance Win32_Process -Filter "ParentProcessId=${pid}" | Select-Object -ExpandProperty ProcessId`,
        ],
        { encoding: 'utf8' }
      );
      if (!r || r.status !== 0 || !r.stdout) return [];
      return r.stdout
        .split('\n')
        .map((l) => l.trim())
        .filter(Boolean)
        .map(Number);
    }
    const r = cp.spawnSync('ps', ['-o', 'pid=', '--ppid', String(pid)], { encoding: 'utf8' });
    if (!r || r.status !== 0 || !r.stdout) return [];
    return r.stdout
      .split('\n')
      .map((l) => l.trim())
      .filter(Boolean)
      .map(Number);
  };

  const vivos = [];
  const fila = [pidRaiz];
  while (fila.length > 0) {
    const atual = fila.shift();
    for (const filho of filhosDiretos(atual)) {
      vivos.push(filho);
      fila.push(filho);
    }
  }
  return vivos;
}

/** Sono síncrono cross-platform — para dar tempo do SO atualizar a tabela de processos. */
function dormirSincrono(ms) {
  if (process.platform === 'win32') {
    cp.spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', `Start-Sleep -Milliseconds ${ms}`]);
  } else {
    cp.spawnSync('sleep', [String(ms / 1000)]);
  }
}

testa('timeout nao deixa descendente vivo', () => {
  // Intercepta child_process.spawnSync para capturar o PID do filho direto
  // que rodarCli cria — sem mudar a assinatura/retorno público de rodarCli.
  const spawnSyncOriginal = cp.spawnSync;
  let pidCriado = null;
  cp.spawnSync = function interceptado(...args) {
    const r = spawnSyncOriginal.apply(this, args);
    if (pidCriado === null && r && typeof r.pid === 'number') {
      pidCriado = r.pid;
    }
    return r;
  };

  delete require.cache[CLI_EXTERNO_PATH];
  const { rodarCli: rodarCliInterceptado } = require(CLI_EXTERNO_PATH);

  let resultado;
  try {
    const cmd = `node "${path.join(FIXTURES_SEGUNDA_OPINIAO, 'externo-indisponivel-timeout.cjs')}"`;
    resultado = rodarCliInterceptado({ cmd, entrada: '', timeoutMs: 800 });
  } finally {
    cp.spawnSync = spawnSyncOriginal;
    delete require.cache[CLI_EXTERNO_PATH];
  }

  if (resultado.status !== null) {
    throw new Error(`Esperava status null (timeout), recebeu: ${resultado.status}`);
  }
  if (pidCriado === null) {
    throw new Error('Não foi possível capturar o PID do filho direto criado por rodarCli');
  }

  dormirSincrono(2000);

  const sobreviventes = listarDescendentesVivos(pidCriado);
  if (sobreviventes.length > 0) {
    throw new Error(
      `Descendente(s) sobreviveram ao timeout: PID(s) ${sobreviventes.join(', ')} ` +
      `(raiz PID ${pidCriado})`
    );
  }
});

console.log('');

// ---- Cleanup ----
fs.rmSync(TEMP_DIR, { recursive: true, force: true });

// ---- Resumo ----
const total = ok + falhou;
console.log('==== Resultado ====');
console.log(`ok: ${ok}`);
console.log(`falhou: ${falhou}`);
console.log(`total: ${total}`);

if (falhou > 0) {
  console.log('');
  console.log(`Vermelhas: [${falhou}]`);
  process.exit(1);
} else {
  process.exit(0);
}
