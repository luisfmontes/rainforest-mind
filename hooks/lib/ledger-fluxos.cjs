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
//   { "<session_id>": { "ts": <epoch_ms>, "fluxos": [ { "slug", "estagio", "aberto", "ts" } ] } }
//
// `estagio` e o ultimo estagio TOCADO (o que o call site passou). `aberto` e o
// PROXIMO estagio nao-fechado (o que `scripts/estado.cjs:proximo(estado)` ja
// calcula), ou `null` quando o fluxo completou. Sao informacoes diferentes:
// `exigir --estagio fechar` toca `fechar` mas o fluxo continua aberto nele
// mesmo; `marcar --estagio fechar --status ok` tambem toca `fechar`, mas dessa
// vez o fluxo completou. Sem o campo `aberto` essas duas gravacoes ficam
// indistinguiveis, e o hook de titulo de sessao (Parte B) nao tem como decidir
// `[ok]` vs `[aberto: <estagio>]`.
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
 * Carimba `{slug, estagio, aberto}` na entrada da sessão atual (lida de
 * `CLAUDE_SESSION_ID`). Sem a variável de ambiente, não grava nada.
 * Nunca lança — qualquer falha de leitura, parse ou escrita é engolida.
 *
 * `aberto` é o próximo estágio não-fechado (string) ou `null` quando o fluxo
 * completou. Campo opcional: chamador que não passa `aberto` deixa a chave DE
 * FORA do registro — nunca grava `null` por omissão. `null` é o único jeito
 * explícito de dizer "fechado" (é o que o hook de SessionEnd, Parte B, lê
 * para decidir `[ok]`); gravar `null` por omissão marcaria como fechado um
 * fluxo que ninguém mediu. Chave ausente é o estado seguro, e é também o que
 * um ledger escrito por uma versão anterior deste arquivo (sem o campo
 * `aberto`) já produz — o mesmo tratamento vale para os dois casos.
 *
 * @param {{slug: string, estagio: string, aberto?: string|null}} o
 */
function carimbarFluxo(o) {
  try {
    const sessao = process.env.CLAUDE_SESSION_ID;
    if (!sessao) return;
    const slug = o && o.slug;
    const estagio = o && o.estagio;
    const temAberto = !!(o && Object.prototype.hasOwnProperty.call(o, 'aberto'));
    const aberto = temAberto ? o.aberto : undefined;
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

    const registro = temAberto ? { slug, estagio, aberto, ts: agora } : { slug, estagio, ts: agora };
    const idx = fluxos.findIndex((f) => f && f.slug === slug);
    if (idx >= 0) {
      fluxos[idx] = registro;
    } else {
      fluxos.push(registro);
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

module.exports = { carimbarFluxo, caminhoLedger };
