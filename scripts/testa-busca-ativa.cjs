#!/usr/bin/env node
'use strict';
// @categoria: sensor
/**
 * Bateria da busca ativa como INSTRUCAO (D1 de docs/rainforest/design/2026-10-09-assunto-regua.md;
 * tarefa 1 do plano docs/rainforest/planos/2026-10-09-assunto-regua.md).
 *
 * Os transcritos sao MONTADOS a partir da linha `assistant` REAL de
 * scripts/fixtures/memoria-assunto/agente-pai.jsonl (linha 0, message.content[] com `tool_use`),
 * trocando so `name` e `input.command`. Quem conta e o `contarBuscas` real e quem grava e o
 * `pontuarSessao` real, sobre uma caixa criada pelo `criarSchema` real. Nunca toca ~/.rainforest.
 * Nenhum caso le o texto do fonte.
 *
 * Uso: node scripts/testa-busca-ativa.cjs
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const SRC = path.resolve(__dirname, '..');
const memoria = require(path.join(SRC, 'scripts', 'memoria.cjs'));
const { contarBuscas, pontuarSessao } = require(path.join(SRC, 'scripts', 'lib', 'utilidade.cjs'));

const PAI = fs
  .readFileSync(path.join(SRC, 'scripts', 'fixtures', 'memoria-assunto', 'agente-pai.jsonl'), 'utf8')
  .split('\n')
  .filter(Boolean);
const LINHA_REAL = JSON.parse(PAI[0]);
assert.ok(Array.isArray(LINHA_REAL.message.content) && LINHA_REAL.message.content[0].type === 'tool_use', 'fixture real sem tool_use');

let ok = 0;
let falhou = 0;
function caso(nome, fn) {
  try {
    fn();
    ok++;
    console.log(`ok  ${nome}`);
  } catch (e) {
    falhou++;
    console.log(`FALHA  ${nome}\n  ${String(e.message).split('\n')[0]}`);
  }
}

const tmp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'testa-busca-ativa-')));

// Uma linha `assistant` com um tool_use, derivada da linha real.
function linhaTool(name, command) {
  const l = JSON.parse(JSON.stringify(LINHA_REAL));
  l.message.content = [{ ...LINHA_REAL.message.content[0], name, input: { command } }];
  return JSON.stringify(l);
}
const linhaUser = (texto) => JSON.stringify({ type: 'user', message: { role: 'user', content: texto } });

const B = 'Bash';
const CONTAM = [
  [B, 'node scripts/memoria.cjs buscar --texto alfa'],
  [B, 'cd /c/repo && node scripts/memoria.cjs buscar --projeto alfa --json'],
  [B, 'RFM_ROOT=/tmp/caixa FOO=1 node ../scripts/memoria.cjs buscar --texto beta'],
  [B, 'git status; node scripts/memoria.cjs buscar --texto gama | head -5'],
  [B, 'ls\nnode scripts/memoria.cjs buscar --texto delta'],
  ['PowerShell', 'Set-Location C:\\repo; node scripts\\memoria.cjs buscar --texto eps'],
];
const HEREDOC_COMMIT = "git commit -F - <<'EOF'\nTitulo\n\nnode scripts/memoria.cjs buscar --texto zeta\nEOF";
const NAO_CONTAM = [
  [B, HEREDOC_COMMIT],
  [B, 'grep -rn "memoria.cjs buscar" docs/'],
  [B, 'echo "rode node scripts/memoria.cjs buscar"'],
  [B, 'node scripts/memoria.cjs backup'],
  [B, 'cat <<EOF > /tmp/x.md\nnode scripts/memoria.cjs buscar --texto eta\nEOF'],
  [B, "cat <<-'FIM'\nnode scripts/memoria.cjs buscar --texto teta\n\tFIM"],
];

// Transcrito principal de uma sessao em <caixa>/<sessao>.jsonl, com subagentes opcionais.
function montar(caixa, sessao, principal, filhos) {
  fs.mkdirSync(caixa, { recursive: true });
  const arquivo = path.join(caixa, `${sessao}.jsonl`);
  fs.writeFileSync(arquivo, principal.join('\n') + '\n');
  filhos.forEach((linhas, i) => {
    const dir = path.join(caixa, sessao, 'subagents');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, `agent-a${i + 1}.jsonl`), linhas.join('\n') + '\n');
  });
  return arquivo;
}

let n = 0;
for (const [name, cmd] of CONTAM) {
  caso(`conta como busca: ${JSON.stringify(cmd).slice(0, 70)}`, () => {
    const t = montar(path.join(tmp, `c${n++}`), 's1', [linhaTool(name, cmd)], []);
    assert.deepStrictEqual(contarBuscas(t), { buscasPrincipal: 1, buscasSubagente: 0, subagentes: 0 });
  });
}
for (const [name, cmd] of NAO_CONTAM) {
  caso(`nao conta como busca: ${JSON.stringify(cmd).slice(0, 70)}`, () => {
    const t = montar(path.join(tmp, `n${n++}`), 's1', [linhaTool(name, cmd)], []);
    assert.deepStrictEqual(contarBuscas(t), { buscasPrincipal: 0, buscasSubagente: 0, subagentes: 0 });
  });
}

const CAIXA = path.join(tmp, 'caixa');
const filhoLinhas = () => [
  linhaTool(B, 'node scripts/memoria.cjs buscar --texto k1'),
  linhaTool(B, 'cd /c/repo && node scripts/memoria.cjs buscar --projeto alfa'),
  linhaTool(B, HEREDOC_COMMIT),
  linhaUser('rode node scripts/memoria.cjs buscar --texto citado'),
];
const principalLinhas = () => [
  ...CONTAM.map(([name, cmd]) => linhaTool(name, cmd)),
  ...NAO_CONTAM.map(([name, cmd]) => linhaTool(name, cmd)),
  linhaUser('node scripts/memoria.cjs buscar --texto so-citado-pelo-usuario'),
];

caso('sessao completa: 12 tool_use no principal, 3 num subagente (principal 6, subagente 2, subagentes 1)', () => {
  const t = montar(CAIXA, 's1', principalLinhas(), [filhoLinhas()]);
  const tools = principalLinhas().filter((l) => JSON.parse(l).type === 'assistant');
  assert.strictEqual(tools.length, 12);
  assert.deepStrictEqual(contarBuscas(t), { buscasPrincipal: 6, buscasSubagente: 2, subagentes: 1 });
});

caso('heredoc que cita o comando, passando por pontuarSessao real, grava buscas_principal = 0', () => {
  const dir = path.join(tmp, 'raiz');
  fs.mkdirSync(dir, { recursive: true });
  const db = new DatabaseSync(path.join(dir, 'rainforest.db'));
  try {
    memoria.criarSchema(db);
    const t = montar(CAIXA, 's2', [linhaTool(B, HEREDOC_COMMIT)], []);
    pontuarSessao(db, 's2', t);
    const r = db.prepare("SELECT buscas_principal, buscas_subagente, subagentes FROM uso_memoria_sessoes WHERE sessao = 's2'").get();
    assert.deepStrictEqual({ ...r }, { buscas_principal: 0, buscas_subagente: 0, subagentes: 0 });
  } finally {
    db.close();
  }
});

try {
  fs.rmSync(tmp, { recursive: true, force: true });
} catch (e) {
  // limpeza best-effort
}

console.log(`\n${ok} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
