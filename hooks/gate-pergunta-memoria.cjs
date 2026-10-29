#!/usr/bin/env node
// @categoria: sensor
/**
 * Stop — barra UMA vez o turno que sobe uma pergunta `Q<n>` ao usuário quando um
 * arquivo da memória do projeto já responde.
 *
 * Só os ARQUIVOS de memória contam (a pasta memory/ do repositório principal e a do
 * transcrito). O banco de observações saiu deste gate: em 11 de 11
 * bloqueios medidos em 2026-10-29 a observação citada não respondia a pergunta, só
 * compartilhava um termo raro (design 2026-10-29-gate-memoria-sem-banco, D2).
 *
 * Protege contra: pergunta com marcador `Q<n>` que um arquivo da memória do projeto
 * já responde (o turno é barrado e a resposta da memória sai no stderr).
 * Não protege contra: pergunta em prosa, sem `Q<n>` (o marcador é o que o gate
 * enxerga); pergunta que só o banco responderia (passa, exit 0); memória que não
 * compartilha termos com a pergunta (abaixo de LIMIAR_TERMOS); gate desligado
 * (RAINFOREST_GATE_OFF ou `gate-pergunta-memoria` false na config).
 *
 * Design D6 do plano 2026-10-28-colheita-observacoes. Anti-loop: o `stop_hook_active`
 * do próprio harness faz o segundo Stop passar livre, então o turno é barrado uma vez.
 *
 * Saídas silenciosas (exit 0): RAINFOREST_GATE_OFF; `agent_id` (não é janela principal);
 * `stop_hook_active`; gate desligado; `transcript_path` ausente ou ilegível; payload
 * ilegível; qualquer exceção (o main inteiro está num try).
 */

const fs = require('node:fs');
const path = require('node:path');

const LIMIAR_TERMOS = 3;
const LIMITE_PERGUNTA = 400;
const JANELA_VIVA_MS = 6 * 3600 * 1000;
// Marcador de pergunta: Q<n> no começo da linha (admite `- `, `> `, `**`, emoji, cabeçalho `#`, `• `, `+ ` e item
// numerado `1. `/`1) ` até dois dígitos, para não ler ano como item: "2026. Q3 ...?"). Recap em prosa
// ("Fechado: Q1 (b)") não conta.
const RE_MARCADOR_Q = /^[ \t>*_\-#•+\p{Extended_Pictographic}\p{M}]*(?:\d{1,2}[.)][ \t*_]*)?Q(\d+)\b/gmu;

// Palavras comuns demais para contar como assunto. Já normalizadas (sem acento, minúsculas).
const PALAVRAS_VAZIAS = new Set([
  'sobre', 'quando', 'porque', 'entao', 'ainda', 'sempre', 'depois', 'antes', 'agora',
  'assim', 'tambem', 'nesse', 'nessa', 'outro', 'outra', 'todos', 'todas', 'recomendo',
  'pergunta', 'decisao', 'resposta', 'sessao', 'projeto',
  // Vocabulário do próprio projeto: aparece em toda memória e não é assunto.
  'regra', 'regras', 'fluxo', 'fluxos', 'worktree', 'agente', 'agentes', 'plano', 'planos',
  'entrega', 'codex', 'claude', 'continua', 'ficar', 'tarefa', 'tarefas', 'commit', 'branch',
  'hooks', 'issue', 'issues', 'arquivo', 'arquivos', 'memoria',
]);

// writeSync no fd 2: sai antes do process.exit, sem depender de o stderr estar flushado.
function bloqueia(motivo) {
  fs.writeSync(2, motivo);
  process.exit(2);
}

function normalizar(texto) {
  return String(texto || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

function termosDe(texto) {
  const brutos = normalizar(texto).match(/[a-z0-9]{5,}/g) || [];
  return new Set(brutos.filter((t) => !PALAVRAS_VAZIAS.has(t)));
}

// Mesma fronteira do gate-turno-prometido: o turno começa na última linha `user` que não é
// tool_result, e o último bloco `text` do assistant depois dela (sidechain fora) é o que vale.
function ultimoTextoDoTurno(linhas) {
  let inicio = -1;
  for (let i = linhas.length - 1; i >= 0; i--) {
    const l = linhas[i];
    if (l.type === 'user' && l.isSidechain !== true) {
      const c = l.message && l.message.content;
      const ehToolResult = Array.isArray(c) && c.some((b) => b && b.type === 'tool_result');
      if (!ehToolResult) { inicio = i; break; }
    }
  }
  if (inicio === -1) return null;
  let ultimo = null;
  for (const l of linhas.slice(inicio + 1)) {
    if (l.isSidechain === true || l.type !== 'assistant' || !l.message) continue;
    const c = l.message.content;
    if (Array.isArray(c)) {
      for (const b of c) if (b && b.type === 'text' && b.text) ultimo = b.text;
    } else if (typeof c === 'string') {
      ultimo = c;
    }
  }
  return ultimo;
}

// Cada pergunta vai do marcador Q<n> até o próximo marcador (ou o fim), no máximo 400 caracteres,
// cortada no primeiro `?` (inclusive). Trecho sem `?` não é pergunta e sai da lista.
function perguntas(texto) {
  const marcadores = [...texto.matchAll(RE_MARCADOR_Q)];
  return marcadores.map((m, i) => {
    const inicio = m.index;
    const fim = i + 1 < marcadores.length ? marcadores[i + 1].index : texto.length;
    const trecho = texto.slice(inicio, Math.min(fim, inicio + LIMITE_PERGUNTA));
    const q = trecho.indexOf('?');
    return q === -1 ? null : { n: m[1], texto: trecho.slice(0, q + 1) };
  }).filter(Boolean);
}

function frontmatter(conteudo) {
  const m = conteudo.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) return { meta: '', corpo: conteudo };
  return { meta: m[1], corpo: conteudo.slice(m[0].length) };
}

function campo(meta, nome) {
  const m = meta.match(new RegExp('^' + nome + ':\\s*(.*)$', 'm'));
  return m ? m[1].trim() : '';
}

// Uma entrada por *.md da pasta memory/ (MEMORY.md é o índice, fica de fora).
// Arquivo que não lê é pulado: uma memória ilegível não pode derrubar as outras.
// Casa só por name e description: o corpo de uma memória fala de muita coisa e encheria o casamento.
function memorias(pasta) {
  let nomes = [];
  try {
    nomes = fs.readdirSync(pasta).filter((n) => n.endsWith('.md') && n !== 'MEMORY.md').sort();
  } catch {
    return [];
  }
  const lista = [];
  for (const arquivo of nomes) {
    try {
      const { meta, corpo } = frontmatter(fs.readFileSync(path.join(pasta, arquivo), 'utf8'));
      const description = campo(meta, 'description');
      const resumo = (description || corpo.replace(/\s+/g, ' ').trim()).slice(0, 160);
      lista.push({ arquivo, resumo, termos: termosDe([campo(meta, 'name'), description].join(' ')) });
    } catch {
      // arquivo ilegível: segue para o próximo
    }
  }
  return lista;
}

// A memória que mais compartilha termos com a pergunta; só conta com LIMIAR_TERMOS ou mais.
function melhorMemoria(termosPergunta, lista) {
  let melhor = null;
  for (const m of lista) {
    let comuns = 0;
    for (const t of termosPergunta) if (m.termos.has(t)) comuns++;
    if (comuns >= LIMIAR_TERMOS && (!melhor || comuns > melhor.comuns)) melhor = { ...m, comuns };
  }
  return melhor;
}

// Design D6: o Claude Code guarda a memória do PROJETO em <projects>/<slug do principal>/memory/.
// Sessão aberta num worktree grava o transcrito em <projects>/<slug do worktree>/, que não tem
// memory/. Por isso as pastas candidatas são a do principal (a) e a do próprio transcrito (b).
const slugDoProjeto = (p) => p.replace(/[^A-Za-z0-9]/g, "-");

// Candidatas sem duplicar, na ordem (a) e depois (b). Sem git, ou com erro, só (b).
function pastasDeMemoria(transcriptPath, cwd) {
  const dirTranscrito = path.dirname(transcriptPath);
  const pastas = [];
  try {
    const { raizDoPrincipal } = require('./lib/config.cjs');
    const principal = path.resolve(raizDoPrincipal(cwd));
    // raizDoPrincipal devolve o próprio cwd quando não acha o principal: aí (a) seria (b).
    if (principal !== path.resolve(cwd)) {
      pastas.push(path.join(path.dirname(dirTranscrito), slugDoProjeto(principal), 'memory'));
    }
  } catch {
    // sem git: segue só com (b)
  }
  pastas.push(path.join(dirTranscrito, 'memory'));
  return [...new Set(pastas)];
}

// Sessões vivas (mesmo critério da abertura: idade + PID + sem worktree de agente) que
// estão em OUTRO repositório. Repositório é o checkout principal, como no gate de config.
function sessoesDeOutrosRepos(raiz, cwd) {
  const { sessoesVivas } = require('./lib/contexto-sessao.cjs');
  const { raizDoPrincipal } = require('./lib/config.cjs');
  const chave = (d) => path.resolve(raizDoPrincipal(d)).toLowerCase();
  const state = JSON.parse(fs.readFileSync(path.join(raiz, 'sessoes.json'), 'utf8'));
  const meu = chave(cwd);
  return sessoesVivas(state, Date.now(), JANELA_VIVA_MS)
    .map(([, s]) => s)
    .filter((s) => s.cwd && chave(s.cwd) !== meu)
    .map((s) => ({ cwd: s.cwd, trabalhando: (s.prompt_ts || 0) > (s.stop_ts || 0) }));
}

function main() {
  let ev;
  try {
    ev = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch {
    process.exit(0);
  }
  if (!ev || typeof ev !== 'object') process.exit(0);

  if (process.env.RAINFOREST_GATE_OFF) process.exit(0);

  // Apenas janela principal
  if (ev.agent_id) process.exit(0);

  // Anti-loop: já barrou uma vez neste turno
  if (ev.stop_hook_active === true) process.exit(0);

  if (!require('./lib/config.cjs').ligado('gate-pergunta-memoria', { projeto: ev.cwd })) process.exit(0);

  if (!ev.transcript_path || !fs.existsSync(ev.transcript_path)) process.exit(0);
  const conteudo = fs.readFileSync(ev.transcript_path, 'utf8').trim();
  if (!conteudo) process.exit(0);

  const linhas = conteudo.split(/\r?\n/).filter(Boolean).map((l) => {
    try { return JSON.parse(l); } catch { return null; }
  }).filter(Boolean);

  const ultimo = ultimoTextoDoTurno(linhas);
  if (!ultimo || !/\bQ\d+\b/.test(ultimo)) process.exit(0);

  const cwd = ev.cwd || process.cwd();
  const { raiz } = require('./lib/raiz.cjs').resolverRaiz({ cwd, plugin: path.resolve(__dirname, '..') });

  const lista = pastasDeMemoria(ev.transcript_path, cwd).flatMap((p) => memorias(p));

  const acertos = [];
  for (const p of perguntas(ultimo)) {
    const m = melhorMemoria(termosDe(p.texto), lista);
    if (m) acertos.push(`Q${p.n}: a memória tem ${m.arquivo} — ${m.resumo}`);
  }

  if (acertos.length === 0) process.exit(0);

  let outras = [];
  if (raiz) {
    try { outras = sessoesDeOutrosRepos(raiz, cwd); } catch { outras = []; }
  }

  let motivo =
    `BLOQUEADO pelo gate de pergunta com memória do rainforest-mind.\n\n` +
    acertos.map((a) => a + '\n').join('') +
    `\nConfira se responde. Se responde, use a memória e não pergunte; se não responde, termine o turno de novo.\n` +
    `Desliga o gate se for falso positivo: node scripts/setup.cjs --desligar gate-pergunta-memoria\n`;
  if (outras.length) {
    motivo +=
      `\nSessões vivas em outros repositórios (pergunte a elas antes de perguntar ao usuário):\n` +
      outras.map((s) => `- ${s.cwd} (${s.trabalhando ? 'trabalhando' : 'ociosa'})\n`).join('');
  }
  bloqueia(motivo);
}

try {
  main();
} catch {
  process.exit(0);
}
