#!/usr/bin/env node
/**
 * Portões — oráculos executáveis para o ciclo do rainforest.
 *
 * Reescrito a partir de unlazy (MIT), Leonxlnx. O mecanismo adotado é o do
 * original — um portão declara o comando que o decide e o marcador que o output
 * precisa conter, e cumprido é exit 0 E match, os dois, re-executáveis a
 * qualquer momento. O que NÃO veio junto está nomeado no design
 * (`docs/rainforest/design/fluxo-6-design-portoes.md`, seção "O que fica de
 * fora"): aprovação de comandos herdados, `OWNS:`, waves, dispatch paralelo.
 *
 * O PROBLEMA QUE ISTO RESOLVE. O fluxo 1 endureceu `executar`/`verificar`: `ok`
 * exige evidência colada. Mas evidência colada é prosa — o modelo cola um output
 * e afirma que ele prova o critério, e nada re-executa. Nada impede que o
 * critério seja "tudo funciona" com evidência `echo ok`. O portão troca a
 * afirmação pela re-execução.
 *
 * E O QUE ELE NÃO RESOLVE SOZINHO. O checker prova que o oráculo declarado rodou
 * e devolveu o prometido; ele não pergunta se o oráculo vale alguma coisa.
 * `CHECK: echo ok` / `ESPERA: ok` passa em tudo. Por isso o `lint` existe, e por
 * isso ele é a peça de maior valor deste arquivo — a autoria do portão é o elo
 * fraco, e o lint audita a autoria sem executar nada.
 *
 * Uso:
 *   node scripts/portoes.cjs status <arquivo>        # parse + estado, NUNCA executa
 *   node scripts/portoes.cjs lint   <arquivo>        # qualidade dos oráculos, NUNCA executa
 *   node scripts/portoes.cjs rodar  <arquivo>        # executa os CHECKs pendentes, em ordem
 *   node scripts/portoes.cjs rodar --reverificar <a> # re-executa TODOS, inclusive cumpridos
 *
 * Exit codes — o contrato, porque quem chama decide por ele:
 *   0  tudo certo (status/lint limpos; rodar com todos os portões cumpridos)
 *   1  veredito negativo (lint achou erro; rodar teve portão não cumprido ou ABANDONA)
 *   2  arquivo malformado, ou uso errado — nunca é conclusão sobre os portões
 *
 * A distinção entre 1 e 2 é o ponto: "os portões reprovaram" e "eu não consegui
 * ler os portões" são respostas diferentes, e tratá-las igual foi o que fez o
 * guarda do Issue #142 responder com confiança sobre o repositório errado.
 */

'use strict';

const fs = require('fs');
const path = require('path');

/** Estados possíveis de um portão. */
const CUMPRIDO = 'cumprido';
const PENDENTE = 'pendente';
const ABANDONADO = 'abandonado';
/**
 * `inconsistente` é o estado que o design não previu e a implementação obrigou a
 * nomear: checkbox `[x]` com `EVIDENCIA: pendente`. O design diz "checkbox
 * marcado com EVIDENCIA pendente conta como não cumprido" — mas contar como
 * pendente em silêncio esconde que alguém marcou o checkbox à mão. Não-cumprido
 * ele é; mudo é que não pode ser.
 */
const INCONSISTENTE = 'inconsistente';

/** Lê markdown normalizando BOM e CRLF. Mesma forma de `conferir-fluxo.cjs`. */
function lerMarkdown(arquivo) {
  if (!fs.existsSync(arquivo)) return null;
  let conteudo = fs.readFileSync(arquivo, 'utf8');
  if (conteudo.charCodeAt(0) === 0xFEFF) conteudo = conteudo.slice(1);
  return conteudo.replace(/\r\n/g, '\n');
}

/** Erro de parse — carrega a mensagem que o usuário vai ler, já pronta. */
class ErroDeParse extends Error {}

const RE_PORTAO = /^\s*-\s*\[( |x|X)\]\s*(P\d+)\s*:\s*(.*)$/;
const RE_CAMPO = /^\s*(CHECK|ESPERA|EVIDENCIA)\s*:\s*(.*)$/;
const RE_ABANDONA = /^\s*ABANDONA\s*:\s*(P\d+)\s*(.*)$/;

/**
 * Parseia o arquivo de portões.
 *
 * @returns {{portoes: Array, abandonos: Map<string,string>}}
 * @throws {ErroDeParse} em id duplicado, arquivo sem portão, CHECK sem ESPERA
 *   (ou vice-versa), ABANDONA sem razão, ou ABANDONA de portão inexistente.
 */
function parsear(conteudo) {
  const linhas = conteudo.split('\n');
  const portoes = [];
  const abandonos = new Map();
  const vistos = new Set();
  let atual = null;

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];
    const numero = i + 1;

    const mAbandona = RE_ABANDONA.exec(linha);
    if (mAbandona) {
      const id = mAbandona[1];
      const razao = mAbandona[2].trim();
      if (!razao) {
        throw new ErroDeParse(
          `linha ${numero}: ABANDONA de ${id} sem razão. Abandono sem razão é `
          + `desistência muda — a razão é obrigatória e diz o que precisa de decisão humana.`
        );
      }
      if (abandonos.has(id)) {
        throw new ErroDeParse(`linha ${numero}: ABANDONA repetido para ${id}.`);
      }
      abandonos.set(id, razao);
      atual = null;
      continue;
    }

    const mPortao = RE_PORTAO.exec(linha);
    if (mPortao) {
      const marcado = mPortao[1].toLowerCase() === 'x';
      const id = mPortao[2];
      const titulo = mPortao[3].trim();
      if (vistos.has(id)) {
        throw new ErroDeParse(
          `linha ${numero}: id de portão duplicado: ${id}. Id é a chave pela qual `
          + `a evidência é gravada e o ABANDONA aponta — duplicado torna as duas ambíguas.`
        );
      }
      vistos.add(id);
      atual = {
        id, titulo, marcado, linha: numero,
        check: null, espera: null, evidencia: null,
      };
      portoes.push(atual);
      continue;
    }

    const mCampo = RE_CAMPO.exec(linha);
    if (mCampo && atual) {
      const chave = mCampo[1];
      const valor = mCampo[2].trim();
      if (chave === 'CHECK') atual.check = valor;
      else if (chave === 'ESPERA') atual.espera = valor;
      else atual.evidencia = valor;
    }
  }

  if (portoes.length === 0) {
    throw new ErroDeParse(
      'arquivo sem portão nenhum. Arquivo de portões vazio não é "tudo cumprido" — '
      + 'é arquivo que não diz nada, e tratar isso como sucesso é o furo clássico.'
    );
  }

  for (const p of portoes) {
    const temCheck = p.check !== null && p.check !== '';
    const temEspera = p.espera !== null && p.espera !== '';
    if (temCheck !== temEspera) {
      const falta = temCheck ? 'ESPERA' : 'CHECK';
      throw new ErroDeParse(
        `linha ${p.linha}: ${p.id} tem ${temCheck ? 'CHECK' : 'ESPERA'} sem ${falta}. `
        + `Portão executável tem os dois; portão manual não tem nenhum. Meio-termo é `
        + `oráculo pela metade: ou roda um comando cujo sucesso ninguém definiu, ou `
        + `espera um marcador que nada produz.`
      );
    }
  }

  for (const id of abandonos.keys()) {
    if (!vistos.has(id)) {
      throw new ErroDeParse(
        `ABANDONA aponta para ${id}, que não existe no arquivo.`
      );
    }
  }

  return { portoes, abandonos };
}

/**
 * Estado de um portão, decidido pela EVIDÊNCIA, nunca pelo checkbox sozinho.
 *
 * O arquivo não é a verdade; a execução é. O checkbox é conveniência de leitura
 * humana — e é editável por qualquer um, inclusive por um modelo com pressa.
 */
function estadoDe(portao, abandonos) {
  if (abandonos.has(portao.id)) return ABANDONADO;

  let evidenciaReal = false;
  if (portao.evidencia && portao.evidencia !== 'pendente') {
    try {
      const j = JSON.parse(portao.evidencia);
      evidenciaReal = j && j.match === true && j.exit === 0;
    } catch (_) {
      evidenciaReal = false;
    }
  }

  if (portao.marcado && !evidenciaReal) return INCONSISTENTE;
  if (!portao.marcado && evidenciaReal) return INCONSISTENTE;
  return evidenciaReal ? CUMPRIDO : PENDENTE;
}

/** Carrega e parseia, ou sai com 2 dizendo por quê. */
function carregar(arquivo) {
  const conteudo = lerMarkdown(arquivo);
  if (conteudo === null) {
    console.error(`RECUSADO: arquivo de portões não existe: ${arquivo}`);
    process.exit(2);
  }
  try {
    return parsear(conteudo);
  } catch (err) {
    if (err instanceof ErroDeParse) {
      console.error(`RECUSADO: ${arquivo} malformado.`);
      console.error(`  ${err.message}`);
      process.exit(2);
    }
    throw err;
  }
}

/**
 * `status` — reporta o estado de cada portão. NUNCA executa CHECK nenhum.
 *
 * Esta é a garantia mais importante do arquivo, e a bateria a prova com um
 * fixture cujo CHECK criaria um arquivo-sentinela: depois do `status`, a
 * sentinela não existe. Um leitor de estado que executa comando é uma superfície
 * de execução que ninguém pediu — e `status` é justamente o modo que se roda
 * para decidir se vale a pena executar.
 */
function cmdStatus(arquivo) {
  const { portoes, abandonos } = carregar(arquivo);
  let pendentes = 0;
  for (const p of portoes) {
    const estado = estadoDe(p, abandonos);
    if (estado !== CUMPRIDO && estado !== ABANDONADO) pendentes++;
    let sufixo = '';
    if (estado === ABANDONADO) sufixo = ` — ${abandonos.get(p.id)}`;
    if (estado === INCONSISTENTE) {
      sufixo = ' — checkbox e EVIDENCIA discordam; vale a EVIDENCIA (não cumprido)';
    }
    console.log(`${p.id}: ${estado}${sufixo}`);
  }
  console.log(
    `PARSE OK — ${portoes.length} portão(ões), ${pendentes} não cumprido(s), `
    + `${abandonos.size} abandonado(s)`
  );
  process.exit(0);
}

function uso() {
  console.error('uso: node scripts/portoes.cjs status <arquivo>');
  console.error('     node scripts/portoes.cjs lint   <arquivo> [--strict]');
  console.error('     node scripts/portoes.cjs rodar  <arquivo> [--reverificar]');
  process.exit(2);
}

function main() {
  const argv = process.argv.slice(2);
  const modo = argv[0];
  const arquivo = argv.find((a, i) => i > 0 && !a.startsWith('--'));

  if (!modo || !arquivo) uso();
  const caminho = path.resolve(arquivo);

  if (modo === 'status') return cmdStatus(caminho);
  if (modo === 'lint' || modo === 'rodar') {
    console.error(`'${modo}' ainda não implementado (tarefas 2 e 3 do plano).`);
    process.exit(2);
  }
  uso();
}

if (require.main === module) main();
module.exports = {
  parsear, estadoDe, lerMarkdown, ErroDeParse,
  CUMPRIDO, PENDENTE, ABANDONADO, INCONSISTENTE,
};
