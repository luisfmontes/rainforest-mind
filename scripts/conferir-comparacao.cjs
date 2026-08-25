#!/usr/bin/env node
/**
 * Catraca de comparação: RODA um comando em dois lugares e carimba onde cada
 * lado rodou. Não lê uma afirmação de "testei antes e depois" — produz a
 * evidência ela mesma, porque enquanto o veredito de uma checagem for
 * redigido pelo mesmo agente que ela deveria travar, ela não trava nada
 * (frase que originou o `conferir-entrega.cjs`, e vale idêntica aqui).
 *
 * POR QUE EXISTE, com data e número. Issue #101 (P6 da #61, desmembrada em
 * 2026-08-25): o `cwd` do shell PERSISTE entre chamadas, e uma comparação
 * "rodei na main e deu verde, rodei na branch e deu vermelho" degenera **em
 * silêncio** para branch contra ela mesma quando o `cd` de uma chamada
 * anterior vazou para a seguinte. Não é o agente mentindo — quem afirma
 * "testei antes e depois" acredita que testou. Só a localização REAL de cada
 * execução pega isso, e só pega se for o script a medir, não o relato.
 *
 * O incidente que batiza a checagem 3 (item "toplevel não bate com o
 * diretório"): 2026-08-19, registrado na regra 11. `git -C <dir>` (e, do
 * mesmo jeito, `git rev-parse --show-toplevel` com `cwd` apontando para
 * `<dir>`) SOBE para o diretório ANCESTRAL em silêncio quando `<dir>` não é,
 * ele mesmo, a raiz de um repositório — e devolve o hash de lá como se fosse
 * o de cá. Um agente aceitou esse hash sem notar a subida e a comparação
 * inteira rodou no repo errado. A defesa aqui é a mesma do
 * `conferir-entrega.cjs`: comparar o toplevel DEVOLVIDO contra o diretório
 * INFORMADO, e recusar quando não batem — nunca aceitar o hash do pai calado.
 *
 * Duas falhas do mesmo formato — "prosa no formato de transcrição" — deram
 * nome aos cuidados de stdin/teto, em 2026-08-25, na mesma sessão que abriu
 * esta issue:
 *
 *   - Um relato colou, como se fosse a saída real de um comando, um
 *     `erro: slug vazio / exit=1` limpo — quando o programa de verdade
 *     produzia um stack trace não tratado. O exit code batia (1 nos dois
 *     casos); só a saída CRUA do processo, carimbada por quem RODOU e não por
 *     quem RELATOU, discrimina os dois casos.
 *   - Outro relatou uma bateria "verde" que na verdade nunca tinha rodado
 *     onde deveria — o nome do arquivo de teste não continha nada que
 *     distinguisse ambiente nenhum.
 *
 * Nenhuma das duas seria pega relendo o relato. As duas são pegas por um
 * script que roda o comando ele mesmo, em cada lado, com `cwd` explícito no
 * processo filho — nunca herdado — e imprime toplevel + HEAD + branch + exit
 * code + a saída crua, ANTES de qualquer veredito.
 *
 * STDIN FECHADO E TETO DE TEMPO: mesmo motivo do `conferir-mutacao.cjs`
 * (relatório de 2026-08-19, seção 6) — um comando que lê payload do stdin
 * herdado pendura o terminal sem sinal nenhum. Aqui os dois filhos (o de
 * "antes" e o de "depois") nascem sem stdin e com teto.
 *
 * Uso:
 *   node scripts/conferir-comparacao.cjs --antes <dir> --depois <dir> \
 *        --comando "<comando>" [--espera diferente|igual] [--timeout <ms>]
 *
 *   --antes    <dir>      diretório do lado "antes" (ex.: worktree/checkout 1)
 *   --depois   <dir>      diretório do lado "depois" (ex.: worktree/checkout 2)
 *   --comando  <comando>  linha de comando rodada nos DOIS lados, via shell
 *   --espera   <valor>    diferente (padrão: antes falha, depois passa) | igual
 *   --timeout  <ms>       teto de tempo de CADA execução do comando (padrão: 300000)
 *
 * Exit:
 *   0  sucesso — o resultado bateu com --espera
 *   1  erro de uso, ou lado SEM VEREDITO (comando estourou o teto de tempo,
 *      foi morto por sinal, ou não executou)
 *   2  RECUSADO: comparação DEGENERADA — antes e depois são o MESMO lado
 *      (mesmo toplevel E mesmo HEAD). A mensagem nomeia qual dos dois coincide.
 *   3  RECUSADO: um dos lados NÃO é (raiz de) repositório git — inclui o caso
 *      em que o toplevel devolvido é um ANCESTRAL do diretório informado
 *      (incidente de 2026-08-19: nunca aceitar esse hash calado)
 *   4  RECUSADO: o resultado saiu CONTRÁRIO ao --espera
 *
 * Os códigos 2, 3 e 4 são DIFERENTES de propósito: quem chama este script de
 * dentro de outra checagem precisa distinguir "a comparação nem existia" (2)
 * de "um dos lados não é onde deveria ser" (3) de "existia, rodou, e o
 * resultado não é o esperado" (4) sem depender de ler a mensagem.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const TIMEOUT_PADRAO = 300000; // 5 min, mesmo padrão do conferir-mutacao.cjs
const TIMEOUT_GIT = 15000; // teto interno para os comandos git de localização

const USO = `uso: node scripts/conferir-comparacao.cjs --antes <dir> --depois <dir> --comando "<comando>" [--espera diferente|igual] [--timeout <ms>]

  --antes    <dir>      diretorio do lado "antes"
  --depois   <dir>      diretorio do lado "depois"
  --comando  <comando>  comando rodado nos dois lados, via shell
  --espera   <valor>    diferente (padrao: antes falha, depois passa) | igual
  --timeout  <ms>       teto de tempo de CADA execucao do comando (padrao: ${TIMEOUT_PADRAO})

exit: 0 sucesso | 1 erro de uso / sem veredito (timeout) | 2 comparacao DEGENERADA
      (mesmo toplevel e mesmo HEAD) | 3 lado nao e (raiz de) repositorio git |
      4 resultado CONTRARIO ao --espera

Bateria/comando: rodado via shell. No Unix e /bin/sh; no Windows (cmd.exe) use
bash explicitamente (ex.: \`bash scripts/testa.sh\`), ou exporte SHELL=/bin/bash.`;

function erroUso(msg) {
  console.error(`erro: ${msg}`);
  console.error('');
  console.error(USO);
  process.exit(1);
}

function ler(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1) return null;
  if (i + 1 >= process.argv.length) erroUso(`--${nome} veio sem valor`);
  return process.argv[i + 1];
}

function ultimasLinhas(texto, n) {
  const linhas = String(texto || '').replace(/\s+$/, '').split(/\r?\n/);
  if (linhas.length <= n) return linhas.join('\n');
  return [`... (${linhas.length - n} linha(s) acima omitida(s))`, ...linhas.slice(-n)].join('\n');
}

/**
 * Compara caminho sem tropeçar em barra invertida, maiúscula e link — mesma
 * função (e mesmo motivo, Issue #16 de 2026-08-17) do `conferir-entrega.cjs`:
 * `realpathSync.native` primeiro porque `realpathSync` puro do Node não
 * expande nome curto 8.3 no Windows, e o git sempre responde na forma longa.
 */
function norm(p) {
  let alvo;
  try {
    alvo = fs.realpathSync.native(p);
  } catch {
    try {
      alvo = fs.realpathSync(p);
    } catch {
      alvo = path.resolve(p);
    }
  }
  return alvo.replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase();
}

/** Roda `git <args...>` com cwd EXPLÍCITO (nunca `-C`, nunca herdado). */
function git(dir, args) {
  const r = spawnSync('git', args, {
    cwd: dir,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: TIMEOUT_GIT,
    maxBuffer: 8 * 1024 * 1024,
  });
  if (r.error || r.status === null) {
    return { rc: 1, saida: '' };
  }
  return { rc: r.status, saida: `${r.stdout || ''}${r.stderr || ''}`.trim() };
}

/**
 * Resolve a localização de UM lado, de dentro do próprio diretório: primeiro
 * o toplevel, e só depois o HEAD — nesta ordem, porque é o toplevel quem
 * detecta a subida silenciosa para o repositório ancestral (incidente de
 * 2026-08-19). Recusa (process.exit(3)) antes de aceitar qualquer hash.
 */
function resolverLado(rotulo, flag, dir) {
  if (dir === null) erroUso(`falta --${flag}`);
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    console.error(`RECUSADO: --${flag} nao e uma pasta: ${dir}`);
    process.exit(3);
  }

  const { rc: rcTop, saida: top } = git(dir, ['rev-parse', '--show-toplevel']);
  if (rcTop !== 0 || !top) {
    console.error(`RECUSADO: lado "${rotulo}" (${dir}) nao e repositorio git.`);
    console.error(`  $ git rev-parse --show-toplevel   (cwd=${dir})`);
    console.error(`  (sem toplevel — fora de qualquer repositorio)`);
    process.exit(3);
  }
  if (norm(top) !== norm(dir)) {
    console.error(`RECUSADO: lado "${rotulo}" (${dir}) nao e a RAIZ de um repositorio git.`);
    console.error(`  o toplevel devolvido foi ${top}, um ANCESTRAL do diretorio informado.`);
    console.error('  isto e o modo de falha exato do incidente de 2026-08-19: git sobe para');
    console.error('  o repositorio pai em silencio, e aceitar esse hash comparava o lado');
    console.error('  errado sem ninguem notar. Aponte --antes/--depois para a raiz do repo.');
    process.exit(3);
  }

  const { rc: rcHead, saida: head } = git(dir, ['rev-parse', 'HEAD']);
  if (rcHead !== 0 || !head) {
    console.error(`RECUSADO: lado "${rotulo}" (${dir}) nao tem HEAD resolvivel (repositorio sem commit?).`);
    process.exit(3);
  }

  const { rc: rcBranch, saida: branchSaida } = git(dir, ['rev-parse', '--abbrev-ref', 'HEAD']);
  const branch = rcBranch === 0 && branchSaida ? branchSaida : '(desconhecida)';

  return { rotulo, dir, top, head, branch };
}

function rodarComando(lado, comando, timeout) {
  const inicio = Date.now();
  const r = spawnSync(comando, {
    shell: true,
    cwd: lado.dir,
    encoding: 'utf8',
    // stdin fechado: comando que leria payload do stdin recebe EOF em vez de
    // pendurar (mesmo cuidado do conferir-mutacao.cjs, relatorio 2026-08-19).
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout,
    maxBuffer: 32 * 1024 * 1024,
  });
  const duracao = Date.now() - inicio;
  return { r, duracao };
}

function imprimeBlocoLado(lado, exitCode, saida, duracao) {
  console.log(`--- lado "${lado.rotulo}" ---`);
  console.log(`  dir      : ${lado.dir}`);
  console.log(`  toplevel : ${lado.top}`);
  console.log(`  HEAD     : ${lado.head}`);
  console.log(`  branch   : ${lado.branch}`);
  console.log(`  exit     : ${exitCode === null ? '(sem veredito)' : exitCode}`);
  console.log(`  duracao  : ${duracao} ms`);
  console.log('  saida    :');
  const linhas = ultimasLinhas(saida, 20);
  for (const l of linhas ? linhas.split('\n') : ['(vazio)']) console.log(`    ${l}`);
  console.log('');
}

function main() {
  if (process.argv.length <= 2) {
    console.error(USO);
    process.exit(1);
  }

  const antesDir = ler('antes');
  const depoisDir = ler('depois');
  const comando = ler('comando');
  const espera = ler('espera') || 'diferente';
  const timeoutStr = ler('timeout');

  if (antesDir === null) erroUso('falta --antes');
  if (depoisDir === null) erroUso('falta --depois');
  if (comando === null) erroUso('falta --comando');
  if (comando.trim() === '') erroUso('--comando vazio');
  if (espera !== 'diferente' && espera !== 'igual') {
    erroUso(`--espera precisa ser 'diferente' ou 'igual', veio '${espera}'`);
  }
  const timeout = timeoutStr === null ? TIMEOUT_PADRAO : Number(timeoutStr);
  if (!Number.isFinite(timeout) || timeout <= 0) erroUso('--timeout precisa ser um numero de ms positivo');

  console.log(`comando : ${comando}`);
  console.log(`espera  : ${espera}`);
  console.log('');

  // ================================================== Fase 1: localizacao
  // Resolve CADA lado de dentro do proprio diretorio, toplevel antes de HEAD.
  // Recusa (exit 3) antes de aceitar qualquer hash — isto acontece dentro de
  // resolverLado() e termina o processo se algum lado nao for repo git.
  const antes = resolverLado('antes', 'antes', antesDir);
  const depois = resolverLado('depois', 'depois', depoisDir);

  console.log('--- localizacao de cada lado ---');
  console.log(`  antes  : toplevel=${antes.top}  HEAD=${antes.head}  branch=${antes.branch}`);
  console.log(`  depois : toplevel=${depois.top}  HEAD=${depois.head}  branch=${depois.branch}`);
  console.log('');

  // ============================================ Fase 2: recusa degenerada
  // Mesmo toplevel E mesmo HEAD = os dois lados sao o MESMO lado. Isto e a
  // prova central da Issue #101: o cwd persistente entre chamadas faz --antes
  // e --depois colapsarem no mesmo diretorio/commit em silencio.
  const mesmoToplevel = norm(antes.top) === norm(depois.top);
  const mesmoHead = antes.head === depois.head;
  if (mesmoToplevel && mesmoHead) {
    console.error('RECUSADO: comparacao DEGENERADA — antes e depois sao o MESMO lado.');
    console.error(`  toplevel coincide : ${antes.top}`);
    console.error(`  HEAD coincide     : ${antes.head}`);
    console.error('  Isto e exatamente como o defeito da Issue #101 acontece de verdade: o');
    console.error('  cwd de uma chamada de shell anterior vazou para esta invocacao, e');
    console.error('  --antes/--depois acabaram apontando para o mesmo lugar no mesmo commit.');
    console.error('  Nao ha comparacao nenhuma aqui — e branch contra ela mesma.');
    process.exit(2);
  }

  // ==================================================== Fase 3: execucao
  // cwd EXPLICITO no processo filho, nunca herdado. Filho sem stdin e com
  // teto — mesmo cuidado do conferir-mutacao.cjs.
  const rAntes = rodarComando(antes, comando, timeout);
  const rDepois = rodarComando(depois, comando, timeout);

  function veredictoDoLado(res) {
    if (res.r.error && res.r.error.code === 'ETIMEDOUT') return { semVeredito: true, motivo: `estourou o teto de ${timeout} ms` };
    if (res.r.error) return { semVeredito: true, motivo: res.r.error.message };
    if (res.r.status === null) return { semVeredito: true, motivo: `morto pelo sinal ${res.r.signal}, sem exit code` };
    return { semVeredito: false, exit: res.r.status };
  }

  const vAntes = veredictoDoLado(rAntes);
  const vDepois = veredictoDoLado(rDepois);

  imprimeBlocoLado(antes, vAntes.semVeredito ? null : vAntes.exit, `${rAntes.r.stdout || ''}${rAntes.r.stderr || ''}`, rAntes.duracao);
  imprimeBlocoLado(depois, vDepois.semVeredito ? null : vDepois.exit, `${rDepois.r.stdout || ''}${rDepois.r.stderr || ''}`, rDepois.duracao);

  if (vAntes.semVeredito) {
    console.error(`SEM VEREDITO: lado "antes" — ${vAntes.motivo}.`);
    process.exit(1);
  }
  if (vDepois.semVeredito) {
    console.error(`SEM VEREDITO: lado "depois" — ${vDepois.motivo}.`);
    process.exit(1);
  }

  // ===================================================== Fase 4: veredito
  let bateu;
  if (espera === 'diferente') {
    // antes FALHA (exit != 0) e depois PASSA (exit == 0).
    bateu = vAntes.exit !== 0 && vDepois.exit === 0;
  } else {
    // igual: os dois saem com o MESMO exit code.
    bateu = vAntes.exit === vDepois.exit;
  }

  if (!bateu) {
    console.error(`RECUSADO: resultado CONTRARIO ao --espera ${espera}.`);
    console.error(`  antes  exit=${vAntes.exit}`);
    console.error(`  depois exit=${vDepois.exit}`);
    if (espera === 'diferente') {
      console.error('  esperado: antes != 0 (falha) e depois == 0 (passa).');
    } else {
      console.error('  esperado: antes == depois.');
    }
    process.exit(4);
  }

  console.log(`ok: resultado bate com --espera ${espera}.`);
  console.log(`  antes  exit=${vAntes.exit}  |  depois exit=${vDepois.exit}`);
  process.exit(0);
}

main();
