'use strict';
/**
 * Reconhece a falha passageira "sem cota" do Codex CLI, para que despacho,
 * transferência e gate falhem FECHADOS e LEGÍVEIS (D5 do design
 * 2026-09-08-validar-ponte-codex-ao-vivo).
 *
 * Medido em 2026-09-08 com o limite de 5 h estourado: `codex exec` sai 1,
 * não cria o `-o` e escreve no stderr
 *   ERROR: You've hit your usage limit. Upgrade to Pro (...) or try again at 5:41 PM.
 * Com `--json`, o mesmo texto vem no stdout, dentro de um evento
 *   {"type":"error","message":"You've hit your usage limit. ..."}
 * Por isso a busca é no texto cru (stderr + stdout), não em JSON.
 *
 * Exit 75 é EX_TEMPFAIL (sysexits.h): "tente de novo mais tarde". Distingue
 * cota (passageiro, hora de retorno no texto) de Codex quebrado (exit 1).
 */

const PADRAO = /hit your usage limit/i;
const EXIT_SEM_COTA = 75;

/**
 * Devolve a linha que denuncia a falta de cota, limpa do prefixo `ERROR:`
 * e de JSON em volta, ou null se o texto não fala de cota.
 * @param {string} texto stderr + stdout do Codex, concatenados
 * @returns {string|null}
 */
function detectarSemCota(texto) {
  if (!texto || !PADRAO.test(texto)) return null;
  const linha = texto.split(/\r?\n/).find(l => PADRAO.test(l)) || '';
  // Evento --json: extrai só a mensagem.
  const m = linha.match(/"message"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  const bruto = m ? m[1].replace(/\\"/g, '"') : linha;
  return bruto.replace(/^\s*ERROR:\s*/i, '').trim();
}

/**
 * Só para saída `--json` com exit 0: procura a mensagem de cota DENTRO de um
 * evento `error` ou `turn.failed`, nunca em texto de agente. Sem isso, um
 * revisor que comentasse "hit your usage limit" num parecer legítimo viraria
 * falso "sem cota" (CRÍTICO 1 do revisar de 2026-09-08).
 * @param {string} stdout JSONL do Codex
 * @returns {string|null}
 */
function detectarSemCotaEmEventos(stdout) {
  if (!stdout) return null;
  for (const linha of stdout.split(/\r?\n/)) {
    if (!linha.trim().startsWith('{')) continue;
    let ev;
    try { ev = JSON.parse(linha); } catch { continue; }
    if (!ev || typeof ev !== 'object') continue;
    const msg = ev.type === 'error' ? ev.message
      : ev.type === 'turn.failed' ? (ev.error && ev.error.message)
        : null;
    if (typeof msg === 'string' && PADRAO.test(msg)) return msg.trim();
  }
  return null;
}

module.exports = { detectarSemCota, detectarSemCotaEmEventos, EXIT_SEM_COTA, PADRAO };
