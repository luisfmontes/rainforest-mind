#!/usr/bin/env node
// @categoria: sensor
/**
 * Descobre o território do repositório e imprime o bloco de UM estágio do fluxo.
 *
 * Uso: node scripts/territorio.cjs estagio <nome> [--raiz <repo>]
 *
 * POR QUE EXISTE. Um território (conjunto de ferramentas e agentes de uma linguagem
 * ou domínio) vive em plugin próprio e declara, num `territorio.json`, o que cada
 * estágio do fluxo deve usar. A injeção por hook de abertura é cortada pelo teto de
 * entrega do harness, então cada skill de estágio chama este script e lê o bloco
 * impresso — script verificável por exit code, não prosa que o modelo pode ignorar.
 *
 * Saídas: 0 = bloco impresso ou `sem territorio`; 2 = contrato violado
 * (versao_contrato != 0, ou apontamento do repo para território inexistente).
 * Sem território, nada muda para o repositório: imprime `sem territorio` e sai 0.
 *
 * Variáveis (D6, D7): `{arquivo}` vem de --arquivo; as demais, de
 * ~/.rainforest/territorios/<nome>.json. Variável usada sem valor: exit 3.
 * Itens (D5): agente ou skill `<plugin>:<nome>` de plugin ausente ou desabilitado é
 * indisponível — opcional vira `aviso:` e exit 0; obrigatório sai 2.
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const IGNORADAS = new Set(['.git', 'node_modules']);
const PROFUNDIDADE_MAX = 5;

function falha(msg) {
  console.error(msg);
  process.exit(2);
}

// Mesmo padrão de `configDirsDoHarness` em saude.cjs: a declaração da sessão manda;
// sem ela, o ~/.claude padrão.
function configDir() {
  if (process.env.CLAUDE_CONFIG_DIR) return path.resolve(process.env.CLAUDE_CONFIG_DIR);
  return path.join(process.env.USERPROFILE || process.env.HOME || os.homedir(), '.claude');
}

function desabilitados() {
  try {
    const ep = JSON.parse(fs.readFileSync(path.join(configDir(), 'settings.json'), 'utf8')).enabledPlugins;
    return ep && typeof ep === 'object' ? ep : {};
  } catch {
    return {};
  }
}

function lerRegistro() {
  try {
    return (JSON.parse(fs.readFileSync(path.join(configDir(), 'plugins', 'installed_plugins.json'), 'utf8')) || {}).plugins || {};
  } catch {
    return {};
  }
}

// Plugin disponível = instalado e não desabilitado (ausente de enabledPlugins = habilitado).
function pluginsDisponiveis() {
  const ep = desabilitados();
  const ok = new Set();
  for (const chave of Object.keys(lerRegistro())) if (ep[chave] !== false) ok.add(chave.split('@')[0]);
  return ok;
}

function descobrirCandidatos() {
  let registro;
  try {
    registro = JSON.parse(fs.readFileSync(path.join(configDir(), 'plugins', 'installed_plugins.json'), 'utf8'));
  } catch {
    return [];
  }
  const candidatos = [];
  const ep = desabilitados();
  for (const [chave, lista] of Object.entries((registro && registro.plugins) || {})) {
    if (ep[chave] === false) continue;
    for (const item of Array.isArray(lista) ? lista : []) {
      if (!item || !item.installPath) continue;
      const arq = path.join(item.installPath, 'territorio.json');
      if (!fs.existsSync(arq)) continue;
      const plugin = chave.split('@')[0];
      let manifesto;
      try {
        manifesto = JSON.parse(fs.readFileSync(arq, 'utf8'));
      } catch (e) {
        falha(`territorio.json ilegivel no plugin ${plugin}: ${e.message}`);
      }
      if (manifesto.versao_contrato !== 0) {
        falha(`plugin ${plugin}: versao_contrato ${manifesto.versao_contrato} nao suportada (esperado 0)`);
      }
      candidatos.push({ plugin, raiz: item.installPath, manifesto });
    }
  }
  return candidatos;
}

function temExtensao(dir, extensoes, nivel) {
  if (nivel > PROFUNDIDADE_MAX) return false;
  let entradas;
  try {
    entradas = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return false;
  }
  for (const e of entradas) {
    if (e.isDirectory()) {
      if (!IGNORADAS.has(e.name) && temExtensao(path.join(dir, e.name), extensoes, nivel + 1)) return true;
    } else if (extensoes.includes(path.extname(e.name).toLowerCase())) {
      return true;
    }
  }
  return false;
}

function detecta(t, raiz) {
  const d = t.manifesto.deteccao || {};
  const exts = (d.extensoes || []).map((x) => x.toLowerCase());
  if (exts.length && temExtensao(raiz, exts, 0)) return true;
  return (d.arquivos || []).some((a) => fs.existsSync(path.join(raiz, a)));
}

function lerApontamento(raiz) {
  try {
    const linha = fs.readFileSync(path.join(raiz, '.rainforest', 'territorio'), 'utf8').split(/\r?\n/)[0].trim();
    return linha || null;
  } catch {
    return null;
  }
}

function resolver(candidatos, raiz, apontado) {
  if (apontado) return candidatos.find((t) => t.manifesto.nome === apontado) || null;
  return candidatos.find((t) => detecta(t, raiz)) || null;
}

function indisponivel(tipo, disponiveis) {
  const i = tipo.indexOf(':');
  return i > 0 && !disponiveis.has(tipo.slice(0, i));
}

function imprimirEstagio(manifesto, estagio, arquivo) {
  const e = (manifesto.estagios || {})[estagio];
  const disponiveis = pluginsDisponiveis();
  const comandos = (e && e.comandos) || [];
  for (const a of (e && e.agentes) || []) {
    if (a.obrigatorio === true && indisponivel(a.tipo, disponiveis)) falha(`agente obrigatorio indisponivel: ${a.tipo}`);
  }
  const arquivoLocal = path.join(os.homedir(), '.rainforest', 'territorios', `${manifesto.nome}.json`);
  let valores = null;
  try {
    valores = JSON.parse(fs.readFileSync(arquivoLocal, 'utf8'));
  } catch (err) {
    if (err.code !== 'ENOENT') falha(`config local ilegivel em ${arquivoLocal}: ${err.message}`);
  }
  const usadas = new Set();
  for (const c of comandos) for (const m of c.comando.matchAll(/\{(\w+)\}/g)) if (m[1] !== 'arquivo') usadas.add(m[1]);
  const faltando = [...usadas].filter((v) => !valores || typeof valores[v] !== 'string');
  if (faltando.length) { console.error(`variavel sem valor em ${arquivoLocal}: ${faltando.join(', ')}`); process.exit(3); }
  console.log(`territorio: ${manifesto.nome}`);
  if (!e) {
    console.log('estagio sem declaracao');
    return;
  }
  if (e.modo) console.log(`modo: ${e.modo}`);
  for (const a of e.agentes || []) {
    if (indisponivel(a.tipo, disponiveis)) {
      console.log('aviso: agente indisponivel, papel padrao do rainforest');
      continue;
    }
    console.log(`agente: ${a.tipo} obrigatorio=${a.obrigatorio === true} mcp=${a.mcp || 'orquestrador'}`);
  }
  for (const m of e.mcp || []) {
    console.log(`mcp: ${m.tool} quem=${m.quem || 'orquestrador'} obrigatorio=${m.obrigatorio === true}`);
  }
  for (const s of e.skills || []) {
    console.log(indisponivel(s, disponiveis) ? 'aviso: skill indisponivel, papel padrao do rainforest' : `skill: ${s}`);
  }
  for (const c of comandos) {
    const cmd = c.comando.replace(/\{(\w+)\}/g, (m, v) => (v === 'arquivo' ? (arquivo === undefined ? m : arquivo) : valores[v]));
    console.log(`comando: ${c.id} ${cmd} obrigatorio=${c.obrigatorio === true}`);
  }
}

function main() {
  const [sub, estagio, ...resto] = process.argv.slice(2);
  if (sub !== 'estagio' || !estagio) {
    console.error('uso: territorio.cjs estagio <nome> [--raiz <repo>] [--arquivo <caminho>]');
    process.exit(1);
  }
  const i = resto.indexOf('--raiz');
  const raiz = path.resolve(i >= 0 && resto[i + 1] ? resto[i + 1] : process.cwd());
  const j = resto.indexOf('--arquivo');
  const arquivo = j >= 0 ? resto[j + 1] : undefined;
  const candidatos = descobrirCandidatos();
  const apontado = lerApontamento(raiz);
  const t = resolver(candidatos, raiz, apontado);
  if (!t && apontado) falha(`territorio apontado em .rainforest/territorio nao existe: ${apontado}`);
  if (!t) {
    console.log('sem territorio');
    return;
  }
  imprimirEstagio(t.manifesto, estagio, arquivo);
}

main();
