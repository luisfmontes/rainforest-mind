'use strict';
const { cortarBytes } = require('./bytes.cjs');

/**
 * memoria-sessao.cjs — motor puro do SessionStart de memória (memoria-session-start.cjs).
 *
 * É PURO de propósito: entra JSON de observações, sai TEXTO. Não lê arquivo,
 * não abre banco, não abre socket. Quem faz I/O é o adaptador (memoria-session-start.cjs).
 * A divisão é a mesma do contexto-sessao.cjs de propósito — sem ela, testar
 * a injeção exige subir uma sessão de verdade.
 *
 * ORÇAMENTO: o bloco de memória é item separado (D10) com teto próprio em bytes,
 * independente do teto de 8.000 B do hook de foco. A disputa por bytes já deixou
 * regras fora da injeção antes; este item de contexto novo não deve repetir isso.
 *
 * Teto: dimensionado em bytes, com corte ANUNCIADO. Banco ausente/vazio/corrompido
 * entrega bloco vazio, exit 0 — nunca erro.
 */

/** Tetos do bloco de memória, em BYTES. */
const TETOS = {
  /** Teto do bloco inteiro de memória. */
  MEMORIA_MAX_BYTES: 3000,
  /**
   * Teto da LEGENDA VISÍVEL de memória (o `systemMessage`), em BYTES.
   *
   * Canal separado do `additionalContext` — o harness conta os dois em métricas
   * distintas —, então este teto não disputa bytes com as 14 observações
   * injetadas. É pequeno porque a legenda responde UMA pergunta ("onde eu tinha
   * parado?"), não substitui o corpus.
   */
  LEGENDA_MAX_BYTES: 420,
  /** Quantas marcas a legenda mostra. O resto continua no `additionalContext`. */
  LEGENDA_MARCAS: 2,
  /**
   * Teto de UMA linha da legenda, em CARACTERES — não em bytes.
   *
   * A unidade importa, e ela estava errada até 2026-08-25: o teto era de 150 BYTES,
   * mas quem corta a linha é o TERMINAL, que conta caractere. Com acento e emoji,
   * 150 bytes viraram 143 caracteres, e o harness ainda prefixa
   * `SessionStart:startup says: ` (27 caracteres) na primeira linha do bloco — 170
   * de largura, cortados com `…` no meio da frase. Medido em captura de tela dele.
   *
   * É a mesma família do `AVANCOS_MAX_BYTES` de `contexto-sessao.cjs`: parâmetro cuja
   * unidade não é a unidade do problema continua parecendo certo enquanto mente.
   *
   * 90 é dimensionado para o pior caso — primeira linha, com prefixo, em terminal de
   * 120 colunas. E é disciplina, não só limite: legenda que não cabe num olhar para
   * de ser lida.
   */
  LEGENDA_LINHA_MAX_CHARS: 90,
};

/**
 * Teto duro em BYTES, com aviso explícito de corte que cabe dentro do teto.
 * `cortarBytes` vem de bytes.cjs — compartilhada com contexto-sessao.cjs.
 */
function limitarBytes(texto, maxBytes, nomeDoBloco) {
  const s = String(texto || '');
  if (Buffer.byteLength(s, 'utf8') <= maxBytes) return s;
  const aviso = `\n\n[${nomeDoBloco} truncado no teto de ${maxBytes} bytes — o arquivo em disco está inteiro, leia-o se precisar do resto.]`;
  const espaco = Math.max(0, maxBytes - Buffer.byteLength(aviso, 'utf8'));
  return cortarBytes(s, espaco).trimEnd() + aviso;
}

/**
 * Corta em CARACTERES (code points), acrescentando `…` quando cortou.
 *
 * `Array.from` e não `slice`: emoji fora do plano básico ocupa dois code units, e
 * `slice` por índice de string parte o par substituto no meio — o terminal desenha o
 * losango de caractere inválido. O teto conta o `…` dentro do limite, para que o
 * resultado nunca passe do que foi pedido.
 *
 * @param {string} texto
 * @param {number} maxChars teto em caracteres, incluindo a reticência
 * @returns {string}
 */
function cortarCaracteres(texto, maxChars) {
  const s = String(texto || '');
  const chars = Array.from(s);
  if (chars.length <= maxChars) return s;
  return chars.slice(0, Math.max(0, maxChars - 1)).join('').trimEnd() + '…';
}

/**
 * Extrai título e subtítulo de uma observação (conteúdo estruturado em markdown).
 * Observações têm estrutura: ## Título\n\nSubtítulo\n\n### Seções...
 *
 * @param {string} conteudo conteúdo da observação
 * @returns {object} {titulo, subtitulo}
 */
function extrairTituloESubtitulo(conteudo) {
  if (!conteudo) return { titulo: '', subtitulo: '' };

  const linhas = conteudo.split('\n').map(l => l.trim()).filter(Boolean);

  // Primeira linha não vazia é o título (remove ## se existir)
  let titulo = linhas[0] || '';
  titulo = titulo.replace(/^#+\s*/, '').trim();

  // Próxima linha não vazia que não seja cabeçalho (###, ##, etc) é o subtítulo
  let subtitulo = '';
  for (let i = 1; i < linhas.length; i++) {
    if (!linhas[i].match(/^#+\s/)) {
      subtitulo = linhas[i];
      break;
    }
  }

  return { titulo, subtitulo };
}

/**
 * Formata uma observação como linha curta com título e subtítulo.
 * Formato: [data (projeto)] título — subtítulo
 *
 * @param {object} obs observação do banco
 * @param {object} [apelidos] mapa chave-do-banco -> nome curto para exibição
 * @returns {string} linha formatada
 */
function formatarObservacao(obs, apelidos) {
  if (!obs) return '';
  const { conteudo, projeto, criada_em } = obs;
  // criada_em é timestamp ISO; tira a hora para economizar bytes.
  const data = (criada_em || '').split('T')[0] || '';
  // O rótulo exibe o apelido curto quando há um. A chave que o banco guarda é a
  // pasta do harness (`C--Projetos-rainforest-mind`), ~12 bytes a mais por linha
  // que o nome curto — e o bloco tem teto duro. Medido em 2026-08-22: a chave
  // longa derrubou a injeção de 15 observações para 12.
  const nome = (apelidos && apelidos[projeto]) || projeto;
  const proj = nome ? ` (${nome})` : '';

  // Extrai título e subtítulo do conteúdo
  const { titulo, subtitulo } = extrairTituloESubtitulo(conteudo);

  // Formata como: [data (projeto)] título — subtítulo
  let linha = `[${data}${proj}]`;
  if (titulo) linha += ` ${titulo}`;
  if (subtitulo) linha += ` — ${subtitulo}`;

  return linha.trim();
}

/**
 * Constrói o aviso de corte do bloco de memória — vai no TOPO do payload, e
 * NOMEIA quantas observações/resumos ficaram de fora (não o genérico
 * "conteúdo truncado").
 *
 * Corte silencioso já aconteceu aqui: em 2026-08-10, 50 de 50 sessões
 * receberam ~2,2 KB de um payload de 32 KB, e regras inteiras nunca chegaram
 * a sessão nenhuma — sem uma linha dizendo que 93% do texto tinha sumido.
 *
 * @param {number} cortadas quantas linhas (observações/resumos) ficaram de fora
 * @param {number} total quantas linhas existiam antes do corte
 * @param {number} maxBytes teto em bytes do bloco
 * @returns {string} aviso com quebra dupla no fim, ou '' quando nada foi cortado
 */
function construirAvisoCorteMemoria(cortadas, total, maxBytes) {
  if (cortadas <= 0) return '';
  return `⚠️ Memória acima do orçamento: ${cortadas} de ${total} observação(ões)/resumo(s) não couberam no teto de ${maxBytes} B e foram cortados.\n\n`;
}

/**
 * Corta o bloco de memória por OBSERVAÇÃO INTEIRA (nunca no meio de uma
 * linha), mantendo as mais recentes (início do array) e descartando as mais
 * antigas primeiro, com o aviso de `construirAvisoCorteMemoria` no topo.
 *
 * Busca do maior prefixo de linhas para o menor: o aviso muda de tamanho
 * conforme quantas ficam de fora, então o ponto de corte certo é o primeiro
 * que cabe com o PRÓPRIO aviso já somado — não dá para calcular em uma
 * conta só.
 *
 * @param {string[]} linhas linhas já formatadas, mais recentes primeiro
 * @param {string} cabecalho cabeçalho fixo do bloco
 * @param {string} rodape rodapé fixo do bloco
 * @param {number} maxBytes teto em bytes
 * @returns {string}
 */
function travarOrcamentoMemoria(linhas, cabecalho, rodape, maxBytes) {
  for (let n = linhas.length; n >= 0; n--) {
    const cortadas = linhas.length - n;
    const aviso = construirAvisoCorteMemoria(cortadas, linhas.length, maxBytes);
    const corpo = linhas.slice(0, n).join('\n');
    const texto = aviso + cabecalho + corpo + rodape;
    if (Buffer.byteLength(texto, 'utf8') <= maxBytes) {
      return texto;
    }
  }
  // Nem cabeçalho + rodapé + aviso, sozinhos (0 observações), coube no teto:
  // corte duro em bytes como último recurso, mas o aviso continua no topo.
  const aviso = construirAvisoCorteMemoria(linhas.length, linhas.length, maxBytes);
  return cortarBytes(aviso + cabecalho + rodape, maxBytes);
}

/**
 * Monta o bloco de memória para injeção.
 *
 * @param {object} o
 * @param {array} [o.observacoes] array de observações do banco
 * @param {object} [o.apelidos] mapa chave-do-banco -> nome curto para exibição
 * @param {string[]} [o.avisos] linhas de aviso de PIPELINE (Tarefa 6, D8 —
 *   captura/manutenção paradas), que entram no TOPO do bloco, DENTRO do
 *   mesmo teto de bytes do corpus — nunca um canal à parte que só se
 *   preenche se sobrar espaço. Um corpus de 11 mil observações reais já
 *   enche o teto de 3.000 B sozinho; um aviso que só aparecesse "se coubesse
 *   depois" nunca apareceria em produção — o mesmo silêncio que o D8 existe
 *   pra matar (#282, pipeline parado por 13 dias sem ninguém ver). Por isso
 *   o aviso vira parte do CABEÇALHO fixo, e é a observação mais antiga que
 *   cede lugar quando o orçamento aperta — o mesmo mecanismo que já existe
 *   pra o aviso de CORTE (`travarOrcamentoMemoria`), generalizado.
 * @returns {string} bloco montado, dentro do teto de bytes
 */
function montarMemoria(o) {
  const observacoes = Array.isArray(o?.observacoes) ? o.observacoes : [];
  const apelidos = (o && typeof o.apelidos === 'object' && o.apelidos) || null;
  const avisos = Array.isArray(o?.avisos) ? o.avisos.filter(Boolean) : [];
  const prefixoAvisos = avisos.length ? `${avisos.join('\n')}\n\n` : '';

  // Sem observação nenhuma: sem corpus pra injetar. O aviso de pipeline,
  // se houver, ainda é a única coisa que precisa chegar à abertura — banco
  // vazio não é motivo pra calar "a captura está parada".
  if (!observacoes.length) {
    if (!avisos.length) return '';
    const soAviso = avisos.join('\n');
    return Buffer.byteLength(soAviso, 'utf8') <= TETOS.MEMORIA_MAX_BYTES
      ? soAviso
      : cortarBytes(soAviso, TETOS.MEMORIA_MAX_BYTES);
  }

  // Cabeçalho do bloco — o aviso de pipeline (se houver) entra ANTES do
  // título do corpus, como prefixo fixo do cabeçalho.
  const cabecalho = `${prefixoAvisos}## Memória (corpus residentes)\n`;

  // Formata cada observação como linha curta (título + subtítulo).
  const linhas = observacoes.map((obs) => formatarObservacao(obs, apelidos)).filter(Boolean);
  const corpo = linhas.join('\n');

  // Rodapé ensinando busca sob demanda (D11 — mantém acesso ao corpus completo).
  // Formato: linha única começando com "mais: " para economizar bytes.
  const rodape = '\n\nmais: node scripts/memoria.cjs buscar --texto "<termo>"';

  const texto = cabecalho + corpo + rodape;

  // Cabendo no teto, devolve sem acrescentar byte nenhum de aviso de corte.
  if (Buffer.byteLength(texto, 'utf8') <= TETOS.MEMORIA_MAX_BYTES) {
    return texto;
  }

  // Estourou: corta por observação inteira e avisa NO TOPO o que ficou de
  // fora. O aviso de PIPELINE, por já estar dentro do `cabecalho`, nunca é
  // ele que sai — é sempre a observação mais antiga que cede lugar primeiro.
  return travarOrcamentoMemoria(linhas, cabecalho, rodape, TETOS.MEMORIA_MAX_BYTES);
}

/**
 * Monta a LEGENDA VISÍVEL da memória — o texto do `systemMessage`, que é o que o
 * usuario VÊ na abertura. O `montarMemoria` acima continua sendo o que o MODELO
 * recebe; são dois canais e dois públicos.
 *
 * Por que existe (2026-08-25): o corpus era injetado em silêncio no
 * `additionalContext`. O modelo abria a sessão sabendo onde tinha parado, e o
 * usuario abria a sessão olhando para uma tela vazia. Quem precisa lembrar do
 * fio da meada é ele.
 *
 * @param {object} o
 * @param {array} [o.observacoes] observações do banco, mais recentes primeiro
 * @param {object} [o.apelidos] mapa chave-do-banco -> nome curto
 * @param {number} [o.quantas] quantas marcas mostrar (default: TETOS.LEGENDA_MARCAS)
 * @param {number} [o.teto] teto em bytes (default: TETOS.LEGENDA_MAX_BYTES)
 * @returns {string} legenda, ou '' quando não há marca nenhuma
 */
function montarLegendaMemoria(o) {
  const observacoes = Array.isArray(o?.observacoes) ? o.observacoes.filter(Boolean) : [];
  if (!observacoes.length) return '';
  const apelidos = (o && typeof o.apelidos === 'object' && o.apelidos) || null;
  const quantas = Number.isFinite(o?.quantas) ? o.quantas : TETOS.LEGENDA_MARCAS;
  const teto = Number.isFinite(o?.teto) ? o.teto : TETOS.LEGENDA_MAX_BYTES;

  const linhas = observacoes.slice(0, Math.max(0, quantas)).map((obs) => {
    // Data curta: quem lê na abertura quer "quando", não o ano — e o ano custa
    // 5 dos 150 bytes da linha.
    const iso = String(obs.criada_em || '').split('T')[0];
    const partes = iso.split('-');
    const data = partes.length === 3 ? `${partes[2]}/${partes[1]}` : iso;
    const nome = (apelidos && apelidos[obs.projeto]) || obs.projeto || '';
    const { titulo, subtitulo } = extrairTituloESubtitulo(obs.conteudo);
    // Título vazio acontece (observação só com corpo): o subtítulo assume, em vez
    // de sair uma linha com data e nada.
    const texto = titulo || subtitulo || '(sem título)';
    const linha = `🧠 ${data}${nome ? ` ${nome}` : ''} — ${texto}`;
    // Corte MUDO aqui, ao contrário do teto do bloco: a linha já é um resumo de
    // resumo, e um aviso de truncamento por linha custaria mais que o texto.
    //
    // Por CARACTERE, e com `Array.from` em vez de `slice`: emoji fora do plano básico
    // ocupa dois code units em JS, e cortar por índice de string parte o par
    // substituto no meio — o terminal desenha o losango de caractere inválido, que é
    // pior que a linha longa que se queria evitar.
    return cortarCaracteres(linha, TETOS.LEGENDA_LINHA_MAX_CHARS);
  }).filter(Boolean);

  if (!linhas.length) return '';
  return limitarBytes(linhas.join('\n'), teto, 'Legenda da memória');
}

/**
 * Compõe a linha de aviso de CAPTURA parada, para o topo do bloco de memória
 * (Tarefa 6, D8).
 *
 * O `/saude` já acusava "pipeline parado há mais de 48h" e ninguém viu por 13
 * dias (#282) — aviso que só aparece quando alguém pergunta não é aviso. Esta
 * linha é a mesma informação, na abertura da sessão, sem precisar perguntar.
 *
 * SUPERFÍCIE HUMANA: a linha nomeia as TRÊS coisas de que a pessoa precisa
 * pra agir — que está parado, há quantas horas, e o comando que religa. Sem
 * uma das três ela não serve pra decidir nada.
 *
 * @param {number} horasParada horas desde a marca d'água mais antiga pendente
 *   (mesma seleção EXPLÍCITA de `scripts/saude.cjs`, verificação 3:
 *   `ORDER BY processada_em ASC LIMIT 1` — nunca a ordem de varredura do SQLite)
 * @param {{falhou: boolean, quando: string, horasDesde: number}|null} [ultimaManutencao]
 *   contexto da última passada de manutenção registrada no log — recebido
 *   pra manter a mesma assinatura de quem chama os dois avisos, mas NÃO
 *   entra no texto desta linha: se a manutenção TAMBÉM falhou, é
 *   `avisoDeManutencaoFalhou` (função irmã, abaixo) que soma a segunda
 *   linha, cada uma nomeando seu próprio problema sem repetir a do outro —
 *   escolha deliberada pra não ter duas linhas dizendo a mesma coisa de
 *   jeitos diferentes.
 * @returns {string} linha pronta, sem quebra de linha no fim
 */
function avisoDePipeline(horasParada, ultimaManutencao) {
  const horas = Math.max(0, Math.round(Number(horasParada) || 0));
  return `⚠️ Captura da memória parada há ${horas}h — religa com: node scripts/observar.cjs`;
}

/**
 * Compõe a linha de aviso de MANUTENÇÃO falhada (Tarefa 6, D8) — a segunda
 * metade do D8, independente da captura estar ou não em dia: uma passada de
 * manutenção que terminou em `manutencao: completa com falhas` significa que
 * reconciliação e/ou consolidação pararam de rodar, mesmo com a captura viva.
 *
 * @param {number} horasDesde horas desde que a última passada (com falha) terminou
 * @returns {string} linha pronta, sem quebra de linha no fim
 */
function avisoDeManutencaoFalhou(horasDesde) {
  const horas = Math.max(0, Math.round(Number(horasDesde) || 0));
  return `⚠️ Manutenção da memória falhou há ${horas}h (última passada) — religa com: node scripts/memoria.cjs manutencao`;
}

module.exports = {
  TETOS,
  montarMemoria,
  montarLegendaMemoria,
  formatarObservacao,
  extrairTituloESubtitulo,
  limitarBytes,
  cortarBytes,
  cortarCaracteres,
  construirAvisoCorteMemoria,
  travarOrcamentoMemoria,
  avisoDePipeline,
  avisoDeManutencaoFalhou,
};
