// Configuração do rainforest, em camadas — o que está ligado, e onde.
//
// Por que existe: até 2026-08-11 tudo era obrigatório. Os dois gates de git valiam
// em QUALQUER repositório da máquina, o fluxo aparecia para quem nunca vai
// desenvolver, e a única saída era a de emergência (`RAINFOREST_GATE_OFF=1` ou um
// arquivo `.rainforest-gate-off` na raiz, lido até a #417 e hoje ignorado). Saída de emergência serve para o
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
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra escrita de subagente fora de worktree isolado',
    entrevista: null,
  },
  'gate-staging': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra `git add -A` e `git commit -a`',
    entrevista: null,
  },
  'gate-publicacao': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra escrita de dados sensíveis em arquivo rastreado',
    entrevista: null,
  },
  'gate-repo-alheio': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra escrita cujo destino está dentro de outro repositório git',
    entrevista: null,
  },
  'gate-git-verificacao': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra pulo de verificação no git (--no-verify, -n em commit, --no-gpg-sign)',
    entrevista: null,
  },
  'gate-fechar-issue': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra `gh issue close` direto, palavras-chave falsas em português, e `gh pr create/edit/merge`, `gh issue create/comment` sem evidência/com falsa chave',
    entrevista: null,
  },
  'gate-merge-auto': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra `gh pr merge --auto`: neste repo sem check obrigatório mergeia na hora, sem esperar o CI',
    entrevista: null,
  },
  'gate-agente-em-voo': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra sessão quando há agente em voo que morreu',
    entrevista: null,
  },
  'gate-turno-prometido': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra turno que promete despacho ou espera de máquina sem concretizar',
    entrevista: null,
  },
  'gate-pergunta-memoria': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra uma vez o turno que sobe pergunta Q<n> que a memória do projeto ou o banco já responde',
    entrevista: null,
  },
  'gate-verificador-staged': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra commit quando o `verificador-staged` do config reprova conteúdo staged',
    entrevista: null,
  },
  'contrato-veredito': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'grava o veredito de uma linha do revisor em SubagentStop (hooks/veredito-revisor.cjs)',
    entrevista: null,
  },
  'contrato-relato-executor': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'devolve a vez ao executor de fluxo que termina sem a linha `ENTREGA:` em SubagentStop (hooks/relato-executor.cjs)',
    entrevista: null,
  },
  'agente-folha': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'a portaria nega Agent vindo de dentro de subagente (agent_id presente) — regra 10, agente despachado e folha',
    entrevista: null,
  },
  'busca-na-raiz': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'nega find a partir da raiz do disco dentro de subagente — prende o agente em segundo plano',
    entrevista: null,
  },
  'bateria-sem-timeout': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'nega bateria sem timeout explícito dentro de subagente — varredura completa só roda na integração',
    entrevista: null,
  },
  'subagente-sem-gh': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'nega `gh` de escrita (issue/pr/release/repo/label/secret/variable/workflow/run/api) dentro de subagente — direto, em wrapper ou em heredoc',
    entrevista: null,
  },
  'subagente-sem-instalar': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'nega instalação de pacotes e desligamento de gate dentro de subagente',
    entrevista: null,
  },
  'matar-por-nome': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'barra matar processo por nome (taskkill /IM, pkill, killall, Stop-Process -Name) na janela e no subagente; mata-se pelo PID',
    entrevista: null,
  },
  'aviso-fluxo': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'bloqueia edição de código (Edit/Write/MultiEdit) e despacho de agente que escreve, e avisa código novo deixado pelo shell (Bash/PowerShell), sem fluxo aberto nem `leve` na branch, quando o repositório tem fluxo',
    entrevista: null,
  },
  'aviso-duplicata': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'avisa, na edição, função ou classe que já está definida em outro arquivo rastreado (reusar antes de duplicar)',
    entrevista: null,
  },
  fluxo: {
    tipo: 'boolean',
    padrao: true,
    descricao: 'os sete estágios (brainstorm → plano → … → fechar)',
    entrevista: null,
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
    tipo: 'boolean',
    padrao: false,
    descricao: 'as rondas headless agendadas (exigem PowerShell, claude.exe e destino de envio)',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } },
  },
  // FOCO (2.0.0, D2 do design 2026-10-25-versao-2-0-0): o radar de escopo, o guarda-corpo
  // de jornada e o radar multi-janela saem da abertura por padrão, e esta chave os traz de
  // volta. Nasce DESLIGADA como `vigias`, e quem a lê também **não usa `ligado()`**: usa
  // `focoLigado()`, logo abaixo, que trata falha como desligado.
  foco: {
    tipo: 'boolean',
    padrao: false,
    descricao: 'o foco na abertura: radar de escopo, jornada e janelas paralelas (regras 3, 8 e 17)',
    entrevista: { grupo: 'foco', detectar: {} },
  },
  // RONDAS — um toggle por ronda, ligado por padrao de proposito: quem ja tem
  // `vigias: true` gravado continua com as cinco rodando. So vale com `vigias`
  // tambem ligado (o run-vigia.ps1 olha as duas chaves, nesta ordem).
  'vigia-batedor-repos': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'ronda batedor-repos dos vigias; so roda com `vigias` tambem ligado',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } },
  },
  'vigia-jardineiro-ideias': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'ronda jardineiro-ideias dos vigias; so roda com `vigias` tambem ligado',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } },
  },
  'vigia-revisao-bimestral': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'ronda revisao-bimestral dos vigias; so roda com `vigias` tambem ligado',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } },
  },
  'vigia-sentinela-foco': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'ronda sentinela-foco dos vigias; so roda com `vigias` tambem ligado',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } },
  },
  'vigia-tickets': {
    tipo: 'boolean',
    padrao: true,
    descricao: 'ronda tickets dos vigias; so roda com `vigias` tambem ligado',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['powershell', 'claude'] } },
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
    tipo: 'boolean',
    padrao: false,
    descricao: 'gera CLAUDE.md para Claude Code SEM o plugin (regras sem as travas)',
    entrevista: { grupo: 'ferramentas', detectar: {} },
  },
  'ponte-codex': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'gera AGENTS.md para o Codex',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['codex'] } },
  },
  'ponte-gemini': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'gera GEMINI.md para o Gemini CLI',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['gemini'] } },
  },
  // ATENÇÃO: esta chave inverte o sentido das outras (`principal-livre`, abaixo,
  // é a segunda com o mesmo sentido), e por isso inverte também o lado seguro da
  // falha.
  //
  // Nas de cima, ligado = trava de pé, e config ilegível cai para LIGADO (ver
  // `ligado()` lá embaixo): na dúvida, protege. Aqui ligado = `git branch -D`, que
  // APAGA branch não mergeada — a trava é o desligado. Então quem lê esta chave
  // **não pode usar `ligado()`**, que devolve `true` em erro e em chave
  // desconhecida; tem de ler `resolverConfig().valores` e tratar qualquer falha
  // como `false`. O `limpar-branches.cjs` faz assim, e diz por quê no lugar.
  'branch-forcar': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'usa `git branch -D` (apaga sem conferir merge) em vez de `-d`',
    entrevista: null,
  },
  'conselho-codex': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'Codex participa do conselho como membro externo (exige `codex` CLI)',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['codex'] } },
  },
  'conselho-gemini': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'Gemini participa do conselho como membro externo (exige `GEMINI_API_KEY` no ambiente)',
    entrevista: { grupo: 'ferramentas', detectar: { env: ['GEMINI_API_KEY'] } },
  },
  // Sentido invertido como `branch-forcar`: ligada, DESLIGA uma trava. Quem lê
  // (`scripts/estado.cjs`) não usa `ligado()` — que devolve `true` em erro e em
  // chave desconhecida —, lê `resolverConfig().valores` e trata falha como
  // `false`, igual ao `limpar-branches.cjs`.
  'principal-livre': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'libera estado.cjs iniciar no checkout principal fora da branch padrão (clone dedicado a uma frente)',
    entrevista: null,
  },
  poda: {
    tipo: 'boolean',
    padrao: true,
    descricao: 'passthrough de proxy medido: escreve metricas.jsonl e contexto.json',
    entrevista: null,
  },
  // INTEGRACOES — repositórios opcionais do usuário com ciclo de release próprio.
  // Cada uma tem stub `checar()` que devolve status — as checagens reais vêm depois.
  // Declaráveis via `--ligar integracao-<nome>`, desligadas por padrão.
  'integracao-whatsapp-mcp': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'MCP para bridge WhatsApp local (127.0.0.1:3005)',
    entrevista: { grupo: 'ferramentas', detectar: { integracao: 'whatsapp-mcp' } },
  },
  'integracao-sabia': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'Sabiá: transcrição local de reunião com diarização (quem falou), CLI Python',
    entrevista: { grupo: 'ferramentas', detectar: { integracao: 'sabia' } },
  },
  'visibilidade-repo': {
    tipo: 'privada',
    padrao: null,
    descricao: 'declara o repositório privado quando o gh não o enxerga (GitLab etc.); só libera termos da lista privada',
    entrevista: null,
  },
  idioma: {
    tipo: 'texto',
    padrao: null,
    descricao: 'idioma preferido para respostas na compactação (ex.: "português do Brasil")',
    entrevista: { grupo: 'idioma', detectar: {} },
  },
  pastas: {
    tipo: 'pastas',
    padrao: null,
    descricao: 'pastas de mapas/design/planos quando o repo já usa outra (ex.: {"design": "docs/plans"})',
    entrevista: null,
  },
  'saude-ignorar-config-dirs': {
    tipo: 'padroes',
    padrao: null,
    descricao: 'padrões de nome de config dir que o /saude não compara; null = *bench* e *.aposentada',
    entrevista: null,
  },
  // CODEX COMO RUNTIME — chaves de modelo que mapeiam model: do agente para -m do Codex
  'codex-modelo-haiku': {
    tipo: 'modelo',
    padrao: null,
    descricao: 'mapeia model: haiku do agente para -m e model_reasoning_effort do Codex (null = usar ~/.codex/config.toml)',
    entrevista: null,
  },
  'codex-modelo-sonnet': {
    tipo: 'modelo',
    padrao: null,
    descricao: 'mapeia model: sonnet do agente para -m e model_reasoning_effort do Codex (null = usar ~/.codex/config.toml)',
    entrevista: null,
  },
  'codex-modelo-opus': {
    tipo: 'modelo',
    padrao: null,
    descricao: 'mapeia model: opus do agente para -m e model_reasoning_effort do Codex (null = usar ~/.codex/config.toml)',
    entrevista: null,
  },
  'transfer-codex': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'transfere a sessão Claude Code para uma thread Codex, sob demanda',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['codex'] } },
  },
  'gate-review-codex': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'o revisor em Codex revisa a última resposta no Stop; falha fechada',
    entrevista: { grupo: 'ferramentas', detectar: { executaveis: ['codex'] } },
  },
  // Sentido invertido como `branch-forcar`: ligada, AUTORIZA o merge do PR pelo
  // `fechar` depois do CI verde. Quem lê (`scripts/publicar-branch.cjs`) não usa
  // `ligado()`, que devolve `true` em erro; lê `resolverConfig().valores` e trata
  // falha como `false`. Padrão falso: merge sem revisão humana é mão única.
  'fechar-mergear': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'o fechar mergeia o PR (squash) depois do CI verde; desligada, para no PR aberto',
    entrevista: { grupo: 'fechar', detectar: {} },
  },
  // Sentido igual ao de `fechar-mergear`: ligada, a sessão segue entre `plano ok` e o
  // merge sem perguntar, e registra cada decisão com `estado.cjs decidir` (D4 e D5 do
  // design executar-autonomo). Padrão falso: repo de cliente ou de outra pessoa não
  // passa a rodar sozinho por atualizar o plugin. Quem lê deve tratar falha como `false`.
  'executar-autonomo': {
    tipo: 'boolean',
    padrao: false,
    descricao: 'entre plano ok e o merge, a sessão decide sem perguntar e registra com `estado.cjs decidir`; desligada, pergunta como hoje',
    entrevista: { grupo: 'fechar', detectar: {} },
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
 * Raiz do checkout PRINCIPAL de `dir`. Dentro de um worktree linkado
 * (`.claude/worktrees/x`) ou de um subdiretório, o `.rainforest/config.json` do
 * projeto mora no principal, não ali. Sem git, com erro, ou com o git-common-dir
 * fora do padrão `<raiz>/.git` (bare, submódulo), devolve `dir` inalterado.
 */
function raizDoPrincipal(dir) {
  try {
    const { caminhoExecutavel } = require('./resolver-executavel.cjs');
    const r = require('child_process').spawnSync(
      caminhoExecutavel('git'), ['rev-parse', '--path-format=absolute', '--git-common-dir'],
      { cwd: dir, encoding: 'utf8', timeout: 3000, windowsHide: true });
    if (r.status !== 0 || !r.stdout) return dir;
    const comum = r.stdout.trim();
    return path.basename(comum) === '.git' ? path.dirname(comum) : dir;
  } catch {
    return dir;
  }
}

/**
 * Valida se um valor combina com o tipo esperado. Usada por resolverConfig e pelo
 * --aplicar do setup: UMA regra, para o que se grava ser o que se le de volta.
 */
function validarTipo(valor, tipo) {
  if (tipo === 'boolean') {
    return typeof valor === 'boolean';
  } else if (tipo === 'modelo') {
    // Tipo 'modelo': aceita objeto {modelo: string, esforco?: string} ou null
    if (valor === null) return true;
    return typeof valor === 'object' && valor !== null &&
           typeof valor.modelo === 'string' &&
           (valor.esforco === undefined || typeof valor.esforco === 'string');
  } else if (tipo === 'texto') {
    // Tipo 'texto': string não vazia até 60 caracteres, ou null
    if (valor === null) return true;
    return typeof valor === 'string' && valor.length > 0 && valor.length <= 60;
  } else if (tipo === 'privada') {
    // Tipo 'privada': só o literal "privada", ou null. Qualquer outro valor é inválido.
    return valor === null || valor === 'privada';
  } else if (tipo === 'pastas') {
    // Tipo 'pastas': null ou objeto só com mapas/design/planos; cada valor é
    // caminho relativo ao repo, sem drive, sem raiz absoluta, sem segmento '..'.
    if (valor === null) return true;
    if (typeof valor !== 'object' || Array.isArray(valor)) return false;
    return Object.entries(valor).every(([k, v]) => ['mapas', 'design', 'planos'].includes(k) &&
      typeof v === 'string' && v.trim().length > 0 &&
      !/^([a-zA-Z]:|[\\/])/.test(v) && !v.split(/[\\/]/).includes('..'));
  } else if (tipo === 'padroes') {
    // Tipo 'padroes': null, ou array de strings não vazias até 60 caracteres. Array
    // vazio vale: é o jeito de dizer "não ignore nenhuma".
    if (valor === null) return true;
    return Array.isArray(valor) && valor.every((p) => typeof p === 'string' && p.length > 0 && p.length <= 60);
  }
  return false;
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
  const projetoDir = raizDoPrincipal(o.projeto || env.CLAUDE_PROJECT_DIR || process.cwd());

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
  // manda. Devolve `undefined` quando nenhum dos nomes traz valor válido, para o
  // arquivo seguinte da cadeia ser consultado.
  const buscar = (cfg, chave, tipo) => {
    if (!cfg) return undefined;
    for (const nome of [chave, ...(ALIASES[chave] || [])]) {
      if (validarTipo(cfg[nome], tipo)) return { valor: cfg[nome], nome };
    }
    return undefined;
  };

  const valores = {};
  const origem = {};
  for (const [chave, def] of Object.entries(CHAVES)) {
    const tipo = def.tipo || 'boolean';
    const noProjeto = buscar(cfgProjeto, chave, tipo);
    const noUsuario = buscar(cfgUsuario, chave, tipo);
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

/** A chave `foco` (2.0.0): só `true` gravado liga; erro de leitura = DESLIGADO, o inverso de `ligado()`. */
function focoLigado(o = {}) {
  try {
    return resolverConfig(o).valores.foco === true;
  } catch {
    return false;
  }
}

// Grupos da entrevista do /setup, na ordem em que ela pergunta (D8 do design
// 2026-10-17). O conferidor de D7 compara a seção "Ordem da entrevista" do SKILL.md
// com esta lista, então a ordem aqui é a que vale.
const GRUPOS_ENTREVISTA = ['dados', 'idioma', 'projetos', 'ferramentas', 'fechar', 'estrategia', 'foco'];

module.exports = { CHAVES, resolverConfig, ligado, focoLigado, raizDoPrincipal, validarTipo, GRUPOS_ENTREVISTA };
