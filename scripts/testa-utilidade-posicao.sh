#!/bin/bash
# Bateria da posição servida (D5) em scripts/lib/utilidade.cjs.
# Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-4.md (D5)
# Plano:  docs/rainforest/planos/2026-10-24-apoio-ao-dev-lote-4.md, tarefa 3
# Uso: bash scripts/testa-utilidade-posicao.sh
#
# O que prova, caso a caso:
#   - a terceira linha de um bloco de abertura grava posicao 3 (1, 2, 3 na ordem do bloco);
#   - o canal `pedido` conta a posição dentro de CADA injeção (cada bloco começa no 1);
#   - a mesma memória em dois canais grava a posição do canal que venceu (abertura);
#   - o briefing de subagente conta a posição dentro do seu bloco;
#   - banco antigo sem a coluna: a linha antiga fica com posicao nula e o relatório não quebra;
#   - `utilidade --relatorio` ganha a faixa 1-3 / 4-7 / 8+ sem ser ignorada nem mudar as linhas de hoje.
#
# HERMÉTICA: banco criado pelo `criarSchema` real numa caixa `mktemp -d`; os
# transcritos são MONTADOS a partir das fixtures reais de scripts/fixtures/memoria-assunto
# (trocando só o texto do bloco). Nunca toca ~/.rainforest nem o banco real.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

SANDBOXES=()
novo_sandbox() { local d; d=$(mktemp -d); SANDBOXES+=("$d"); echo "$d"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

CAIXA="$(novo_sandbox)"
CAIXA_WIN="$(cygpath -m "$CAIXA" 2>/dev/null || printf '%s' "$CAIXA")"

cat > "$CAIXA/casos.cjs" <<'EOF'
'use strict';
const fs = require('fs');
const path = require('path');
const SRC = process.env.SRC_WIN;
const CAIXA = process.env.CAIXA_WIN;
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(SRC + '/scripts/memoria.cjs');
const { formatarObservacao } = require(SRC + '/hooks/lib/memoria-sessao.cjs');
const U = require(SRC + '/scripts/lib/utilidade.cjs');

const FIX = SRC + '/scripts/fixtures/memoria-assunto/';
const lerLinhas = (f) => fs.readFileSync(f, 'utf8').split('\n').filter(Boolean);
const PEDIDO = lerLinhas(FIX + 'prompt-submit.jsonl')[0];
const PAI = lerLinhas(FIX + 'agente-pai.jsonl');
const FILHO = lerLinhas(FIX + 'agente-filho.jsonl')[0];
const SINT = lerLinhas(SRC + '/scripts/fixtures/utilidade/transcrito-sessao.jsonl').map((l) => JSON.parse(l));
const SESSION_START = SINT.find((o) => o.type === 'attachment' && o.attachment.hookEvent === 'SessionStart');
const USER_PROMPT = SINT.find((o) => o.type === 'user' && typeof o.message.content === 'string');

const PROJ = 'proj-posicao';
const caminhoDb = path.join(CAIXA, 'rainforest.db');
const db = new DatabaseSync(caminhoDb);
criarSchema(db);
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');

// Observações com termo raro próprio: a linha servida casa só com a sua.
const OBS = {};
for (const t of ['x', 'y', 'z', 'p1', 'p2', 'p3', 'dupla', 's1', 's2']) {
  const raro = 'zzrarops' + t + 'um zzrarops' + t + 'dois';
  const conteudo = 'titulo ' + t + ' corpusfiller\nsubtitulo ' + t + ' ' + raro;
  const criada = '2026-10-05T12:00:00.000Z';
  const r = ins.run(PROJ, conteudo, criada, 'obs-' + t);
  OBS[t] = { id: Number(r.lastInsertRowid), raro, linha: formatarObservacao({ conteudo, projeto: PROJ, criada_em: criada }, null) };
}
for (let i = 0; i < 4; i++) ins.run(PROJ, 'titulo filler' + i + ' corpusfiller\nsubtitulo filler' + i + ' fillerrarops' + i, '2026-10-01T09:0' + i + ':00.000Z', 'filler-' + i);

// ---- montagem de transcritos a partir das fixtures reais ----
const bloco = (linhas) => '## Memória do assunto\n' + linhas.join('\n') + '\n';
const blocoAbertura = (linhas) => '## Memória (corpus residentes)\n' + linhas.join('\n') + '\n\nmais: node scripts/memoria.cjs buscar --texto "<termo>"';
const esc = (s) => JSON.stringify(s).slice(1, -1);

function linhaSessionStart(linhas) {
  const o = JSON.parse(JSON.stringify(SESSION_START));
  o.attachment.stdout = JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: blocoAbertura(linhas) } });
  return JSON.stringify(o);
}
function linhaUser(texto) {
  const o = JSON.parse(JSON.stringify(USER_PROMPT));
  o.message.content = texto;
  return JSON.stringify(o);
}
function linhaPedido(linhas) {
  const marca = 'contexto de teste MARCA-ASSUNTO-7f3 fim';
  if (!PEDIDO.includes(marca)) throw new Error('fixture prompt-submit sem a marca esperada');
  return PEDIDO.split(marca).join(esc(bloco(linhas)));
}
function linhasPai(linhas) {
  const user = JSON.parse(PAI[2]);
  if (!user.toolUseResult.prompt.includes('MARCA-AGENTE-9c1')) throw new Error('fixture agente-pai sem a marca esperada');
  user.toolUseResult.prompt = user.toolUseResult.prompt.replace('MARCA-AGENTE-9c1', () => bloco(linhas));
  return [PAI[0], PAI[1], JSON.stringify(user)];
}
const AGENT_ID = JSON.parse(PAI[2]).toolUseResult.agentId;
function escreverFilho(transcrito, linhas) {
  const dir = transcrito.replace(/\.jsonl$/, '') + '/subagents';
  fs.mkdirSync(dir, { recursive: true });
  const f = JSON.parse(FILHO);
  f.message.content = f.message.content.replace('MARCA-AGENTE-9c1', () => bloco(linhas));
  fs.writeFileSync(path.join(dir, 'agent-' + AGENT_ID + '.jsonl'), JSON.stringify(f) + '\n');
}
function escreverTranscrito(nome, partes) {
  const f = path.join(CAIXA, nome + '.jsonl');
  fs.writeFileSync(f, partes.flat().join('\n') + '\n');
  return f;
}
// abertura: um bloco com as linhas dadas; pedidos: lista de [prompt, linhasDaInjecao]; subagente: linhas do briefing
function montar(nome, { ab = [], pedidos = [], su = [] }) {
  const partes = [];
  if (ab.length) partes.push(linhaSessionStart(ab));
  for (const [prompt, linhas] of pedidos) {
    partes.push(linhaUser(prompt));
    if (linhas.length) partes.push(linhaPedido(linhas));
  }
  if (su.length) partes.push(...linhasPai(su));
  const f = escreverTranscrito(nome, partes);
  if (su.length) escreverFilho(f, su);
  return f;
}

const posicoes = (sessao) => db.prepare('SELECT ref_id, canal, posicao FROM uso_memoria WHERE sessao = ? AND servida = 1 ORDER BY ref_id').all(sessao);
const rodar = (sessao, f) => { db.exec('DELETE FROM uso_memoria WHERE sessao = \'' + sessao + '\''); return U.pontuarSessao(db, sessao, f); };
const posDe = (sessao, obs) => (posicoes(sessao).find((r) => r.ref_id === obs.id) || {}).posicao;

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (cond, msg) => { if (!cond) throw new Error(msg); };

caso('a terceira linha do bloco grava posicao 3', () => {
  const f = montar('t-tres', { ab: [OBS.x.linha, OBS.y.linha, OBS.z.linha] });
  rodar('s-tres', f);
  const l = posicoes('s-tres');
  console.log('  saida: ' + JSON.stringify(l));
  afirma(posDe('s-tres', OBS.x) === 1, 'x deveria ser posicao 1, veio ' + posDe('s-tres', OBS.x));
  afirma(posDe('s-tres', OBS.y) === 2, 'y deveria ser posicao 2, veio ' + posDe('s-tres', OBS.y));
  afirma(posDe('s-tres', OBS.z) === 3, 'z deveria ser posicao 3, veio ' + posDe('s-tres', OBS.z));
});

caso('canal pedido: cada injecao conta a posicao do 1 dentro do proprio bloco', () => {
  const f = montar('t-pedido', { pedidos: [['pedido um', [OBS.p1.linha, OBS.p2.linha]], ['pedido dois', [OBS.p3.linha]]] });
  rodar('s-pedido', f);
  const l = posicoes('s-pedido');
  console.log('  saida: ' + JSON.stringify(l));
  afirma(l.every((r) => r.canal === 'pedido'), 'todas deveriam ser do canal pedido');
  afirma(posDe('s-pedido', OBS.p1) === 1 && posDe('s-pedido', OBS.p2) === 2, 'bloco 1: deveria ser 1 e 2');
  afirma(posDe('s-pedido', OBS.p3) === 1, 'bloco 2 (outra injeção) deveria recomeçar em 1, veio ' + posDe('s-pedido', OBS.p3));
});

caso('mesma memoria em dois canais grava a posicao do canal que venceu (abertura)', () => {
  // dupla é a 2ª linha do bloco de abertura e a 1ª do pedido: vence a abertura -> posicao 2
  const f = montar('t-venceu', { ab: [OBS.x.linha, OBS.dupla.linha], pedidos: [['pedido', [OBS.dupla.linha]]] });
  rodar('s-venceu', f);
  const l = posicoes('s-venceu');
  console.log('  saida: ' + JSON.stringify(l));
  const d = l.find((r) => r.ref_id === OBS.dupla.id);
  afirma(d && d.canal === 'abertura', 'canal deveria ser abertura, veio ' + JSON.stringify(d));
  afirma(d.posicao === 2, 'posicao deveria ser 2 (a do bloco da abertura), veio ' + d.posicao);
});

caso('briefing de subagente conta a posicao dentro do seu bloco', () => {
  const f = montar('t-sub', { su: [OBS.s1.linha, OBS.s2.linha] });
  rodar('s-sub', f);
  const l = posicoes('s-sub');
  console.log('  saida: ' + JSON.stringify(l));
  afirma(posDe('s-sub', OBS.s1) === 1 && posDe('s-sub', OBS.s2) === 2, 'subagente deveria gravar 1 e 2, veio ' + JSON.stringify(l));
});

caso('linha antiga sem posicao fica nula e o relatorio nao quebra', () => {
  // banco do esquema anterior: o SQL atual menos a linha `posicao INTEGER,`
  const sqlAtual = fs.readFileSync(SRC + '/scripts/esquema-memoria.sql', 'utf8');
  const sqlAntigo = sqlAtual.replace(/\n\s*posicao INTEGER,/, '');
  afirma(sqlAntigo !== sqlAtual, 'precondicao: a linha posicao deveria existir no esquema atual');
  const velho = new DatabaseSync(path.join(CAIXA, 'velho.db'));
  velho.exec(sqlAntigo);
  velho.prepare('INSERT INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em, canal) VALUES (?,?,?,?,?,?,?)')
    .run('observacao', 7, 'sv', 1, 0.5, '2026-01-01T00:00:00.000Z', 'abertura');
  velho.prepare('INSERT INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?,?)').run('sv', '2026-01-01T00:00:00.000Z');
  const relVelho = U.gerarRelatorio(velho); // somente leitura, antes da migração: não pode lançar
  console.log('  saida antes da migracao: ' + JSON.stringify(relVelho.split('\n').slice(-1)[0]));
  afirma(!/posição servida/.test(relVelho), 'sem a coluna, a faixa não deveria aparecer');
  criarSchema(velho);
  const linha = velho.prepare('SELECT ref_id, posicao FROM uso_memoria WHERE ref_id = 7').get();
  console.log('  saida depois da migracao: ' + JSON.stringify(linha));
  afirma(linha && linha.posicao === null, 'linha antiga deveria ficar com posicao nula, veio ' + JSON.stringify(linha));
  const rel = U.gerarRelatorio(velho);
  const faixa = rel.split('\n').find((l) => l.startsWith('nota média por posição servida')) || '';
  console.log('  saida faixa: ' + faixa);
  afirma(/nota média por posição servida: 1–3: — \(n=0\) · 4–7: — \(n=0\) · 8\+: — \(n=0\)/.test(faixa), 'linha antiga deveria ficar fora da faixa: ' + faixa);
  velho.close();
});

caso('relatorio ganha a faixa 1-3 / 4-7 / 8+ e mantem as linhas de hoje', () => {
  const rel = new DatabaseSync(path.join(CAIXA, 'rel.db'));
  criarSchema(rel);
  rel.prepare('INSERT INTO uso_memoria_sessoes (sessao, pontuada_em) VALUES (?,?)').run('sr', '2026-10-20T10:00:00.000Z');
  const ins2 = rel.prepare('INSERT INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em, canal, posicao) VALUES (?,?,?,?,?,?,?,?)');
  const t = '2026-10-20T10:00:00.000Z';
  ins2.run('observacao', 1, 'sr', 1, 0.2, t, 'abertura', 1);
  ins2.run('observacao', 2, 'sr', 1, 0.4, t, 'abertura', 2);
  ins2.run('observacao', 3, 'sr', 1, 0.6, t, 'abertura', 3);
  // bordas das faixas: 4 e 7 caem em 4–7, 8 cai em 8+
  ins2.run('observacao', 4, 'sr', 1, 0.9, t, 'abertura', 4);
  ins2.run('observacao', 7, 'sr', 1, 0.5, t, 'abertura', 7);
  ins2.run('observacao', 5, 'sr', 1, 0.1, t, 'abertura', 8);
  ins2.run('observacao', 6, 'sr', 1, 1.0, t, 'abertura', null);
  // servida sem nota fica fora da média (SQL_MEDIDA), mesmo com posição
  ins2.run('observacao', 8, 'sr', 1, null, t, 'abertura', 1);
  const comPosicao = U.gerarRelatorio(rel);
  const faixaComPosicao = comPosicao.split('\n').filter((l) => l.startsWith('nota média por posição servida'));
  console.log('  saida: ' + JSON.stringify(faixaComPosicao));
  afirma(faixaComPosicao.length === 1 && faixaComPosicao[0] === 'nota média por posição servida: 1–3: 0.40 (n=3) · 4–7: 0.70 (n=2) · 8+: 0.10 (n=1)',
    'faixa diferente do esperado: ' + JSON.stringify(faixaComPosicao));
  // as linhas de hoje não mudam: o mesmo banco com a posição apagada dá o mesmo texto, menos a faixa
  rel.exec('UPDATE uso_memoria SET posicao = NULL');
  const semPosicao = U.gerarRelatorio(rel);
  const tirarFaixa = (t) => t.split('\n').filter((l) => !l.startsWith('nota média por posição servida')).join('\n');
  const antes = tirarFaixa(comPosicao);
  const depois = tirarFaixa(semPosicao);
  console.log('  saida: linhas de hoje iguais = ' + (antes === depois) + '; ultima linha = ' + JSON.stringify(comPosicao.split('\n').pop()));
  afirma(antes === depois, 'as linhas que o relatório já imprimia mudaram com a posição');
  afirma(!comPosicao.split('\n').pop().startsWith('nota média'), 'a faixa não pode ser a última linha do relatório');
  rel.close();
});

let ok = 0, falha = 0;
for (const [nome, fn] of casos) {
  try {
    console.log('== ' + nome);
    fn();
    ok++;
    console.log('  ok   ' + nome);
  } catch (e) {
    falha++;
    console.log('  FALHA ' + nome + ': ' + e.message);
  }
}
db.close();
console.log('== resultado: ' + ok + ' ok, ' + falha + ' falha(s) ==');
process.exitCode = falha === 0 ? 0 : 1;
EOF

echo "  comando: node casos.cjs (caixa hermetica: criarSchema real + transcritos montados das fixtures memoria-assunto)"
SRC_WIN="$SRC_WIN" CAIXA_WIN="$CAIXA_WIN" node --no-warnings "$CAIXA/casos.cjs"
exit $?
