'use strict';
/**
 * Configuracao fixa da abertura entregue pelo mod (secao do system prompt, sem o
 * teto de entrega do hook SessionStart) e a validacao dela. Nenhum hook usa isto
 * ainda; as tarefas seguintes do fluxo `mod-regras-inteiras` consomem.
 *
 * Campos de `hooks/abertura-mod.json` (JSON nao tem comentario, entao ficam aqui):
 *
 *   elaboracoes           lista de numeros de regra cuja ELABORACAO inteira
 *                         (`skills/rainforest-mind/references/regra-NN.md`) entra
 *                         na abertura, em ordem. Toda regra listada precisa ter o
 *                         arquivo; as demais entram so pelo nucleo.
 *   orcamentoRegrasBytes  teto da parte das regras: NUCLEO medido + as elaboracoes.
 *   orcamentoFocoBytes    teto da parte do foco (FOCO.md).
 *   orcamentoMemoriaBytes teto da parte da memoria.
 *   orcamentoTotalBytes   teto do conjunto. E a soma EXATA das tres partes: subir
 *                         uma parte sem subir o total falha (soma > total), e
 *                         total acima da soma tambem falha (folga escondida).
 *
 * O nucleo NAO e digitado aqui: e medido com as mesmas funcoes que o hook
 * SessionStart usa (`filtrarRegras` + `extrairNucleo` de contexto-sessao.cjs), a
 * partir do SKILL.md real. Numero digitado envelhece em silencio.
 *
 * Toda recusa e um `throw new Error` que nomeia o campo e, quando for o caso, a regra.
 */

const fs = require('fs');
const path = require('path');

const RAIZ_PLUGIN = path.resolve(__dirname, '..', '..');
const CAMINHO_JSON = path.join(RAIZ_PLUGIN, 'hooks', 'abertura-mod.json');
const PARTES = ['orcamentoRegrasBytes', 'orcamentoFocoBytes', 'orcamentoMemoriaBytes'];

/** Bytes do texto como a injecao o veria: CRLF -> LF (autocrlf muda o tamanho em disco). */
function bytes(texto) {
  return Buffer.byteLength(String(texto).replace(/\r\n/g, '\n'), 'utf8');
}

/** Caminho de `regra-NN.md` (NN com dois digitos) sob a raiz do plugin. */
function caminhoRegra(n, raiz = RAIZ_PLUGIN) {
  return path.join(raiz, 'skills', 'rainforest-mind', 'references', `regra-${String(n).padStart(2, '0')}.md`);
}

/** Bytes do nucleo das regras, medido no SKILL.md real com as funcoes do hook. */
function medirNucleo(raiz = RAIZ_PLUGIN) {
  const lib = require(path.join(raiz, 'hooks', 'lib', 'contexto-sessao.cjs'));
  const skill = fs.readFileSync(path.join(raiz, 'skills', 'rainforest-mind', 'SKILL.md'), 'utf8');
  return bytes(lib.extrairNucleo(lib.filtrarRegras(skill)).trim());
}

function inteiroPositivo(v) {
  return typeof v === 'number' && Number.isInteger(v) && v > 0;
}

/** Valida `cfg` contra os arquivos reais e devolve as medidas. Recusa com throw. */
function validar(cfg, raiz = RAIZ_PLUGIN) {
  if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) {
    throw new Error('abertura-mod: a configuracao nao e um objeto JSON');
  }
  if (!Array.isArray(cfg.elaboracoes) || cfg.elaboracoes.length === 0
      || !cfg.elaboracoes.every(inteiroPositivo)) {
    throw new Error('abertura-mod: campo elaboracoes deve ser lista nao vazia de numeros de regra inteiros positivos');
  }
  if (new Set(cfg.elaboracoes).size !== cfg.elaboracoes.length) {
    throw new Error('abertura-mod: campo elaboracoes tem regra repetida');
  }
  for (const campo of [...PARTES, 'orcamentoTotalBytes']) {
    if (!inteiroPositivo(cfg[campo])) {
      throw new Error(`abertura-mod: campo ${campo} deve ser inteiro positivo (veio ${JSON.stringify(cfg[campo])})`);
    }
  }

  let elaboracoesBytes = 0;
  const arquivos = {};
  for (const n of cfg.elaboracoes) {
    const arq = caminhoRegra(n, raiz);
    let texto;
    try {
      texto = fs.readFileSync(arq, 'utf8');
    } catch (e) {
      throw new Error(`abertura-mod: campo elaboracoes lista a regra ${n}, mas nao ha arquivo ${path.relative(raiz, arq)}`);
    }
    arquivos[n] = arq;
    // Mede o que a abertura INJETA: o indice das references sai (tirarIndice).
    elaboracoesBytes += bytes(require(path.join(raiz, 'hooks', 'lib', 'contexto-sessao.cjs')).tirarIndice(texto));
  }

  const nucleoBytes = medirNucleo(raiz);
  const regrasBytes = nucleoBytes + elaboracoesBytes;
  if (regrasBytes > cfg.orcamentoRegrasBytes) {
    throw new Error(`abertura-mod: campo orcamentoRegrasBytes (${cfg.orcamentoRegrasBytes}) nao comporta nucleo ${nucleoBytes} + elaboracoes [${cfg.elaboracoes}] ${elaboracoesBytes} = ${regrasBytes}`);
  }

  const soma = cfg.orcamentoRegrasBytes + cfg.orcamentoFocoBytes + cfg.orcamentoMemoriaBytes;
  if (soma > cfg.orcamentoTotalBytes) throw new Error(
    `abertura-mod: campo orcamentoTotalBytes (${cfg.orcamentoTotalBytes}) menor que a soma das partes (${soma}); suba o total junto com a parte`);
  if (soma < cfg.orcamentoTotalBytes) {
    throw new Error(`abertura-mod: campo orcamentoTotalBytes (${cfg.orcamentoTotalBytes}) maior que a soma das partes (${soma}); o total e a soma exata`);
  }

  return {
    elaboracoes: cfg.elaboracoes.slice(),
    regras: cfg.orcamentoRegrasBytes,
    foco: cfg.orcamentoFocoBytes,
    memoria: cfg.orcamentoMemoriaBytes,
    total: cfg.orcamentoTotalBytes,
    nucleoBytes,
    elaboracoesBytes,
    regrasBytes,
    arquivos,
  };
}

/** Le o JSON (padrao: o do plugin) e valida. Recusa com throw, inclusive JSON ilegivel. */
function carregar(caminhoJson = CAMINHO_JSON, raiz = RAIZ_PLUGIN) {
  let cfg;
  try {
    cfg = JSON.parse(fs.readFileSync(caminhoJson, 'utf8'));
  } catch (e) {
    throw new Error(`abertura-mod: nao consegui ler ${caminhoJson}: ${e.message}`);
  }
  return validar(cfg, raiz);
}

module.exports = { carregar, validar, medirNucleo, caminhoRegra, CAMINHO_JSON };
