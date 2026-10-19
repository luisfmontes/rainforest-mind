#!/usr/bin/env node
// @categoria: sensor
"use strict";
// Conferidor do catálogo do /setup contra o skills/setup/SKILL.md (D7 e D12 do
// design docs/rainforest/design/2026-10-17-setup-entrevista-guiada.md).
//
// Por que existe: a tabela de chaves e a ordem da entrevista no SKILL.md eram
// copiadas à mão do CHAVES — passaram de 3 de 8 para 5 de 43 em dois meses, e à mão
// não segura. Uma chave nova sem o campo `entrevista` nasce fora da entrevista sem
// que ninguém veja (foi assim com `vigias`). A checagem (a) fica numa linha só, de
// propósito: a catraca de mutação precisa atingi-la exatamente.

const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const DETECTAR_PERMITIDO = ['executaveis', 'env', 'integracao'];

const USO = `uso: node scripts/conferir-setup.cjs [--so-catalogo] [--config <arquivo.json>] [--skill <arquivo>]
  --so-catalogo        confere só o catálogo (a)-(c); pula a tabela e a ordem do SKILL.md
  --config <arquivo>   JSON {"CHAVES": {...}, "GRUPOS_ENTREVISTA": [...]} no lugar do catálogo real
  --skill <arquivo>    SKILL.md no lugar de skills/setup/SKILL.md
exit: 0 limpo | 1 problema(s), listados por nome | 2 erro de uso ou de leitura`;

class ErroDeUso extends Error {}

const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const listaDeTexto = (v) => Array.isArray(v) && v.every((x) => typeof x === 'string');

function lerArgs(argv) {
  const o = { soCatalogo: false, config: null, skill: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--so-catalogo') {
      o.soCatalogo = true;
    } else if (a === '--config' || a === '--skill') {
      const v = argv[++i];
      if (!v) throw new ErroDeUso(USO);
      if (a === '--config') o.config = v;
      else o.skill = v;
    } else {
      throw new ErroDeUso(`argumento desconhecido: ${a}\n${USO}`);
    }
  }
  return o;
}

function lerTexto(arq, rotulo) {
  try {
    return fs.readFileSync(arq, 'utf8');
  } catch (e) {
    throw new ErroDeUso(`nao consegui ler ${rotulo} ${arq}: ${e.message}`);
  }
}

function carregarCatalogo(o) {
  if (o.config) {
    let c;
    try {
      c = JSON.parse(lerTexto(o.config, 'o catalogo de teste'));
    } catch (e) {
      if (e instanceof ErroDeUso) throw e;
      throw new ErroDeUso(`JSON invalido em ${o.config}: ${e.message}`);
    }
    if (!ehObjeto(c) || !ehObjeto(c.CHAVES) || !Array.isArray(c.GRUPOS_ENTREVISTA)) {
      throw new ErroDeUso(`${o.config}: precisa de {"CHAVES": {...}, "GRUPOS_ENTREVISTA": [...]}`);
    }
    return { CHAVES: c.CHAVES, GRUPOS: c.GRUPOS_ENTREVISTA };
  }
  const real = require(path.join(RAIZ, 'hooks', 'lib', 'config.cjs'));
  return { CHAVES: real.CHAVES, GRUPOS: real.GRUPOS_ENTREVISTA };
}

function conferirCatalogo(CHAVES, GRUPOS, INTEGRACOES) {
  const problemas = [];
  const nomes = Object.keys(CHAVES);
  const semCampo = nomes.filter((k) => !Object.prototype.hasOwnProperty.call(CHAVES[k], 'entrevista'));
  for (const k of semCampo) {
    problemas.push(`${k}: sem o campo \`entrevista\` (use { grupo, detectar } ou null)`);
  }
  for (const k of nomes) {
    const ent = CHAVES[k].entrevista;
    if (ent === null) continue;
    if (ent === undefined) {
      // Ausência é de (a), que a recusa; aqui só entra o campo presente com valor undefined.
      if (Object.prototype.hasOwnProperty.call(CHAVES[k], 'entrevista')) {
        problemas.push(`${k}: \`entrevista\` está undefined (use { grupo, detectar } ou null)`);
      }
      continue;
    }
    if (!ehObjeto(ent)) {
      problemas.push(`${k}: \`entrevista\` deve ser objeto ou null`);
      continue;
    }
    if (!GRUPOS.includes(ent.grupo)) {
      problemas.push(`${k}: grupo '${ent.grupo}' fora de GRUPOS_ENTREVISTA`);
    }
    const det = ent.detectar;
    if (!ehObjeto(det)) {
      problemas.push(`${k}: \`detectar\` deve ser objeto`);
      continue;
    }
    for (const dk of Object.keys(det)) {
      if (!DETECTAR_PERMITIDO.includes(dk)) problemas.push(`${k}: detectar tem chave desconhecida '${dk}'`);
    }
    if (det.executaveis !== undefined && !listaDeTexto(det.executaveis)) {
      problemas.push(`${k}: detectar.executaveis deve ser lista de strings`);
    }
    if (det.env !== undefined && !listaDeTexto(det.env)) {
      problemas.push(`${k}: detectar.env deve ser lista de strings`);
    }
    if (det.integracao !== undefined && (typeof det.integracao !== 'string' || !INTEGRACOES.includes(det.integracao))) {
      problemas.push(`${k}: integracao '${det.integracao}' nao existe em INTEGRACOES (${INTEGRACOES.join(', ')})`);
    }
  }
  return { nomes, problemas };
}

// Primeiro token do subtítulo, sem acento e sem pontuação: "### Estratégia — ..." vira "estrategia".
const normalizarGrupo = (s) => s.trim().split(/\s+/)[0]
  .normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z]/g, '');

function conferirSkill(nomes, GRUPOS, arqSkill) {
  const linhas = lerTexto(arqSkill, 'o SKILL.md').split(/\r?\n/);
  const problemas = [];

  const naTabela = new Set();
  for (const l of linhas) {
    const m = /^\| `([^`]+)` \|/.exec(l);
    if (m) naTabela.add(m[1]);
  }
  for (const k of nomes) {
    if (!naTabela.has(k)) problemas.push(`tabela do SKILL.md sem a chave: ${k}`);
  }
  for (const k of naTabela) {
    if (!nomes.includes(k)) problemas.push(`tabela do SKILL.md tem chave que nao existe no catalogo: ${k}`);
  }

  const ini = linhas.findIndex((l) => l.trim() === '## Ordem da entrevista');
  if (ini < 0) {
    problemas.push('SKILL.md sem a seção "## Ordem da entrevista"');
  } else {
    const seq = [];
    for (let i = ini + 1; i < linhas.length && !/^## /.test(linhas[i]); i++) {
      const m = /^### (.+)$/.exec(linhas[i]);
      if (m) seq.push(normalizarGrupo(m[1]));
    }
    if (JSON.stringify(seq) !== JSON.stringify(GRUPOS)) {
      problemas.push(`ordem da entrevista no SKILL.md (${seq.join(' > ') || 'vazia'}) difere de GRUPOS_ENTREVISTA (${GRUPOS.join(' > ')})`);
    }
  }
  return problemas;
}

function main() {
  const o = lerArgs(process.argv.slice(2));
  const { CHAVES, GRUPOS } = carregarCatalogo(o);
  const INTEGRACOES = Object.keys(require(path.join(RAIZ, 'hooks', 'lib', 'integracoes.cjs')).INTEGRACOES);
  const { nomes, problemas } = conferirCatalogo(CHAVES, GRUPOS, INTEGRACOES);
  if (!o.soCatalogo) {
    problemas.push(...conferirSkill(nomes, GRUPOS, o.skill || path.join(RAIZ, 'skills', 'setup', 'SKILL.md')));
  }
  if (problemas.length) {
    console.log(`conferir-setup: ${problemas.length} problema(s)`);
    for (const p of problemas) console.log(`  - ${p}`);
    process.exitCode = 1;
    return;
  }
  console.log(`ok: ${nomes.length} chaves conferidas${o.soCatalogo ? ' (so catalogo; SKILL.md nao conferido)' : ' (catalogo e SKILL.md)'}`);
  process.exitCode = 0;
}

try {
  main();
} catch (e) {
  if (e instanceof ErroDeUso) {
    console.error(e.message);
    process.exitCode = 2;
  } else {
    throw e;
  }
}
