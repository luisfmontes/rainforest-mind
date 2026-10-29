#!/usr/bin/env node
/**
 * Bateria de exemplos prescritos contra o gate-fechar-issue (D6, D7, D8).
 *
 * Extrai de skills/**, commands/*.md e agents/*.md cada `gh issue|pr <verbo de
 * escrita> ...` que o texto prescreve (entre crases ou em bloco de código),
 * troca os marcadores <...> por valores fixos e roda cada forma como processo
 * `node hooks/gate-fechar-issue.cjs` com o payload PreToolUse de Bash. Forma
 * barrada (exit 2) que não está na lista de exceções é falha.
 *
 * O `gh` real nunca roda: um stub entra à frente do PATH e responde só o que o
 * gate lê (`pr view --json body` e `issue view --json comments`).
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const SRC = path.join(__dirname, '..');
const HOOK = path.join(SRC, 'hooks', 'gate-fechar-issue.cjs');
const VERBOS_DE_ESCRITA = ['create', 'close', 'merge', 'edit', 'comment', 'reopen'];

/**
 * Formas que saem 2 e são aceitas de propósito. Cada item: `forma` (como está
 * no arquivo, com os <...>), `arquivo` (relativo à raiz) e `motivo` não vazio.
 */
const EXCECOES = [
  {
    forma: 'gh issue close',
    arquivo: 'skills/setup/SKILL.md',
    motivo: 'linha de tabela de gates que descreve o que o gate-fechar-issue barra ("barra `gh issue close` direto"); nomeia a forma barrada, nao prescreve uso',
  },
  {
    forma: 'gh pr merge --auto',
    arquivo: 'skills/setup/SKILL.md',
    motivo: 'linha de tabela de gates que descreve o que o gate-merge-auto barra ("barra `gh pr merge --auto`"); nomeia o --auto como proibido, nao prescreve uso',
  },
];

const STUB_JS = `const a = process.argv.slice(2);
if (a[0] === 'pr' && a[1] === 'view') {
  process.stdout.write(JSON.stringify({ body: 'Descricao de teste sem palavra-chave.' }));
}
if (a[0] === 'issue' && a[1] === 'view') {
  process.stdout.write(JSON.stringify({ comments: [] }));
}
process.exit(0);
`;

function listarMarkdown() {
  const arquivos = [];
  const varrer = (dir) => {
    for (const nome of fs.readdirSync(dir, { withFileTypes: true })) {
      const caminho = path.join(dir, nome.name);
      if (nome.isDirectory()) varrer(caminho);
      else if (nome.name.endsWith('.md')) arquivos.push(caminho);
    }
  };
  varrer(path.join(SRC, 'skills'));
  for (const pasta of ['commands', 'agents']) {
    const dir = path.join(SRC, pasta);
    if (!fs.existsSync(dir)) continue;
    for (const nome of fs.readdirSync(dir)) {
      if (nome.endsWith('.md')) arquivos.push(path.join(dir, nome));
    }
  }
  return arquivos.sort();
}

function ehFormaDeEscrita(texto) {
  const m = /^gh (issue|pr) (\S+)/.exec(texto);
  return m !== null && VERBOS_DE_ESCRITA.includes(m[2]);
}

/** Formas prescritas num arquivo: { forma, linha } com forma normalizada. */
function extrairFormas(texto) {
  const formas = [];
  const linhas = texto.split('\n');
  const naoCerca = [];
  let emCerca = false;
  linhas.forEach((linha, i) => {
    if (linha.trim().startsWith('```')) {
      emCerca = !emCerca;
      return;
    }
    if (emCerca) {
      const t = linha.trim().replace(/\s+/g, ' ');
      if (ehFormaDeEscrita(t)) formas.push({ forma: t, linha: i + 1 });
      return;
    }
    naoCerca.push({ texto: linha + '\n', linha: i + 1 });
  });
  // Crase simples pode cruzar linha: junta o texto fora de cerca e acha o início.
  const corrido = naoCerca.map((p) => p.texto).join('');
  const inicioDaLinha = [];
  let acumulado = 0;
  for (const p of naoCerca) {
    inicioDaLinha.push({ inicio: acumulado, linha: p.linha });
    acumulado += p.texto.length;
  }
  const linhaDe = (indice) => {
    let l = naoCerca[0].linha;
    for (const r of inicioDaLinha) if (r.inicio <= indice) l = r.linha;
    return l;
  };
  const reInline = /`([^`]+)`/g;
  let m;
  while ((m = reInline.exec(corrido)) !== null) {
    const t = m[1].replace(/\s+/g, ' ').trim();
    if (ehFormaDeEscrita(t)) formas.push({ forma: t, linha: linhaDe(m.index) });
  }
  return formas;
}

/**
 * Troca os marcadores. Número na posição 3 (depois de `gh issue|pr <verbo>`) vira
 * 1; valor de --body-file vira arquivo vazio em tmpdir (nunca /tmp do Git Bash,
 * que o gate não lê); o resto vira x.
 */
function instanciar(forma, dirCorpo) {
  const toks = forma.split(' ');
  return toks
    .map((t, i) => {
      if (!/<[^>]+>/.test(t)) return t;
      if (i === 3 && /^<[^>]+>$/.test(t)) return '1';
      if (i > 0 && toks[i - 1] === '--body-file') return `"${path.join(dirCorpo, 'corpo.md')}"`;
      return t.replace(/<[^>]+>/g, 'x');
    })
    .join(' ');
}

function criarStub(dir) {
  const js = path.join(dir, 'gh-stub.cjs');
  fs.writeFileSync(js, STUB_JS);
  fs.writeFileSync(path.join(dir, 'gh.cmd'), `@echo off\r\n"${process.execPath}" "${js}" %*\r\n`);
  const sh = path.join(dir, 'gh');
  fs.writeFileSync(sh, `#!/bin/sh\nexec "${process.execPath}" "${js}" "$@"\n`);
  fs.chmodSync(sh, 0o755);
}

function ambienteComStub(dirStub) {
  const env = { ...process.env };
  let pathOriginal = '';
  for (const k of Object.keys(env)) {
    if (k.toUpperCase() === 'PATH') {
      pathOriginal = env[k];
      delete env[k];
    }
  }
  env.PATH = dirStub + path.delimiter + pathOriginal;
  delete env.RAINFOREST_GATE_OFF;
  return env;
}

function rodarNoGate(comando, env, dirSandbox) {
  const payload = {
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: { command: comando },
    cwd: dirSandbox,
  };
  const r = cp.spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify(payload),
    env,
    cwd: dirSandbox,
    encoding: 'utf8',
    timeout: 60000,
  });
  return r.status;
}

function main() {
  const falhas = [];
  let ok = 0;
  let excecao = 0;
  let total = 0;

  const arquivos = listarMarkdown();
  const formasPorArquivo = new Map();
  const todas = [];
  for (const abs of arquivos) {
    const rel = path.relative(SRC, abs).split(path.sep).join('/');
    const formas = extrairFormas(fs.readFileSync(abs, 'utf8'));
    formasPorArquivo.set(rel, new Set(formas.map((f) => f.forma)));
    for (const f of formas) todas.push({ arquivo: rel, ...f });
  }

  // Validação da lista de exceções: motivo obrigatório e forma ainda presente.
  for (const e of EXCECOES) {
    if (typeof e.motivo !== 'string' || e.motivo.trim() === '') {
      falhas.push(`excecao sem motivo: [${e.arquivo}] ${e.forma}`);
    }
    const presentes = formasPorArquivo.get(e.arquivo);
    if (!presentes || !presentes.has(e.forma)) {
      falhas.push(`excecao cuja forma nao aparece mais em ${e.arquivo}: ${e.forma}`);
    }
  }

  const dirSandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'exemplos-prescritos-'));
  const dirStub = path.join(dirSandbox, 'bin');
  const dirCorpo = path.join(dirSandbox, 'corpo');
  fs.mkdirSync(dirStub);
  fs.mkdirSync(dirCorpo);
  fs.writeFileSync(path.join(dirCorpo, 'corpo.md'), '');
  criarStub(dirStub);
  const env = ambienteComStub(dirStub);

  try {
    for (const f of todas) {
      total++;
      const comando = instanciar(f.forma, dirCorpo);
      const exit = rodarNoGate(comando, env, dirSandbox);
      const excetuada = EXCECOES.find((e) => e.arquivo === f.arquivo && e.forma === f.forma);
      let marca = '';
      if (exit === 0 && excetuada) {
        // Controle positivo: a forma da lista existe porque o gate a barra.
        // Saindo 0, o gate esta desligado (config do usuario) ou falhou aberto,
        // e o verde das outras formas deixaria de medir alguma coisa.
        falhas.push(`excecao que o gate nao barrou (gate desligado ou lista velha): ${f.arquivo}:${f.linha} ${comando}`);
        marca = ' [FALHA]';
      } else if (exit === 0) {
        ok++;
      } else if (exit === 2 && excetuada && excetuada.motivo && excetuada.motivo.trim()) {
        excecao++;
        marca = ' [excecao]';
      } else if (exit === 2) {
        falhas.push(`barrada e fora da lista: ${f.arquivo}:${f.linha} ${comando}`);
        marca = ' [FALHA]';
      } else {
        falhas.push(`exit inesperado ${exit}: ${f.arquivo}:${f.linha} ${comando}`);
        marca = ' [FALHA]';
      }
      console.log(`${f.arquivo}:${f.linha} | ${comando} | ${exit}${marca}`);
    }
    // Controle fixo, independente da lista: sem ele, uma lista vazia com o gate
    // desligado deixaria todas as formas verdes.
    const controle = rodarNoGate('gh issue close 1', env, dirSandbox);
    console.log(`controle | gh issue close 1 | ${controle}`);
    if (controle !== 2) falhas.push(`controle: gh issue close 1 deveria sair 2 (gate barrando), saiu ${controle}`);
  } finally {
    fs.rmSync(dirSandbox, { recursive: true, force: true });
  }

  console.log('');
  console.log(`== exemplos prescritos: ${total} formas, ${ok} ok, ${excecao} excecao, ${falhas.length} falha(s) ==`);
  if (falhas.length > 0) {
    for (const f of falhas) console.log(`  FALHA ${f}`);
    process.exit(1);
  }
  process.exit(0);
}

if (require.main === module) main();

module.exports = { extrairFormas, instanciar };
