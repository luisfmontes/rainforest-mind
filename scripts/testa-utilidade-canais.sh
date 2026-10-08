#!/bin/bash
# Bateria dos canais de servida (memória por assunto) em scripts/lib/utilidade.cjs.
# Design: docs/rainforest/design/2026-10-08-memoria-por-assunto.md (D8, D10)
# Plano:  docs/rainforest/planos/2026-10-08-memoria-por-assunto.md, tarefa 6
# Uso: bash scripts/testa-utilidade-canais.sh
#
# O que prova, caso a caso:
#   - extrairSessao devolve as servidas dos 3 canais (abertura, pedido, subagente);
#   - pontuarSessao grava a coluna `canal` certa em uso_memoria;
#   - D8: a nota do canal `pedido` exclui o pedido que disparou a injeção (e
#     passa a > 0 quando um pedido POSTERIOR contém os termos raros);
#   - o canal `subagente` é pontuado pelos tool_use do transcrito do filho,
#     nunca pelo briefing;
#   - banco antigo sem a coluna migra sem perder linha (lê `abertura`);
#   - nenhuma coluna de texto livre nova em uso_memoria (D10);
#   - a mesma memória em dois canais grava uma vez, abertura > pedido > subagente.
#
# HERMÉTICA: banco criado pelo `criarSchema` real numa caixa `mktemp -d`; os
# transcritos são MONTADOS a partir das linhas das fixtures reais do harness
# (scripts/fixtures/memoria-assunto/*.jsonl) trocando só o texto do bloco —
# nada é inventado fora disso, salvo a linha assistant do filho (copiada da
# linha assistant do pai, só com `input` trocado) e as linhas user/SessionStart
# do fixture sintético scripts/fixtures/utilidade/transcrito-sessao.jsonl.
# Nunca toca ~/.rainforest nem o banco real.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_WIN="$(cygpath -m "$SRC" 2>/dev/null || printf '%s' "$SRC")"

SANDBOXES=()
novo_sandbox() { local d; d=$(mktemp -d); SANDBOXES+=("$d"); echo "$d"; }
cleanup() { for dir in "${SANDBOXES[@]}"; do rm -rf "$dir" 2>/dev/null || true; done; }
trap cleanup EXIT

CAIXA="$(novo_sandbox)"
CAIXA_WIN="$(cygpath -m "$CAIXA" 2>/dev/null || printf '%s' "$CAIXA")"

cat > "$CAIXA/casos.cjs" <<EOF
'use strict';
const fs = require('fs');
const path = require('path');
const SRC = '$SRC_WIN';
const CAIXA = '$CAIXA_WIN';
const { DatabaseSync } = require('node:sqlite');
const { criarSchema } = require(SRC + '/scripts/memoria.cjs');
const { formatarObservacao } = require(SRC + '/hooks/lib/memoria-sessao.cjs');
const U = require(SRC + '/scripts/lib/utilidade.cjs');

const FIX = SRC + '/scripts/fixtures/memoria-assunto/';
const lerLinhas = (f) => fs.readFileSync(f, 'utf8').split('\n').filter(Boolean);
const PEDIDO = lerLinhas(FIX + 'prompt-submit.jsonl')[0];
const PAI = lerLinhas(FIX + 'agente-pai.jsonl'); // 0 assistant Agent, 1 hook_success, 2 user/toolUseResult
const FILHO = lerLinhas(FIX + 'agente-filho.jsonl')[0];
const SINT = lerLinhas(SRC + '/scripts/fixtures/utilidade/transcrito-sessao.jsonl').map((l) => JSON.parse(l));
const SESSION_START = SINT.find((o) => o.type === 'attachment' && o.attachment.hookEvent === 'SessionStart');
const USER_PROMPT = SINT.find((o) => o.type === 'user' && typeof o.message.content === 'string');

// ---- banco: criarSchema real + observações sintéticas ----
const PROJ = 'proj-canais';
const OBS = {
  abertura: { t: 'abertura', raro: 'zzraroaberturaum zzraroaberturadois' },
  pedido: { t: 'pedido', raro: 'zzraropedidoum zzraropedidodois' },
  subagente: { t: 'subagente', raro: 'zzrarosubagum zzrarosubagdois' },
  dupla: { t: 'dupla', raro: 'zzraroduplaum zzraroduplados' },
};
const caminhoDb = path.join(CAIXA, 'rainforest.db');
const db = new DatabaseSync(caminhoDb);
criarSchema(db);
const ins = db.prepare('INSERT INTO observacoes (projeto, conteudo, criada_em, origem) VALUES (?, ?, ?, ?)');
let n = 0;
for (const k of Object.keys(OBS)) {
  const o = OBS[k];
  o.conteudo = 'titulo ' + o.t + ' corpusfiller\nsubtitulo ' + o.t + ' ' + o.raro;
  o.criada = '2026-10-05T12:00:00.000Z';
  const r = ins.run(PROJ, o.conteudo, o.criada, 'obs-' + k);
  o.id = Number(r.lastInsertRowid);
  o.linha = formatarObservacao({ conteudo: o.conteudo, projeto: PROJ, criada_em: o.criada }, null);
  n++;
}
// filler: garante df(titulo/subtitulo/corpusfiller) > LIMIAR_DF, para só os raros pontuarem
for (let i = 0; i < 4; i++) ins.run(PROJ, 'titulo filler' + i + ' corpusfiller\nsubtitulo filler' + i + ' fillerrarox' + i, '2026-10-01T09:0' + i + ':00.000Z', 'filler-' + i);

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
// attachment real do UserPromptSubmit: só o texto do bloco muda
function linhaPedido(linhas) {
  const marca = 'contexto de teste MARCA-ASSUNTO-7f3 fim';
  if (!PEDIDO.includes(marca)) throw new Error('fixture prompt-submit sem a marca esperada');
  return PEDIDO.split(marca).join(esc(bloco(linhas)));
}
// pai real: user/toolUseResult.prompt recebe o bloco no lugar da marca
function linhasPai(linhas) {
  const user = JSON.parse(PAI[2]);
  if (!user.toolUseResult.prompt.includes('MARCA-AGENTE-9c1')) throw new Error('fixture agente-pai sem a marca esperada');
  user.toolUseResult.prompt = user.toolUseResult.prompt.replace('MARCA-AGENTE-9c1', () => bloco(linhas));
  return [PAI[0], PAI[1], JSON.stringify(user)];
}
const AGENT_ID = JSON.parse(PAI[2]).toolUseResult.agentId;
// filho real: primeira linha user com o briefing já acrescido do bloco; opcionalmente
// uma linha assistant (copiada da do pai) com tool_use.input = textoTool
function escreverFilho(transcrito, linhas, textoTool) {
  const dir = transcrito.replace(/\.jsonl\$/, '') + '/subagents';
  fs.mkdirSync(dir, { recursive: true });
  const f = JSON.parse(FILHO);
  f.message.content = f.message.content.replace('MARCA-AGENTE-9c1', () => bloco(linhas));
  const saida = [JSON.stringify(f)];
  if (textoTool !== null) {
    const a = JSON.parse(PAI[0]);
    a.isSidechain = true;
    a.agentId = AGENT_ID;
    a.message.content[0].name = 'Bash';
    a.message.content[0].input = { command: textoTool };
    delete a.wireToolInputs;
    saida.push(JSON.stringify(a));
  }
  fs.writeFileSync(path.join(dir, 'agent-' + AGENT_ID + '.jsonl'), saida.join('\n') + '\n');
}
function escreverTranscrito(nome, partes) {
  const f = path.join(CAIXA, nome + '.jsonl');
  fs.writeFileSync(f, partes.flat().join('\n') + '\n');
  return f;
}
// transcrito completo dos 3 canais
function montarTres(nome, { ab, pe, su, prompt1, prompt2, toolFilho }) {
  const partes = [linhaSessionStart(ab), linhaUser(prompt1), linhaPedido(pe)];
  if (prompt2) partes.push(linhaUser(prompt2));
  partes.push(...linhasPai(su));
  const f = escreverTranscrito(nome, partes);
  escreverFilho(f, su, toolFilho);
  return f;
}

const linhasUso = (sessao) => db.prepare('SELECT origem, ref_id, servida, nota, canal FROM uso_memoria WHERE sessao = ? AND servida = 1 ORDER BY ref_id').all(sessao);
const rodar = (sessao, f) => { db.exec('DELETE FROM uso_memoria WHERE sessao = \'' + sessao + '\''); return U.pontuarSessao(db, sessao, f); };

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);
const afirma = (cond, msg) => { if (!cond) throw new Error(msg); };

caso('extrai as servidas dos 3 canais', () => {
  const f = montarTres('t-extrai', { ab: [OBS.abertura.linha], pe: [OBS.pedido.linha], su: [OBS.subagente.linha], prompt1: 'um pedido qualquer', toolFilho: 'echo nada' });
  const r = U.extrairSessao(f);
  const por = (c) => r.servidasCanal.filter((s) => s.canal === c).map((s) => s.linha);
  console.log('  saida: ' + JSON.stringify(r.servidasCanal.map((s) => [s.canal, s.linha])));
  afirma(JSON.stringify(por('abertura')) === JSON.stringify([OBS.abertura.linha]), 'abertura: ' + JSON.stringify(por('abertura')));
  afirma(JSON.stringify(por('pedido')) === JSON.stringify([OBS.pedido.linha]), 'pedido: ' + JSON.stringify(por('pedido')));
  afirma(JSON.stringify(por('subagente')) === JSON.stringify([OBS.subagente.linha]), 'subagente: ' + JSON.stringify(por('subagente')));
  afirma(r.servidas.length === 3, 'servidas (formato antigo) deveria listar as 3 linhas, veio ' + r.servidas.length);
});

caso('grava a coluna canal certa em uso_memoria', () => {
  const f = montarTres('t-grava', { ab: [OBS.abertura.linha], pe: [OBS.pedido.linha], su: [OBS.subagente.linha], prompt1: 'um pedido qualquer', toolFilho: 'echo nada' });
  rodar('s-grava', f);
  const l = linhasUso('s-grava');
  console.log('  saida: ' + JSON.stringify(l));
  const canalDe = (o) => (l.find((x) => x.ref_id === o.id) || {}).canal;
  afirma(l.length === 3, 'esperava 3 linhas servidas, veio ' + l.length);
  afirma(canalDe(OBS.abertura) === 'abertura' && canalDe(OBS.pedido) === 'pedido' && canalDe(OBS.subagente) === 'subagente', 'canais errados');
});

caso('nota do canal pedido exclui o pedido que disparou', () => {
  // o único casamento da servida com a sessão é o PRÓPRIO pedido que a disparou
  const f = montarTres('t-d8a', { ab: [], pe: [OBS.pedido.linha], su: [], prompt1: 'trate de ' + OBS.pedido.raro, toolFilho: null });
  rodar('s-d8a', f);
  const l = linhasUso('s-d8a');
  console.log('  saida: ' + JSON.stringify(l));
  afirma(l.length === 1 && l[0].canal === 'pedido', 'esperava 1 linha do canal pedido');
  afirma(l[0].nota === 0, 'nota deveria ser 0 (so o pedido casa), veio ' + l[0].nota);
});

caso('nota do canal pedido sobe com pedido posterior que contem os termos raros', () => {
  const f = montarTres('t-d8b', { ab: [], pe: [OBS.pedido.linha], su: [], prompt1: 'trate de ' + OBS.pedido.raro, prompt2: 'agora aprofunde ' + OBS.pedido.raro, toolFilho: null });
  rodar('s-d8b', f);
  const l = linhasUso('s-d8b');
  console.log('  saida: ' + JSON.stringify(l));
  afirma(l.length === 1 && l[0].nota > 0, 'nota deveria ser > 0, veio ' + JSON.stringify(l));
});

caso('subagente e pontuado pelo tool_use do filho, nao pelo briefing', () => {
  // o briefing do filho (e a linha) cita o assunto; só o tool_use conta
  const com = montarTres('t-sub-com', { ab: [], pe: [], su: [OBS.subagente.linha], prompt1: 'um pedido qualquer', toolFilho: 'grep ' + OBS.subagente.raro });
  rodar('s-sub-com', com);
  const sem = montarTres('t-sub-sem', { ab: [], pe: [], su: [OBS.subagente.linha], prompt1: 'um pedido qualquer', toolFilho: 'echo nada' });
  rodar('s-sub-sem', sem);
  const a = linhasUso('s-sub-com'), b = linhasUso('s-sub-sem');
  console.log('  saida: com tool_use=' + JSON.stringify(a) + ' sem=' + JSON.stringify(b));
  afirma(a.length === 1 && a[0].canal === 'subagente' && a[0].nota > 0, 'com tool_use deveria pontuar > 0');
  afirma(b.length === 1 && b[0].canal === 'subagente' && b[0].nota === 0, 'sem tool_use deveria ser 0');
});

caso('migracao de banco antigo sem a coluna preserva linhas e le abertura', () => {
  const dbVelho = new DatabaseSync(path.join(CAIXA, 'velho.db'));
  dbVelho.exec('CREATE TABLE uso_memoria (origem TEXT NOT NULL, ref_id INTEGER NOT NULL, sessao TEXT NOT NULL, servida INTEGER NOT NULL, nota REAL, pontuada_em TEXT NOT NULL, UNIQUE(origem, ref_id, sessao))');
  dbVelho.prepare('INSERT INTO uso_memoria VALUES (?,?,?,?,?,?)').run('observacao', 7, 'sv', 1, 0.5, '2026-01-01T00:00:00.000Z');
  const antes = dbVelho.prepare('PRAGMA table_info(uso_memoria)').all().some((c) => c.name === 'canal');
  criarSchema(dbVelho);
  criarSchema(dbVelho); // idempotente
  const linhas = dbVelho.prepare('SELECT ref_id, nota, canal FROM uso_memoria').all();
  console.log('  saida: tinha canal antes=' + antes + '; depois=' + JSON.stringify(linhas));
  afirma(antes === false, 'banco antigo deveria nascer sem canal');
  afirma(linhas.length === 1 && linhas[0].ref_id === 7 && linhas[0].nota === 0.5 && linhas[0].canal === 'abertura', 'linha antiga perdida ou sem abertura');
  dbVelho.close();
});

caso('PRAGMA table_info(uso_memoria) sem coluna de texto livre nova', () => {
  const cols = db.prepare('PRAGMA table_info(uso_memoria)').all();
  console.log('  saida: ' + JSON.stringify(cols.map((c) => c.name + ':' + c.type)));
  const permitidas = new Set(['origem', 'sessao', 'pontuada_em', 'canal']);
  const textos = cols.filter((c) => /TEXT/i.test(c.type)).map((c) => c.name);
  afirma(textos.every((t) => permitidas.has(t)), 'coluna TEXT inesperada: ' + textos);
  afirma(cols.some((c) => c.name === 'canal'), 'sem coluna canal');
});

caso('mesma memoria em dois canais grava uma vez, abertura > pedido > subagente', () => {
  const L = OBS.dupla.linha;
  const f1 = montarTres('t-dup1', { ab: [L], pe: [L], su: [L], prompt1: 'um pedido qualquer', toolFilho: 'echo nada' });
  rodar('s-dup1', f1);
  const f2 = montarTres('t-dup2', { ab: [], pe: [L], su: [L], prompt1: 'um pedido qualquer', toolFilho: 'echo nada' });
  rodar('s-dup2', f2);
  const f3 = montarTres('t-dup3', { ab: [], pe: [], su: [L], prompt1: 'um pedido qualquer', toolFilho: 'echo nada' });
  rodar('s-dup3', f3);
  const r1 = linhasUso('s-dup1'), r2 = linhasUso('s-dup2'), r3 = linhasUso('s-dup3');
  console.log('  saida: ' + JSON.stringify([r1, r2, r3]));
  afirma(r1.length === 1 && r1[0].canal === 'abertura', 'tres canais -> abertura');
  afirma(r2.length === 1 && r2[0].canal === 'pedido', 'pedido+subagente -> pedido');
  afirma(r3.length === 1 && r3[0].canal === 'subagente', 'so subagente -> subagente');
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
node --no-warnings "$CAIXA/casos.cjs"
exit $?
