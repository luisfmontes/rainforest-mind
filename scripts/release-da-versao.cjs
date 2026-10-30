'use strict';
// Publica a release da versão do manifesto, para que a release não dependa de a
// sessão lembrar. Design docs/rainforest/design/2026-10-30-release-automatica.md, D2 e D3.
// O workflow release.yml chama este script no push do bump à main. Sem dependência
// externa: node puro mais o `gh`, chamado pelo resolvedor do repo (no Windows o
// spawnSync('gh') ignora um stub sem extensão).
//
// Uso: node scripts/release-da-versao.cjs --sha <sha> [--seco] [--raiz <dir>]

const fs = require('fs');
const os = require('os');
const path = require('path');
const { executar } = require('../hooks/lib/resolver-executavel.cjs');

const RAIZ_PADRAO = path.resolve(__dirname, '..');

function uso() {
  process.stderr.write('uso: node scripts/release-da-versao.cjs --sha <sha> [--seco] [--raiz <dir>]\n');
  process.exit(2);
}

function lerArgs(argv) {
  const args = { sha: null, seco: false, raiz: RAIZ_PADRAO };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--seco') {
      args.seco = true;
    } else if (a === '--sha' || a === '--raiz') {
      const valor = argv[++i];
      if (valor === undefined) uso();
      if (a === '--sha') args.sha = valor;
      else args.raiz = path.resolve(valor);
    } else {
      uso();
    }
  }
  return args;
}

// Seção `## <versão> ...` até a próxima `## `, sem a linha do título, aparada.
function secaoDoChangelog(texto, versao) {
  const linhas = texto.split(/\r?\n/);
  const inicio = linhas.findIndex(l => l.startsWith('## ' + versao + ' '));
  if (inicio < 0) return '';
  const proxima = linhas.findIndex((l, i) => i > inicio && l.startsWith('## '));
  const corpo = linhas.slice(inicio + 1, proxima < 0 ? undefined : proxima);
  return corpo.join('\n').trim();
}

function main() {
  const args = lerArgs(process.argv.slice(2));
  if (!args.sha) uso();

  const manifesto = JSON.parse(fs.readFileSync(path.join(args.raiz, '.claude-plugin', 'plugin.json'), 'utf8'));
  const versao = manifesto.version;

  const visto = executar('gh', ['release', 'view', 'v' + versao], { cwd: args.raiz });
  const jaExiste = visto.status === 0;
  if (jaExiste) {
    process.stdout.write(`release v${versao} já existe — nada a fazer\n`);
    process.exit(0);
  }

  let changelog = '';
  try {
    changelog = fs.readFileSync(path.join(args.raiz, 'CHANGELOG.md'), 'utf8');
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
  const notas = secaoDoChangelog(changelog, versao);
  if (!notas) {
    process.stderr.write(`CHANGELOG sem a seção ${versao}\n`);
    process.exit(1);
  }

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-'));
  const arq = path.join(dir, 'notas.md');
  fs.writeFileSync(arq, notas + '\n');
  const argsCreate = ['release', 'create', 'v' + versao, '--target', args.sha,
    '--title', 'rainforest-mind ' + versao, '--notes-file', arq];

  if (args.seco) {
    process.stdout.write('comando: gh ' + argsCreate.join(' ') + '\n');
    process.stdout.write(notas + '\n');
    fs.rmSync(dir, { recursive: true, force: true });
    process.exit(0);
  }

  const criado = executar('gh', argsCreate, { cwd: args.raiz, stdio: 'inherit' });
  fs.rmSync(dir, { recursive: true, force: true });
  if (criado.status !== 0) process.exit(criado.status || 1);
}

main();
