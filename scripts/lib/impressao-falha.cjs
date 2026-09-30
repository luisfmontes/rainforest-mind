'use strict';
// Impressao digital de falha de vigia (enxerto do reef), rotulo unico: recorrente.
// Recorrente = a mesma impressao (vigia + causa normalizada) ocorreu ao menos MINIMO_OCORRENCIAS vezes
// na janela de 30 dias, contando so depois do ultimo RESOLVIDO da propria vigia.
// So le vigias/ERROS.md (ou RFM_VIGIAS_DIR/ERROS.md); nunca le log, nunca escreve, nunca lanca por arquivo ausente.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const JANELA_DIAS = 30;
const MINIMO_OCORRENCIAS = 2;

const RE_ERRO = /^- (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}) \[([^\]]+)\]: (.*)$/;

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

function classificar({ erros, agora }) {
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
    porVigia.get(vigia).push({ data, motivo });
  }

  const saida = [];
  for (const [vigia, ocs] of porVigia) {
    const grupos = new Map();
    for (const o of ocs) {
      const id = impressao(vigia, o.motivo);
      if (!grupos.has(id)) grupos.set(id, []);
      grupos.get(id).push(o);
    }
    for (const [id, grupo] of grupos) {
      const n = grupo.length;
      if (n < MINIMO_OCORRENCIAS) continue;
      saida.push({
        vigia,
        causa: normalizarCausa(grupo[0].motivo),
        impressao: id,
        rotulo: 'recorrente',
        n,
        desde: grupo[0].data,
        ultima: grupo[n - 1].data,
      });
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
  const dir = process.env.RFM_VIGIAS_DIR || path.join(__dirname, '..', '..', 'vigias');
  const erros = ler(path.join(dir, 'ERROS.md'));
  if (!erros) return [];
  return classificar({ erros, agora });
}

function ddmm(iso) {
  return iso.slice(8, 10) + '/' + iso.slice(5, 7);
}

function formatar(r) {
  return `${r.vigia}: ${r.causa} - recorrente x${r.n} em ${JANELA_DIAS} dias, desde ${ddmm(r.desde)}, ultima ${ddmm(r.ultima)}`;
}

module.exports = { JANELA_DIAS, MINIMO_OCORRENCIAS, normalizarCausa, impressao, classificar, falhasRecorrentes, formatar };
