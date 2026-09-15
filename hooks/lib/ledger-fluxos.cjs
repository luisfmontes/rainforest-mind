// Ledger local: liga session_id -> fluxos (slugs) que aquela sessão tocou.
//
// Por que existe: o heartbeat (`hooks/heartbeat.cjs`) sabe que uma sessão está
// viva, mas não sabe QUAIS fluxos ela tocou. Este arquivo fecha essa lacuna
// para os verbos de `scripts/estado.cjs` (iniciar/exigir/marcar), sem mexer
// no contrato do heartbeat nem no `sessoes.json` — são donos diferentes.
//
// Onde mora: mesma raiz de dados que `sessoes.json` — resolvida por
// `resolverRaiz` (a cadeia RFM_ROOT > projeto > global > plugin), do jeito
// que `hooks/heartbeat.cjs` já faz (linhas ~40-42 daquele arquivo). Dado de
// sessão, não de projeto — por isso NÃO usa RFM_ESTADO_ROOT (essa variável é
// do `scripts/estado.cjs`, e é sobre outro tipo de estado: ver o comentário
// no topo daquele arquivo).
//
// Forma do arquivo:
//   { "<session_id>": { "ts": <epoch_ms>, "fluxos": [ { "slug", "estagio", "ts" } ] } }
//
// Uma entrada por slug: rodar o verbo de novo no mesmo slug ATUALIZA o
// `estagio` daquela entrada (mesma posição no array), nunca acrescenta outra.
//
// Poda por idade, espelhando o corte de 24h do `heartbeat.cjs`: entradas de
// sessão cujo `ts` é mais velho que o corte saem na escrita seguinte.
//
// Toda falha é silenciosa (leitura, parse e escrita) — esta função nunca pode
// lançar nem mudar o exit code de quem a chama. Os verbos de `estado.cjs` têm
// exit codes que são contrato (regra 11); o ledger é um efeito colateral
// best-effort, nunca um gate.

const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./raiz.cjs');

// Duas pastas acima deste arquivo (hooks/lib/ledger-fluxos.cjs -> raiz do repo),
// igual ao CODIGO_ROOT de hooks/heartbeat.cjs (que está uma pasta acima do dele).
const CODIGO_ROOT = path.resolve(__dirname, '..', '..');

const CORTE_MS = 24 * 3600 * 1000;

function caminhoLedger() {
  const raiz = resolverRaiz({ plugin: CODIGO_ROOT }).raiz || CODIGO_ROOT;
  return path.join(raiz, 'fluxos-sessao.json');
}

/**
 * Carimba `{slug, estagio}` na entrada da sessão atual (lida de
 * `CLAUDE_SESSION_ID`). Sem a variável de ambiente, não grava nada.
 * Nunca lança — qualquer falha de leitura, parse ou escrita é engolida.
 *
 * @param {{slug: string, estagio: string}} o
 */
function carimbarFluxo(o) {
  try {
    const sessao = process.env.CLAUDE_SESSION_ID;
    if (!sessao) return;
    const slug = o && o.slug;
    const estagio = o && o.estagio;
    if (!slug || !estagio) return;

    const arquivo = caminhoLedger();

    let ledger = {};
    try {
      const bruto = fs.readFileSync(arquivo, 'utf8');
      const lido = JSON.parse(bruto);
      if (lido && typeof lido === 'object' && !Array.isArray(lido)) ledger = lido;
    } catch {
      ledger = {};
    }

    const agora = Date.now();
    const entradaAtual = ledger[sessao];
    const fluxos = entradaAtual && Array.isArray(entradaAtual.fluxos)
      ? entradaAtual.fluxos.slice()
      : [];

    const idx = fluxos.findIndex((f) => f && f.slug === slug);
    if (idx >= 0) {
      fluxos[idx] = { slug, estagio, ts: agora };
    } else {
      fluxos.push({ slug, estagio, ts: agora });
    }

    ledger[sessao] = { ts: agora, fluxos };

    // Poda por idade — a mesma rede embaixo do heartbeat.cjs: entrada sem
    // atividade há 24h+ sai. A sessão que acabou de carimbar nunca é podada
    // aqui (o `ts` dela é `agora`).
    const corte = agora - CORTE_MS;
    for (const [id, dado] of Object.entries(ledger)) {
      const ts = dado && typeof dado.ts === 'number' ? dado.ts : 0;
      if (ts < corte) delete ledger[id];
    }

    try {
      fs.writeFileSync(arquivo, JSON.stringify(ledger));
    } catch {
      // escrita falhou (disco cheio, permissão, raiz inexistente): silencioso
    }
  } catch {
    // qualquer outra falha inesperada: silencioso, nunca propaga
  }
}

module.exports = { carimbarFluxo };
