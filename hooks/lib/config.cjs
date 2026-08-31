// Configuração do rainforest, em camadas — o que está ligado, e onde.
//
// Por que existe: até 2026-08-11 tudo era obrigatório. Os dois gates de git valiam
// em QUALQUER repositório da máquina, o fluxo aparecia para quem nunca vai
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
  'gate-publicacao': {
    padrao: true,
    descricao: 'barra escrita de dados sensíveis em arquivo rastreado',
  },
  'gate-repo-alheio': {
    padrao: true,
    descricao: 'barra escrita cujo destino está dentro de outro repositório git',
  },
  fluxo: {
    padrao: true,
    descricao: 'os sete estágios (brainstorm → plano → … → fechar)',
  },
  // Os VIGIAS entram na lista a pedido do usuario (2026-08-12), e o pedido corrige
  // o critério escrito no comentário acima. A frase "vigia degrada sozinho quando a
  // dependência não existe" estava certa sobre o CÓDIGO e errada sobre a
  // EXPERIÊNCIA: as rondas exigem PowerShell, um `claude.exe` no caminho e um
  // destino de envio configurado, e quem instala o plugin sem nada disso não quer
  // descobrir a dependência por mensagem de erro numa tarefa agendada.
  //
  // Nasce DESLIGADO — é a única com padrão falso junto de `branch-forcar`, e pela
  // mesma razão: aqui ligado = ronda dispara, então o lado seguro da falha é o
  // desligado. Quem lê esta chave **não pode usar `ligado()`**, que devolve `true`
  // em erro; tem de ler `resolverConfig().valores` e tratar falha como `false`. O
  // `setup.cjs --ligado` faz assim, e é por ele que o `run-vigia.ps1` pergunta —
  // reimplementar a cadeia de 3 níveis em PowerShell seria a segunda cópia que
  // diverge calada.
  vigias: {
    padrao: false,
    descricao: 'as rondas headless agendadas (exigem PowerShell, claude.exe e destino de envio)',
  },
  // PONTES — quais hosts de agente recebem as regras deste plugin, geradas do mesmo
  // SKILL.md (`scripts/ponte.cjs`). Entram aqui porque "quais agentes eu uso nesta
  // máquina" é configuração do usuário, e configuração mora no `/setup`; o que NÃO
  // é configuração é o repositório de destino, que continua sendo alvo explícito do
  // comando, com ensaio, porque o arquivo gerado vai ser commitado por outra pessoa.
  //
  // Padrão falso nos três: gerar arquivo em repo de terceiro nunca é padrão. E são
  // três, não dois — `ponte-claude` existe para quem usa Claude Code **sem o plugin
  // instalado**, que é o caminho de quem vai receber o convite antes de instalar
  // qualquer coisa.
  'ponte-claude': {
    padrao: false,
    descricao: 'gera CLAUDE.md para Claude Code SEM o plugin (regras sem as travas)',
  },
  'ponte-codex': {
    padrao: false,
    descricao: 'gera AGENTS.md para o Codex',
  },
  'ponte-gemini': {
    padrao: false,
    descricao: 'gera GEMINI.md para o Gemini CLI',
  },
  // ATENÇÃO: esta chave é a ÚNICA que inverte o sentido das outras, e por isso
  // inverte também o lado seguro da falha.
  //
  // Nas de cima, ligado = trava de pé, e config ilegível cai para LIGADO (ver
  // `ligado()` lá embaixo): na dúvida, protege. Aqui ligado = `git branch -D`, que
  // APAGA branch não mergeada — a trava é o desligado. Então quem lê esta chave
  // **não pode usar `ligado()`**, que devolve `true` em erro e em chave
  // desconhecida; tem de ler `resolverConfig().valores` e tratar qualquer falha
  // como `false`. O `limpar-branches.cjs` faz assim, e diz por quê no lugar.
  'branch-forcar': {
    padrao: false,
    descricao: 'usa `git branch -D` (apaga sem conferir merge) em vez de `-d`',
  },
  poda: {
    padrao: true,
    descricao: 'passthrough de proxy medido: escreve metricas.jsonl e contexto.json',
  },
};

/**
 * Nomes ANTIGOS que ainda são lidos do config em disco, por chave atual.
 *
 * Renomear chave de config é mudança silenciosa por natureza: o arquivo do
 * usuario continua no disco dizendo `"esteira": false`, o código passa a
 * perguntar por `fluxo`, ninguém casa, e o padrão `true` religa a trava sem uma
 * linha de aviso. Quem desligou fica sabendo pelo comportamento.
 *
 * Então o nome novo é o que se escreve (`/setup`, docs, `CHAVES`), e o velho
 * continua sendo LIDO — com precedência menor que a do novo dentro do mesmo
 * arquivo, para que quem já migrou não seja arrastado de volta pela linha
 * antiga que esqueceu de apagar.
 *
 * `esteira` → `fluxo` em 2026-08-22, quando o termo mudou no plugin inteiro.
 */
const ALIASES = {
  fluxo: ['esteira'],
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
 * onde foi desligado manda o usuario procurar num de três lugares. O `/saude` e o
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

  // Nome novo primeiro, aliases depois: dentro do MESMO arquivo, quem já migrou
  // manda. Devolve `undefined` quando nenhum dos nomes traz booleano, para o
  // arquivo seguinte da cadeia ser consultado.
  const buscar = (cfg, chave) => {
    if (!cfg) return undefined;
    for (const nome of [chave, ...(ALIASES[chave] || [])]) {
      if (typeof cfg[nome] === 'boolean') return { valor: cfg[nome], nome };
    }
    return undefined;
  };

  const valores = {};
  const origem = {};
  for (const [chave, def] of Object.entries(CHAVES)) {
    const noProjeto = buscar(cfgProjeto, chave);
    const noUsuario = buscar(cfgUsuario, chave);
    if (env.RAINFOREST_GATE_OFF && chave.startsWith('gate-')) {
      // A saída de emergência continua sendo a mais forte, e continua valendo para
      // os dois gates de uma vez. Ela existe para o incidente — quem a usa quer
      // desligar tudo agora, não escolher.
      valores[chave] = false;
      origem[chave] = 'RAINFOREST_GATE_OFF';
    } else if (noProjeto) {
      valores[chave] = noProjeto.valor;
      // A origem diz o nome ANTIGO quando foi ele que decidiu — senão o `/saude`
      // manda procurar por `fluxo` num arquivo que só tem `esteira`.
      origem[chave] = noProjeto.nome === chave ? 'projeto' : `projeto (${noProjeto.nome})`;
    } else if (noUsuario) {
      valores[chave] = noUsuario.valor;
      origem[chave] = noUsuario.nome === chave ? 'usuario' : `usuario (${noUsuario.nome})`;
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
