#!/usr/bin/env node
// dados-batedor-repos.js — apura a ANCORA da ronda do batedor: os problemas vivos.
//
// O batedor nao sai olhando repositorio bonito. Ele sai procurando solucao para
// problema que o usuario tem AGORA — e a lista de problemas sai daqui, apurada por
// script, nao pela lembranca do agente (regra do _comum.md: conte pelo campo).
//
// Fontes, em ordem de prioridade:
//   1. ideias.jsonl — plantadas (ideia) e observacoes da regra 13 ainda abertas
//   2. relatorios/*.md — propostas com destino executavel ainda NAO cumprido
//   3. vigias/ERROS.md — falhas de vigia nas ultimas 24h
//
// Uso: node vigias/dados-batedor-repos.js [--json]
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = process.env.RFM_ROOT || 'C:\\Projetos\\rainforest-mind';
const TETO_REPOS = 3;   // teto de repos por ronda; o excedente vai declarado

function lerLinhas(rel) {
  try { return fs.readFileSync(path.join(ROOT, rel), 'utf8').split(/\r?\n/); }
  catch { return []; }
}

function ideiasAbertas() {
  const out = { ideias: [], observacoes: [] };
  for (const linha of lerLinhas('ideias.jsonl')) {
    if (!linha.trim()) continue;
    let d;
    try { d = JSON.parse(linha); } catch { continue; }
    if (d.status !== 'plantada' && d.status !== 'em-colheita') continue;
    const item = {
      id: d.id,
      titulo: d.titulo,
      projeto: String(d.projeto || 'solta').replace(/[\r\n\t]+/g, ' '),
      dias: d.plantada_em
        ? Math.floor((Date.now() - Date.parse(d.plantada_em)) / 86400000)
        : null,
    };
    (d.tipo === 'observacao' ? out.observacoes : out.ideias).push(item);
  }
  return out;
}

// Proposta de relatorio que ainda nao tem destino cumprido. Heuristica honesta:
// pega o titulo da proposta e o destino que ela nomeia; quem julga se foi
// cumprido e o batedor, lendo o destino. O script NAO decide isso — decidir aqui
// seria inventar veredito a partir de regex.
function propostasDeRelatorio() {
  const dir = path.join(ROOT, 'relatorios');
  let arquivos = [];
  try { arquivos = fs.readdirSync(dir).filter((f) => f.endsWith('.md')); } catch { return []; }
  const props = [];
  for (const f of arquivos.sort().reverse().slice(0, 4)) {   // so os 4 mais recentes
    const texto = fs.readFileSync(path.join(dir, f), 'utf8');
    for (const m of texto.matchAll(/^\*\*(P\d+)\s*[—-]\s*(.+?)\*\*/gm)) {
      props.push({ relatorio: f.replace(/\.md$/, ''), tag: m[1], titulo: m[2].trim() });
    }
  }
  return props;
}

function errosRecentes() {
  const limite = Date.now() - 24 * 3600 * 1000;
  return lerLinhas('vigias/ERROS.md')
    .filter((l) => l.startsWith('- '))
    .filter((l) => {
      const m = l.match(/^- (\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})/);
      return m && Date.parse(`${m[1]}T${m[2]}:00`) >= limite;
    });
}

const TRILHAS_VALIDAS = ['instalar', 'enxertar', 'ler'];

// Fila de repos do batedor (D4 do design 2026-08-25): candidato + ancora +
// trilha DECLARADOS antes da busca (D1) — a trilha escolhida depois de ver o
// candidato e a trilha em que ele passa.
//
// Entrada SEM trilha, ou com trilha fora do vocabulario fechado (instalar |
// enxertar | ler), RECUSA aquele candidato, nomeando o que falta (D5). Nunca
// assume 'instalar' por omissao: o default natural seria esse, que e a regua
// de hoje, e assumi-lo devolveria o desenho ao ponto de partida EM SILENCIO —
// justamente para as entradas que ninguem revisou. Recusa e por ENTRADA: os
// outros candidatos da fila seguem normalmente.
function filaDeRepos() {
  const utilizaveis = [];
  const recusados = [];
  lerLinhas('vigias/fila-de-repos.jsonl').forEach((linhaBruta, i) => {
    if (!linhaBruta.trim()) return;
    const numero = i + 1;
    let d;
    try {
      d = JSON.parse(linhaBruta);
    } catch (e) {
      recusados.push({ candidato: `(linha ${numero})`, motivo: `JSON invalido na linha ${numero}: ${e.message}` });
      return;
    }
    const candidato = (d && d.candidato) ? String(d.candidato) : `(linha ${numero} sem campo "candidato")`;
    let trilha = d ? d.trilha : undefined;
    if (trilha === undefined || trilha === null || trilha === '') {
      recusados.push({ candidato, motivo: 'falta o campo "trilha" nesta entrada' });
      return;
    }
    if (!TRILHAS_VALIDAS.includes(trilha)) {
      recusados.push({ candidato, motivo: `trilha "${trilha}" fora do vocabulario fechado da fila` });
      return;
    }
    utilizaveis.push({
      candidato,
      ancora: (d && d.ancora) || null,
      trilha,
      plantada_em: (d && d.plantada_em) || null,
    });
  });
  return { utilizaveis, recusados };
}

const dados = {
  gerado_para: 'batedor',
  teto_repos: TETO_REPOS,
  ...ideiasAbertas(),
  propostas: propostasDeRelatorio(),
  erros_24h: errosRecentes(),
  fila_de_repos: filaDeRepos(),
};

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(dados, null, 2));
} else {
  const { ideias, observacoes, propostas, erros_24h, fila_de_repos } = dados;
  console.log(`teto de repos nesta ronda: ${TETO_REPOS}`);
  console.log(`\nIDEIAS ABERTAS (${ideias.length}) — ancora principal`);
  ideias.forEach((i) => console.log(`  [${i.dias ?? '?'}d] ${i.titulo}\n        ${i.id} · ${i.projeto}`));
  console.log(`\nOBSERVACOES DA REGRA 13 ABERTAS (${observacoes.length})`);
  observacoes.forEach((o) => console.log(`  [${o.dias ?? '?'}d] ${o.titulo}\n        ${o.id}`));
  console.log(`\nPROPOSTAS NOS 4 RELATORIOS MAIS RECENTES (${propostas.length})`);
  propostas.forEach((p) => console.log(`  ${p.tag} ${p.titulo}\n        ${p.relatorio}`));
  console.log(`\nERROS DE VIGIA NAS ULTIMAS 24H (${erros_24h.length})`);
  erros_24h.forEach((e) => console.log(`  ${e}`));
  console.log(`\nFILA DE REPOS — ${fila_de_repos.utilizaveis.length} utilizavel(is), ${fila_de_repos.recusados.length} recusada(s)`);
  fila_de_repos.utilizaveis.forEach((c) => console.log(`  [${c.trilha}] ${c.candidato}\n        ancora: ${c.ancora ?? '(sem ancora)'}`));
  fila_de_repos.recusados.forEach((r) => console.log(`  RECUSADO ${r.candidato}: ${r.motivo}`));
}
