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

function pad(n, len = 2) {
  return String(n).padStart(len, '0');
}

function carimboAgora() {
  const d = new Date();
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}-` +
    `${pad(d.getMilliseconds(), 3)}`
  );
}

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
 * Faz backup do FOCO.md para .foco-backups/foco-<timestamp>.md.
 * Implementa rodízio: mantém até --teto cópias (padrão 10), deletando a mais antiga.
 * FOCO.md ausente: exit 1, avisa qual arquivo não achou, não cria diretório nenhum.
 */
function backup() {
  const raiz = valorDe('raiz') || RAIZ_PADRAO;
  const teto = Number(valorDe('teto') || 10);
  if (!Number.isFinite(teto) || teto <= 0) morrer('--teto precisa ser um número positivo');

  const alvoFoco = path.join(raiz, 'FOCO.md');
  const dirBackup = path.join(raiz, '.foco-backups');

  if (!fs.existsSync(alvoFoco)) morrer(`não achei o FOCO.md em ${raiz}`);

  const carimbo = carimboAgora();

  // Cria diretório se não existir
  fs.mkdirSync(dirBackup, { recursive: true });

  // Caminho do novo backup — cópia byte a byte do original
  const alvoBackup = path.join(dirBackup, `foco-${carimbo}.md`);
  fs.copyFileSync(alvoFoco, alvoBackup);

  // --- rodízio: deleta TODAS as cópias antigas enquanto houver excesso ---
  let arquivos = fs.readdirSync(dirBackup)
    .filter(f => f.startsWith('foco-') && f.endsWith('.md'))
    .sort();

  while (arquivos.length > teto) {
    const maisAntigo = path.join(dirBackup, arquivos[0]);
    fs.unlinkSync(maisAntigo);
    // Relê a lista após apagar, porque a ordem mudou
    arquivos = fs.readdirSync(dirBackup)
      .filter(f => f.startsWith('foco-') && f.endsWith('.md'))
      .sort();
  }

  const original = fs.readFileSync(alvoFoco, 'utf8');
  const relato = {
    raiz, teto, foco: alvoFoco, backup: alvoBackup,
    bytes: bytes(original), totalBackups: arquivos.length,
  };

  if (tem('json')) {
    console.log(JSON.stringify(relato, null, 2));
    return;
  }

  console.log(`backup: ${alvoBackup}`);
  console.log(`  ${bytes(original)} bytes do FOCO.md`);
  console.log(`  cópias guardadas: ${arquivos.length}/${teto}`);
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
//
// RODADA 2 (retrabalho): a primeira versão roteava LINHA A LINHA, e contra o
// FOCO.md real do usuário (prosa com quebra dura em ~80 colunas) isso partia
// frases no meio — cinco parágrafos cortados, com metades órfãs nos dois
// arquivos. "Nada se perde" (a conservação de bytes) não bastava: os dois
// arquivos ficavam ilegíveis, e a fragmentação da identidade fazia o
// `priorizarFoco` deixar de reconhecê-la (ela para de começar com `**` quando
// a primeira linha sobrevivente é prosa solta), reintroduzindo exatamente o
// "só ponteiros" que a issue existe para resolver.
//
// A unidade agora é o PARÁGRAFO (bloco separado por linha em branco), nunca a
// linha. Um parágrafo vai inteiro para um lado ou para o outro. Dentro de
// `## Ativo`, o PRIMEIRO parágrafo que começa com `**` é a identidade — a
// mesma regra que `priorizarFoco` usa (`secaoAtual === 'Ativo' && /^\*\*/`) —
// e fica no tático INTEIRO, com a linha em branco antes dele preservada (é
// essa linha em branco que faz o parágrafo seguinte ser reconhecido como
// bloco próprio). Qualquer outro parágrafo da região (prosa-meta, contexto de
// negócio) vai inteiro para o ESTRATEGIA.md.
//
// CONSEQUÊNCIA ACEITA, não escondida: quando a identidade mistura campo
// tático (Pastas:, Critério de pronto) com prosa de negócio NO MESMO
// parágrafo — o formato real do usuário faz isso —, a prosa vai junto pro
// lado tático, porque não dá para cortar dentro do parágrafo sem repetir o
// defeito que motivou este retrabalho. Isso pode fazer a identidade sozinha
// estourar o orçamento do bloco de foco; `separar` não tenta consertar
// reescrevendo a prosa do usuário — ele MEDE e AVISA (`medirAjusteIdentidade`
// abaixo), e quem decide o que cortar é o usuário, olhando o aviso.

/**
 * Divide a região de IDENTIDADE/PROSA de `## Ativo` (tudo antes de "Marcos" e
 * "Avanços:") em PARÁGRAFOS — nunca em linhas — e separa o primeiro parágrafo
 * que começa com `**` (a identidade, mesma regra do `priorizarFoco`) do resto
 * (prosa-meta e contexto de negócio, que vão inteiros para o ESTRATEGIA.md).
 *
 * @param {string} regiao texto entre o cabeçalho `## Ativo` e o bloco "Marcos"
 * @returns {{identidade: string, prosa: string}}
 */
function dividirPorParagrafo(regiao) {
  const paragrafos = String(regiao || '')
    .split(/\n{2,}/)
    .map((p) => p.trim())
    .filter(Boolean);

  let identidade = '';
  const prosa = [];
  let identidadeAchada = false;
  for (const p of paragrafos) {
    if (!identidadeAchada && /^\*\*/.test(p)) {
      identidade = p;
      identidadeAchada = true;
    } else {
      prosa.push(p);
    }
  }
  return { identidade, prosa: prosa.join('\n\n') };
}

/**
 * Divide o texto de `## Ativo` (com o cabeçalho `## Ativo` incluso) em quatro
 * pedaços: o cabeçalho, a identidade (parágrafo inteiro, ver
 * `dividirPorParagrafo`), o bloco "Marcos" (inteiro, intocado) e o bloco
 * "Avanços:" (inteiro, intocado — ele já tem cadência própria via
 * `rotacionar`, acima). A PROSA que sobra é o quinto pedaço, para o
 * ESTRATEGIA.md.
 *
 * Marcos e Avanços continuam recortados por MARCADOR (não por parágrafo):
 * são listas, o hook já os resume na injeção (`resumirMarcos`,
 * `resumirAvancos`) sem precisar que o arquivo em disco mude de forma, e o
 * corte por marcador é o mesmo que `resumirMarcos`/`recortarBloco` já usam —
 * reaproveitar a convenção evita uma segunda definição do que é "o bloco
 * Marcos" divergindo da primeira.
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

  const { identidade, prosa } = dividirPorParagrafo(resto);
  return { cabecalho, essencial: identidade, blocoMarcos, blocoAvancos, prosa };
}

/**
 * Motor PURO de `separar`: recebe o texto do FOCO.md monolítico, devolve
 * `{ foco, estrategia }` — o conteúdo dos dois arquivos. Não lê nem escreve
 * disco; quem faz I/O é `separar()`, abaixo, seguindo a mesma divisão
 * motor/adaptador de `hooks/lib/contexto-sessao.cjs`.
 *
 * NADA SE PERDE: toda seção e todo parágrafo do original está em UM dos dois
 * textos devolvidos, sempre INTEIRO — o que muda é só o arquivo, nunca o
 * conteúdo nem a forma da frase. As únicas exceções são estruturais e
 * pequenas (o título `# Estratégia` do arquivo novo, e o cabeçalho "## Ativo
 * (contexto)" que dá um lar para a prosa que saiu de dentro de `## Ativo`) —
 * nenhuma delas apaga ou reparte uma frase do usuário.
 *
 * CRLF: se o original usa `\r\n` (o arquivo real do usuário usa), a saída dos
 * dois arquivos é normalizada de volta para `\r\n` — todo o processamento
 * interno roda em `\n` (é a unidade que `split`/`match` deste arquivo inteiro
 * assume), e converter só na saída evita misturar as duas convenções no
 * mesmo arquivo, que é o defeito que a rodada passada introduziu.
 */
function dividirFoco(textoOriginal) {
  const bruto = String(textoOriginal || '');
  const usaCRLF = /\r\n/.test(bruto);
  const texto = bruto.replace(/\r\n/g, '\n');

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
  let foco = `${partesFoco.filter(Boolean).join('\n\n')}\n`;

  const partesEstrategia = ['# Estratégia'];
  if (ativoDividido && ativoDividido.prosa) {
    partesEstrategia.push(`## Ativo (contexto)\n\n${ativoDividido.prosa}`);
  }
  partesEstrategia.push(...estrategicas);
  let estrategia = `${partesEstrategia.filter(Boolean).join('\n\n')}\n`;
  let identidadeTexto = ativoDividido ? ativoDividido.essencial : '';

  if (usaCRLF) {
    foco = foco.replace(/\n/g, '\r\n');
    estrategia = estrategia.replace(/\n/g, '\r\n');
    identidadeTexto = identidadeTexto.replace(/\n/g, '\r\n');
  }

  return { foco, estrategia, identidade: identidadeTexto };
}

/**
 * Marcas que `hooks/lib/contexto-sessao.cjs` emite quando o bloco de foco (ou
 * a identidade dentro dele) não coube na injeção. Mesma lista do critério de
 * aceite da issue — usada aqui para MEDIR, não para decidir nada em produção.
 */
const RE_MARCA_CORTE = /O foco saiu com só ponteiros|O foco não coube|identidade cortada por espaço/;

/**
 * Mede se o parágrafo de IDENTIDADE do `## Ativo` tático cabe na injeção real
 * — rodando o MESMO `montarContexto` que o hook usa, com o SKILL.md de
 * verdade lido do disco, em vez de reimplementar a conta do orçamento (que já
 * mora em `hooks/lib/contexto-sessao.cjs` e diverge se copiada aqui).
 *
 * NENHUM ARQUIVO É ESCRITO por esta função — ela só monta candidatos EM
 * MEMÓRIA e olha o texto que `montarContexto` devolveria.
 *
 * Quando a identidade não cabe inteira, faz uma busca binária por CARACTERE
 * no próprio parágrafo para achar o maior prefixo que ainda passa sem marca
 * de corte — não para usar esse prefixo em lugar nenhum (`separar` nunca
 * reescreve a prosa do usuário), só para reportar a conta: quantos bytes
 * cabem, quantos faltam.
 *
 * @param {object} o
 * @param {string} o.focoCandidato   o texto que IRIA para o FOCO.md tático
 * @param {string} o.identidade      só o parágrafo de identidade, para medir o déficit
 * @param {string} [o.root]          raiz real (entra no custo fixo do rodapé — não usar placeholder)
 * @param {boolean} [o.temEstrategia]
 * @param {string} [o.estrategiaPath]
 * @returns {{identidadeBytes: number, cabe: boolean, maxBytes: number, deficit: number}}
 */
function medirAjusteIdentidade(o) {
  const { montarContexto } = require('../hooks/lib/contexto-sessao.cjs');
  const caminhoSkill = path.join(LOCAL, 'skills', 'rainforest-mind', 'SKILL.md');
  let skillText = '';
  try { skillText = fs.readFileSync(caminhoSkill, 'utf8'); } catch { /* sem SKILL.md, mede mesmo assim */ }
  const raizFallback = o.estrategiaPath ? path.dirname(o.estrategiaPath) : 'C:\\medicao-separar';

  const identidadeBytes = bytes(o.identidade || '');
  if (!o.identidade) return { identidadeBytes: 0, cabe: true, maxBytes: 0, deficit: 0 };

  const rodar = (focoTexto) => montarContexto({
    skillText,
    focoText: focoTexto,
    caminhoSkill,
    // O `root` real, NAO um placeholder curto: ele entra na linha "Arquivos
    // de apoio" do rodape, que e CUSTO FIXO do orcamento -- um placeholder
    // mais curto que o caminho real SUBESTIMA esse custo e reporta "cabe"
    // quando a injecao de verdade vai cortar. Medido nesta rodada: com
    // placeholder a identidade cabia inteira; com o `raiz` real (mais longo)
    // a mesma identidade sai cortada -- a diferenca era so o tamanho do
    // caminho no rodape.
    root: o.root || raizFallback,
    temEstrategia: Boolean(o.temEstrategia),
    estrategiaPath: o.estrategiaPath,
  });

  const trocarIdentidade = (idTexto) => {
    // Troca só o parágrafo de identidade dentro do candidato real, mantendo
    // Marcos/Avanços/demais seções exatamente como `separar` os produziu —
    // a medição tem que refletir o MESMO orçamento que o resto do arquivo
    // tático já está consumindo, não um cenário isolado e mais folgado.
    return o.identidade
      ? o.focoCandidato.replace(o.identidade, idTexto)
      : o.focoCandidato;
  };

  const cabeInteira = (idTexto) => {
    if (!idTexto) return true;
    const ctx = rodar(trocarIdentidade(idTexto));
    const primeiraLinha = idTexto.split('\n')[0];
    return ctx.includes(primeiraLinha) && !RE_MARCA_CORTE.test(ctx);
  };

  if (cabeInteira(o.identidade)) {
    return { identidadeBytes, cabe: true, maxBytes: identidadeBytes, deficit: 0 };
  }

  const chars = Array.from(o.identidade);
  let baixo = 0;
  let alto = chars.length;
  while (baixo < alto) {
    const meio = Math.ceil((baixo + alto) / 2);
    if (cabeInteira(chars.slice(0, meio).join(''))) baixo = meio; else alto = meio - 1;
  }
  const maxBytes = bytes(chars.slice(0, baixo).join(''));
  return { identidadeBytes, cabe: false, maxBytes, deficit: identidadeBytes - maxBytes };
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
  const { foco, estrategia, identidade } = dividirFoco(original);

  // A CONTA, não o conserto (Issue #74, retrabalho): "separar" nunca reescreve
  // a prosa do usuário para caber no orçamento — quando o parágrafo de
  // identidade (mantido INTEIRO, ver dividirAtivo/dividirPorParagrafo) não
  // cabe na injeção real, isso é medido e IMPRESSO, para o usuário decidir o
  // que cortar. temEstrategia:true porque a medição é sobre o cenário PÓS-
  // split (é para lá que ESTRATEGIA.md está indo).
  const ajuste = medirAjusteIdentidade({
    focoCandidato: foco, identidade, root: raiz, temEstrategia: true, estrategiaPath: alvoEstrategia,
  });

  const relato = {
    raiz, foco: alvoFoco, estrategia: alvoEstrategia,
    antes: bytes(original), focoDepois: bytes(foco), estrategiaDepois: bytes(estrategia),
    identidadeBytes: ajuste.identidadeBytes, identidadeCabe: ajuste.cabe,
    identidadeMaxBytes: ajuste.maxBytes, identidadeDeficit: ajuste.deficit,
    aplicado: false,
  };

  const linhaConta = ajuste.identidadeBytes === 0
    ? null
    : ajuste.cabe
      ? `Identidade do foco ativo: ${ajuste.identidadeBytes} B — cabe inteira na injeção.`
      : `⚠️ Identidade do foco ativo: ${ajuste.identidadeBytes} B, mas só ${ajuste.maxBytes} B cabem na ` +
        `injeção real — faltam cortar ~${ajuste.deficit} B (o parágrafo mistura campo tático com ` +
        `prosa de negócio; "separar" não reescreve a frase do usuário — corte manual no FOCO.md ` +
        `depois do split, ou aceite o aviso de corte na injeção).`;

  if (tem('json') && !tem('aplicar')) {
    console.log(JSON.stringify({ ...relato, planoFoco: foco, planoEstrategia: estrategia }, null, 2));
    return;
  }

  if (!tem('aplicar')) {
    console.log(`FOCO.md hoje: ${relato.antes} B.`);
    console.log(`Plano: ${alvoFoco} (${relato.focoDepois} B) + ${alvoEstrategia} (${relato.estrategiaDepois} B).`);
    if (linhaConta) console.log(linhaConta);
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
  if (linhaConta) console.log(linhaConta);
}

function main() {
  const comando = process.argv[2];
  if (comando === 'rotacionar') return rotacionar();
  if (comando === 'separar') return separar();
  if (comando === 'backup') return backup();
  if (comando === 'caminho') return caminho();
  console.error('uso: node scripts/foco.cjs rotacionar [--aplicar] [--teto N] [--raiz DIR] [--json]');
  console.error('     node scripts/foco.cjs separar [--aplicar] [--raiz DIR] [--json]');
  console.error('     node scripts/foco.cjs backup [--teto N] [--raiz DIR] [--json]');
  console.error('     node scripts/foco.cjs caminho [--raiz DIR] [--json]');
  process.exit(2);
}

if (require.main === module) main();
module.exports = {
  rotacionar, separar, backup, caminho, main,
  dividirFoco, dividirAtivo, dividirPorParagrafo, medirAjusteIdentidade,
  RAIZ_PADRAO,
};
