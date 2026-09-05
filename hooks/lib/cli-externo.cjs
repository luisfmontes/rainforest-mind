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

  // `status === null` é o timeout, mas não SÓ o timeout: qualquer término por
  // sinal cai aqui (um cmd.exe abatido por outro motivo, por exemplo). É o
  // gatilho certo mesmo assim — em todos esses casos o filho direto morreu sem
  // levar a descendência junto, que é exatamente o que se quer limpar. O que
  // não vale é chamar isto de "ramo de timeout" e alguém acreditar.
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
 *
 * DUAS guardas de reuso, não uma. A primeira versão só filtrava os
 * DESCENDENTES por data de criação, e duas revisões independentes acharam o
 * mesmo buraco: ninguém conferia o `pidRaiz`. Quando `matarDescendencia` roda,
 * o `cmd.exe` já morreu — é por isso que o PID dele vira candidato a reuso — e
 * a consulta CIM custa ~1s. Nessa janela o Windows pode reatribuir aquele PID a
 * um processo alheio; qualquer filho que ESSE processo criar nasce, por
 * definição, depois de `marco`, passa pela guarda de data e é morto. Máquina
 * com várias sessões abertas é exatamente o cenário da regra 15.
 *
 * A guarda que fecha isso está em `raizConfiavel()`: o `pidRaiz` AUSENTE da
 * tabela prova que ninguém o reusou até o instante do snapshot, e então os
 * filhos com aquele `ParentProcessId` só podem ser os órfãos legítimos. Ver o
 * comentário da função para os outros dois estados.
 */
function matarDescendenciaWindows(pidRaiz, marco) {
  const consulta = spawnSync(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CreationDate,Name | ConvertTo-Json -Compress',
    ],
    { encoding: 'utf8', timeout: 5000 }
  );

  if (!consulta || consulta.status !== 0 || !consulta.stdout) {
    // Falhar aqui não é inofensivo: o órfão que esta função existe para matar
    // continua vivo, e sem esta linha ninguém saberia. Não lança — só avisa.
    avisar(`nao consegui consultar a tabela de processos; pode ter sobrado orfao do PID ${pidRaiz}`);
    return;
  }

  let processos;
  try {
    processos = JSON.parse(consulta.stdout);
  } catch (e) {
    avisar(`saida da consulta de processos ilegivel; pode ter sobrado orfao do PID ${pidRaiz}`);
    return;
  }
  if (!Array.isArray(processos)) {
    processos = [processos];
  }

  const filhosPorPai = new Map();
  const porPid = new Map();
  for (const p of processos) {
    if (!p || typeof p.ProcessId !== 'number' || typeof p.ParentProcessId !== 'number') {
      continue;
    }
    const entrada = {
      pid: p.ProcessId,
      criadoEm: parseDataCim(p.CreationDate),
      nome: typeof p.Name === 'string' ? p.Name.toLowerCase() : null,
    };
    porPid.set(p.ProcessId, entrada);
    const lista = filhosPorPai.get(p.ParentProcessId) || [];
    lista.push(entrada);
    filhosPorPai.set(p.ParentProcessId, lista);
  }

  if (!raizConfiavel(porPid.get(pidRaiz), 'cmd.exe')) {
    avisar(
      `PID ${pidRaiz} foi reusado por outro processo; nao vou matar descendencia que pode nao ser minha`
    );
    return;
  }

  const alvos = [];
  const visitados = new Set([pidRaiz]);
  const fila = [pidRaiz];
  while (fila.length > 0) {
    const atual = fila.shift();
    const filhos = filhosPorPai.get(atual) || [];
    for (const filho of filhos) {
      // guarda de reuso de PID: só desce/mata quem nasceu depois do início da chamada
      if (filho.criadoEm === null || filho.criadoEm <= marco) continue;
      // `visitados` não é defesa contra ciclo (a tabela de processos não tem um
      // num único snapshot) — é contra linha duplicada do provider WMI, que
      // reprocessaria a mesma subárvore e repetiria PID na lista de alvos.
      if (visitados.has(filho.pid)) continue;
      visitados.add(filho.pid);
      alvos.push(filho.pid);
      fila.push(filho.pid);
    }
  }

  if (alvos.length === 0) {
    return;
  }

  // Reconfere a data de criação DENTRO do PowerShell, imediatamente antes de
  // matar. Entre o snapshot acima e este comando passa mais um startup de
  // powershell.exe, e nessa janela um dos PIDs-alvo também pode ter sido
  // reciclado. Reconferir aqui fecha o resto da corrida: o alvo só morre se
  // ainda for um processo nascido depois do início desta chamada.
  const script =
    `$marco=[datetime]::new(1970,1,1,0,0,0,'Utc').AddMilliseconds(${marco});` +
    `foreach($id in @(${alvos.join(',')})){` +
    `$p=Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue;` +
    `if($p -and $p.CreationDate.ToUniversalTime() -gt $marco){` +
    `Stop-Process -Id $id -Force -ErrorAction SilentlyContinue}}`;

  spawnSync(
    'powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', script],
    { encoding: 'utf8', timeout: 5000 }
  );
}

/**
 * O `pidRaiz` ainda é o processo que esta chamada criou?
 *
 * Três estados, e só dois autorizam descer a árvore:
 *
 * - **ausente da tabela** (`undefined`): é o caso normal e o mais forte. O
 *   `spawnSync` matou o `cmd.exe`/`sh` no timeout e ninguém ocupou o PID até o
 *   snapshot. Se ninguém o ocupou, todo processo que carrega aquele
 *   `ParentProcessId` só pode ser filho do processo original — órfão legítimo.
 * - **presente com o nome esperado**: o filho direto não morreu (ou morreu e o
 *   PID foi reusado por outro `cmd.exe`, que é o resíduo aceito aqui). Descer é
 *   o comportamento certo nos dois casos.
 * - **presente com outro nome**: o PID foi reciclado por um processo alheio.
 *   Aborta — a descendência que se veria é dele, não nossa.
 */
function raizConfiavel(entradaRaiz, nomeEsperado) {
  if (!entradaRaiz) return true;
  if (entradaRaiz.nome === null) return false;
  return entradaRaiz.nome === nomeEsperado;
}

/** Aviso de limpeza que não deu certo. Nunca lança, nunca vira exceção. */
function avisar(mensagem) {
  try {
    process.stderr.write(`[cli-externo] ${mensagem}\n`);
  } catch (e) {
    // nem o aviso pode derrubar o rodarCli
  }
}

/**
 * Ramo POSIX: descobre filhos diretos com `ps --ppid`, mata quem nasceu
 * depois de `marco` (guarda de reuso de PID via etimes) com process.kill, e
 * desce recursivamente só nos ramos validados.
 *
 * Mesma guarda de raiz do ramo Windows, e pelo mesmo motivo: o `sh` já morreu
 * quando isto roda, então o PID dele é candidato a reuso. Aqui a janela é bem
 * menor (um `ps` custa muito menos que subir um `powershell.exe`), mas a
 * lacuna de desenho é idêntica, e fechá-la custa uma chamada.
 *
 * Só a raiz é conferida por nome — nos níveis abaixo, o ancestral vivo e
 * verificado já garante a linhagem, e é a guarda de `etimes` que cobre o resto.
 *
 * Portabilidade: `--ppid` e `etimes` são sintaxe GNU/procps. Em BSD e macOS o
 * `ps` recusa, `spawnSync` volta com status ≠ 0, e a função degrada para o lado
 * seguro — não acha ninguém, não mata ninguém, não lança. Nenhum teste desta
 * entrega exercita este ramo: a bateria roda no Windows, e só o ramo de
 * `process.platform` da máquina dispara. Está anotado no PR como lacuna.
 */
function matarDescendenciaPosix(pidRaiz, marco, ehRaiz = true) {
  if (ehRaiz && !raizConfiavelPosix(pidRaiz)) {
    avisar(
      `PID ${pidRaiz} foi reusado por outro processo; nao vou matar descendencia que pode nao ser minha`
    );
    return;
  }
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
    matarDescendenciaPosix(filho.pid, marco, false);
  }
}

/**
 * Espelho POSIX do `raizConfiavel`: o PID raiz sumiu (ninguém o reusou até
 * aqui) ou ainda é o shell que este módulo criou? Qualquer outro comando
 * naquele PID significa reuso, e aborta.
 */
function raizConfiavelPosix(pidRaiz) {
  const r = spawnSync('ps', ['-o', 'comm=', '-p', String(pidRaiz)], {
    encoding: 'utf8',
    timeout: 5000,
  });
  // status ≠ 0 é o `ps` dizendo que o PID não existe: raiz morta, sem reuso.
  if (!r || r.status !== 0) return true;
  const comm = (r.stdout || '').trim();
  if (!comm) return true;
  return comm === 'sh' || comm.endsWith('/sh');
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
