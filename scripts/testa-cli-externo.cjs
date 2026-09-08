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
let pulado = 0;

/**
 * Sinaliza "não deu para MEDIR", que é diferente de "o código errou".
 *
 * Nasceu em 2026-09-08, de um vermelho de CI que não era regressão: no runner
 * Windows a consulta `Get-CimInstance Win32_Process` falhou, o
 * `matarDescendencia` avisou que não conseguiu consultar a tabela de processos
 * e voltou sem matar nada — e o teste 10, que afirma "timeout não deixa
 * descendente vivo", viu o descendente vivo e gritou FALHA. O código estava
 * certo: ele não matou porque não teve como enxergar.
 *
 * Chamar isso de falha é o defeito que este acervo persegue em todo lugar — o
 * instrumento respondendo quando não mediu. A mesma bateria passava 11/11 na
 * máquina do Luís no mesmo commit, e o custo do engano foi um rerun de 20
 * minutos de CI e a suspeita sobre um diff que não tinha nada a ver.
 *
 * PULADO é ruidoso de propósito: sai na tela, entra no total e aparece no
 * resumo. Silencioso, viraria a próxima forma de verde que não prova nada.
 */
class NaoDeuParaMedir extends Error {}

function testa(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`  ok   ${nome}`);
  } catch (e) {
    if (e instanceof NaoDeuParaMedir) {
      pulado++;
      console.log(`  PULADO ${nome}`);
      console.log(`         ${e.message}`);
      return;
    }
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

  // O `matarDescendencia` avisa por stderr quando NAO consegue enxergar a
  // tabela de processos. Esse aviso é a diferença entre "não matou porque
  // errou" e "não matou porque não teve como olhar" — e sem capturá-lo aqui,
  // os dois chegam ao assert idênticos. Ver `NaoDeuParaMedir`, no topo.
  const stderrOriginal = process.stderr.write.bind(process.stderr);
  let stderrCapturado = '';
  process.stderr.write = (chunk, ...resto) => {
    stderrCapturado += String(chunk);
    return stderrOriginal(chunk, ...resto);
  };

  let resultado;
  try {
    const cmd = `node "${path.join(FIXTURES_SEGUNDA_OPINIAO, 'externo-indisponivel-timeout.cjs')}"`;
    resultado = rodarCliInterceptado({ cmd, entrada: '', timeoutMs: 800 });
  } finally {
    process.stderr.write = stderrOriginal;
    cp.spawnSync = spawnSyncOriginal;
    delete require.cache[CLI_EXTERNO_PATH];
  }

  const NAO_ENXERGOU = [
    'nao consegui consultar a tabela de processos',
    'saida da consulta de processos ilegivel',
  ];
  const cego = NAO_ENXERGOU.find((marca) => stderrCapturado.includes(marca));
  if (cego) {
    throw new NaoDeuParaMedir(
      `matarDescendencia nao conseguiu enxergar a tabela de processos ("${cego}"), ` +
      `entao a limpeza nunca teve chance de rodar. Descendente vivo aqui mede o ambiente, ` +
      `nao o codigo. Sem processo para inspecionar, este teste nao conclui nada.`
    );
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

// ---- Teste 11: PID raiz reusado nao mata descendencia alheia ----
//
// O cenario que duas revisoes independentes acharam: quando matarDescendencia
// roda, o cmd.exe ja morreu, e o PID dele e' candidato a reuso. Se o SO
// reatribuir aquele numero a um processo alheio dentro da janela da consulta,
// os filhos DESSE processo nascem depois do marco, passam pela guarda de data
// e seriam mortos.
//
// Aqui o cenario e' encenado sem depender de corrida: passamos o PID deste
// proprio processo node como "raiz". Ele nao e' cmd.exe/sh, entao representa
// exatamente o PID reciclado por outro dono — e o filho legitimo dele, criado
// depois do marco, TEM de sobreviver. Sem a guarda de raiz este teste mata o
// proprio filho e falha.
console.log('Teste 11: PID raiz reusado nao mata descendencia alheia');
testa('raiz que nao e a minha aborta em vez de matar', () => {
  const { matarDescendencia } = require('../hooks/lib/cli-externo.cjs');
  const marco = Date.now();
  const alheio = cp.spawn(
    process.execPath,
    ['-e', 'setTimeout(() => process.exit(0), 30000)'],
    { stdio: 'ignore', detached: false }
  );
  try {
    // nasce depois do marco e e' descendente do PID passado: sem a guarda de
    // raiz, cai direto na lista de alvos
    const esperaAte = Date.now() + 3000;
    while (Date.now() < esperaAte && !listarDescendentesVivos(process.pid).includes(alheio.pid)) {
      cp.spawnSync(process.execPath, ['-e', '0']);
    }
    if (!listarDescendentesVivos(process.pid).includes(alheio.pid)) {
      throw new Error(`andaime falhou: o filho ${alheio.pid} nao apareceu como descendente`);
    }

    matarDescendencia(process.pid, marco);

    cp.spawnSync(process.execPath, ['-e', 'setTimeout(()=>{},1200)']);
    if (!listarDescendentesVivos(process.pid).includes(alheio.pid)) {
      throw new Error(
        `matou processo de outro dono: o filho ${alheio.pid} do PID ${process.pid} ` +
          `(que nao e cmd.exe/sh) foi morto — a guarda de reuso do PID raiz nao pegou`
      );
    }
  } finally {
    try {
      alheio.kill();
    } catch (e) {
      /* ja saiu */
    }
  }
});

console.log('');

// ---- Cleanup ----
fs.rmSync(TEMP_DIR, { recursive: true, force: true });

// ---- Resumo ----
const total = ok + falhou + pulado;
console.log('==== Resultado ====');
console.log(`ok: ${ok}`);
console.log(`falhou: ${falhou}`);
if (pulado > 0) {
  // Sai SEMPRE que houver, e antes do total: pulado que se esconde no rodapé
  // é a próxima forma de verde que não prova nada.
  console.log(`PULADO: ${pulado} (nao deu para medir — leia o motivo acima)`);
}
console.log(`total: ${total}`);

if (falhou > 0) {
  console.log('');
  console.log(`Vermelhas: [${falhou}]`);
  process.exit(1);
} else {
  process.exit(0);
}
