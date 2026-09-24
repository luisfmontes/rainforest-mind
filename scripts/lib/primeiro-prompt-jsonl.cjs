"use strict";
/**
 * Primeiro prompt de um transcrito `.jsonl` de subagente, e a linha `Slug:`
 * dentro dele — mesmo formato que `scripts/conferir-divergencia.cjs` já lê
 * (~99-129) para outro mecanismo (`divergir-frames`): a primeira linha do
 * arquivo é um registro `{type:"user", message:{role:"user", content}}`,
 * com `content` tanto string pura (formato real, achado 4 do plano
 * `docs/rainforest/design/2026-09-23-contrato-de-veredito.md`) quanto array
 * de blocos `{type:"text", text}` (defensivo — não confirmado na captura
 * real, mas aceito sem custo).
 *
 * Best-effort: qualquer arquivo ausente, JSON quebrado ou formato
 * inesperado devolve `null`, nunca lança — quem chama é um hook de
 * `SubagentStop` que não pode derrubar a sessão do usuário por um
 * transcrito ilegível.
 */

const fs = require('fs');

/**
 * Lê só a primeira linha do jsonl (o resto pode ser megabytes de
 * transcript que não interessam aqui — mesmo corte de
 * `scripts/conferir-divergencia.cjs`) e devolve o texto do prompt do
 * primeiro registro `user`, ou `null` se qualquer passo falhar.
 */
function primeiroPrompt(caminhoJsonl) {
  let conteudo;
  try {
    conteudo = fs.readFileSync(caminhoJsonl, 'utf8');
  } catch {
    return null;
  }
  const nl = conteudo.indexOf('\n');
  const primeira = (nl === -1 ? conteudo : conteudo.slice(0, nl)).trim();
  if (!primeira) return null;

  let obj;
  try {
    obj = JSON.parse(primeira);
  } catch {
    return null;
  }
  if (!obj || obj.type !== 'user' || !obj.message || obj.message.role !== 'user') {
    return null;
  }

  const c = obj.message.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    const texto = c
      .filter((b) => b && typeof b.text === 'string')
      .map((b) => b.text)
      .join('\n');
    return texto || null;
  }
  return null;
}

/**
 * Linha isolada `Slug: <slug>` em qualquer lugar do prompt — mesmo estilo
 * de `Runtime:`/`Sensor:` (`hooks/portaria.cjs`), case-insensitive,
 * primeira ocorrência vence. `null` quando não há nenhuma (revisão avulsa,
 * D5 do design: sem `Slug:`, o hook não grava nem trava).
 */
function extrairSlug(prompt) {
  if (!prompt || typeof prompt !== 'string') return null;
  const linhas = prompt.split(/\r\n|\r|\n/);
  for (const linha of linhas) {
    const m = linha.match(/^\s*slug\s*:\s*(.+?)\s*$/i);
    if (m && m[1]) return m[1];
  }
  return null;
}

/**
 * Última mensagem de TEXTO do assistente no transcrito inteiro (não só a
 * primeira linha — Tarefa 16, D12). Varre toda linha `type:"assistant"` cujo
 * `message.content` tem bloco de texto não vazio (string pura, ou array
 * `[{type:'text', text}]` — mesmos dois formatos de `primeiroPrompt` acima) e
 * devolve o texto da ÚLTIMA que casar. Mensagem só com tool_use/tool_result
 * (sem bloco de texto) não conta e não sobrescreve a última encontrada.
 *
 * `null` quando o arquivo não existe, não parseia, ou nenhuma linha casa —
 * best-effort, mesmo contrato de `primeiroPrompt`: quem chama (o subcomando
 * `veredito`) trata `null` como "não confirma", nunca lança.
 */
function ultimaMensagemAssistente(caminhoJsonl) {
  let conteudo;
  try {
    conteudo = fs.readFileSync(caminhoJsonl, 'utf8');
  } catch {
    return null;
  }

  let ultima = null;
  for (const linha of conteudo.split(/\r?\n/)) {
    const l = linha.trim();
    if (!l) continue;
    let obj;
    try {
      obj = JSON.parse(l);
    } catch {
      continue;
    }
    if (!obj || obj.type !== 'assistant' || !obj.message || obj.message.role !== 'assistant') {
      continue;
    }
    const c = obj.message.content;
    let texto = null;
    if (typeof c === 'string' && c.trim() !== '') {
      texto = c;
    } else if (Array.isArray(c)) {
      const blocos = c.filter((b) => b && b.type === 'text' && typeof b.text === 'string' && b.text.trim() !== '');
      if (blocos.length > 0) texto = blocos.map((b) => b.text).join('\n');
    }
    if (texto !== null) ultima = texto;
  }
  return ultima;
}

module.exports = { primeiroPrompt, extrairSlug, ultimaMensagemAssistente };
