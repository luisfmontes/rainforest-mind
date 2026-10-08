#!/usr/bin/env node
'use strict';
/**
 * Instrumento de medição (não é runtime): calibra o limiar bm25 da memória
 * escolhida pelo assunto do pedido (fluxo 2026-10-08-memoria-por-assunto).
 *
 * Para cada pedido DIGITADO do usuário nos transcritos das sessões pontuadas,
 * busca no observacoes_fts (bm25, até 3, vivas, não consolidadas, criadas ANTES
 * do pedido) e dá a cada candidata a nota de utilidade (calcularNota) contra o
 * que veio DEPOIS do pedido (o próprio pedido não entra). Depois varre os
 * limiares: candidata entra se bm25 <= L (bm25 do SQLite é negativo; mais
 * negativo = mais relevante).
 *
 * Uso: node scripts/calibrar-limiar-assunto.cjs --db <copia.db> --limiares -2,-4
 *        [--sem-filtro-temporal] [--caso-nota]
 * Abre o banco SOMENTE-LEITURA; passe uma cópia.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');
const { calcularNota } = require('./lib/utilidade.cjs');
const { filtroVivas } = require('./memoria.cjs');
const { construirQueryAssunto, TETO_DF_FRACAO } = require('../hooks/lib/memoria-assunto.cjs');

const NOTA_UTIL = 0.5;
const TETO_POR_PEDIDO = 3;

function argumentos(argv) {
  const a = { db: null, limiares: null, tetos: [TETO_DF_FRACAO], semFiltroTemporal: false, casoNota: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--db') a.db = argv[++i];
    else if (argv[i] === '--limiares') a.limiares = argv[++i];
    else if (argv[i] === '--tetos') a.tetos = argv[++i].split(',').map(Number);
    else if (argv[i] === '--sem-filtro-temporal') a.semFiltroTemporal = true;
    else if (argv[i] === '--caso-nota') a.casoNota = true;
  }
  if (!a.db || !a.limiares) {
    console.error('uso: --db <copia.db> --limiares -2,-4,... [--sem-filtro-temporal] [--caso-nota]');
    process.exit(2);
  }
  a.limiares = a.limiares.split(',').map(Number);
  if (a.limiares.some((n) => !Number.isFinite(n)) || a.tetos.some((n) => !Number.isFinite(n))) {
    console.error('valor invalido em --limiares ou --tetos');
    process.exit(2);
  }
  return a;
}

function acharTranscrito(id) {
  const home = os.homedir();
  for (const cfg of ['.claude-personal', '.claude']) {
    const base = path.join(home, cfg, 'projects');
    let dirs = [];
    try {
      dirs = fs.readdirSync(base);
    } catch (e) {
      continue;
    }
    for (const d of dirs) {
      const p = path.join(base, d, id + '.jsonl');
      if (fs.existsSync(p)) return p;
    }
  }
  return null;
}

// Lê o transcrito numa lista ordenada de eventos: pedido digitado (com ts) ou
// texto "de trabalho" (pedido/tool_use input) que entra na nota dos pedidos anteriores.
function lerEventos(caminho) {
  const eventos = [];
  for (const linha of fs.readFileSync(caminho, 'utf8').split('\n')) {
    if (!linha.trim()) continue;
    let e;
    try {
      e = JSON.parse(linha);
    } catch (err) {
      continue;
    }
    if (!e.message || e.isSidechain) continue;
    const c = e.message.content;
    if (e.type === 'user') {
      if (e.isMeta) continue;
      let texto = null;
      if (typeof c === 'string') texto = c;
      else if (Array.isArray(c)) {
        if (c.some((b) => b && b.type === 'tool_result')) continue;
        texto = c.filter((b) => b && b.type === 'text' && typeof b.text === 'string').map((b) => b.text).join('\n');
      }
      if (!texto || !texto.trim()) continue;
      const t = texto.trim();
      const digitado = !t.startsWith('/') && !t.startsWith('<') && !t.startsWith('[Request interrupted');
      eventos.push({ tipo: 'pedido', ts: e.timestamp || null, texto, digitado });
    } else if (e.type === 'assistant' && Array.isArray(c)) {
      for (const b of c) {
        if (b && b.type === 'tool_use' && b.input !== undefined) {
          try {
            eventos.push({ tipo: 'tool', texto: JSON.stringify(b.input) });
          } catch (err) {
            // input nao serializavel: ignora
          }
        }
      }
    }
  }
  return eventos;
}

function main() {
  const a = argumentos(process.argv.slice(2));
  const db = new DatabaseSync(a.db, { readOnly: true });

  const sql = `SELECT o.id, o.conteudo, bm25(observacoes_fts) AS bm25
     FROM observacoes_fts JOIN observacoes o ON o.id = observacoes_fts.rowid
     WHERE observacoes_fts MATCH ? ${filtroVivas('o.')} AND o.consolidada_em IS NULL
       ${a.semFiltroTemporal ? '' : 'AND o.criada_em < ?'}
     ORDER BY bm25(observacoes_fts) LIMIT ${TETO_POR_PEDIDO}`;
  const busca = db.prepare(sql);

  const sessoes = db.prepare('SELECT sessao FROM uso_memoria_sessoes').all().map((r) => r.sessao);
  let ausentes = 0;
  let pedidos = 0;
  const candidatasPorTeto = new Map(a.tetos.map((t) => [t, []])); // teto -> [{bm25, nota}[]] por pedido
  let casoNota = null;

  for (const id of sessoes) {
    const caminho = acharTranscrito(id);
    if (!caminho) {
      ausentes++;
      continue;
    }
    const eventos = lerEventos(caminho);
    for (let i = 0; i < eventos.length; i++) {
      const ev = eventos[i];
      if (ev.tipo !== 'pedido' || !ev.digitado || !ev.ts) continue;
      pedidos++;
      let posterior = null;
      const notas = new Map(); // obs.id -> nota (a nota nao depende do teto)
      for (const teto of a.tetos) {
        // Consulta montada pela funcao do hook, com o teto em calibracao.
        let query = null;
        try {
          query = construirQueryAssunto(db, ev.texto, teto);
        } catch (err) {
          query = null;
        }
        let linhas = [];
        if (query) {
          try {
            linhas = a.semFiltroTemporal ? busca.all(query) : busca.all(query, ev.ts);
          } catch (err) {
            linhas = [];
          }
        }
        const cands = [];
        for (const l of linhas) {
          if (posterior === null) posterior = eventos.slice(i + 1).map((x) => x.texto).join('\n');
          if (!notas.has(l.id)) notas.set(l.id, calcularNota(db, l.conteudo, posterior));
          const nota = notas.get(l.id);
          cands.push({ bm25: l.bm25, nota });
          if (a.casoNota && !casoNota) {
            const notaCom = calcularNota(db, l.conteudo, ev.texto + '\n' + posterior);
            if (notaCom > nota) casoNota = { sessao: id, pedido: pedidos, obs: l.id, notaCom, notaSem: nota };
          }
        }
        candidatasPorTeto.get(teto).push(cands);
      }
    }
  }

  console.log('teto | limiar | injecoes | fracao_util(nota>=0.5) | media_por_pedido | fracao_pedidos_sem_injecao');
  for (const teto of a.tetos) {
    for (const L of a.limiares) {
      let inj = 0;
      let uteis = 0;
      let semInj = 0;
      for (const cands of candidatasPorTeto.get(teto)) {
        const dentro = cands.filter((c) => c.bm25 <= L);
        inj += dentro.length;
        uteis += dentro.filter((c) => c.nota >= NOTA_UTIL).length;
        if (dentro.length === 0) semInj++;
      }
      const f = (n, d) => (d ? (n / d).toFixed(3) : 'n/a');
      console.log(`${teto} | ${L} | ${inj} | ${f(uteis, inj)} | ${f(inj, pedidos)} | ${f(semInj, pedidos)}`);
    }
  }
  console.log(`sessoes=${sessoes.length} pedidos=${pedidos} transcritos_ausentes=${ausentes}`);
  if (a.casoNota) {
    console.log(casoNota
      ? `caso_nota: sessao=${casoNota.sessao} pedido#=${casoNota.pedido} obs=${casoNota.obs} nota_com_pedido=${casoNota.notaCom.toFixed(3)} nota_sem_pedido=${casoNota.notaSem.toFixed(3)}`
      : 'caso_nota: nenhum');
  }
}

main();
