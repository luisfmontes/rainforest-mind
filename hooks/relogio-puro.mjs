// Logica pura do relogio do mod (jornada e janela parada). ES module sem Node e sem
// o objeto do engine: o relogio entra por argumento (`agora`, em ms), nunca por leitura.
// Contrato: docs/rainforest/planos/2026-10-03-mod-jornada-relogio.md.

export const LIMITE_EFETIVA_MIN = 540;
export const HORA_NOITE = 19;
export const HORA_FIM_MADRUGADA = 5;
export const JANELA_MSG_MIN = 30;
export const OCIOSIDADE_PADRAO_MIN = 45;

const pad2 = (n) => String(n).padStart(2, '0');

// Mesma forma de `hhmm` em scripts/jornada.cjs: `9h12`, `45 min`.
export function hhmm(minutos) {
  const total = Math.round(minutos);
  const h = Math.floor(total / 60);
  const m = total % 60;
  return h ? h + 'h' + pad2(m) : m + ' min';
}

export function diaLocal(ms) {
  const d = new Date(ms);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}

export function horaLocal(ms) {
  const d = new Date(ms);
  return d.getHours() + 'h' + pad2(d.getMinutes());
}

// Ultimo segmento do caminho; o cwd real do Windows vem com barra invertida.
function pastaDe(cwd) {
  const partes = String(cwd || '').replace(/[\\/]+$/, '').split(/[\\/]/);
  return partes[partes.length - 1] || '';
}

// jornada: { efetiva_min, ultimo_ms } | null
// sessoes: { ociosidade_min, janelas: [{ cwd, desde }] } | null
export function avaliarRelogio({ jornada, sessoes, agora }) {
  let j = null;
  if (jornada) {
    const { efetiva_min, ultimo_ms } = jornada;
    const hora = new Date(agora).getHours();
    const longa = efetiva_min > LIMITE_EFETIVA_MIN;
    const noite = (hora >= HORA_NOITE || hora < HORA_FIM_MADRUGADA) && agora - ultimo_ms <= JANELA_MSG_MIN * 60000;
    const mesmoDia = diaLocal(ultimo_ms) === diaLocal(agora);
    if (mesmoDia && (longa || noite)) j = { efetiva_min, hora: horaLocal(agora), dia: diaLocal(agora) };
  }

  let parada = null;
  if (sessoes && Array.isArray(sessoes.janelas)) {
    const limite = typeof sessoes.ociosidade_min === 'number' ? sessoes.ociosidade_min : OCIOSIDADE_PADRAO_MIN;
    const acima = sessoes.janelas
      .filter((w) => (agora - w.desde) / 60000 > limite)
      .sort((a, b) => a.desde - b.desde);
    if (acima.length > 0) {
      const w = acima[0];
      parada = {
        cwd: w.cwd,
        pasta: pastaDe(w.cwd),
        min: Math.floor((agora - w.desde) / 60000),
        outras: acima.length - 1,
      };
    }
  }
  return { jornada: j, parada };
}

export function linhaRelogio(r) {
  if (!r || (!r.jornada && !r.parada)) return null;
  const partes = [];
  if (r.jornada) partes.push('jornada ' + hhmm(r.jornada.efetiva_min) + ' · ' + r.jornada.hora);
  if (r.parada) {
    const mais = r.parada.outras > 0 ? ' (+' + r.parada.outras + ')' : '';
    partes.push(r.parada.pasta + ' parada há ' + hhmm(r.parada.min) + mais);
  }
  return '⏰ ' + partes.join(' | ');
}

// Nunca os minutos: so o dia (jornada) e quem esta mais parada e quantas passam do limite.
export function assinaturaRelogio(r) {
  if (!r) return '';
  const trechos = [];
  if (r.jornada) trechos.push('j:' + r.jornada.dia);
  if (r.parada) trechos.push('p:' + r.parada.cwd + ':' + (r.parada.outras + 1));
  return trechos.join('|');
}

export function notaJornada(r) {
  if (!r || !r.jornada) return null;
  return (
    'Relógio do mod (regra 8): a jornada efetiva de hoje é ' + hhmm(r.jornada.efetiva_min) +
    ' e são ' + r.jornada.hora + '. Avalie o aviso da regra 8 neste turno: se o usuário está ' +
    'produzindo ativamente, avise uma única vez (a hora, um ponto de parada concreto, a checagem de corpo); ' +
    'se está delegando em projeto de descanso, não avise. Esta nota não se repete hoje.'
  );
}
