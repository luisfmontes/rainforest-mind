#!/usr/bin/env node
// @categoria: guia
// UserPromptSubmit: injeta memorias de QUALQUER projeto que tratam do assunto do pedido
// (design 2026-10-08-memoria-por-assunto, D1/D2/D3/D6/D10) e os verbetes do GLOSSARIO.md do
// repo que o pedido cita (design 2026-10-08-glossario-compartilhado, D1/D9). Somente leitura no
// banco; os unicos arquivos escritos sao <raiz>/memoria-assunto/<session_id>.json (so ids, D10)
// e <raiz>/memoria-assunto/<session_id>.glossario.json (so chaves de verbete, nunca texto do pedido).
// D6: qualquer falha -> stdout vazio e exit 0. O pedido do usuario nunca espera nem quebra por isto.
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./lib/raiz.cjs');
const { buscarPorAssunto, montarBlocoAssunto } = require('./lib/memoria-assunto.cjs');
const { lerVerbetes, verbeteValido, acharGlossario, casarVerbetes, montarBlocoGlossario, chaveDe } = require('./lib/glossario.cjs');
const { abrirBancoSomenteLeitura, resolverCaminhos } = require(path.join(__dirname, '..', 'scripts', 'memoria.cjs'));
const { extrairLinhasServidas, acharAlvo } = require(path.join(__dirname, '..', 'scripts', 'lib', 'utilidade.cjs'));
const CAB_ABERTURA = '## Memória (corpus residentes)';

const MIN_TERMOS = 3;
const MIN_TAMANHO_TERMO = 3;

function termosUteis(texto) {
  const brutos = String(texto || '').match(/[\p{L}\p{N}]+/gu) || [];
  return new Set(brutos.map((t) => t.toLowerCase()).filter((t) => t.length >= MIN_TAMANHO_TERMO)).size;
}

function lerIds(arquivo) {
  const dado = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  if (!Array.isArray(dado)) throw new Error('arquivo de sessao invalido');
  return dado.filter((n) => Number.isInteger(n));
}

function persistirServidos(arquivo, ids) {
  fs.mkdirSync(path.dirname(arquivo), { recursive: true });
  fs.writeFileSync(arquivo, JSON.stringify(Array.from(ids)));
}

// Chaves de verbete ja injetadas nesta sessao. Arquivo ausente ou fora do formato = nenhuma.
function lerChaves(arquivo) {
  if (!fs.existsSync(arquivo)) return [];
  const dado = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  if (!Array.isArray(dado)) return [];
  return dado.filter((c) => typeof c === 'string');
}

// Qualquer erro de leitura ou de parse (arquivo corrompido, sem permissao) = nenhuma chave ja injetada.
// O bloco do glossario continua saindo; a gravacao em seguida regrava o arquivo com as chaves certas.
function lerChavesOuVazio(arquivo) {
  try { return lerChaves(arquivo); } catch (e) { return []; }
}

function persistirChaves(arquivo, chaves) {
  fs.mkdirSync(path.dirname(arquivo), { recursive: true });
  fs.writeFileSync(arquivo, JSON.stringify(Array.from(new Set(chaves))));
}

// O attachment de SessionStart vem no comeco do transcrito: le so os primeiros 2 MiB
// (transcrito real chega a 95 MB; extrairSessao inteiro leva 12 s contra o timeout de 5 s).
// A ultima linha pode vir cortada: JSON invalido e ignorado.
const BYTES_SEMEADURA = 2 * 1024 * 1024;
function lerServidasDoInicio(caminhoTranscrito) {
  const fd = fs.openSync(caminhoTranscrito, 'r');
  let texto;
  try {
    const buf = Buffer.alloc(BYTES_SEMEADURA);
    const lidos = fs.readSync(fd, buf, 0, BYTES_SEMEADURA, 0);
    texto = buf.toString('utf8', 0, lidos);
  } finally { fs.closeSync(fd); }
  const servidas = [];
  for (const l of texto.split('\n')) {
    if (!l.includes('SessionStart')) continue;
    let e;
    try { e = JSON.parse(l); } catch (err) { continue; }
    if (e.type !== 'attachment' || !e.attachment || e.attachment.hookEvent !== 'SessionStart') continue;
    let ctx = null;
    try { ctx = JSON.parse(e.attachment.stdout).hookSpecificOutput.additionalContext; } catch (err) { ctx = null; }
    if (ctx) for (const linha of extrairLinhasServidas(ctx, [CAB_ABERTURA])) servidas.push(linha);
  }
  return servidas;
}

// Bloco do glossario para este pedido, ou ''. Lanca em falha; quem chama isola com try proprio.
// Nao toca no banco: o GLOSSARIO.md e arquivo do repo.
function glossarioDoPedido(cwd, prompt, sessao, raiz) {
  const arquivo = acharGlossario(cwd);
  if (!arquivo) return '';
  const verbetes = lerVerbetes(fs.readFileSync(arquivo, 'utf8')).map((v) => Object.assign(v, { chave: chaveDe(v.termo) }));
  const arquivoChaves = raiz ? path.join(raiz, 'memoria-assunto', sessao + '.glossario.json') : null;
  const jaGlossario = new Set(arquivoChaves ? lerChavesOuVazio(arquivoChaves) : []);
  const blocoGlossario = montarBlocoGlossario(casarVerbetes(verbetes, prompt).filter((v) => !jaGlossario.has(v.chave)));
  if (!blocoGlossario) return '';

  const linhas = blocoGlossario.split('\n').slice(1);
  const injetados = verbetes.filter((v) => verbeteValido(v) && linhas.some((l) => l.startsWith('- **' + v.termo + '**:')));
  // Gravacao em try proprio: falha de escrita (pasta impossivel, disco cheio) nunca apaga o bloco ja montado.
  if (arquivoChaves) {
    try { persistirChaves(arquivoChaves, [...jaGlossario, ...injetados.map((v) => v.chave)]); } catch (e) { /* sem dedup nesta chamada */ }
  }
  return blocoGlossario;
}

// Bloco da memoria por assunto para este pedido, ou ''. Lanca em falha; quem chama isola.
function memoriaDoPedido(entrada, prompt, sessao, raiz, cwd) {
  const { caminhoDb, canonico, projeto } = resolverCaminhos(cwd);
  if (!fs.existsSync(caminhoDb)) throw new Error('banco ausente');
  const conexao = abrirBancoSomenteLeitura(caminhoDb);
  if (!conexao) throw new Error('banco indisponivel');

  try {
    const arquivo = path.join(raiz, 'memoria-assunto', sessao + '.json');
    let servidos;
    if (fs.existsSync(arquivo)) {
      servidos = new Set(lerIds(arquivo));
    } else {
      // Primeiro pedido da sessao: semeia com o que a abertura ja serviu (transcrito).
      servidos = new Set();
      const apelidos = { [canonico]: projeto };
      for (const linha of lerServidasDoInicio(String(entrada.transcript_path || ''))) {
        const alvo = acharAlvo(conexao, linha, apelidos);
        if (alvo && alvo.origem === 'observacao') servidos.add(alvo.id);
      }
      // A semeadura roda uma vez por sessao: grava ja, com ou sem acerto, para o proximo
      // pedido nao reparsear o transcrito.
      persistirServidos(arquivo, servidos);
    }

    const achadas = buscarPorAssunto(conexao, prompt, { projetoAtual: canonico, jaServidos: servidos, max: 3 });
    const bloco = montarBlocoAssunto(achadas);
    if (!bloco) return '';

    for (const a of achadas) servidos.add(a.id);
    persistirServidos(arquivo, Array.from(servidos));
    return bloco;
  } finally {
    try { conexao.close(); } catch (e) { /* melhor esforco */ }
  }
}

// Devolve o JSON a imprimir, ou '' quando nao ha o que injetar. Lanca em qualquer falha.
function executar() {
  const entrada = JSON.parse(fs.readFileSync(0, 'utf8'));
  const prompt = typeof entrada.prompt === 'string' ? entrada.prompt : '';
  const sessao = String(entrada.session_id || '');
  if (!/^[A-Za-z0-9_-]+$/.test(sessao)) throw new Error('session_id invalido');
  if (prompt.trimStart().startsWith('/')) return '';

  const cwd = entrada.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const { raiz } = resolverRaiz({ cwd, plugin: path.resolve(__dirname, '..') });
  // Sem raiz o glossario entra, mas sem dedup: a memoria por assunto continua exigindo raiz.
  // Glossario antes de qualquer saida cedo da memoria e antes de qualquer acesso ao banco.
  let blocoGlossario = '';
  try { blocoGlossario = glossarioDoPedido(cwd, prompt, sessao, raiz); } catch (e) { blocoGlossario = ''; }

  let blocoMemoria = '';
  if (raiz && termosUteis(prompt) >= MIN_TERMOS) {
    try { blocoMemoria = memoriaDoPedido(entrada, prompt, sessao, raiz, cwd); } catch (e) { blocoMemoria = ''; }
  }

  const contexto = [blocoGlossario, blocoMemoria].filter(Boolean).join('\n\n');
  if (!contexto) return '';
  return JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: contexto } });
}

try {
  const saida = executar();
  if (saida) process.stdout.write(saida + '\n');
} catch (e) {
  process.exitCode = 0;
}
