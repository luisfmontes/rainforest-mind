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

module.exports = { primeiroPrompt, extrairSlug };
