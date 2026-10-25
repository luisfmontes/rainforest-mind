#!/usr/bin/env node
// @categoria: sensor
/**
 * SubagentStop — o relato do executor de fluxo tem fim declarado (D4 do lote 6,
 * `docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-6.md`).
 *
 * O executor despachado dentro de fluxo (briefing com `Slug:`, mesmo critério do
 * revisor) tem de terminar com uma linha sozinha e exata: `ENTREGA: completa` ou
 * `ENTREGA: parcial`. Sem ela, este hook devolve a vez UMA vez
 * (`{"decision":"block"}`) pedindo o relato completo com a linha final. Na
 * segunda parada (`stop_hook_active === true`) deixa passar.
 *
 * Não grava estado. Best-effort, sempre sai 0: payload ilegível, agente que não
 * é executor, transcrito ausente ou sem `Slug:` (executor fora de fluxo, regra 10)
 * e chave `contrato-relato-executor` desligada — nada acontece.
 *
 * A última mensagem vem de `last_assistant_message` do payload; sem a linha
 * ali, vale a última mensagem de texto do transcrito (mesma reserva de
 * `hooks/veredito-revisor.cjs`).
 */

const fs = require('fs');
const path = require('path');
const { primeiroPrompt, extrairSlug, ultimaMensagemAssistente } = require(path.join(__dirname, '..', 'scripts', 'lib', 'primeiro-prompt-jsonl.cjs'));
const { extrairUltimaLinha } = require(path.join(__dirname, '..', 'scripts', 'lib', 'extrair-veredito.cjs'));
const { caminhoTranscritoSubagente } = require(path.join(__dirname, 'lib', 'transcrito-subagente.cjs'));
const { toplevel } = require(path.join(__dirname, 'lib', 'aviso-fluxo-comum.cjs'));
const { ligado } = require(path.join(__dirname, 'lib', 'config.cjs'));

const AGENTES = ['executor', 'rainforest-mind:executor'];
const SENTINELA = /^entrega: (completa|parcial)$/;

const REASON = 'Relato sem a linha final de fim declarado. Reemita o RELATO COMPLETO nesta mensagem (não só a linha) e termine com uma linha sozinha e exata: ENTREGA: completa, ou ENTREGA: parcial quando houver item NÃO FEITO. Negrito ou crase em volta da linha é aceito. A linha tem de ser a última da mensagem.';

/** A última linha da mensagem casa a sentinela? extrairUltimaLinha já tira negrito e põe em minúsculas. */
function temEntrega(mensagem) {
  return typeof mensagem === 'string' && SENTINELA.test(extrairUltimaLinha(mensagem));
}

function main() {
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0); // payload ilegível nunca derruba a sessão do usuário
  }
  if (!payload || typeof payload !== 'object') process.exit(0);

  if (!AGENTES.includes(payload.agent_type)) process.exit(0);

  const caminho = caminhoTranscritoSubagente(payload);
  if (!caminho) process.exit(0);

  const prompt = primeiroPrompt(caminho);
  if (!prompt) process.exit(0);

  const slug = extrairSlug(prompt);
  if (!slug) process.exit(0); // executor fora de fluxo (regra 10): não é tocado

  // Segunda parada: a vez já foi devolvida uma vez. Não laça o executor.
  if (payload.stop_hook_active === true) process.exit(0);

  if (typeof payload.cwd !== 'string' || !payload.cwd) process.exit(0);
  const repoRoot = toplevel(payload.cwd);
  if (!repoRoot) process.exit(0);

  if (!ligado('contrato-relato-executor', { projeto: repoRoot })) process.exit(0);

  const doPayload = typeof payload.last_assistant_message === 'string' ? payload.last_assistant_message : null;
  if (temEntrega(doPayload)) process.exit(0);
  if (temEntrega(ultimaMensagemAssistente(caminho))) process.exit(0);

  process.stdout.write(JSON.stringify({ decision: 'block', reason: REASON }) + '\n');
  process.exit(0);
}

main();
