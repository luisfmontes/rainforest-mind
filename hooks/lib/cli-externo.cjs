/**
 * Transporte de CLI externo — spawn com stdin, timeout, e extração de JSON
 *
 * Fatos pagos:
 * - Stdin explícito evita quebra com aspas/quebras de linha no cmd.exe
 * - stdin fechado após escrita evita travamento conhecido do codex exec
 * - windowsVerbatimArguments obrigatório no Windows
 * - timeout obrigatório — sem teto abre pendência
 * - o timeout do spawnSync mata só o filho direto (cmd.exe/sh); o neto que
 *   executa de verdade fica órfão vivo para sempre — matarDescendencia varre
 *   a árvore do PID e mata quem sobrou, só no ramo de timeout
 *
 * Exporta:
 * - rodarCli({ cmd, entrada, timeoutMs, env }) → { status, stdout, stderr }
 * - extrairJson(stdout) → objeto ou null
 * - matarDescendencia(pid, nascidoDepoisDe) → void (nunca lança)
 */

const { spawnSync } = require('child_process');

/**
 * Executa comando externo com stdin e timeout.
 *
 * @param {Object} opts - Opções
 * @param {string} opts.cmd - Comando a executar (ex: 'codex exec -s read-only')
 * @param {string} opts.entrada - Conteúdo para stdin
 * @param {number} opts.timeoutMs - Timeout em ms (obrigatório — sem ele a função recusa)
 * @param {Object} [opts.env] - Variáveis de ambiente (default: process.env)
 * @returns {Object} { status, stdout, stderr }
 * @throws se timeoutMs não for fornecido
 */
function rodarCli(opts) {
  const { cmd, entrada, timeoutMs, env } = opts;

  if (typeof timeoutMs !== 'number' || timeoutMs <= 0) {
    throw new Error('rodarCli: timeoutMs obrigatório e deve ser > 0');
  }

  const isWindows = process.platform === 'win32';
  const spawnArgs = isWindows
    ? ['cmd.exe', ['/d', '/s', '/c', `"${cmd}"`]]
    : ['sh', ['-c', cmd]];

  const nascidoDepoisDe = Date.now();

  const resultado = spawnSync(spawnArgs[0], spawnArgs[1], {
    encoding: 'utf8',
    input: entrada,
    env: env || process.env,
    windowsVerbatimArguments: isWindows,
    timeout: timeoutMs,
  });

  if (resultado.status === null) {
    matarDescendencia(resultado.pid, nascidoDepoisDe);
  }

  return {
    status: resultado.status,
    stdout: resultado.stdout || '',
    stderr: resultado.stderr || '',
  };
}

/**
 * Mata toda a descendência viva de um PID, recursivamente, para conter o
 * órfão que o timeout do spawnSync deixa (mata o filho direto, nunca o
 * neto). Nunca mata por nome de processo, caminho de executável, string de
 * comando ou porta — só por PID descendente do PID recebido, e só quem foi
 * criado depois de `nascidoDepoisDe` (guarda contra reuso de PID pelo SO).
 *
 * Custo pago só quando chamada: nenhuma consulta de processo acontece no
 * caminho feliz do rodarCli. Nunca lança — falha ao consultar ou ao matar é
 * engolida, porque o timeout já é o erro que interessa.
 *
 * @param {number} pid - PID do processo raiz (o filho direto que o spawnSync devolveu em .pid)
 * @param {number|Date} nascidoDepoisDe - instante (epoch ms ou Date) em que a chamada de rodarCli começou
 */
function matarDescendencia(pid, nascidoDepoisDe) {
  try {
    if (typeof pid !== 'number' || !Number.isFinite(pid) || pid <= 0) {
      return;
    }
    const marco =
      nascidoDepoisDe instanceof Date ? nascidoDepoisDe.getTime() : Number(nascidoDepoisDe);
    if (!Number.isFinite(marco)) {
      return;
    }

    if (process.platform === 'win32') {
      matarDescendenciaWindows(pid, marco);
    } else {
      matarDescendenciaPosix(pid, marco);
    }
  } catch (e) {
    // engolido de propósito — matarDescendencia nunca pode derrubar rodarCli
  }
}

/**
 * Extrai o epoch ms de uma data no formato CIM ("/Date(<ms-desde-epoch>)/",
 * ex.: a serialização de Get-CimInstance | ConvertTo-Json para CreationDate).
 * @param {string} valor
 * @returns {number|null}
 */
function parseDataCim(valor) {
  if (typeof valor !== 'string') return null;
  const m = valor.match(/\/Date\((\d+)\)\//);
  return m ? Number(m[1]) : null;
}

/**
 * Ramo Windows: consulta Win32_Process via CIM (PowerShell), desce a árvore
 * a partir de `pidRaiz` filtrando por data de criação (guarda de reuso de
 * PID), e mata os descendentes achados com Stop-Process -Force.
 */
function matarDescendenciaWindows(pidRaiz, marco) {
  const consulta = spawnSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CreationDate | ConvertTo-Json -Compress',
    ],
    { encoding: 'utf8', timeout: 5000 }
  );

  if (!consulta || consulta.status !== 0 || !consulta.stdout) {
    return;
  }

  let processos;
  try {
    processos = JSON.parse(consulta.stdout);
  } catch (e) {
    return;
  }
  if (!Array.isArray(processos)) {
    processos = [processos];
  }

  const filhosPorPai = new Map();
  for (const p of processos) {
    if (!p || typeof p.ProcessId !== 'number' || typeof p.ParentProcessId !== 'number') {
      continue;
    }
    const lista = filhosPorPai.get(p.ParentProcessId) || [];
    lista.push({ pid: p.ProcessId, criadoEm: parseDataCim(p.CreationDate) });
    filhosPorPai.set(p.ParentProcessId, lista);
  }

  const alvos = [];
  const fila = [pidRaiz];
  while (fila.length > 0) {
    const atual = fila.shift();
    const filhos = filhosPorPai.get(atual) || [];
    for (const filho of filhos) {
      // guarda de reuso de PID: só desce/mata quem nasceu depois do início da chamada
      if (filho.criadoEm !== null && filho.criadoEm > marco) {
        alvos.push(filho.pid);
        fila.push(filho.pid);
      }
    }
  }

  if (alvos.length === 0) {
    return;
  }

  spawnSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      `Stop-Process -Id ${alvos.join(',')} -Force -ErrorAction SilentlyContinue`,
    ],
    { encoding: 'utf8', timeout: 5000 }
  );
}

/**
 * Ramo POSIX: descobre filhos diretos com `ps --ppid`, mata quem nasceu
 * depois de `marco` (guarda de reuso de PID via etimes) com process.kill, e
 * desce recursivamente só nos ramos validados.
 */
function matarDescendenciaPosix(pidRaiz, marco) {
  const filhos = obterFilhosPosix(pidRaiz);
  for (const filho of filhos) {
    if (filho.criadoEm === null || filho.criadoEm <= marco) {
      continue;
    }
    try {
      process.kill(filho.pid, 'SIGKILL');
    } catch (e) {
      // processo já pode ter saído sozinho — segue
    }
    matarDescendenciaPosix(filho.pid, marco);
  }
}

/**
 * @param {number} pid
 * @returns {Array<{pid: number, criadoEm: number|null}>}
 */
function obterFilhosPosix(pid) {
  const r = spawnSync('ps', ['-o', 'pid=,etimes=', '--ppid', String(pid)], {
    encoding: 'utf8',
    timeout: 5000,
  });
  if (!r || r.status !== 0 || !r.stdout) {
    return [];
  }
  const agora = Date.now();
  return r.stdout
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => {
      const partes = l.split(/\s+/);
      const cpid = Number(partes[0]);
      const etimes = Number(partes[1]);
      const criadoEm = Number.isFinite(etimes) ? agora - etimes * 1000 : null;
      return { pid: cpid, criadoEm };
    })
    .filter((p) => Number.isFinite(p.pid));
}

/**
 * Extrai JSON do stdout de um CLI externo.
 * Tenta três abordagens em cascata:
 * 1. Regex com cerca: ```json ... ``` (CLI output com markdown)
 * 2. Regex simples: {...} (JSON com object literal)
 * 3. Fallback: stdout cru (JSON puro sem marcação — arrays top-level, etc)
 *
 * Caso de uso do fallback: alguns CLIs retornam JSON puro sem markdown,
 * incluindo arrays top-level ([...]) que não casam com as regex anteriores.
 * Exemplo: CLI que emite "[1,2,3]" direto sem cerca ou wrapper de objeto.
 *
 * @param {string} stdout - Conteúdo para buscar JSON
 * @returns {Object|null} Objeto parseado ou null se não conseguir
 */
function extrairJson(stdout) {
  try {
    // Primeira regex: ```json ... ```
    let match = stdout.match(/```json\s*([\s\S]*?)\s*```/);
    // Segunda regex: {...}
    if (!match) {
      match = stdout.match(/({[\s\S]*})/);
    }

    // Fallback: tenta stdout cru se nenhuma regex casou
    // Rescata CLIs que retornam JSON puro (arrays top-level, etc)
    const json = match ? match[1] : stdout;
    return JSON.parse(json);
  } catch (e) {
    return null;
  }
}

module.exports = { rodarCli, extrairJson, matarDescendencia };
