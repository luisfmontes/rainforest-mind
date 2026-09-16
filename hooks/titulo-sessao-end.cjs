#!/usr/bin/env node
// SessionEnd: marca no título da sessão se o fluxo que ela tocou fechou ou
// onde parou. Design: docs/rainforest/design/2026-09-15-titulo-de-sessao-encerrada.md
//
// Duas fontes de verdade somadas aqui: o ledger local
// (`hooks/lib/ledger-fluxos.cjs`, escrito pelos verbos de `scripts/estado.cjs`)
// diz QUAIS fluxos esta sessão tocou e em que estágio cada um ficou; o
// transcript da própria sessão (`data.transcript_path`) diz o NOME que já
// existe (custom-title de /rename, ou o ai-title automático) — o hook só
// prefixa, nunca inventa nome (D3, D10).
//
// Guarda dupla antes de escrever: `reason` tem que ser `prompt_input_exit`
// (D7 — clear/resume são continuação, logout é raro, other inclui crash) e a
// sessão tem que ter pelo menos um fluxo carimbado no ledger (D2 — nada de
// retro-marcar sessão que este mecanismo não viu nascer).
//
// Escrita é SEMPRE append de uma linha JSON, nunca reescreve, trunca ou
// reordena o transcript (D4). Falha em qualquer ponto — reason errado, sem
// ledger, sem conseguir escrever — é silêncio: exit 0, sem stdout, sem
// stderr. Um SessionEnd que falha alto suja o encerramento de toda sessão.

const fs = require('fs');
const { caminhoLedger } = require('./lib/ledger-fluxos.cjs');

// `caminhoLedger()` já resolve a raiz de dados via `resolverRaiz` — mesma
// cadeia que `hooks/lib/ledger-fluxos.cjs` usa para ESCREVER. Ler e escrever
// pelo mesmo resolvedor é o que garante achar o arquivo que os verbos de
// `scripts/estado.cjs` carimbaram.

// Do menos ao mais avançado. `arqueologia` entra aqui — mesmo sendo opcional
// e ficando fora de `proximo()` em scripts/estado.cjs — porque um fluxo pode
// tê-la carimbada como `aberto` num ledger futuro; ela é o estágio menos
// avançado que existe, então abre a lista.
const ORDEM_ESTAGIOS = ['arqueologia', 'design', 'plano', 'executar', 'revisar', 'verificar', 'fechar'];

function indiceEstagio(estagio) {
  const i = ORDEM_ESTAGIOS.indexOf(estagio);
  return i === -1 ? Infinity : i;
}

/** @returns {{marcador: string, fluxoEscolhido: object}|null} */
function decidirMarcador(fluxos) {
  if (!fluxos.length) return null;

  // `aberto === null` é o único jeito explícito de "fechado". Ledger de antes
  // desta feature (Parte A) não tem a chave — `undefined` cai no mesmo `!==
  // null` e conta como aberto: mais seguro que assumir `[ok]` sobre um fluxo
  // que este carimbo nunca mediu.
  const todosFechados = fluxos.every((f) => f && f.aberto === null);
  if (todosFechados) {
    return { marcador: '[ok]', fluxoEscolhido: fluxos[0] };
  }

  const abertos = fluxos.filter((f) => f && f.aberto !== null);
  let escolhido = abertos[0];
  for (const f of abertos) {
    if (indiceEstagio(f.aberto) < indiceEstagio(escolhido.aberto)) escolhido = f;
  }
  return { marcador: `[aberto: ${escolhido.aberto}]`, fluxoEscolhido: escolhido };
}

/** Último `custom-title` e último `ai-title` do transcript, lendo linha a
 *  linha (JSONL). Linha que não é JSON válido é ignorada — o transcript do CC
 *  tem tipos de linha variados (user, assistant, etc.), e nenhum deles é
 *  problema nosso aqui. */
function lerTitulosDoTranscript(caminho) {
  let conteudo;
  try {
    conteudo = fs.readFileSync(caminho, 'utf8');
  } catch {
    return { customTitle: undefined, aiTitle: undefined };
  }
  let customTitle;
  let aiTitle;
  for (const linha of conteudo.split(/\r?\n/)) {
    if (!linha.trim()) continue;
    let obj;
    try {
      obj = JSON.parse(linha);
    } catch {
      continue;
    }
    if (!obj || typeof obj !== 'object') continue;
    if (obj.type === 'custom-title' && typeof obj.customTitle === 'string') {
      customTitle = obj.customTitle;
    } else if (obj.type === 'ai-title' && typeof obj.aiTitle === 'string') {
      aiTitle = obj.aiTitle;
    }
  }
  return { customTitle, aiTitle };
}

// Âncora do marcador que ESTE hook escreve — só remove reentrada própria
// (D11). Um `/rename` que comece com `[` mas não case (ex.: `[rascunho] x`)
// fica intacto: a âncora exige a palavra `ok` ou `aberto: <estagio>` exata.
const ANCORA_MARCADOR = /^\[(ok|aberto: [a-z]+)\] /;

function tirarMarcadorAntigo(texto) {
  return texto.replace(ANCORA_MARCADOR, '');
}

// `customTitle` não pode conter aspas duplas — o picker do CC extrai com
// /"customTitle":"([^"]+)"/, e uma aspa no meio quebraria essa extração.
function sanitizar(texto) {
  return texto.replace(/"/g, "'");
}

function dormirSincrono(ms) {
  try {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  } catch {
    // ambiente sem SharedArrayBuffer/Atomics: sem retry, mas nunca lança
  }
}

/** Até 3 tentativas, ~300ms de teto total, desiste em silêncio (D9). */
function appendComRetry(caminho, linha) {
  const TENTATIVAS = 3;
  const ESPERA_MS = 100;
  for (let i = 0; i < TENTATIVAS; i++) {
    try {
      fs.appendFileSync(caminho, linha);
      return true;
    } catch {
      if (i < TENTATIVAS - 1) dormirSincrono(ESPERA_MS);
    }
  }
  return false;
}

function main() {
  let input = '';
  try {
    input = fs.readFileSync(0, 'utf8');
  } catch {
    process.exit(0);
  }

  let data = {};
  try {
    data = JSON.parse(input);
  } catch {
    process.exit(0);
  }

  // Guarda 1 (D7) — literal: é o alvo da catraca de mutação da tarefa.
  if (data.reason !== 'prompt_input_exit') process.exit(0);

  if (!data.session_id || !data.transcript_path) process.exit(0);

  // Guarda 2 (D2) — sem ledger para esta sessão, silêncio total.
  const arquivoLedger = caminhoLedger();

  let ledger = {};
  try {
    ledger = JSON.parse(fs.readFileSync(arquivoLedger, 'utf8'));
  } catch {
    process.exit(0);
  }

  const entrada = ledger[data.session_id];
  const fluxos = entrada && Array.isArray(entrada.fluxos) ? entrada.fluxos : [];
  if (fluxos.length === 0) process.exit(0);

  // Passo 3 — decide o marcador e o fluxo cujo slug vira o fallback de texto.
  const decisao = decidirMarcador(fluxos);
  if (!decisao) process.exit(0);
  const { marcador, fluxoEscolhido } = decisao;

  // Passo 4 — decide o texto base.
  const { customTitle, aiTitle } = lerTitulosDoTranscript(data.transcript_path);
  const textoBase = customTitle !== undefined
    ? customTitle
    : aiTitle !== undefined
      ? aiTitle
      : fluxoEscolhido.slug;

  // Passo 5 — tira marcador antigo (reentrada, D11).
  const textoSemMarcador = tirarMarcadorAntigo(textoBase);

  // Passo 6 — monta e escreve.
  const customTitleFinal = sanitizar(`${marcador} ${textoSemMarcador}`);
  const linha = `${JSON.stringify({ type: 'custom-title', customTitle: customTitleFinal, sessionId: data.session_id })}\n`;

  appendComRetry(data.transcript_path, linha);
  process.exit(0);
}

main();
