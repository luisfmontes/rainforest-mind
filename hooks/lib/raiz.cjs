// Cadeia de resolução da raiz de dados (FOCO.md, ideias.jsonl).
//
// Por que existe: até 2026-08-11 a raiz era `RFM_ROOT || 'C:\Projetos\rainforest-mind'`
// — um nível de configuração e um caminho da máquina do Luís cravado no código. Isso
// funciona para o usuário número um e para mais ninguém, e o plugin passou a ser
// instalado por outros devs.
//
// O desenho vem do `package-manager.js` do everything-claude-code, que é a única peça
// daquele repo que resolve configuração em camadas de verdade (relatório em
// referencias/2026-08-11-everything-claude-code.md). A regra é: **o projeto sobrescreve
// o global, e a detecção automática cobre quem não declarou nada.**
//
// A ordem, do mais específico para o mais genérico:
//
//   1. RFM_ROOT              — declaração explícita, vence tudo
//   2. <projeto>/.rainforest — estado por projeto (foco e ideias daquele repo)
//   3. <config>/rainforest   — estado global do usuário, sob CLAUDE_CONFIG_DIR
//   4. raiz do plugin        — instalação auto-hospedada (o repo é o próprio plugin)
//   5. legado                — o caminho antigo do Luís, só se existir
//
// O nível 5 existe porque `RFM_ROOT` NÃO está definida na máquina dele e o plugin roda
// de uma cópia em cache: tirar o caminho legado sem mais nada apagaria o foco dele no
// meio de uma sessão. Ele sai quando `RFM_ROOT` ou o nível 3 estiverem montados —
// e o próprio `resolverRaiz` diz qual nível respondeu, para isso ser visível.

const fs = require('fs');
const path = require('path');

// O que faz uma pasta ser raiz de dados: ter pelo menos um dos dois arquivos.
// Pasta vazia não conta — senão um `.rainforest` criado por engano sequestra o foco.
const MARCADORES = ['FOCO.md', 'ideias.jsonl'];

function ehRaiz(dir) {
  if (!dir) return false;
  try {
    return MARCADORES.some((m) => fs.existsSync(path.join(dir, m)));
  } catch {
    return false;
  }
}

/**
 * Resolve a raiz de dados percorrendo a cadeia de 5 níveis.
 *
 * @param {object} [o]
 * @param {object} [o.env]      variáveis de ambiente (default: process.env)
 * @param {string} [o.cwd]      diretório do projeto (default: CLAUDE_PROJECT_DIR ou cwd)
 * @param {string} [o.plugin]   raiz do plugin (default: duas pastas acima deste arquivo)
 * @param {string} [o.legado]   caminho legado a aceitar como último recurso
 * @returns {{raiz: string|null, nivel: string, escopo: 'projeto'|'usuario'|null}}
 */
function resolverRaiz(o = {}) {
  const env = o.env || process.env;
  const projeto = o.cwd || env.CLAUDE_PROJECT_DIR || process.cwd();
  const plugin = o.plugin || path.resolve(__dirname, '..', '..');
  const legado = 'legado' in o ? o.legado : 'C:\\Projetos\\rainforest-mind';

  // 1. Declaração explícita. Vence mesmo sem marcador — quem declarou sabe o que quer,
  //    e exigir marcador aqui impediria montar uma raiz nova pela primeira vez.
  if (env.RFM_ROOT) {
    return { raiz: env.RFM_ROOT, nivel: 'RFM_ROOT', escopo: 'usuario' };
  }

  // 2. Projeto. É o nível que responde ao "independente do projeto": cada repo pode ter
  //    o próprio foco e as próprias ideias, sem env var e sem configurar nada.
  const doProjeto = path.join(projeto, '.rainforest');
  if (ehRaiz(doProjeto)) {
    return { raiz: doProjeto, nivel: 'projeto', escopo: 'projeto' };
  }

  // 3. Global do usuário: `~/.rainforest`, no HOME — e **não** sob CLAUDE_CONFIG_DIR.
  //
  // Decidido em 2026-08-11, e a razão é concreta: esta máquina tem DUAS config dirs
  // (`~/.claude` para trabalho, `~/.claude-personal` para pessoal), mantidas em
  // sincronia à mão. Ancorar os dados na config dir partiria o foco e as ideias em
  // dois conjuntos conforme a conta que abriu a sessão — e a divergência entre as
  // duas já mordeu duas vezes no mesmo dia (um plugin habilitado de um lado só, e
  // a checagem de dependências lendo o settings.json errado, que virou a regra 14).
  //
  // O home é um lugar só por máquina. `RFM_ROOT` continua vencendo para quem
  // quiser outro, e é por ele que se aponta uma pasta versionada em repo privado.
  const doUsuario = path.join(env.USERPROFILE || env.HOME || '', '.rainforest');
  if (ehRaiz(doUsuario)) {
    return { raiz: doUsuario, nivel: 'global', escopo: 'usuario' };
  }

  // 4. Auto-hospedado: o repo é o próprio plugin (desenvolvimento do rainforest).
  if (ehRaiz(plugin)) {
    return { raiz: plugin, nivel: 'plugin', escopo: 'usuario' };
  }

  // 5. Legado. Sai quando 1 ou 3 estiverem montados.
  if (legado && ehRaiz(legado)) {
    return { raiz: legado, nivel: 'legado', escopo: 'usuario' };
  }

  return { raiz: null, nivel: 'nenhum', escopo: null };
}

module.exports = { resolverRaiz, ehRaiz, MARCADORES };
