#!/usr/bin/env node
// @categoria: sensor
// Log das falhas de ferramenta de todas as sessões, para triar depois.
//
// O contador "Erros N" do mod zerava com a sessão e não guardava qual foi o erro.
// Daqui em diante cada falha (deny ou isError) vira uma linha em
// `<raiz>/erros.jsonl` **na hora**, não no SessionEnd: janela fechada no X não
// dispara SessionEnd (o mesmo buraco da janela fantasma do relógio, 2026-10-07),
// e são justamente as sessões que mais erram que acabam fechadas assim.
//
// Uso:
//   node scripts/erros.cjs gravar < falha.json   (JSON: sessao, cwd, ferramenta, tipo, comando, mensagem)
//   node scripts/erros.cjs listar [--horas 24]   (texto agrupado por tipo)
//   node scripts/erros.cjs contar [--horas 24]   (JSON: { total, erro, bloqueio })
// Exit 1 sem raiz de dados; exit 2 com uso errado. `gravar` nunca grava data
// vinda de fora: quem carimba é o relógio local daqui.
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('../hooks/lib/raiz.cjs');

const PLUGIN = path.resolve(__dirname, '..');
const TETO_BYTES = 1024 * 1024;
const TETO_TEXTO = 300;
const TIPOS = new Set(['erro', 'bloqueio']);

function valorDe(nome) {
  const i = process.argv.indexOf(nome);
  return i !== -1 && i + 1 < process.argv.length ? process.argv[i + 1] : null;
}

// Uma linha, sem controle, cortada: a mensagem de erro vem da ferramenta e pode ser enorme.
function texto(v, teto) {
  const s = String(v ?? '').replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim();
  return s.length > teto ? s.slice(0, teto - 1) + '…' : s;
}

function arquivo() {
  const { raiz } = resolverRaiz({ plugin: PLUGIN });
  return raiz ? path.join(raiz, 'erros.jsonl') : null;
}

// Passou do teto: fica a metade mais nova. Escrita atômica por rename.
function podar(alvo) {
  let tam = 0;
  try { tam = fs.statSync(alvo).size; } catch { return; }
  if (tam <= TETO_BYTES) return;
  const linhas = fs.readFileSync(alvo, 'utf8').split('\n').filter(Boolean);
  const tmp = `${alvo}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, linhas.slice(Math.floor(linhas.length / 2)).join('\n') + '\n');
  fs.renameSync(tmp, alvo);
}

function gravar(alvo) {
  let e;
  try { e = JSON.parse(fs.readFileSync(0, 'utf8')); } catch {
    process.stderr.write('erros: entrada nao e JSON\n');
    return 2;
  }
  if (!e || typeof e !== 'object' || !TIPOS.has(e.tipo) || !e.ferramenta) {
    process.stderr.write('erros: precisa de tipo (erro|bloqueio) e ferramenta\n');
    return 2;
  }
  const linha = {
    ts: new Date().toISOString(),
    sessao: texto(e.sessao, 64),
    cwd: texto(e.cwd, 260),
    ferramenta: texto(e.ferramenta, 80),
    tipo: e.tipo,
    comando: texto(e.comando, 160),
    mensagem: texto(e.mensagem, TETO_TEXTO),
  };
  fs.appendFileSync(alvo, JSON.stringify(linha) + '\n');
  podar(alvo);
  return 0;
}

function recentes(alvo, horas) {
  const corte = Date.now() - horas * 3600 * 1000;
  let bruto = '';
  try { bruto = fs.readFileSync(alvo, 'utf8'); } catch { return []; }
  const saida = [];
  for (const l of bruto.split('\n')) {
    if (!l.trim()) continue;
    try {
      const o = JSON.parse(l);
      if (Date.parse(o.ts) >= corte) saida.push(o);
    } catch {}
  }
  return saida;
}

function pasta(cwd) {
  return String(cwd || '').replace(/[\\/]+$/, '').split(/[\\/]/).pop() || '?';
}

function hora(ts) {
  const d = new Date(ts);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getDate())}/${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function listar(alvo, horas) {
  const itens = recentes(alvo, horas);
  if (itens.length === 0) {
    process.stdout.write(`Nenhum erro de ferramenta nas últimas ${horas} h.\n`);
    return 0;
  }
  const partes = [`${itens.length} falha(s) de ferramenta nas últimas ${horas} h (${alvo}):`];
  for (const tipo of ['bloqueio', 'erro']) {
    const doTipo = itens.filter((o) => o.tipo === tipo).reverse();
    if (doTipo.length === 0) continue;
    partes.push('', tipo === 'erro' ? `Erros (${doTipo.length}):` : `Bloqueios — gate ou permissão negada (${doTipo.length}):`);
    for (const o of doTipo.slice(0, 30)) {
      const cmd = o.comando ? ` ${o.comando}` : '';
      partes.push(`- ${hora(o.ts)} [${pasta(o.cwd)}] ${o.ferramenta}${cmd}`);
      if (o.mensagem) partes.push(`    ${o.mensagem}`);
    }
    if (doTipo.length > 30) partes.push(`  (+${doTipo.length - 30} mais antigos no arquivo)`);
  }
  process.stdout.write(partes.join('\n') + '\n');
  return 0;
}

function contar(alvo, horas) {
  const itens = recentes(alvo, horas);
  const erro = itens.filter((o) => o.tipo === 'erro').length;
  process.stdout.write(JSON.stringify({ total: itens.length, erro, bloqueio: itens.length - erro }) + '\n');
  return 0;
}

function main() {
  const sub = process.argv[2];
  const horas = Number(valorDe('--horas') || 24);
  if (!['gravar', 'listar', 'contar'].includes(sub) || !(horas > 0)) {
    process.stderr.write('uso: erros.cjs gravar|listar|contar [--horas N]\n');
    return 2;
  }
  const alvo = arquivo();
  if (!alvo) {
    process.stderr.write('erros: sem raiz de dados\n');
    return 1;
  }
  if (sub === 'gravar') return gravar(alvo);
  if (sub === 'listar') return listar(alvo, horas);
  return contar(alvo, horas);
}

module.exports = { recentes, texto };
if (require.main === module) process.exitCode = main();
