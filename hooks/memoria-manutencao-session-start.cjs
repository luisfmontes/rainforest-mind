#!/usr/bin/env node
// @categoria: sensor
/**
 * Hook: dispara a passada de manutenção da memória (reconciliar + consolidar)
 * uma vez por dia, em segundo plano.
 *
 * Tarefa 5 do plano `docs/rainforest/planos/2026-09-16-memoria-reconciliacao-e-consolidacao.md`
 * (D1, D5).
 *
 * FINO POR DESIGN (D1): este arquivo só cria a trava do dia, dispara um
 * filho destacado (`node scripts/memoria.cjs manutencao`) e sai. Nenhuma
 * chamada de LLM roda aqui dentro — foi exatamente no caminho síncrono do
 * hook de captura (`observar.cjs`, 30 s de orçamento) que a chamada de LLM
 * calou a captura por 13 dias (#282). Quem roda a manutenção de verdade é o
 * subcomando `manutencao` de `scripts/memoria.cjs`, no processo filho.
 *
 * TRAVA ATÔMICA POR DIA (D5): `<raiz>/manutencao-<AAAA-MM-DD>.lock`, criada
 * com `fs.openSync(trava, 'wx')` — nunca `existsSync` seguido de escrita,
 * porque duas sessões abrindo a trava ao mesmo tempo passariam as duas pela
 * janela entre a checagem e a escrita. O PID do filho destacado vai dentro
 * da trava, e é por ele que a próxima sessão (ou um teste) identifica o
 * processo.
 *
 * DEGRADAÇÃO (regra do plano): raiz inacessível, banco ausente ou spawn que
 * não vai — aviso no stderr e exit 0 sempre. Hook que derruba a abertura da
 * sessão é pior que manutenção que não roda.
 *
 * REGRA 15: nada é escrito fora da raiz de dados resolvida (trava e log).
 * Nenhum PATH, variável de ambiente, config ou serviço é tocado.
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { resolverRaiz } = require('./lib/raiz.cjs');

// Data local (não UTC) de "hoje", em AAAA-MM-DD. `Date.toISOString()` usa
// UTC — nesta máquina (UTC-3), a trava do dia viraria de nome antes da
// meia-noite local, e duas sessões do fim de noite passariam a criar travas
// com nomes DIFERENTES (uma ainda "ontem" UTC, outra já "hoje" UTC),
// disparando a manutenção duas vezes no mesmo dia do usuário. "Por dia" é o
// dia de quem abre a sessão, não o dia em Greenwich.
function dataLocalHoje() {
  const agora = new Date();
  const ano = agora.getFullYear();
  const mes = String(agora.getMonth() + 1).padStart(2, '0');
  const dia = String(agora.getDate()).padStart(2, '0');
  return `${ano}-${mes}-${dia}`;
}

function main() {
  let raiz;
  try {
    ({ raiz } = resolverRaiz({ plugin: path.resolve(__dirname, '..') }));
  } catch (e) {
    console.error(`AVISO: não consegui resolver a raiz de dados: ${e.message}`);
    process.exit(0);
  }

  if (!raiz) {
    console.error('AVISO: nenhuma raiz de dados encontrada; manutenção não disparada');
    process.exit(0);
  }

  try {
    fs.mkdirSync(raiz, { recursive: true });
  } catch (e) {
    console.error(`AVISO: não consegui criar a raiz de dados (${raiz}): ${e.message}`);
    process.exit(0);
  }

  const hoje = dataLocalHoje();
  const trava = path.join(raiz, `manutencao-${hoje}.lock`);

  // Criação atômica: 'wx' falha com EEXIST se o arquivo já existir. Não há
  // janela entre checar e criar — a checagem É a criação.
  let fd;
  try {
    fd = fs.openSync(trava, 'wx');
  } catch (e) {
    if (e.code === 'EEXIST') process.exit(0);
    console.error(`AVISO: não consegui criar a trava do dia (${trava}): ${e.message}`);
    process.exit(0);
  }

  try {
    const script = path.join(__dirname, '..', 'scripts', 'memoria.cjs');
    const processo = process.execPath;
    const filho = spawn(processo, [script, 'manutencao'], {
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    });
    filho.unref();

    fs.writeSync(fd, String(filho.pid));
  } catch (e) {
    console.error(`AVISO: não consegui disparar a manutenção: ${e.message}`);
  } finally {
    try { fs.closeSync(fd); } catch (_) {}
  }

  process.exit(0);
}

if (require.main === module) {
  main();
}

module.exports = { main };
