// Resolver que honra a ordem do PATH — incidente 2026-09-03:
// Node no Windows não honra a ordem do PATH quando resolve executáveis;
// gh.cmd (sandbox) é vencido por gh.exe (sistema). Resolver manual.
// Node 18.20+ recusa .cmd/.bat sem shell (CVE-2024-27980 EINVAL); executar() ajusta.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// Cache separados para cada resolvedor (nome + '\0' + PATH)
const cacheResolverExecutavel = new Map();
const cacheCaminhoExecutavel = new Map();

function lerPath(env = process.env) {
  // Encontra a chave PATH case-insensitive
  const chave = Object.keys(env).find(k => k.toUpperCase() === 'PATH');
  const PATH = env[chave] || '';
  const separador = process.platform === 'win32' ? ';' : ':';

  const dirs = PATH.split(separador).filter(d => d && path.isAbsolute(d));

  return { PATH, dirs };
}

function resolverExecutavel(nome, env = process.env) {
  const { PATH, dirs } = lerPath(env);
  const separador = process.platform === 'win32' ? ';' : ':';
  const extensoes = process.platform === 'win32' ? ['.cmd', '.bat', '.exe', ''] : [''];

  // Memoização: chave = nome + '\0' + PATH
  const chave = nome + '\0' + PATH;
  if (cacheResolverExecutavel.has(chave)) {
    return cacheResolverExecutavel.get(chave);
  }

  for (const dir of dirs) {
    for (const ext of extensoes) {
      const caminhoCompleto = path.join(dir, nome + ext);
      if (fs.existsSync(caminhoCompleto)) {
        cacheResolverExecutavel.set(chave, caminhoCompleto);
        return caminhoCompleto;
      }
    }
  }

  cacheResolverExecutavel.set(chave, null);
  return null;
}

function caminhoExecutavel(nome, env = process.env) {
  const { PATH, dirs } = lerPath(env);
  const extensoes = process.platform === 'win32' ? ['.com', '.exe'] : [''];

  // Memoização: chave = nome + '\0' + PATH
  const chave = nome + '\0' + PATH;
  if (cacheCaminhoExecutavel.has(chave)) {
    return cacheCaminhoExecutavel.get(chave);
  }

  for (const dir of dirs) {
    for (const ext of extensoes) {
      const caminhoCompleto = path.join(dir, nome + ext);
      if (fs.existsSync(caminhoCompleto)) {
        cacheCaminhoExecutavel.set(chave, caminhoCompleto);
        return caminhoCompleto;
      }
    }
  }

  // Não achou: devolve caminho absoluto inexistente
  const caminhoInexistente = path.join(__dirname, 'ausente-do-PATH', nome);
  cacheCaminhoExecutavel.set(chave, caminhoInexistente);
  return caminhoInexistente;
}

// Rodada 19 (lote 3): quando `exe` resolve para `.cmd`/`.bat`, `shell:true` é
// obrigatório (Node recusa .cmd/.bat sem shell — CVE-2024-27980), mas
// `spawnSync(arquivo.cmd, args, {shell:true})` NÃO escapa os elementos do
// array contra os metacaracteres do `cmd.exe` no Windows — um argumento como
// `"5 & echo INJETADO > pwned.txt"` executa como comando de shell, não como
// texto literal. Postura escolhida: RECUSAR (não escapar) — mais
// conservadora, e todo chamador já trata `status !== 0` como "não consegui
// executar" e bloqueia. Reproduzido em caixa de areia antes do conserto:
// `gh.cmd` de mentira + esse argumento criava o arquivo no disco.
const METACARACTERES_CMD = /[&|<>^"%()!\n\r]/;

function executar(nome, args, opts = {}) {
  const exe = resolverExecutavel(nome);
  if (!exe) {
    return {
      status: 127,
      stdout: '',
      stderr: `${nome} not found`,
      error: new Error(`${nome} not found`)
    };
  }

  const ehCmd = /\.(cmd|bat)$/i.test(exe);

  if (ehCmd) {
    for (const arg of args) {
      if (typeof arg === 'string' && METACARACTERES_CMD.test(arg)) {
        return {
          status: 1,
          stdout: '',
          stderr: `executar: argumento recusado — contém metacaractere de cmd.exe (${JSON.stringify(arg)}). ` +
            `${nome} resolve para .cmd/.bat e exige shell:true, que não escapa argumentos no Windows.`,
          error: new Error('executar: argumento com metacaractere de cmd.exe recusado')
        };
      }
    }
  }

  return spawnSync(exe, args, {
    ...opts,
    shell: ehCmd ? true : (opts.shell !== undefined ? opts.shell : false),
    encoding: 'utf-8'
  });
}

module.exports = { lerPath, resolverExecutavel, caminhoExecutavel, executar };
