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
// Poda por idade: entradas de sessão cujo `ts` é mais velho que o corte saem
// na escrita seguinte, mais um teto de contagem (mantendo as mais recentes por
// `ts`) para o arquivo não crescer sem limite.
//
// A janela aqui é de 30 DIAS, não as 24h do `heartbeat.cjs` — de propósito,
// não por descuido: o `ts` do `heartbeat.cjs` é tocado a cada prompt daquela
// sessão, então uma sessão viva nunca esfria ali. Aqui o `ts` só é tocado
// quando a sessão chama um verbo do `estado.cjs` (iniciar/exigir/marcar) — uma
// sessão pode ficar horas ou dias dentro de um `executar` longo sem chamar
// nenhum, e uma janela de 24h podaria o carimbo dela por baixo, fazendo o
// título de SessionEnd sair sem marcador para um fluxo que ainda estava vivo
// (achado 2 da revisão de 2026-09-15). 30 dias cobre esse intervalo com folga
// e ainda descarta lixo de sessão realmente abandonada; o teto de 500
// entradas é a segunda rede, para não depender só do tempo.
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

const CORTE_MS = 30 * 24 * 3600 * 1000;
const MAX_ENTRADAS = 500;

// Lock exclusivo em volta do ciclo ler->mesclar->gravar (achado 1 da revisão
// de 2026-09-15): sem ele, duas escritas quase simultâneas leem o mesmo
// estado velho e uma sobrescreve a outra por inteiro — reproduzido com 80
// processos concorrentes, 9 de 80 chaves sobreviveram. `wx` falha se o
// arquivo já existe: é o mutex portável, sem depender de lib nenhuma.
//
// O ciclo em si é rápido (um JSON pequeno, ler->mesclar->gravar), mas sob
// disputa de dezenas de processos o TEMPO DE FILA para cada um conseguir sua
// vez pode passar longe de poucas centenas de ms — medido: com orçamento de
// 20 tentativas x 15ms (300ms) só 1 de 80 processos concorrentes conseguia
// gravar, porque os outros 79 desistiam antes de chegar a vez deles. O
// orçamento por tentativa é curto de propósito (a fila anda rápido); o que
// precisa ser generoso é o número de tentativas. `LOCK_ORFAO_MS` não muda com
// isso: ele mede a idade do arquivo de lock (tempo de posse), não o tempo de
// espera de quem está tentando — posse continua curta mesmo com fila funda.
const LOCK_TENTATIVAS = 400;
const LOCK_ESPERA_MS = 20;
// Lock mais velho que isto é considerado órfão (processo morreu sem liberar
// em `finally` — kill -9, crash). Bem acima do tempo que um ciclo
// ler->mesclar->gravar leva de verdade (posse é sempre curta, mesmo sob fila
// funda — ver comentário acima), para nunca confundir "lock em uso" com
// "lock abandonado".
const LOCK_ORFAO_MS = 5000;

function dormirSincrono(ms) {
  try {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  } catch {
    // ambiente sem SharedArrayBuffer/Atomics: sem espera, só sem retry
  }
}

function caminhoLedger() {
  const raiz = resolverRaiz({ plugin: CODIGO_ROOT }).raiz || CODIGO_ROOT;
  return path.join(raiz, 'fluxos-sessao.json');
}

/**
 * Tenta abrir o lock exclusivo do arquivo `arquivo`. Devolve o caminho do
 * lock em caso de sucesso, ou `null` se desistiu (não conseguiu em
 * `LOCK_TENTATIVAS` tentativas). Nunca lança.
 */
function adquirirLock(arquivo) {
  const lock = `${arquivo}.lock`;
  for (let i = 0; i < LOCK_TENTATIVAS; i++) {
    try {
      const fd = fs.openSync(lock, 'wx');
      fs.closeSync(fd);
      return lock;
    } catch {
      // já existe (ou outra falha) — antes de esperar de novo, checa se é
      // lock órfão (processo morto sem liberar): se for mais velho que o
      // teto, trata como abandonado e segue em frente.
      try {
        const st = fs.statSync(lock);
        if (Date.now() - st.mtimeMs > LOCK_ORFAO_MS) {
          try {
            fs.unlinkSync(lock);
          } catch {
            // outro processo já limpou, ou não conseguiu: tenta de novo no
            // próximo laço
          }
          continue;
        }
      } catch {
        // stat falhou (arquivo sumiu entre o openSync e aqui): tenta de novo
        continue;
      }
      if (i < LOCK_TENTATIVAS - 1) dormirSincrono(LOCK_ESPERA_MS);
    }
  }
  return null;
}

function liberarLock(lock) {
  try {
    fs.unlinkSync(lock);
  } catch {
    // já removido, ou falha de permissão: nada a fazer
  }
}

/** Escrita atômica: grava num temporário ao lado e troca por cima do destino
 *  com `renameSync` — nunca escreve direto no arquivo final, para uma leitura
 *  concorrente nunca ver conteúdo parcial. */
function escreverAtomico(arquivo, conteudo) {
  const tmp = path.join(
    path.dirname(arquivo),
    `.${path.basename(arquivo)}.${process.pid}.${Date.now()}.tmp`
  );
  fs.writeFileSync(tmp, conteudo);
  fs.renameSync(tmp, arquivo);
}

/**
 * Carimba `{slug, estagio, aberto}` na entrada da sessão atual. Lê
 * `CLAUDE_CODE_SESSION_ID` — o nome real que o Claude Code exporta — e só
 * como reserva `CLAUDE_SESSION_ID` (medido em 2026-09-15: `CLAUDE_SESSION_ID`
 * não existe no ambiente do Claude Code; a reserva não custa nada e cobre um
 * host que exporte o nome antigo). Sem nenhuma das duas, não grava nada.
 * Nunca lança — qualquer falha de leitura, parse ou escrita é engolida.
 *
 * Limitação conhecida, não resolvida aqui: não existe
 * `CLAUDE_CODE_PARENT_SESSION_ID`. Um subagente que rode um verbo de
 * `scripts/estado.cjs` carimba o PRÓPRIO session id, e o hook de SessionEnd
 * (Parte B) roda na sessão-mãe — então aquele carimbo de subagente nunca é
 * visto por ela. Na prática os verbos são rodados pela janela principal.
 * `CLAUDE_CODE_CHILD_SESSION=1` não serve para distinguir os dois casos: ele
 * está presente também no shell da janela principal (medido em 2026-09-15).
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
  let lock = null;
  try {
    const sessao = process.env.CLAUDE_CODE_SESSION_ID || process.env.CLAUDE_SESSION_ID;
    if (!sessao) return;
    const slug = o && o.slug;
    const estagio = o && o.estagio;
    const temAberto = !!(o && Object.prototype.hasOwnProperty.call(o, 'aberto'));
    const aberto = temAberto ? o.aberto : undefined;
    if (!slug || !estagio) return;

    const arquivo = caminhoLedger();

    // Lock exclusivo em volta do ciclo ler->mesclar->gravar inteiro. Não
    // conseguindo o lock (outro processo segurando, ou retentativas
    // esgotadas), desiste em silêncio — o ledger é best-effort, nunca um gate
    // (ver cabeçalho do arquivo).
    lock = adquirirLock(arquivo);
    if (!lock) return;

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

    // Poda por idade: entrada sem atividade há 30 dias+ sai (ver o comentário
    // no topo do arquivo sobre por que a janela aqui é diferente da do
    // heartbeat.cjs). A sessão que acabou de carimbar nunca é podada aqui (o
    // `ts` dela é `agora`).
    const corte = agora - CORTE_MS;
    for (const [id, dado] of Object.entries(ledger)) {
      const ts = dado && typeof dado.ts === 'number' ? dado.ts : 0;
      if (ts < corte) delete ledger[id];
    }

    // Teto de contagem: segunda rede, independente do tempo, para o arquivo
    // não crescer sem limite mesmo com sessões que carimbam dentro dos 30
    // dias. Mantém as `MAX_ENTRADAS` mais recentes por `ts`.
    const entradas = Object.entries(ledger);
    if (entradas.length > MAX_ENTRADAS) {
      entradas.sort((a, b) => (b[1] && b[1].ts || 0) - (a[1] && a[1].ts || 0));
      ledger = Object.fromEntries(entradas.slice(0, MAX_ENTRADAS));
    }

    try {
      escreverAtomico(arquivo, JSON.stringify(ledger));
    } catch {
      // escrita falhou (disco cheio, permissão, raiz inexistente): silencioso
    }
  } catch {
    // qualquer outra falha inesperada: silencioso, nunca propaga
  } finally {
    if (lock) liberarLock(lock);
  }
}

module.exports = { carimbarFluxo, caminhoLedger };
