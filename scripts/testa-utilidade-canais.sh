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
  // D2 (assunto-regua): o termo que o pedido 1 ja citou sai da conta; so o que o
  // pedido 1 NAO citou e o prompt2 traz pode pontuar. Pedido 1 cita o primeiro
  // raro; prompt2 cita o segundo.
  const [raro1, raro2] = OBS.pedido.raro.split(' ');
  const f = montarTres('t-d8b', { ab: [], pe: [OBS.pedido.linha], su: [], prompt1: 'trate de ' + raro1, prompt2: 'agora aprofunde ' + raro2, toolFilho: null });
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

caso('servida do canal assunto cortada em 300 caracteres casa com o id', () => {
  const raro = 'zzrarocortadaum zzrarocortadados';
  const longo = 'palavra'.repeat(1) + ' ' + Array.from({ length: 80 }, (_, i) => 'trecho' + i).join(' ');
  const conteudo = 'titulo cortada corpusfiller\nsubtitulo ' + longo + ' ' + raro;
  const criada = '2026-10-05T12:00:00.000Z';
  const r = ins.run(PROJ, conteudo, criada, 'obs-cortada');
  const id = Number(r.lastInsertRowid);
  const obs = { conteudo, projeto: PROJ, criada_em: criada };
  const cortada = formatarObservacao(obs, null, 300);
  const inteira = formatarObservacao(obs, null);
  afirma(inteira.length > 300 && cortada !== inteira && cortada.endsWith('…'), 'precondicao: linha deveria ser cortada em ...');
  const f = montarTres('t-cortada', { ab: [], pe: [cortada], su: [], prompt1: 'trate de ' + raro, prompt2: 'agora aprofunde ' + raro, toolFilho: null });
  rodar('s-cortada', f);
  const servidas = linhasUso('s-cortada');
  const todas = db.prepare('SELECT ref_id, servida, nota, canal FROM uso_memoria WHERE sessao = ? AND ref_id = ?').all('s-cortada', id);
  console.log('  saida: ' + JSON.stringify(todas));
  afirma(servidas.length === 1 && servidas[0].ref_id === id, 'servida cortada deveria casar com o id ' + id + ', veio ' + JSON.stringify(servidas));
  afirma(servidas[0].canal === 'pedido' && typeof servidas[0].nota === 'number', 'canal pedido com nota numerica');
  afirma(todas.every((x) => x.servida === 1), 'nao pode reaparecer com servida = 0: ' + JSON.stringify(todas));
});

// ---- tarefa 7: buscas ativas (D9) e regua D7 ----
const { execFileSync } = require('child_process');

// linha assistant real (copiada do pai) com um unico bloco; so o bloco muda
function linhaAssistant(bloco) {
  const a = JSON.parse(PAI[0]);
  a.message.content = [bloco];
  delete a.wireToolInputs;
  return JSON.stringify(a);
}
const toolBash = (cmd) => linhaAssistant({ type: 'tool_use', id: 'toolu_x' + cmd.length, name: 'Bash', input: { command: cmd } });

// banco de regua: nSess sessoes, cada uma com 1 servida (canal rotativo); as
// primeiras nUtil tem nota 0.8 (util), as demais 0.1; as primeiras nPerda tem
// tambem uma nao-servida com nota 0.95 (acima da melhor servida => perda).
// Perda e util sao independentes (nUtil/nPerda contam a partir do indice 0 e
// do fim, respectivamente), para provar que a regua olha as DUAS fracoes.
// As linhas de uso_memoria nascem no mesmo instante da sessao (pontuarSessao
// grava as duas juntas); a primeira sessao serve pelo canal pedido, entao a
// janela da regua D7 cobre as nSess. A opcao antigas acrescenta sessoes so de
// abertura ANTES do canal novo existir (dia 2026-10-07), uteis e sem perda.
function bancoRegua(nome, nSess, nUtil, nPerda, opcoes) {
  const { antigas = 0, soAbertura = false } = opcoes || {};
  const dir = path.join(CAIXA, nome);
  fs.mkdirSync(dir, { recursive: true });
  const b = new DatabaseSync(path.join(dir, 'rainforest.db'));
  criarSchema(b);
  const canais = soAbertura ? ['abertura'] : ['pedido', 'abertura', 'subagente'];
  const iU = b.prepare('INSERT INTO uso_memoria (origem, ref_id, sessao, servida, nota, pontuada_em, canal) VALUES (?,?,?,?,?,?,?)');
  const iS = b.prepare('INSERT INTO uso_memoria_sessoes (sessao, pontuada_em, buscas_principal, buscas_subagente, subagentes) VALUES (?,?,?,?,?)');
  const esperado = { abertura: [0, 0], pedido: [0, 0], subagente: [0, 0] };
  for (let i = 0; i < antigas; i++) {
    const t = '2026-10-07T00:00:' + String(i % 60).padStart(2, '0') + '.000Z';
    iU.run('observacao', 1, 'old' + i, 1, 0.8, t, 'abertura');
    iS.run('old' + i, t, 0, 0, 0);
    esperado.abertura[1]++;
    esperado.abertura[0]++;
  }
  for (let i = 0; i < nSess; i++) {
    const s = 's' + i, canal = canais[i % canais.length], util = i < nUtil;
    const t = '2026-10-08T00:00:' + String(i % 60).padStart(2, '0') + '.000Z';
    iU.run('observacao', 1, s, 1, util ? 0.8 : 0.1, t, canal);
    if (i >= nSess - nPerda) iU.run('observacao', 2, s, 0, 0.95, t, 'abertura');
    iS.run(s, t, i % 2 === 0 ? 1 : 0, i % 4 === 0 ? 1 : 0, i % 4 === 0 ? 1 : 0);
    esperado[canal][1]++;
    if (util) esperado[canal][0]++;
  }
  b.close();
  return { dir, esperado };
}
function relatorioCli(dir) {
  // pelo comando real, apontando a raiz de dados para a caixa (nunca o banco real)
  return execFileSync(process.execPath, ['--no-warnings', SRC + '/scripts/memoria.cjs', 'utilidade', '--relatorio'], {
    env: Object.assign({}, process.env, { RFM_ROOT: dir }), cwd: dir, encoding: 'utf8',
  });
}
const ultima = (txt) => txt.trimEnd().split('\n').pop();

function casoRegua(titulo, nUtil, nPerda, veredito) {
  caso('regua D7 exige as duas condicoes: ' + titulo, () => {
    const { dir } = bancoRegua('regua-' + nUtil + '-' + nPerda, 20, nUtil, nPerda);
    const txt = relatorioCli(dir);
    console.log(txt.trimEnd().split('\n').map((l) => '  | ' + l).join('\n'));
    afirma(ultima(txt).indexOf('régua D7: ' + veredito + ' o canal do assunto') === 0, 'ultima linha: ' + ultima(txt));
    afirma(U.REGUA_D7.util === 0.4 && U.REGUA_D7.perda === 1 / 3, 'REGUA_D7 exportada com os limites do design');
  });
}
casoRegua('45% util + 50% perdas -> SAI', 9, 10, 'SAI');
casoRegua('45% util + 30% perdas -> FICA', 9, 6, 'FICA');
casoRegua('35% util + 20% perdas -> SAI', 7, 4, 'SAI');

caso('regua D7 sem sessao do canal novo diz sem dado, nunca FICA', () => {
  const { dir } = bancoRegua('regua-so-abertura', 20, 20, 0, { soAbertura: true });
  const txt = relatorioCli(dir);
  afirma(ultima(txt).indexOf('régua D7: sem dado do canal do assunto') === 0, 'ultima linha: ' + ultima(txt));
});

caso('regua D7 conta so a janela desde o canal novo', () => {
  // 30 sessoes antigas, todas uteis, puxariam 7/20 (35%, SAI) para 37/50 (74%, FICA)
  const { dir } = bancoRegua('regua-janela', 20, 7, 4, { antigas: 30 });
  const txt = relatorioCli(dir);
  afirma(txt.indexOf('janela da régua D7: 20 sessão(ões)') >= 0, 'janela deveria ter 20 sessoes');
  afirma(ultima(txt).indexOf('régua D7: SAI o canal do assunto') === 0, 'ultima linha: ' + ultima(txt));
});

caso('relatorio traz uma linha por canal, a base e as duas fracoes', () => {
  const { dir, esperado } = bancoRegua('regua-linhas', 20, 9, 6);
  const txt = relatorioCli(dir);
  for (const c of ['abertura', 'pedido', 'subagente']) {
    const [x, y] = esperado[c];
    const pct = Math.round((100 * x) / y);
    const alvo = 'canal ' + c + ': sessões com servida útil ' + x + ' de ' + y + ' (' + pct + '%)';
    afirma(txt.indexOf(alvo) >= 0, 'faltou "' + alvo + '"');
  }
  afirma(txt.indexOf('base 2026-10-08: 27% útil') >= 0 && txt.indexOf('base 2026-10-08: 171 de 255 com perda') >= 0, 'faltou a base de 2026-10-08');
  afirma(txt.indexOf('buscas ativas: 10 sessão(ões) principal(is) de 20, 5 subagente(s) de 5') >= 0, 'buscas ativas no relatorio');
  afirma(txt.indexOf('em qualquer canal: 9 de 20 (45%)') >= 0, 'fracao util');
  afirma(txt.indexOf('sessões com perda: 6 de 20 (30%)') >= 0, 'fracao perda');
  const linhas = txt.trimEnd().split('\n');
  afirma(/^régua D7/.test(linhas[linhas.length - 1]) && /^sessões com perda/.test(linhas[linhas.length - 2]), 'ordem: as duas fracoes imediatamente antes da regua D7');
});

caso('buscas ativas conta 2 no principal e 1 no subagente', () => {
  const f = escreverTranscrito('t-busca', [
    linhaUser('procure algo'),
    toolBash('node scripts/memoria.cjs buscar --texto alfa'),
    toolBash('cd x && node scripts/memoria.cjs buscar --texto beta'),
    toolBash('echo nada a ver'),
    linhaAssistant({ type: 'text', text: 'poderia rodar memoria.cjs buscar mas so estou falando' }),
  ]);
  const dir = f.replace(/\.jsonl\$/, '') + '/subagents';
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'agent-' + AGENT_ID + '.jsonl'), [FILHO, toolBash('node scripts/memoria.cjs buscar --texto gama')].join('\n') + '\n');
  const b = U.contarBuscas(f);
  console.log('  saida: contarBuscas=' + JSON.stringify(b));
  afirma(b.buscasPrincipal === 2 && b.buscasSubagente === 1 && b.subagentes === 1, 'contagem errada');
  rodar('s-busca', f);
  const l = db.prepare('SELECT buscas_principal, buscas_subagente, subagentes FROM uso_memoria_sessoes WHERE sessao = ?').get('s-busca');
  console.log('  saida: linha gravada=' + JSON.stringify(l));
  afirma(l.buscas_principal === 2 && l.buscas_subagente === 1 && l.subagentes === 1, 'gravacao errada');
  const semBusca = escreverTranscrito('t-sembusca', [linhaUser('nada'), toolBash('echo oi')]);
  rodar('s-sembusca', semBusca);
  const z = db.prepare('SELECT buscas_principal, buscas_subagente, subagentes FROM uso_memoria_sessoes WHERE sessao = ?').get('s-sembusca');
  afirma(z.buscas_principal === 0 && z.buscas_subagente === 0 && z.subagentes === 0, 'sessao sem busca deveria gravar zeros');
});

caso('migracao das colunas de buscas preserva linhas', () => {
  const dbVelho = new DatabaseSync(path.join(CAIXA, 'velho2.db'));
  dbVelho.exec('CREATE TABLE uso_memoria_sessoes (sessao TEXT PRIMARY KEY, pontuada_em TEXT NOT NULL)');
  dbVelho.prepare('INSERT INTO uso_memoria_sessoes VALUES (?, ?)').run('sv', '2026-01-01T00:00:00.000Z');
  const antes = dbVelho.prepare('PRAGMA table_info(uso_memoria_sessoes)').all().map((c) => c.name);
  criarSchema(dbVelho);
  criarSchema(dbVelho); // idempotente
  const depois = dbVelho.prepare('PRAGMA table_info(uso_memoria_sessoes)').all().map((c) => c.name);
  const linhas = dbVelho.prepare('SELECT * FROM uso_memoria_sessoes').all().map((r) => Object.assign({}, r));
  console.log('  saida: antes=' + JSON.stringify(antes) + ' depois=' + JSON.stringify(depois) + ' linhas=' + JSON.stringify(linhas));
  afirma(!antes.includes('buscas_principal'), 'banco antigo deveria nascer sem a coluna');
  afirma(['buscas_principal', 'buscas_subagente', 'subagentes'].every((n) => depois.includes(n)), 'colunas novas ausentes');
  afirma(linhas.length === 1 && linhas[0].sessao === 'sv' && linhas[0].buscas_principal === null, 'linha antiga perdida ou alterada');
  dbVelho.close();
});

caso('PRAGMA table_info(uso_memoria_sessoes) sem coluna de texto nova', () => {
  const cols = db.prepare('PRAGMA table_info(uso_memoria_sessoes)').all();
  console.log('  saida: ' + JSON.stringify(cols.map((c) => c.name + ':' + c.type)));
  const textos = cols.filter((c) => /TEXT/i.test(c.type)).map((c) => c.name).sort();
  afirma(JSON.stringify(textos) === JSON.stringify(['pontuada_em', 'sessao']), 'coluna TEXT inesperada: ' + textos);
  const novas = cols.filter((c) => ['buscas_principal', 'buscas_subagente', 'subagentes'].includes(c.name));
  afirma(novas.length === 3 && novas.every((c) => c.type === 'INTEGER'), 'as tres colunas novas deveriam ser INTEGER');
});

// ---- tarefa 14: apelido, contagem so de Bash/PowerShell, corte por mais:, ordem do attachment ----
function comCwd(f, cwd) {
  const novas = fs.readFileSync(f, 'utf8').split('\n').filter(Boolean).map((l) => {
    const o = JSON.parse(l);
    if (o.cwd) o.cwd = cwd;
    return JSON.stringify(o);
  });
  fs.writeFileSync(f, novas.join('\n') + '\n');
}

caso('servida do assunto com projeto pelo nome do harness casa com o id mesmo com apelido', () => {
  const repo = path.join(CAIXA, 'repo-curto');
  fs.mkdirSync(repo, { recursive: true });
  execFileSync('git', ['init', '-q', repo]);
  const raroL = 'zzraroapelidolongo zzraroapelidolongodois';
  const raroC = 'zzraroapelidocurto zzraroapelidocurtodois';
  const criada = '2026-10-05T12:00:00.000Z';
  const longo = Array.from({ length: 80 }, (_, i) => 'trecho' + i).join(' ');
  const conteudoL = 'titulo apelidolongo corpusfiller\nsubtitulo ' + longo + ' ' + raroL;
  const conteudoC = 'titulo apelidocurto corpusfiller\nsubtitulo curto ' + raroC;
  const f = montarTres('t-apelido', { ab: [], pe: [], su: [], prompt1: 'trate de ' + raroL + ' e ' + raroC, prompt2: 'agora aprofunde ' + raroL + ' e ' + raroC, toolFilho: null });
  comCwd(f, repo);
  const { harnessKey, curto } = U.lerProjetoDoTranscrito(f);
  afirma(harnessKey && curto && harnessKey !== curto, 'precondicao: sessao deveria ter apelido, veio ' + harnessKey + ' / ' + curto);
  const idL = Number(ins.run(harnessKey, conteudoL, criada, 'obs-apelido-l').lastInsertRowid);
  const idC = Number(ins.run(harnessKey, conteudoC, criada, 'obs-apelido-c').lastInsertRowid);
  const obsL = { conteudo: conteudoL, projeto: harnessKey, criada_em: criada };
  const obsC = { conteudo: conteudoC, projeto: harnessKey, criada_em: criada };
  const linhaL = formatarObservacao(obsL, null, 300);
  const linhaC = formatarObservacao(obsC, null, 300);
  afirma(linhaL.endsWith('…') && linhaL !== formatarObservacao(obsL, null) && linhaL.indexOf('(' + harnessKey + ')') !== -1, 'precondicao: linha longa cortada e com projeto cru');
  const g = montarTres('t-apelido2', { ab: [], pe: [linhaL, linhaC], su: [], prompt1: 'trate de ' + raroL + ' e ' + raroC, prompt2: 'agora aprofunde ' + raroL + ' e ' + raroC, toolFilho: null });
  comCwd(g, repo);
  rodar('s-apelido', g);
  const todas = db.prepare('SELECT ref_id, servida, nota, canal FROM uso_memoria WHERE sessao = ? AND ref_id IN (?, ?) ORDER BY ref_id').all('s-apelido', idL, idC);
  console.log('  saida: ' + JSON.stringify(todas));
  afirma(todas.length === 2 && todas.every((x) => x.servida === 1 && x.canal === 'pedido'), 'as duas servidas (longa cortada e curta) deveriam casar com o id: ' + JSON.stringify(todas));
});

caso('buscas ativas ignora Agent, Write e Edit que citam o comando e conta Bash e PowerShell que o executam', () => {
  const cita = 'rode node scripts/memoria.cjs buscar --texto alfa';
  const f = escreverTranscrito('t-busca-cita', [
    linhaUser('procure'),
    linhaAssistant({ type: 'tool_use', id: 'toolu_ag', name: 'Agent', input: { description: 'x', prompt: cita } }),
    linhaAssistant({ type: 'tool_use', id: 'toolu_wr', name: 'Write', input: { file_path: 'a.md', content: cita } }),
    linhaAssistant({ type: 'tool_use', id: 'toolu_ed', name: 'Edit', input: { file_path: 'a.md', old_string: 'a', new_string: cita } }),
  ]);
  const antes = U.contarBuscas(f);
  console.log('  saida: citando=' + JSON.stringify(antes));
  afirma(antes.buscasPrincipal === 0, 'Agent/Write/Edit citando deveria contar 0, contou ' + antes.buscasPrincipal);
  const g = escreverTranscrito('t-busca-exec', [
    linhaUser('procure'),
    linhaAssistant({ type: 'tool_use', id: 'toolu_ag', name: 'Agent', input: { prompt: cita } }),
    toolBash('node scripts/memoria.cjs buscar --texto beta'),
    linhaAssistant({ type: 'tool_use', id: 'toolu_ps', name: 'PowerShell', input: { command: 'node scripts/memoria.cjs buscar --texto gama' } }),
  ]);
  const depois = U.contarBuscas(g);
  console.log('  saida: executando=' + JSON.stringify(depois));
  afirma(depois.buscasPrincipal === 2, 'Bash e PowerShell executando deveriam contar 2, contou ' + depois.buscasPrincipal);
});

caso('bloco do assunto com jamais: no texto mantem as duas linhas inteiras', () => {
  const l1 = '[2026-10-05 (p)] decisao: jamais: apagar o banco — subtitulo longo';
  const l2 = '[2026-10-04 (p)] segunda linha que nao pode sumir';
  const r = U.extrairLinhasServidas(bloco([l1, l2]));
  console.log('  saida: ' + JSON.stringify(r));
  afirma(r.length === 2 && r[0] === l1 && r[1] === l2, 'as duas linhas deveriam voltar inteiras');
  const ab = U.extrairLinhasServidas(blocoAbertura([l2]) + '\n[2026-10-03 (p)] depois do rodape');
  console.log('  saida: ' + JSON.stringify(ab));
  afirma(ab.length === 1 && ab[0] === l2, 'a abertura continua cortando no mais:');
});

caso('attachment antes ou depois da linha user do pedido da a mesma nota', () => {
  const p1 = 'trate de ' + OBS.pedido.raro;
  const p2 = 'agora so conversa sem o termo';
  const a = escreverTranscrito('t-ordem-a', [linhaSessionStart([]), linhaUser(p1), linhaPedido([OBS.pedido.linha]), linhaUser(p2)]);
  const b = escreverTranscrito('t-ordem-b', [linhaSessionStart([]), linhaPedido([OBS.pedido.linha]), linhaUser(p1), linhaUser(p2)]);
  rodar('s-ordem-a', a);
  rodar('s-ordem-b', b);
  const na = linhasUso('s-ordem-a').find((x) => x.ref_id === OBS.pedido.id);
  const nb = linhasUso('s-ordem-b').find((x) => x.ref_id === OBS.pedido.id);
  console.log('  saida: a=' + JSON.stringify(na) + ' b=' + JSON.stringify(nb));
  afirma(na && nb && na.canal === 'pedido' && nb.canal === 'pedido', 'as duas ordens deveriam gravar o canal pedido');
  afirma(na.nota === nb.nota && nb.nota === 0, 'mesma nota (0, o pedido nao pontua a propria injecao) nas duas ordens');
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
