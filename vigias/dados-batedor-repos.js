#!/usr/bin/env node
// dados-batedor-repos.js — apura a ANCORA da ronda do batedor: os problemas vivos.
//
// O batedor nao sai olhando repositorio bonito. Ele sai procurando solucao para
// problema que o Luis tem AGORA — e a lista de problemas sai daqui, apurada por
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

const dados = {
  gerado_para: 'batedor',
  teto_repos: TETO_REPOS,
  ...ideiasAbertas(),
  propostas: propostasDeRelatorio(),
  erros_24h: errosRecentes(),
};

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(dados, null, 2));
} else {
  const { ideias, observacoes, propostas, erros_24h } = dados;
  console.log(`teto de repos nesta ronda: ${TETO_REPOS}`);
  console.log(`\nIDEIAS ABERTAS (${ideias.length}) — ancora principal`);
  ideias.forEach((i) => console.log(`  [${i.dias ?? '?'}d] ${i.titulo}\n        ${i.id} · ${i.projeto}`));
  console.log(`\nOBSERVACOES DA REGRA 13 ABERTAS (${observacoes.length})`);
  observacoes.forEach((o) => console.log(`  [${o.dias ?? '?'}d] ${o.titulo}\n        ${o.id}`));
  console.log(`\nPROPOSTAS NOS 4 RELATORIOS MAIS RECENTES (${propostas.length})`);
  propostas.forEach((p) => console.log(`  ${p.tag} ${p.titulo}\n        ${p.relatorio}`));
  console.log(`\nERROS DE VIGIA NAS ULTIMAS 24H (${erros_24h.length})`);
  erros_24h.forEach((e) => console.log(`  ${e}`));
}
