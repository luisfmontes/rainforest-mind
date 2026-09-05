#!/usr/bin/env node
/**
 * Stop — barra sessão quando há agente em voo (background) que morreu.
 *
 * Decisão D16: fluxo com agente em voo bloqueado na volta (stop_hook_active
 * falso) até o agente ser aguardado e dado baixa, ou até que seja registrado
 * que ele morreu.
 *
 * - estágio aberto com `em_voo` não vazio e `stop_hook_active` falso → exit 2
 * - estágio aberto com `em_voo` não vazio e `stop_hook_active` verdadeiro → exit 0
 *   (barrado uma vez só; `stop_hook_active` verdadeiro = já disse uma vez)
 * - sem fluxo aberto, sem `em_voo`, payload vazio/ilegível, fora de git → exit 0
 *
 * Saídas de emergência: `RAINFOREST_GATE_OFF=1`, `.rainforest-gate-off`,
 * toggle de `/setup` (chave `gate-agente-em-voo`, padrão true).
 */

const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

const { resolver } = require('./lib/estagio-ativo.cjs');

function bloqueia(motivo) {
  process.stderr.write(motivo);
  process.exit(2);
}

function verificarGit() {
  // Verifica se estamos em um repositório git procurando por .git
  try {
    let atual = process.cwd();
    for (let i = 0; i < 10; i++) {
      if (fs.existsSync(path.join(atual, '.git'))) {
        return atual;
      }
      const pai = path.dirname(atual);
      if (pai === atual) break; // chegou na raiz
      atual = pai;
    }
  } catch {}
  return null;
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0);
  }

  // Verificar saídas de emergência
  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  // Detectar se estamos em repositório git
  const gitTop = verificarGit();
  if (!gitTop) {
    // Não está em repositório git
    process.exit(0);
  }

  if (fs.existsSync(path.join(gitTop, '.rainforest-gate-off'))) {
    process.exit(0);
  }

  // Toggle do setup — usa process.cwd() que é sempre correto em worktree
  try {
    if (!require('./lib/config.cjs').ligado('gate-agente-em-voo', { projeto: process.cwd() })) {
      process.exit(0);
    }
  } catch {}

  // Resolver estágio ativo — se não houver, não há fluxo aberto
  // Usa process.cwd() que é sempre o worktree correto
  const estagio = resolver({ cwd: process.cwd() });
  if (!estagio || !estagio.slug) {
    console.error('DEBUG: sem estagio aberto');
    process.exit(0);
  }

  // Ler estado do fluxo
  const caminhoEstado = path.join(process.cwd(), 'docs', 'rainforest', 'estado', `${estagio.slug}.json`);
  if (!fs.existsSync(caminhoEstado)) {
    process.exit(0);
  }

  let estado;
  try {
    estado = JSON.parse(fs.readFileSync(caminhoEstado, 'utf8'));
  } catch {
    process.exit(0);
  }

  // Verificar se o estágio ativo tem `em_voo` não vazio
  const estagioAtual = estagio.estagio;
  const bloco = estado[estagioAtual];
  if (!bloco || typeof bloco !== 'object' || !bloco.em_voo || !Array.isArray(bloco.em_voo)) {
    // Nada em voo
    process.exit(0);
  }

  // Verificar se há agente em voo
  const agentesEmVoo = bloco.em_voo.filter(a => a && typeof a === 'object' && a.agente);
  if (agentesEmVoo.length === 0) {
    process.exit(0);
  }

  // Se `stop_hook_active` é verdadeiro, já foi avisado uma vez — deixar passar
  if (ev.stop_hook_active === true) {
    process.exit(0);
  }

  // Primeiro aviso: bloqueia
  const primeiroAgente = agentesEmVoo[0];
  const mensagem =
    `BLOQUEADO pelo gate de agente em voo do rainforest-mind.\n\n` +
    `Razão: estágio '${estagioAtual}' tem agente em voo que morreu junto com o turno.\n\n` +
    `Agente: ${primeiroAgente.agente}\n` +
    `Tarefa: ${primeiroAgente.tarefa || '(não registrada)'}\n` +
    `Em voo desde: ${primeiroAgente.desde || '(não registrado)'}\n\n` +
    `O que fazer:\n` +
    `  1. Se o agente ainda está rodando, aguarde e rode:\n` +
    `     node scripts/estado.cjs marcar --slug ${estagio.slug} --estagio ${estagioAtual} --status ok\n\n` +
    `  2. Se o agente morreu, registre:\n` +
    `     node scripts/estado.cjs marcar --slug ${estagio.slug} --estagio ${estagioAtual} --status ok --json '{"em_voo": []}'\n\n`;

  bloqueia(mensagem);
}

if (require.main === module) main();
