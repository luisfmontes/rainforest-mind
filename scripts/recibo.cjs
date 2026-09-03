#!/usr/bin/env node
/**
 * Recibo de colheita — identidade verificável do artefato entregue.
 *
 * O PROBLEMA. Hoje o `fechar` encerra o fluxo com a decisão gravada, mas o
 * artefato entregue não tem identidade. Semanas depois não há como saber se o
 * arquivo em disco é o mesmo que passou pelos portões: edição posterior, merge
 * e regeneração silenciosa são indistinguíveis da entrega original.
 *
 * O contrato vem do `validate→deliver` do tt-a1i/archify (MIT) — só o contrato;
 * o motor de render (11 mil linhas de SVG) não é problema nosso. Quatro cláusulas:
 *
 *   1. Exit não-zero NUNCA é descrito como sucesso. Sem "quase passou".
 *   2. A entrega congela os bytes: valida o snapshot exato e só então grava.
 *   3. O recibo prova identidade: sha256 + bytes de cada entregável.
 *   4. O recibo declara o que ele NÃO prova. Recibo que alega provar tudo é
 *      suspeito por construção — é a tradução do `visualReview: pending`.
 *
 * Uso:
 *   node scripts/recibo.cjs mostrar  <slug>
 *   node scripts/recibo.cjs conferir <slug>
 *   node scripts/recibo.cjs gravar --slug <slug> --nao-provado '["...","..."]'
 *
 * Exit codes — o contrato, e a distinção 1-vs-2 é a mesma do `portoes.cjs`:
 *   0  ok (mostrar sempre; conferir intacto; gravar gravou, ou não havia manifesto)
 *   1  VEREDITO NEGATIVO sobre o trabalho — entregável divergiu, portão reprovou
 *   2  não deu para decidir, ou uso errado — entregável ausente, `nao_provado`
 *      vazio, slug inválido, sem recibo para conferir
 *
 * Confundir 1 com 2 foi o modo de falha do guarda do Issue #142: responder com
 * confiança sobre o que não se mediu.
 *
 * ONDE MORA, e por que fora do git: `.rainforest/colheita/<slug>-recibo.json`.
 * A divisão está no cabeçalho do `estado.cjs` e vale aqui — veredito (que estágio
 * fechou, com que número) é versionado; rastro de execução (hash de bytes de uma
 * máquina, num instante) não é. O recibo é o segundo.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

// Mesma cadeia de `estado.cjs`, `conferir-fluxo.cjs` e `conselho.cjs`. Repetida
// de propósito: `estado.cjs` não exporta `RAIZ` (só `novo, proximo, faltando,
// estaFechado, EXECUCAO, PRE_REQUISITOS, DIR_ESTADO`), e importar o módulo só
// para pegar a raiz criaria acoplamento onde hoje há três cópias de três linhas.
const RAIZ = process.env.RFM_ESTADO_ROOT
  || process.env.CLAUDE_PROJECT_DIR
  || process.cwd();

const DIR_COLHEITA = path.join(RAIZ, '.rainforest', 'colheita');

/** Slug é chave de caminho. `/`, `\`, `:` e `..` viram travessia ou streams alternativos. */
function validarSlug(slug) {
  if (!slug || /[\\/:]/.test(slug) || slug.includes('..')) {
    console.error(`RECUSADO: slug invalido: ${slug}`);
    console.error('  Slug e chave de caminho — nao aceita barra, contrabarra, dois-pontos nem "..".');
    process.exit(2);
  }
  return slug;
}

const caminhoDoRecibo = (slug) => path.join(DIR_COLHEITA, `${slug}-recibo.json`);
const caminhoDoEstado = (slug) =>
  path.join(RAIZ, 'docs', 'rainforest', 'estado', `${slug}.json`);
const caminhoDosPortoes = (slug) =>
  path.join(RAIZ, 'docs', 'rainforest', 'portoes', `${slug}.md`);

/**
 * Resolve um entregável declarado, CONFINADO à árvore do projeto por `realpath`.
 *
 * Por `realpath`, não por comparação de string: `path.resolve` + `startsWith` é
 * teste léxico, e um symlink (ou junction, que no Windows qualquer usuário cria
 * sem privilégio) dentro da raiz apontando para fora passa nele. Achado A3+X2 do
 * fluxo 6, em que a primeira versão desta mesma cerca tinha esse buraco.
 *
 * @returns {{ok: true, real: string} | {ok: false, motivo: string}}
 */
function resolverEntregavel(rel) {
  // A1: UNC antes de qualquer fs. stat/realpath de UNC no Windows abre conexão SMB
  // e tenta autenticação NTLM automática — plano.entregaveis vem de arquivo
  // versionado e compartilhado, então uma UNC ali é acidente ou ataque.
  // Qualquer par de separadores no inicio, em qualquer combinacao: o Windows
  // normaliza `\/host` e `/\host` para `\\host` antes de resolver (achado da
  // rodada 2 do revisar — a versao anterior so olhava `\\` e `//`).
  if (/^[\\/]{2}/.test(rel)) {
    return { ok: false, motivo: 'caminho UNC nao e entregavel (resolver dispararia conexao de rede)' };
  }

  const bruto = path.isAbsolute(rel) ? rel : path.join(RAIZ, rel);
  let real;
  let raizReal;
  try {
    real = fs.realpathSync.native(bruto);
    raizReal = fs.realpathSync.native(RAIZ);
  } catch (_) {
    return { ok: false, motivo: 'nao existe em disco' };
  }
  const dentro = real === raizReal || real.startsWith(raizReal + path.sep);
  if (!dentro) {
    return {
      ok: false,
      motivo: 'resolve para FORA da arvore do projeto (link ou caminho absoluto)',
    };
  }
  if (!fs.statSync(real).isFile()) return { ok: false, motivo: 'nao e arquivo' };
  return { ok: true, real };
}

/** sha256 + bytes de um arquivo. Lê uma vez; hash e tamanho vêm do mesmo buffer. */
function impressao(caminhoReal) {
  const buf = fs.readFileSync(caminhoReal);
  return {
    sha256: crypto.createHash('sha256').update(buf).digest('hex'),
    bytes: buf.length,
  };
}

/** Escrita atômica: temp + rename, como o resto do estado. */
function gravarAtomico(destino, texto) {
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  const tmp = `${destino}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, texto, 'utf8');
  fs.renameSync(tmp, destino);
}

function lerJson(caminho) {
  if (!fs.existsSync(caminho)) return null;
  try {
    return JSON.parse(fs.readFileSync(caminho, 'utf8'));
  } catch (err) {
    console.error(`RECUSADO: ${caminho} nao e JSON valido: ${err.message}`);
    process.exit(2);
  }
}

// ------------------------------------------------------------------- mostrar

/**
 * `mostrar` — imprime o recibo. Ausência NÃO é erro.
 *
 * Sai 0 quando não há recibo, e diz isso. "Este fluxo não tem recibo" é uma
 * resposta legítima — a maioria dos fluxos não vai ter, porque o manifesto é
 * opt-in. Tratar ausência como falha faria `mostrar` mentir sobre o normal.
 */
function cmdMostrar(slug) {
  const arquivo = caminhoDoRecibo(slug);
  const recibo = lerJson(arquivo);
  if (!recibo) {
    console.log(`sem recibo gravado para '${slug}'.`);
    console.log(`  (o recibo nasce no 'fechar', e so quando o plano declara 'entregaveis')`);
    process.exit(0);
  }

  console.log(`recibo de '${recibo.slug}' — colhido em ${recibo.em}`);
  console.log('');
  for (const e of recibo.entregaveis || []) {
    console.log(`  ${e.caminho}`);
    console.log(`    sha256 ${e.sha256}`);
    console.log(`    bytes  ${e.bytes}`);
  }
  if (recibo.portoes) {
    console.log('');
    console.log(`  portoes re-executados: ${recibo.portoes.arquivo}`);
  }
  console.log('');
  console.log('  o que este recibo NAO prova:');
  for (const n of recibo.nao_provado || []) console.log(`    - ${n}`);
  process.exit(0);
}

// -------------------------------------------------------------------- gravar

function cmdGravar(slug, naoProvadoBruto) {
  const estado = lerJson(caminhoDoEstado(slug));
  if (!estado) {
    console.error(`RECUSADO: nao achei o estado do fluxo: ${caminhoDoEstado(slug)}`);
    process.exit(2);
  }

  const declarados = (estado.plano && estado.plano.entregaveis) || null;

  // OPT-IN, e a decisão mora AQUI, num lugar só. `estado.cjs` chama sempre e não
  // precisa saber se há manifesto — dois lugares decidindo a mesma coisa é como
  // eles divergem.
  if (!Array.isArray(declarados) || declarados.length === 0) {
    console.log(`sem manifesto de entregaveis em '${slug}' — 'fechar' segue sem recibo.`);
    process.exit(0);
  }

  // `nao_provado` ANTES de qualquer hash: é a checagem mais barata e a que
  // recusa mais gente. Não faz sentido ler arquivo para depois descobrir que o
  // recibo não podia ser gravado de todo jeito.
  let naoProvado;
  try {
    naoProvado = JSON.parse(naoProvadoBruto || 'null');
  } catch (_) {
    naoProvado = null;
  }
  if (!Array.isArray(naoProvado) || naoProvado.length === 0
      || naoProvado.some((n) => typeof n !== 'string' || !n.trim())) {
    console.error("RECUSADO: 'nao_provado' vazio ou ausente.");
    console.error('  Recibo que alega provar TUDO e suspeito por construcao. Liste o que');
    console.error('  ficou de fora: revisao visual, comportamento em producao, carga real.');
    console.error(`  Ex.: --nao-provado '["revisao visual","comportamento em producao"]'`);
    process.exit(2);
  }

  // Congela os bytes: resolve e lê TODOS antes de gravar qualquer coisa. Um
  // entregável ausente no meio da lista não pode deixar meio recibo em disco.
  const entregaveis = [];
  const problemas = [];
  for (const rel of declarados) {
    const r = resolverEntregavel(rel);
    if (!r.ok) {
      problemas.push(`  ${rel} — ${r.motivo}`);
      continue;
    }
    entregaveis.push({ caminho: rel, ...impressao(r.real) });
  }

  if (problemas.length > 0) {
    console.error(`RECUSADO: ${problemas.length} entregavel(is) declarado(s) que nao dao para congelar:`);
    for (const p of problemas) console.error(p);
    console.error('  Entregavel declarado e ausente nao e "quase pronto": o recibo nao');
    console.error('  pode provar identidade de arquivo que nao esta la.');
    process.exit(2);
  }

  // Os PORTÕES, imediatamente antes de congelar, e com `--reverificar`.
  //
  // A flag é obrigatória, e a razão foi medida: sem ela, `rodar` pula todo portão
  // com evidência gravada — o gate do `verificar` do fluxo 6 fazia isso no seu
  // primeiro uso real e aprovou LENDO o arquivo. Um recibo que carimba a leitura
  // de uma execução de ontem é exatamente a evidência colada que este fluxo
  // existe para substituir, só em JSON em vez de prosa.
  let portoes = null;
  const arquivoPortoes = caminhoDosPortoes(slug);
  if (fs.existsSync(arquivoPortoes)) {
    const exe = path.join(__dirname, 'portoes.cjs');
    if (fs.existsSync(exe)) {
      const r = spawnSync(process.execPath, [exe, 'rodar', arquivoPortoes, '--reverificar'],
        { stdio: 'inherit', cwd: RAIZ });
      if (r.status !== 0) {
        console.error('');
        console.error('RECUSADO: os portoes deste fluxo nao passaram AGORA.');
        console.error('  Nenhum recibo foi gravado nem sobrescrito. O recibo referencia a');
        console.error('  execucao que acabou de rodar, nunca uma anterior.');
        process.exit(1);
      }
      portoes = { arquivo: path.relative(RAIZ, arquivoPortoes).split(path.sep).join('/') };
    }
  }

  const recibo = {
    slug,
    em: new Date().toISOString(),
    entregaveis,
    ...(portoes ? { portoes } : {}),
    nao_provado: naoProvado,
  };

  const caminhoDestino = caminhoDoRecibo(slug);
  const textoRecibo = `${JSON.stringify(recibo, null, 2)}\n`;

  // A3: falha de escrita sai 2, não 1. Essa é dúvida sobre circunstância (máquina
  // cheia, permissão, arquivo trancado), não veredito sobre o trabalho.
  try {
    gravarAtomico(caminhoDestino, textoRecibo);
  } catch (err) {
    // Limpa o arquivo temporário se existir (recalcular tmp como gravarAtomico faz)
    const tmpEstimado = `${caminhoDestino}.tmp-${process.pid}`;
    try {
      require('fs').rmSync(tmpEstimado, { force: true });
    } catch (_) {
      // Ignora falha ao limpar temporário
    }
    console.error(`RECUSADO: nao consegui gravar o recibo em ${caminhoDestino}: ${err.code} ${err.message}`);
    process.exit(2);
  }

  console.log(`recibo gravado: ${entregaveis.length} entregavel(is), `
    + `${naoProvado.length} item(ns) em nao_provado.`);
  process.exit(0);
}

// ------------------------------------------------------------------ conferir

/**
 * `conferir` — responde "esse arquivo ainda é o que foi colhido?".
 *
 * Compara sha256 E bytes. Só bytes aceitaria troca de caractere por outro do
 * mesmo tamanho, que é a edição mais fácil de fazer sem querer.
 */
function cmdConferir(slug) {
  const recibo = lerJson(caminhoDoRecibo(slug));
  if (!recibo) {
    console.error(`RECUSADO: nada para conferir — sem recibo gravado para '${slug}'.`);
    process.exit(2);
  }

  const divergencias = [];
  for (const e of recibo.entregaveis || []) {
    const r = resolverEntregavel(e.caminho);
    if (!r.ok) {
      divergencias.push(`  ${e.caminho} — ${r.motivo} (estava no recibo)`);
      continue;
    }
    const agora = impressao(r.real);
    if (agora.sha256 !== e.sha256) {
      divergencias.push(
        `  ${e.caminho} — conteudo mudou`
        + `${agora.bytes === e.bytes ? ' (tamanho IDENTICO, hash diferente)' : ''}`
        + `\n      recibo: ${e.sha256} (${e.bytes} B)`
        + `\n      agora:  ${agora.sha256} (${agora.bytes} B)`
      );
    } else if (agora.bytes !== e.bytes) {
      // Hash igual e bytes diferentes é impossível para sha256; se aparecer, o
      // recibo foi editado à mão. Vale dizer isso em vez de aprovar.
      divergencias.push(`  ${e.caminho} — hash bate mas bytes nao: recibo adulterado?`);
    }
  }

  if (divergencias.length > 0) {
    console.error(`DIVERGIU: ${divergencias.length} de ${(recibo.entregaveis || []).length} entregavel(is).`);
    for (const d of divergencias) console.error(d);
    process.exit(1);
  }

  console.log(`intacto — ${(recibo.entregaveis || []).length} entregavel(is) `
    + `com o mesmo sha256 de ${recibo.em}.`);
  process.exit(0);
}

// ----------------------------------------------------------------------- CLI

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return (i === -1 || i + 1 >= process.argv.length) ? null : process.argv[i + 1];
}

function uso() {
  console.error('uso: node scripts/recibo.cjs mostrar  <slug>');
  console.error('     node scripts/recibo.cjs conferir <slug>');
  console.error(`     node scripts/recibo.cjs gravar --slug <slug> --nao-provado '["..."]'`);
  process.exit(2);
}

function main() {
  const cmd = process.argv[2];
  if (cmd === 'mostrar' || cmd === 'conferir') {
    const slug = validarSlug(process.argv[3]);
    return cmd === 'mostrar' ? cmdMostrar(slug) : cmdConferir(slug);
  }
  if (cmd === 'gravar') {
    const slug = validarSlug(arg('slug'));
    return cmdGravar(slug, arg('nao-provado'));
  }
  uso();
}

if (require.main === module) main();
module.exports = { resolverEntregavel, impressao, validarSlug, RAIZ, DIR_COLHEITA };
