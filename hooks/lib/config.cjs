// Configuração do rainforest, em camadas — o que está ligado, e onde.
//
// Por que existe: até 2026-08-11 tudo era obrigatório. Os dois gates de git valiam
// em QUALQUER repositório da máquina, a esteira aparecia para quem nunca vai
// desenvolver, e a única saída era a de emergência (`RAINFOREST_GATE_OFF=1` ou um
// arquivo `.rainforest-gate-off` na raiz). Saída de emergência serve para o
// incidente, não para a preferência: quem quer o radar e não quer o gate não tinha
// o que fazer além de desinstalar.
//
// A ordem é a MESMA que o harness já usa para settings e que a cadeia de raiz já
// usa para dados — do mais específico para o mais genérico, o mais específico
// vencendo:
//
//   1. env `RAINFOREST_GATE_OFF`   saída de emergência, continua valendo e vence tudo
//   2. <projeto>/.rainforest/config.json    o que vale NESTE repositório
//   3. <dados>/config.json                  o seu padrão, em qualquer pasta
//   4. o padrão do código (tudo ligado)
//
// Toggle que nada lê é promessa sem mecanismo — o defeito que este repo passou o
// dia 11/08 inteiro catando. Por isso a leitura mora aqui, ao lado dos gates que a
// consomem, e tem bateria própria (`hooks/testa-config.sh`).

const fs = require('fs');
const path = require('path');

/**
 * O que dá para ligar e desligar, e o que cada um significa quando desligado.
 *
 * Curto de propósito: entra na lista o que **muda comportamento em repositório de
 * terceiro** — é lá que um toggle ausente vira motivo para desinstalar. Vigia e
 * guarda-corpo de jornada degradam sozinhos quando a dependência não existe (o
 * `/saude` mostra), então ligar/desligar neles é conforto, não necessidade.
 */
const CHAVES = {
  'gate-worktree': {
    padrao: true,
    descricao: 'barra escrita de subagente fora de worktree isolado',
  },
  'gate-staging': {
    padrao: true,
    descricao: 'barra `git add -A` e `git commit -a`',
  },
  esteira: {
    padrao: true,
    descricao: 'os sete estágios (brainstorm → plano → … → fechar)',
  },
};

function lerJson(p) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

/**
 * Resolve a configuração efetiva, e diz de ONDE veio cada chave.
 *
 * A procedência importa tanto quanto o valor: "o gate está desligado" sem dizer
 * onde foi desligado manda o Luís procurar num de três lugares. O `/saude` e o
 * próprio setup imprimem a origem.
 *
 * @param {object} [o]
 * @param {object} [o.env]      default: process.env
 * @param {string} [o.projeto]  default: CLAUDE_PROJECT_DIR ou cwd
 * @param {string} [o.dados]    raiz de dados; default: resolvida pela cadeia
 * @returns {{valores: object, origem: object, arquivos: {projeto: ?string, usuario: ?string}}}
 */
function resolverConfig(o = {}) {
  const env = o.env || process.env;
  const projetoDir = o.projeto || env.CLAUDE_PROJECT_DIR || process.cwd();

  let dadosDir = o.dados;
  if (dadosDir === undefined) {
    try {
      dadosDir = require('./raiz.cjs').resolverRaiz({ env }).raiz;
    } catch {
      dadosDir = null;
    }
  }

  const doProjeto = path.join(projetoDir, '.rainforest', 'config.json');
  const doUsuario = dadosDir ? path.join(dadosDir, 'config.json') : null;

  const cfgProjeto = lerJson(doProjeto);
  const cfgUsuario = doUsuario ? lerJson(doUsuario) : null;

  const valores = {};
  const origem = {};
  for (const [chave, def] of Object.entries(CHAVES)) {
    if (env.RAINFOREST_GATE_OFF && chave.startsWith('gate-')) {
      // A saída de emergência continua sendo a mais forte, e continua valendo para
      // os dois gates de uma vez. Ela existe para o incidente — quem a usa quer
      // desligar tudo agora, não escolher.
      valores[chave] = false;
      origem[chave] = 'RAINFOREST_GATE_OFF';
    } else if (cfgProjeto && typeof cfgProjeto[chave] === 'boolean') {
      valores[chave] = cfgProjeto[chave];
      origem[chave] = 'projeto';
    } else if (cfgUsuario && typeof cfgUsuario[chave] === 'boolean') {
      valores[chave] = cfgUsuario[chave];
      origem[chave] = 'usuario';
    } else {
      valores[chave] = def.padrao;
      origem[chave] = 'padrao';
    }
  }

  return {
    valores,
    origem,
    arquivos: {
      projeto: fs.existsSync(doProjeto) ? doProjeto : null,
      usuario: doUsuario && fs.existsSync(doUsuario) ? doUsuario : null,
    },
  };
}

/** Atalho para quem só quer saber se pode rodar. Erro de leitura = LIGADO. */
function ligado(chave, o = {}) {
  // Falhar para o lado de LIGAR é deliberado: config ilegível não pode virar
  // trava desligada em silêncio. Trava que some sem avisar é o defeito que o
  // fallback barulhento do hook de abertura existe para não repetir.
  if (!(chave in CHAVES)) return true;
  try {
    return resolverConfig(o).valores[chave] !== false;
  } catch {
    return true;
  }
}

module.exports = { CHAVES, resolverConfig, ligado };
