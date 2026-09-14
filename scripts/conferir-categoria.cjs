#!/usr/bin/env node
// @categoria: sensor
/**
 * Confere a marca `@categoria` (guia | sensor | dado) de toda peça de harness
 * do plugin, e RECUSA quando alguma peça não carrega marca válida.
 *
 * POR QUE EXISTE. O plugin tem três espécies de artefato que se parecem mas
 * agem em momentos diferentes: hook que roda ANTES de uma ação (gate), hook ou
 * CLI que roda DEPOIS ou sob demanda (sensor), e arquivo que não executa nada,
 * só carrega dado lido por outra peça. Sem marca, essa distinção mora só na
 * cabeça de quem escreveu cada arquivo — e evapora. Este script exige a marca
 * e recusa a peça que perdê-la.
 *
 * A REGRA DE CLASSIFICAÇÃO (não é deste script — é do briefing que o criou):
 * classifica-se pelo EVENTO em que o código roda, nunca pelo que ele
 * inspeciona.
 *   - guia   — roda ANTES da ação (hook de PreToolUse, SubagentStart, SessionStart).
 *   - sensor — roda DEPOIS da ação (hook de Stop, PostToolUse) OU é CLI rodado
 *              sob demanda (todo `scripts/conferir-*.cjs` e todo prompt de
 *              vigia se enquadram aqui: "sob demanda" é o evento deles).
 *   - dado   — arquivo que não é peça: não executa nada, só é lido por outra.
 *
 * PEÇA COM MAIS DE UM EVENTO EM `hooks.json`. Três hooks (`heartbeat.cjs`,
 * `memoria-marca.cjs`, `scripts/observar.cjs`) estão registrados em mais de um
 * evento — a regra acima pressupõe um evento por arquivo e não dá desempate
 * para esse caso. Resolvido por leitura, não por este script (que só EXIGE a
 * marca, não a calcula): os três foram marcados `sensor` — nenhum evento de
 * `heartbeat.cjs` (UserPromptSubmit, Stop, SessionEnd) está na lista de guia;
 * `memoria-marca.cjs` tem 2 de 3 registros (Stop, SessionEnd) do lado sensor
 * contra 1 (SessionStart --recover) do lado guia; `observar.cjs` já cai na
 * cláusula "CLI sob demanda" da regra, que resolve sem depender do evento.
 *
 * O CONJUNTO VARRIDO é derivado do disco, não de uma lista fixa neste arquivo:
 *   - hooks citados em `hooks/hooks.json` (comando `node ".../hooks/xxx.cjs"`
 *     ou `.../scripts/xxx.cjs`), deduplicados — um hook registrado em mais de
 *     um evento entra uma vez só;
 *   - todo `scripts/conferir-*.cjs` presente no disco (este arquivo incluso);
 *   - todo `vigias/*.md` presente no disco.
 * Isso significa que criar um hook novo, um conferidor novo ou um vigia novo
 * sem marca já reprova esta checagem — o conjunto cresce sozinho.
 *
 * Uso:
 *   node scripts/conferir-categoria.cjs [--raiz <dir>] [--json]
 *
 * Sem `--raiz`, usa o toplevel do git do cwd (ou cwd, se não houver git).
 *
 * Exit:
 *   0  toda peça do conjunto tem marca `guia`, `sensor` ou `dado`
 *   1  alguma peça não tem marca, ou tem valor fora dos três — nomeada na saída
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const CATEGORIAS_VALIDAS = new Set(['guia', 'sensor', 'dado']);

function resolverRaizPadrao() {
  const r = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  if (r.status === 0 && r.stdout && r.stdout.trim()) return r.stdout.trim();
  return process.cwd();
}

function relPosix(raiz, alvo) {
  return path.relative(raiz, alvo).split(path.sep).join('/');
}

/** Extrai, deduplicados, os caminhos de hook citados em hooks/hooks.json. */
function hooksDoManifesto(raiz) {
  const manifesto = path.join(raiz, 'hooks', 'hooks.json');
  const texto = fs.readFileSync(manifesto, 'utf8');
  const achados = new Set();
  const re = /\$\{CLAUDE_PLUGIN_ROOT\}\/((?:hooks|scripts)\/[A-Za-z0-9_.-]+\.cjs)/g;
  let m;
  while ((m = re.exec(texto))) achados.add(m[1]);
  return [...achados].sort();
}

/** Todo scripts/conferir-*.cjs presente no disco (inclui este arquivo). */
function conferidoresDoDisco(raiz) {
  const dir = path.join(raiz, 'scripts');
  return fs
    .readdirSync(dir)
    .filter((n) => /^conferir-.*\.cjs$/.test(n))
    .map((n) => `scripts/${n}`)
    .sort();
}

/** Todo vigias/*.md presente no disco. */
function vigiasDoDisco(raiz) {
  const dir = path.join(raiz, 'vigias');
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((n) => n.endsWith('.md'))
    .map((n) => `vigias/${n}`)
    .sort();
}

/** Lê a marca `@categoria: <valor>` nas primeiras ~20 linhas do arquivo. */
function lerMarca(caminhoAbs) {
  let conteudo;
  try {
    conteudo = fs.readFileSync(caminhoAbs, 'utf8');
  } catch (e) {
    return { erro: `arquivo não encontrado: ${e.message}` };
  }
  const linhas = conteudo.split(/\r?\n/).slice(0, 20);
  for (const linha of linhas) {
    const m = linha.match(/@categoria:\s*(\S+)/);
    if (m) return { valor: m[1] };
  }
  return { valor: null };
}

function conjuntoDaPeca(raiz) {
  const hooks = hooksDoManifesto(raiz);
  const conferidores = conferidoresDoDisco(raiz);
  const vigias = vigiasDoDisco(raiz);
  return [...hooks, ...conferidores, ...vigias];
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const raizIdx = args.indexOf('--raiz');
  const raiz = raizIdx >= 0 ? path.resolve(args[raizIdx + 1]) : resolverRaizPadrao();

  const pecas = conjuntoDaPeca(raiz);
  const resultado = [];
  for (const rel of pecas) {
    const abs = path.join(raiz, rel);
    const { valor, erro } = lerMarca(abs);
    let status;
    if (erro) status = { ok: false, motivo: erro };
    else if (!valor) status = { ok: false, motivo: 'sem marca @categoria' };
    else if (!CATEGORIAS_VALIDAS.has(valor)) status = { ok: false, motivo: `valor fora do vocabulário: "${valor}"` };
    else status = { ok: true, categoria: valor };
    resultado.push({ arquivo: rel, ...status });
  }

  const invalidas = resultado.filter((r) => !r.ok);

  if (json) {
    console.log(JSON.stringify({ total: resultado.length, invalidas: invalidas.length, pecas: resultado }, null, 2));
    process.exit(invalidas.length ? 1 : 0);
  }

  for (const r of resultado) {
    if (r.ok) console.log(`  ${r.arquivo}  ->  ${r.categoria}`);
    else console.log(`  ${r.arquivo}  ->  RECUSADO (${r.motivo})`);
  }

  console.log(`\nTotal de peças varridas: ${resultado.length}`);

  if (invalidas.length) {
    console.log(`\nRECUSADO — ${invalidas.length} peça(s) sem marca válida:`);
    for (const r of invalidas) console.log(`  ${r.arquivo}  (${r.motivo})`);
    process.exit(1);
  }

  console.log('CONFERIDO — toda peça carrega marca válida (guia, sensor ou dado).');
  process.exit(0);
}

if (require.main === module) main();
module.exports = { hooksDoManifesto, conferidoresDoDisco, vigiasDoDisco, lerMarca, CATEGORIAS_VALIDAS };
