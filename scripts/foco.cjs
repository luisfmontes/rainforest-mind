#!/usr/bin/env node
/**
 * Foco — põe teto no bloco "Avanços" do FOCO.md, movendo o que passou do teto para
 * um `AVANCOS.md` ao lado, sem perder uma linha.
 *
 * POR QUE EXISTE, e por que não é a mesma coisa que o teto que já havia.
 *
 * O `contexto-sessao.cjs` já resume os Avanços na INJEÇÃO (`AVANCOS_MAX_BYTES`,
 * 900 B). Isso resolve o custo da abertura e não resolve o do arquivo: a própria
 * injeção manda "leia o FOCO.md antes de afirmar prazo, marco ou avanço", então
 * toda sessão que obedece lê o arquivo inteiro. Medido em 2026-08-12, com o teto
 * de injeção de pé há três dias:
 *
 *   FOCO.md ......................... 15.386 B / 237 linhas
 *   bloco "Avanços" ................. 11.779 B  (77% do arquivo)
 *   entradas de 06/08 a 10/08 (8) .... 5.124 B
 *   entradas de 11/08 (3) ............ 6.655 B
 *
 * As três entradas de um único dia custam mais que os cinco dias anteriores
 * somados — o arquivo não cresce em linha reta, cresce com o dia que rendeu. Um
 * teto em CONTAGEM de entradas não segura isso; é a mesma lição que já custou uma
 * injeção truncada em 2026-08-10 (`AVANCOS_RESIDENTES: 3` virou byte). Por isso o
 * corte aqui também é em BYTES, e o parâmetro é a política.
 *
 * O QUE ELE NÃO FAZ:
 *
 *   - não apaga nada. Toda entrada que sai do FOCO.md entra no AVANCOS.md antes,
 *     e a igualdade byte a byte é CONFERIDA antes de qualquer escrita — divergiu,
 *     aborta sem tocar em disco;
 *   - não escreve sem `--aplicar`. Sem a flag, imprime o que faria e sai 0. Este
 *     script edita o arquivo pessoal do usuário; o lado seguro da falha é não escrever;
 *   - não decide o teto por conta própria em silêncio: o número aparece na saída.
 *
 * Uso:
 *   node scripts/foco.cjs rotacionar                  # só mostra o que sairia
 *   node scripts/foco.cjs rotacionar --aplicar        # move de verdade
 *   node scripts/foco.cjs rotacionar --teto 8000 --aplicar
 *   node scripts/foco.cjs rotacionar --raiz <dir> --json
 *
 * Rodar duas vezes seguidas é seguro: a segunda rodada não acha o que mover e o
 * ponteiro é reescrito a partir do AVANCOS.md real, não incrementado.
 *
 * --------------------------------------------------------------------------
 *
 * Issue #74 — `separar`: parte um FOCO.md MONOLÍTICO em dois arquivos de
 * cadência diferente, `FOCO.md` (tático — o que muda toda semana) e
 * `ESTRATEGIA.md` (estável — histórico, justificativa de negócio, o que está
 * fora de escopo, frentes, concluídos).
 *
 * O PORQUÊ (medido, não suposto): a injeção do SessionStart já reduz as
 * seções não-táticas do FOCO.md a um PONTEIRO (`resumirFoco`,
 * `SECOES_RESIDENTES` em `hooks/lib/contexto-sessao.cjs`) — elas nunca
 * chegavam inteiras à sessão. Um FOCO.md de 12,9 KB, com `## Ativo` sozinho em
 * ~8,3 KB (identidade ~1,3 KB, Avanços ~6 KB), deixa uma sobra de orçamento tão
 * pequena que a identidade tampouco cabe — o bloco de foco inteiro degradava
 * para "só ponteiros". Separar as seções em outro arquivo não bastava sozinho
 * (elas já eram ponteiro); o corte tem que valer também DENTRO de `## Ativo`,
 * entre os campos que o hook lê por regex (natureza, `Pastas:`, `Ociosidade
 * máxima:`, critério de pronto, prazo) e a prosa que só serve de contexto.
 *
 * Uso:
 *   node scripts/foco.cjs separar                     # só mostra o plano
 *   node scripts/foco.cjs separar --aplicar           # escreve os dois arquivos
 *   node scripts/foco.cjs separar --raiz <dir> --json
 *
 * NUNCA sobrescreve: se `ESTRATEGIA.md` já existe na raiz, `separar --aplicar`
 * recusa (o split é uma migração de UMA VEZ, não uma rotina).
 */

const fs = require('fs');
const path = require('path');

const LOCAL = path.resolve(__dirname, '..');

const RAIZ_PADRAO = (() => {
  try {
    const { resolverRaiz } = require('../hooks/lib/raiz.cjs');
    return resolverRaiz({ plugin: LOCAL }).raiz || LOCAL;
  } catch {
    return LOCAL;
  }
})();

// MESMA lista que decide o que fica RESIDENTE na injeção (`resumirFoco`). Não é
// coincidência: a seção que o hook já mantém inteira na sessão é a mesma que
// `separar` mantém no arquivo TÁTICO; a que o hook já troca por ponteiro é a
// que `separar` manda para o ESTRATEGIA.md. Reimportar em vez de copiar o
// array evita a mesma divergência silenciosa que `hooks/heartbeat.cjs:12-20`
// já pagou uma vez com duas cópias da raiz.
const { SECOES_RESIDENTES } = require('../hooks/lib/contexto-sessao.cjs');

/**
 * Teto do bloco "Avanços" DENTRO do FOCO.md, em bytes.
 *
 * 5.000 B contra as entradas reais de 2026-08-12: mantém as duas últimas (4.736 B)
 * e manda as onze anteriores para o histórico. Não é o teto da injeção (900 B) e
 * nem deveria ser — quem lê o arquivo quer o fio da meada dos últimos dias, quem
 * lê a injeção quer a data do último avanço.
 *
 * O efeito que importa não é o tamanho de hoje, é o regime: a partir daqui cada
 * avanço novo empurra um antigo para fora, e o FOCO.md para de crescer sem teto.
 */
const TETO_PADRAO = 5000;

/** Pelo menos uma entrada fica sempre — a data do último avanço é o que a regra 3 mede. */
const MIN_ENTRADAS = 1;

const MARCADOR = '\nAvanços:';
const ENTRADA_DATADA = /\n(?=- \d{4}-\d{2}-\d{2})/;
const DATA_DA_ENTRADA = /^- (\d{4}-\d{2}-\d{2})/;

/** Linha gerada por este script. É reconhecida (e reescrita) a cada rodada. */
const PONTEIRO = /^- \(histórico:.*\)$/;

const CABECALHO_HISTORICO = [
  '# Avanços anteriores',
  '',
  'Entradas que saíram do `FOCO.md` por teto de tamanho — `scripts/foco.cjs',
  'rotacionar`. Ordem cronológica, nada editado no caminho: o que está aqui é',
  'literalmente o que estava lá. O FOCO.md aponta para este arquivo na linha de',
  'histórico do bloco "Avanços".',
  '',
].join('\n');

const tem = (nome) => process.argv.includes(`--${nome}`);

function valorDe(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return i === -1 ? null : process.argv[i + 1] || null;
}

const bytes = (s) => Buffer.byteLength(s, 'utf8');

function morrer(msg) {
  console.error(`erro: ${msg}`);
  process.exit(1);
}

/**
 * Recorta o bloco "Avanços" de dentro da seção Ativo.
 * Devolve null quando o FOCO.md não tem bloco nenhum — foco recém-declarado é isso,
 * e não é erro.
 */
function recortarBloco(texto) {
  const inicio = texto.indexOf(MARCADOR);
  if (inicio === -1) return null;

  const corpoInicio = inicio + MARCADOR.length;
  const resto = texto.slice(corpoInicio);
  const fim = resto.search(/\n## /);
  return {
    cabeca: texto.slice(0, corpoInicio),
    corpo: fim === -1 ? resto : resto.slice(0, fim),
    cauda: fim === -1 ? '' : resto.slice(fim),
  };
}

/** Separa o ponteiro (se já existir) das entradas datadas. */
function partirCorpo(corpo) {
  const pedacos = corpo.split(ENTRADA_DATADA).map((e) => e.trim()).filter(Boolean);
  const entradas = [];
  let ponteiroAntigo = null;
  for (const pedaco of pedacos) {
    if (DATA_DA_ENTRADA.test(pedaco)) entradas.push(pedaco);
    else if (PONTEIRO.test(pedaco)) ponteiroAntigo = pedaco;
    else entradas.push(pedaco); // prosa solta: trata como conteúdo, nunca descarta
  }
  return { entradas, ponteiroAntigo };
}

/**
 * Do mais recente para o mais antigo, enquanto couber no teto. O que não coube sai
 * na ordem cronológica em que estava — é assim que ele entra no histórico.
 */
function escolher(entradas, teto) {
  const mantidas = [];
  let usado = 0;
  for (const entrada of [...entradas].reverse()) {
    const custo = bytes(entrada) + 1;
    if (mantidas.length >= MIN_ENTRADAS && usado + custo > teto) break;
    mantidas.unshift(entrada);
    usado += custo;
  }
  return { mantidas, movidas: entradas.slice(0, entradas.length - mantidas.length), usado };
}

function datasDe(entradas) {
  return entradas
    .map((e) => (e.match(DATA_DA_ENTRADA) || [])[1])
    .filter(Boolean)
    .sort();
}

function montarPonteiro(entradasNoHistorico) {
  if (!entradasNoHistorico.length) return null;
  const datas = datasDe(entradasNoHistorico);
  const n = entradasNoHistorico.length;
  const faixa = datas.length
    ? `de ${datas[0]} a ${datas[datas.length - 1]}`
    : 'sem data legível';
  // Curto de propósito: esta linha é residente na injeção (o `resumirAvancos` do
  // hook a preserva), então cada byte aqui é byte do orçamento de toda sessão.
  return `- (histórico: ${n} ${n === 1 ? 'avanço' : 'avanços'} ${faixa} em AVANCOS.md.)`;
}

/** Escrita atômica: tmp no mesmo diretório + rename. */
function gravar(alvo, conteudo) {
  const tmp = `${alvo}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, conteudo, 'utf8');
  fs.renameSync(tmp, alvo);
}

function rotacionar() {
  const raiz = valorDe('raiz') || RAIZ_PADRAO;
  const teto = Number(valorDe('teto') || TETO_PADRAO);
  if (!Number.isFinite(teto) || teto <= 0) morrer('--teto precisa ser um número de bytes positivo');

  const alvoFoco = path.join(raiz, 'FOCO.md');
  const alvoHist = path.join(raiz, 'AVANCOS.md');
  if (!fs.existsSync(alvoFoco)) morrer(`não achei o FOCO.md em ${raiz}`);

  const original = fs.readFileSync(alvoFoco, 'utf8');
  const bloco = recortarBloco(original);
  const relato = {
    raiz, teto, foco: alvoFoco, historico: alvoHist,
    antes: bytes(original), movidas: 0, mantidas: 0, aplicado: false,
  };

  if (!bloco) return concluir(relato, 'FOCO.md sem bloco "Avanços" — nada a rotacionar.');

  const { entradas, ponteiroAntigo } = partirCorpo(bloco.corpo);
  const { mantidas, movidas } = escolher(entradas, teto);
  relato.mantidas = mantidas.length;
  relato.movidas = movidas.length;
  relato.blocoAntes = bytes(bloco.corpo);

  if (!movidas.length) {
    return concluir(relato, `bloco "Avanços" com ${bytes(bloco.corpo)} B em ${entradas.length} ` +
      `entrada(s), dentro do teto de ${teto} B — nada a mover.`);
  }

  // --- a conferência que autoriza a escrita -------------------------------------
  // Nada de "confio que o split devolveu tudo": as entradas mantidas mais as movidas
  // têm de reconstituir, byte a byte, a lista original. Divergiu, aborta.
  const reconstituido = [...movidas, ...mantidas].join('\n');
  if (reconstituido !== entradas.join('\n')) {
    morrer('conferência falhou: mantidas + movidas não reconstituem as entradas originais. Nada foi escrito.');
  }

  const histAntes = fs.existsSync(alvoHist) ? fs.readFileSync(alvoHist, 'utf8') : '';
  const jaNoHistorico = movidas.filter((e) => histAntes.includes(e));
  const paraGravar = movidas.filter((e) => !histAntes.includes(e));
  if (jaNoHistorico.length) relato.jaNoHistorico = jaNoHistorico.length;

  const corpoHist = (histAntes || CABECALHO_HISTORICO).replace(/\s*$/, '\n');
  const histDepois = paraGravar.length ? `${corpoHist}\n${paraGravar.join('\n\n')}\n` : corpoHist;

  // O ponteiro descreve o AVANCOS.md real, não um contador incremental: rodar duas
  // vezes não pode inflar o número, e um histórico editado à mão continua descrito.
  const entradasHistorico = partirCorpo(histDepois).entradas.filter((e) => DATA_DA_ENTRADA.test(e));
  const ponteiro = montarPonteiro(entradasHistorico);

  const corpoNovo = `\n${[ponteiro, ...mantidas].filter(Boolean).join('\n')}\n`;
  const focoDepois = bloco.cabeca + corpoNovo + bloco.cauda.replace(/^\n*/, '\n');

  relato.depois = bytes(focoDepois);
  relato.blocoDepois = bytes(corpoNovo);
  relato.ponteiroAntigo = Boolean(ponteiroAntigo);
  relato.historicoDepois = bytes(histDepois);

  if (!tem('aplicar')) {
    return concluir(relato, `sairiam ${movidas.length} entrada(s) para AVANCOS.md ` +
      `(${bytes(movidas.join('\n'))} B); ficariam ${mantidas.length}. ` +
      `FOCO.md: ${relato.antes} B → ${relato.depois} B. Rode com --aplicar para valer.`,
    movidas);
  }

  gravar(alvoHist, histDepois);
  gravar(alvoFoco, focoDepois);
  relato.aplicado = true;
  return concluir(relato, `${movidas.length} entrada(s) movida(s) para ${alvoHist}. ` +
    `FOCO.md: ${relato.antes} B → ${relato.depois} B (bloco "Avanços": ` +
    `${relato.blocoAntes} B → ${relato.blocoDepois} B).`, movidas);
}

function concluir(relato, msg, movidas = []) {
  if (tem('json')) {
    console.log(JSON.stringify({ ...relato, mensagem: msg }, null, 2));
    return;
  }
  console.log(msg);
  if (movidas.length) {
    console.log('');
    for (const e of movidas) console.log(`  ${e.split('\n')[0].slice(0, 88)}`);
  }
  if (relato.jaNoHistorico) {
    console.log(`\n(${relato.jaNoHistorico} entrada(s) já estavam no AVANCOS.md e não foram duplicadas.)`);
  }
}

/**
 * Diz ONDE mora o foco. Existe porque o caminho não é fixo desde 2026-08-11 (a raiz
 * resolve em 4 níveis, `hooks/lib/raiz.cjs`) e o `/foco` trazia um caminho absoluto
 * escrito à mão — que apontava para o repo do código, onde o FOCO.md já não estava.
 */
function caminho() {
  const raiz = valorDe('raiz') || RAIZ_PADRAO;
  const alvo = path.join(raiz, 'FOCO.md');
  const dados = { raiz, foco: alvo, historico: path.join(raiz, 'AVANCOS.md'), existe: fs.existsSync(alvo) };
  if (tem('json')) console.log(JSON.stringify(dados, null, 2));
  else console.log(`${alvo}${dados.existe ? '' : '   (NÃO EXISTE — foco ainda não declarado nesta raiz)'}`);
}

// ============================================================================
// Issue #74 — `separar`: FOCO.md monolítico -> FOCO.md (tático) + ESTRATEGIA.md
// ============================================================================

/**
 * Campos da identidade que o HOOK lê por regex direto do texto do FOCO.md —
 * `pastasDoFoco`, `ociosidadeDoFoco`, `naturezaDoFocoAtivo`, `tituloDoFocoAtivo`
 * em `hooks/lib/contexto-sessao.cjs`. Têm que sobreviver no arquivo TÁTICO:
 * mandar um destes para o ESTRATEGIA.md não é "mover prosa", é quebrar a regra
 * 17 e a legenda em silêncio, porque o hook só lê o FOCO.md.
 */
const RE_CAMPO_TATICO = /^(Pastas:|Ociosidade máxima:|Critério de pronto|Criterio de pronto)/i;
/** Data (prazo, próximo marco) em qualquer formato que o restante do arquivo usa. */
const RE_DATA_IDENTIDADE = /\d{4}-\d{2}-\d{2}|\d{1,2}\/\d{1,2}/;
/** A linha em negrito que declara a natureza — é a mesma que `naturezaDoFocoAtivo` procura. */
const RE_NATUREZA = /\[(trabalho|pessoal)\]/;
/** Linha de CONTINUAÇÃO (indentada) de um campo tático de várias linhas (ex.: `Pastas:` com 2 pastas). */
const RE_CONTINUACAO = /^[ \t]+\S/;

/**
 * Separa a região de PROSA/IDENTIDADE de `## Ativo` (tudo antes de "Marcos" e
 * "Avanços:") em duas: linhas ESSENCIAIS (o hook lê por regex, ficam no
 * FOCO.md) e PROSA (contexto de negócio, histórico — vai para o ESTRATEGIA.md).
 *
 * Linha por linha, nunca por parágrafo: é assim que o título/natureza/data
 * ficam junto de prosa no MESMO parágrafo (o formato real do usuário faz
 * isso) sem arrastar a prosa inteira para o lado tático.
 *
 * Regra, em ordem:
 *   1. a PRIMEIRA linha que declara a natureza (`[trabalho]`/`[pessoal]`) é o
 *      título — sempre essencial, e tudo ANTES dela (prosa-meta explicando o
 *      formato do arquivo) é sempre prosa;
 *   2. depois do título, linha em branco é prosa;
 *   3. campo tático (`Pastas:`, `Ociosidade máxima:`, `Critério de pronto`) ou
 *      linha com data (prazo/próximo marco) é essencial;
 *   4. linha indentada logo após uma linha essencial é CONTINUAÇÃO dela
 *      (`Pastas:` com duas pastas quebra em duas linhas) — essencial também;
 *   5. o resto é prosa.
 */
function separarIdentidade(regiao) {
  const linhas = String(regiao || '').split('\n');
  const essenciais = [];
  const prosa = [];
  let tituloAchado = false;
  let ultimaEssencial = false;

  for (const linha of linhas) {
    const vazia = !linha.trim();
    let essencial;
    if (!tituloAchado && RE_NATUREZA.test(linha)) {
      essencial = true;
      tituloAchado = true;
    } else if (!tituloAchado) {
      essencial = false; // prosa-meta antes do título
    } else if (vazia) {
      essencial = false;
    } else if (RE_CAMPO_TATICO.test(linha) || RE_DATA_IDENTIDADE.test(linha)) {
      essencial = true;
    } else if (RE_CONTINUACAO.test(linha) && ultimaEssencial) {
      essencial = true;
    } else {
      essencial = false;
    }
    (essencial ? essenciais : prosa).push(linha);
    if (!vazia) ultimaEssencial = essencial;
  }

  return { essencial: essenciais.join('\n').trim(), prosa: prosa.join('\n').trim() };
}

/**
 * Divide o texto de `## Ativo` (com o cabeçalho `## Ativo` incluso) em quatro
 * pedaços: o cabeçalho, a identidade ESSENCIAL, o bloco "Marcos" (inteiro,
 * intocado) e o bloco "Avanços:" (inteiro, intocado — ele já tem cadência
 * própria via `rotacionar`, acima). A PROSA que sobra da identidade é o quinto
 * pedaço, e vai para o ESTRATEGIA.md.
 *
 * Marcos e Avanços não passam por `separarIdentidade`: são listas, não prosa,
 * e o hook já os resume NA INJEÇÃO (`resumirMarcos`, `resumirAvancos`) sem
 * precisar que o arquivo em disco mude de forma.
 */
function dividirAtivo(secaoAtivo) {
  const cabecalhoMatch = String(secaoAtivo || '').match(/^## Ativo[ \t]*\n?/);
  const cabecalho = cabecalhoMatch ? cabecalhoMatch[0].trimEnd() : '## Ativo';
  let resto = String(secaoAtivo || '').slice(cabecalhoMatch ? cabecalhoMatch[0].length : 0);

  // "Avanços:" é sempre o ÚLTIMO bloco de `## Ativo` (mesma convenção de
  // `resumirAvancos`/`recortarBloco`) — tudo dele até o fim da seção.
  const idxAvancos = resto.indexOf('\nAvanços:');
  let blocoAvancos = '';
  if (idxAvancos !== -1) {
    blocoAvancos = resto.slice(idxAvancos).trim();
    resto = resto.slice(0, idxAvancos);
  }

  // "Marcos" vai até a próxima linha em branco (mesma convenção de `resumirMarcos`).
  const idxMarcos = resto.search(/^Marcos/m);
  let blocoMarcos = '';
  if (idxMarcos !== -1) {
    const depoisMarcos = resto.slice(idxMarcos);
    const fimRelativo = depoisMarcos.search(/\n\n/);
    blocoMarcos = (fimRelativo === -1 ? depoisMarcos : depoisMarcos.slice(0, fimRelativo)).trim();
    const cauda = fimRelativo === -1 ? '' : depoisMarcos.slice(fimRelativo);
    resto = resto.slice(0, idxMarcos) + cauda;
  }

  const { essencial, prosa } = separarIdentidade(resto);
  return { cabecalho, essencial, blocoMarcos, blocoAvancos, prosa };
}

/**
 * Motor PURO de `separar`: recebe o texto do FOCO.md monolítico, devolve
 * `{ foco, estrategia }` — o conteúdo dos dois arquivos. Não lê nem escreve
 * disco; quem faz I/O é `separar()`, abaixo, seguindo a mesma divisão
 * motor/adaptador de `hooks/lib/contexto-sessao.cjs`.
 *
 * NADA SE PERDE: toda seção e toda linha do original está em UM dos dois
 * textos devolvidos — o que muda é só o arquivo, nunca o conteúdo. As únicas
 * exceções são estruturais e pequenas (o título `# Estratégia` do arquivo
 * novo, e o cabeçalho "## Ativo (contexto)" que dá um lar para a prosa que
 * saiu de dentro de `## Ativo`) — nenhuma delas apaga uma frase do usuário.
 */
function dividirFoco(textoOriginal) {
  const texto = String(textoOriginal || '');
  const blocos = texto.split(/\n(?=## )/);

  let preambulo = '';
  let secoes = blocos;
  if (blocos.length && !/^## /.test(blocos[0])) {
    preambulo = blocos[0].trim();
    secoes = blocos.slice(1);
  }

  const taticas = [];
  const estrategicas = [];
  let ativoDividido = null;

  for (const secao of secoes) {
    const m = secao.match(/^## (.+)$/m);
    const nome = m ? m[1].trim() : '';
    if (nome === 'Ativo') {
      ativoDividido = dividirAtivo(secao);
    } else if (SECOES_RESIDENTES.includes(nome)) {
      taticas.push(secao.trim());
    } else {
      estrategicas.push(secao.trim());
    }
  }

  const partesFoco = [preambulo];
  if (ativoDividido) {
    partesFoco.push([
      ativoDividido.cabecalho,
      ativoDividido.essencial,
      ativoDividido.blocoMarcos,
      ativoDividido.blocoAvancos,
    ].filter(Boolean).join('\n\n'));
  }
  partesFoco.push(...taticas);
  const foco = `${partesFoco.filter(Boolean).join('\n\n')}\n`;

  const partesEstrategia = ['# Estratégia'];
  if (ativoDividido && ativoDividido.prosa) {
    partesEstrategia.push(`## Ativo (contexto)\n\n${ativoDividido.prosa}`);
  }
  partesEstrategia.push(...estrategicas);
  const estrategia = `${partesEstrategia.filter(Boolean).join('\n\n')}\n`;

  return { foco, estrategia };
}

function separar() {
  const raiz = valorDe('raiz') || RAIZ_PADRAO;
  const alvoFoco = path.join(raiz, 'FOCO.md');
  const alvoEstrategia = path.join(raiz, 'ESTRATEGIA.md');
  if (!fs.existsSync(alvoFoco)) morrer(`não achei o FOCO.md em ${raiz}`);
  if (fs.existsSync(alvoEstrategia)) {
    morrer(`${alvoEstrategia} já existe — separar é migração de UMA VEZ e não sobrescreve. Apague-o (depois de olhar) se quiser refazer o split.`);
  }

  const original = fs.readFileSync(alvoFoco, 'utf8');
  const { foco, estrategia } = dividirFoco(original);
  const relato = {
    raiz, foco: alvoFoco, estrategia: alvoEstrategia,
    antes: bytes(original), focoDepois: bytes(foco), estrategiaDepois: bytes(estrategia),
    aplicado: false,
  };

  if (tem('json') && !tem('aplicar')) {
    console.log(JSON.stringify({ ...relato, planoFoco: foco, planoEstrategia: estrategia }, null, 2));
    return;
  }

  if (!tem('aplicar')) {
    console.log(`FOCO.md hoje: ${relato.antes} B.`);
    console.log(`Plano: ${alvoFoco} (${relato.focoDepois} B) + ${alvoEstrategia} (${relato.estrategiaDepois} B).`);
    console.log('');
    console.log(`--- ${alvoFoco} (tático) ---`);
    console.log(foco);
    console.log(`--- ${alvoEstrategia} (estável) ---`);
    console.log(estrategia);
    console.log('Nada foi escrito. Rode com --aplicar para valer.');
    return;
  }

  // ESTRATEGIA.md primeiro: se a escrita dele falhar, o FOCO.md original
  // continua de pé e nada ficou pela metade.
  gravar(alvoEstrategia, estrategia);
  gravar(alvoFoco, foco);
  relato.aplicado = true;

  if (tem('json')) {
    console.log(JSON.stringify(relato, null, 2));
    return;
  }
  console.log(`FOCO.md dividido: ${alvoFoco} (${relato.antes} B -> ${relato.focoDepois} B) ` +
    `+ ${alvoEstrategia} (${relato.estrategiaDepois} B).`);
}

function main() {
  const comando = process.argv[2];
  if (comando === 'rotacionar') return rotacionar();
  if (comando === 'separar') return separar();
  if (comando === 'caminho') return caminho();
  console.error('uso: node scripts/foco.cjs rotacionar [--aplicar] [--teto N] [--raiz DIR] [--json]');
  console.error('     node scripts/foco.cjs separar [--aplicar] [--raiz DIR] [--json]');
  console.error('     node scripts/foco.cjs caminho [--raiz DIR] [--json]');
  process.exit(2);
}

if (require.main === module) main();
module.exports = {
  rotacionar, separar, caminho, main,
  dividirFoco, dividirAtivo, separarIdentidade,
  RAIZ_PADRAO,
};
