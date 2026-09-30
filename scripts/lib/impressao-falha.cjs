'use strict';
// Impressao digital de falha de vigia (enxerto do reef) e os dois rotulos:
// persistente (falhou em todas as rondas recentes) e intermitente (voltou depois de ronda limpa).
// So le vigias/ERROS.md e vigias/log-<vigia>.txt; nunca escreve, nunca lanca por arquivo ausente.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const JANELA_DIAS = 30;
const MINIMO_OCORRENCIAS = 2;

const RE_ERRO = /^- (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}) \[([^\]]+)\]: (.*)$/;
const RE_RONDA = /^=== (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}) ===/;

function normalizarCausa(texto) {
  return String(texto == null ? '' : texto)
    .replace(/[A-Za-z]:[\\/][^\s'"`]*/g, '<path>')
    .replace(/(^|[\s('"`=])\/[^\s'"`)]+/g, '$1<path>')
    .replace(/\b(?=[a-z0-9]*\d)[a-z0-9]{12,}\b/gi, '<id>')
    .replace(/\d+/g, '<n>')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 200);
}

function impressao(vigia, causa) {
  return crypto
    .createHash('sha256')
    .update(vigia + '\x1f' + normalizarCausa(causa))
    .digest('hex')
    .slice(0, 16);
}

function paraMs(data, hora) {
  return new Date(data + 'T' + hora + ':00').getTime();
}

function lerRondas(texto) {
  const rondas = [];
  for (const linha of String(texto || '').split(/\r?\n/)) {
    const m = RE_RONDA.exec(linha);
    if (m) rondas.push(m[1] + ' ' + m[2]);
  }
  return rondas.sort();
}

function classificar({ erros, logs, agora }) {
  const fim = (agora || new Date()).getTime();
  const ini = fim - JANELA_DIAS * 86400000;
  const porVigia = new Map();
  for (const linha of String(erros || '').split(/\r?\n/)) {
    const m = RE_ERRO.exec(linha);
    if (!m) continue;
    const [, data, hora, vigia, motivo] = m;
    if (!porVigia.has(vigia)) porVigia.set(vigia, []);
    if (/^RESOLVIDO/.test(motivo)) {
      porVigia.set(vigia, []);
      continue;
    }
    const t = paraMs(data, hora);
    if (t < ini || t > fim) continue;
    porVigia.get(vigia).push({ data, chave: data + ' ' + hora, motivo });
  }

  const saida = [];
  for (const [vigia, ocs] of porVigia) {
    const grupos = new Map();
    for (const o of ocs) {
      const id = impressao(vigia, o.motivo);
      if (!grupos.has(id)) grupos.set(id, []);
      grupos.get(id).push(o);
    }
    const rondas = lerRondas(logs && logs[vigia]);
    const chaveAgora = (() => {
      const d = new Date(fim);
      const p = (n) => String(n).padStart(2, '0');
      return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
    })();
    const ativas = rondas.filter((r) => r <= chaveAgora);
    const idxRonda = (chave) => {
      let i = -1;
      for (let k = 0; k < ativas.length; k++) if (ativas[k] <= chave) i = k;
      return i;
    };
    for (const [id, grupo] of grupos) {
      const n = grupo.length;
      if (n < MINIMO_OCORRENCIAS) continue;
      const base = {
        vigia,
        causa: normalizarCausa(grupo[0].motivo),
        impressao: id,
        n,
        desde: grupo[0].data,
        ultima: grupo[n - 1].data,
      };
      if (ativas.length === 0) {
        saida.push({ ...base, rotulo: 'persistente' });
        continue;
      }
      const L = ativas.length - 1;
      const idxs = grupo.map((o) => idxRonda(o.chave));
      if (idxs[n - 1] !== L) {
        saida.push({ ...base, rotulo: 'intermitente' });
        continue;
      }
      const com = new Set(idxs);
      let s = 0;
      let k = L;
      while (k >= 0 && com.has(k)) {
        s++;
        k--;
      }
      if (s >= MINIMO_OCORRENCIAS) {
        const inicio = L - s + 1;
        const primeira = grupo[idxs.indexOf(inicio)];
        saida.push({ ...base, rotulo: 'persistente', n: s, desde: primeira.data });
      } else {
        saida.push({ ...base, rotulo: 'intermitente' });
      }
    }
  }
  return saida;
}

function ler(arquivo) {
  try {
    return fs.readFileSync(arquivo, 'utf8');
  } catch (e) {
    return null;
  }
}

function falhasRecorrentes(agora = new Date()) {
  const doPlugin = path.join(__dirname, '..', '..', 'vigias');
  const dir = process.env.RFM_VIGIAS_DIR || doPlugin;
  const dirLogs = process.env.RFM_VIGIAS_DIR ? dir : process.env.RFM_ROOT ? path.join(process.env.RFM_ROOT, 'vigias') : doPlugin;
  const erros = ler(path.join(dir, 'ERROS.md'));
  if (!erros) return [];
  const logs = {};
  for (const linha of erros.split(/\r?\n/)) {
    const m = RE_ERRO.exec(linha);
    if (m && /^[\w.-]+$/.test(m[3]) && !(m[3] in logs)) logs[m[3]] = ler(path.join(dirLogs, 'log-' + m[3] + '.txt'));
  }
  return classificar({ erros, logs, agora });
}

function ddmm(iso) {
  return iso.slice(8, 10) + '/' + iso.slice(5, 7);
}

function formatar(r) {
  if (r.rotulo === 'persistente') return `${r.vigia}: ${r.causa} - persistente x${r.n} desde ${ddmm(r.desde)}`;
  return `${r.vigia}: ${r.causa} - intermitente x${r.n} em ${JANELA_DIAS} dias, ultima ${ddmm(r.ultima)}`;
}

module.exports = { JANELA_DIAS, MINIMO_OCORRENCIAS, normalizarCausa, impressao, classificar, falhasRecorrentes, formatar };
