#!/usr/bin/env node
/**
 * Stop — barra o fim do turno quando o fluxo tem agente em voo.
 *
 * Por que existe (Issue #180): o estágio que despacha agente aposta que o turno
 * dura mais que o agente, e essa aposta é perdida em toda sessão não
 * interativa. Medido em 2026-09-04, numa rodada `claude -p`: o turno acabou com
 * o `revisar` em curso, o revisor morreu junto (`killed.system: 1`), e o texto
 * final prometia "volto com o resultado assim que o revisor terminar" — em `-p`
 * o turno é único, não há para onde voltar.
 *
 * Decisão D16 do lote 4: o paralelismo fica (não se espera agente em
 * foreground, que serializaria o `executar`). O que entra é registro + trava:
 * o estágio grava `em_voo` no estado antes de despachar, e este hook não deixa
 * o turno acabar em silêncio com alguém em voo.
 *
 * - estágio aberto com `em_voo` não vazio e `stop_hook_active` falso → exit 2
 * - o MESMO payload com `stop_hook_active` verdadeiro → exit 0. Barrar duas
 *   vezes vira laço, e laço é pior que o defeito: avisa uma vez.
 * - sem fluxo aberto, sem `em_voo`, payload vazio ou ilegível, fora de git →
 *   exit 0, em silêncio. Hook que derruba a sessão por defeito próprio não
 *   entra.
 *
 * Saídas de emergência, na ordem que os outros gates usam:
 * `RAINFOREST_GATE_OFF` no ambiente, `.rainforest-gate-off` na raiz do repo, e
 * o toggle do `/setup` (chave `gate-agente-em-voo`).
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const { resolver } = require('./lib/estagio-ativo.cjs');

function bloqueia(motivo) {
  process.stderr.write(motivo);
  process.exit(2);
}

/** Raiz do repositório do cwd do EVENTO — nunca a do processo do hook. */
function toplevel(cwd) {
  try {
    return execFileSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim() || null;
  } catch {
    return null;
  }
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0); // payload ilegível nunca derruba a sessão do usuário
  }

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  // O `cwd` do evento é a ÚNICA fonte, sem queda para o do processo. Duas
  // razões, e as duas custaram medição: é o que permite a bateria montar um
  // repositório de fixture e medir o hook contra ELE (queda para
  // `process.cwd()` fazia a bateria medir o repositório de quem a roda), e é o
  // que faz payload vazio sair 0 de verdade em vez de ir consultar o fluxo
  // aberto do diretório em que o processo por acaso nasceu.
  if (!ev.cwd) process.exit(0);
  const gitTop = toplevel(ev.cwd);
  if (!gitTop) process.exit(0);

  try {
    if (fs.existsSync(path.join(gitTop, '.rainforest-gate-off'))) process.exit(0);
  } catch {}

  try {
    if (!require('./lib/config.cjs').ligado('gate-agente-em-voo', { projeto: gitTop })) {
      process.exit(0);
    }
  } catch {}

  const ativo = resolver({ cwd: gitTop });
  if (!ativo || !ativo.slug) process.exit(0);

  const caminhoEstado = path.join(gitTop, 'docs', 'rainforest', 'estado', `${ativo.slug}.json`);
  let estado;
  try {
    estado = JSON.parse(fs.readFileSync(caminhoEstado, 'utf8'));
  } catch {
    process.exit(0);
  }

  const bloco = estado[ativo.estagio];
  const emVoo = bloco && typeof bloco === 'object' && Array.isArray(bloco.em_voo)
    ? bloco.em_voo.filter((a) => a && typeof a === 'object' && a.agente)
    : [];
  if (emVoo.length === 0) process.exit(0);

  // `stop_hook_active` verdadeiro quer dizer que este hook já barrou uma vez
  // neste encerramento. A segunda vez não avisa: deixa o turno acabar.
  if (ev.stop_hook_active === true) process.exit(0);

  const lista = emVoo
    .map((a) => `  - ${a.agente}${a.tarefa ? `, tarefa ${a.tarefa}` : ''}${a.desde ? ` (desde ${a.desde})` : ''}`)
    .join('\n');

  bloqueia(
    `BLOQUEADO pelo gate de agente em voo do rainforest-mind.\n\n` +
    `Razão: o estágio '${ativo.estagio}' do fluxo '${ativo.slug}' tem ${emVoo.length} agente(s)\n` +
    `registrado(s) em voo, e o turno está acabando. Agente em background morre com o\n` +
    `turno — em sessão não interativa, sempre.\n\n` +
    `Em voo:\n${lista}\n\n` +
    `O que fazer:\n` +
    `  1. Se o agente ainda está rodando, espere a volta dele e integre a entrega.\n` +
    `  2. Se ele já voltou, dê a baixa antes de encerrar:\n` +
    `     node scripts/estado.cjs marcar --slug ${ativo.slug} --estagio ${ativo.estagio} --status parcial --json '{"em_voo":[]}'\n` +
    `  3. Se ele morreu, registre isso em vez de deixar o rastro mudo — o campo\n` +
    `     'em_voo' é o que responde "ficou pela metade?" para a próxima sessão.\n\n` +
    `Este aviso sai UMA vez: encerrando de novo, o turno acaba.\n`
  );
}

if (require.main === module) main();
