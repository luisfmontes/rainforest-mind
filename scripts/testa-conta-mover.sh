#!/bin/bash
# rainforest-gate: dados-de-exemplo — fixtures com credenciais FALSAS no formato do .credentials.json; nenhum valor real.
# Testa scripts/lib/conta-mover.cjs (tarefa 2 de 2026-10-10-troca-de-conta, D2 e D11).
# Casos: (a) troca normal: mcpOAuth e trustedDeviceToken com o mesmo sha256,
# claudeAiOauth trocado entre pasta e reservas, reserva de entrada sem a chave,
# oauthAccount do dono; (b) arquivo alterado entre leitura e gravação: sai com
# `mudou` e nenhum dos três arquivos de credencial muda; (c) reserva que entra
# igual ao login da pasta é recusada e nada muda.
# Tudo em mktemp -d com trap; nunca toca ~/.claude nem ~/.claude-personal.
set -euo pipefail
cd "$(dirname "$0")/.."

node - <<'JS'
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { mover } = require('./scripts/lib/conta-mover.cjs');

const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'testa-conta-mover-'));
process.on('exit', () => fs.rmSync(raiz, { recursive: true, force: true }));
let ok = 0, falhas = 0;

function afirma(nome, cond) {
  if (cond) { ok++; console.log(`ok   ${nome}`); }
  else { falhas++; console.log(`FALHA ${nome}`); }
}
const shaBytes = (arq) => crypto.createHash('sha256').update(fs.readFileSync(arq)).digest('hex');
const shaValor = (v) => crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex');
const ler = (arq) => JSON.parse(fs.readFileSync(arq, 'utf8'));
const escrever = (arq, obj) => {
  fs.mkdirSync(path.dirname(arq), { recursive: true });
  fs.writeFileSync(arq, JSON.stringify(obj, null, 2) + '\n');
};

// Fixtures falsas no formato real do .credentials.json e do .claude.json.
function credencial(s) {
  return {
    mcpOAuth: { 'servidor-falso': { accessToken: `falso-access-mcp-${s}`, refreshToken: `falso-refresh-mcp-${s}`, expiresAt: 1, scope: 'a b' } },
    claudeAiOauth: {
      accessToken: `falso-access-${s}`,
      refreshToken: `falso-refresh-${s}`,
      expiresAt: 4102444800000,
      refreshTokenExpiresAt: 4102444800000,
      scopes: ['user:inference', 'user:profile'],
      subscriptionType: 'max',
      rateLimitTier: 'default_claude_max_20x',
    },
    trustedDeviceToken: `falso-tdt-${s}`,
  };
}
const DONO = { accountUuid: '00000000-0000-0000-0000-000000000001', emailAddress: 'y@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa B' };
const ANTIGO = { accountUuid: '00000000-0000-0000-0000-000000000002', emailAddress: 'x@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa A' };

// Monta um cenário numa subpasta própria de raiz (nunca em ~/.claude).
function cenario(nome) {
  const base = path.join(raiz, nome);
  const pasta = path.join(base, 'pasta');
  const reservas = path.join(base, 'reservas');
  const arqs = {
    cred: path.join(pasta, '.credentials.json'),
    claude: path.join(pasta, '.claude.json'),
    entra: path.join(reservas, 'entra.json'),
    sai: path.join(reservas, 'sai.json'),
  };
  escrever(arqs.cred, credencial('pasta'));
  escrever(arqs.claude, { numStartups: 3, oauthAccount: ANTIGO, projects: {} });
  escrever(arqs.entra, credencial('entra'));
  // A reserva de saída começa VAZIA: no modelo de quatro lugares ela é o estacionado ou a reserva
  // que acabou de receber o login de volta (conta-mover recusa saída ocupada).
  escrever(arqs.sai, {});
  return { pasta, arqs };
}

// (a) troca normal
{
  const { pasta, arqs } = cenario('a');
  const antesCred = ler(arqs.cred), antesEntra = ler(arqs.entra);
  const hMcpAntes = shaValor(antesCred.mcpOAuth), hTdtAntes = shaValor(antesCred.trustedDeviceToken);
  console.log(`   sha256 mcpOAuth antes=${hMcpAntes} trustedDeviceToken antes=${shaValor(antesCred.trustedDeviceToken)}`);

  const r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  const depoisCred = ler(arqs.cred), depoisEntra = ler(arqs.entra), depoisSai = ler(arqs.sai), depoisClaude = ler(arqs.claude);
  console.log(`   sha256 mcpOAuth depois=${shaValor(depoisCred.mcpOAuth)} trustedDeviceToken depois=${shaValor(depoisCred.trustedDeviceToken)}`);

  afirma('(a) troca normal devolve ok', r.ok === true);
  afirma('(a) mcpOAuth com o mesmo sha256 de antes', shaValor(depoisCred.mcpOAuth) === hMcpAntes);
  afirma('(a) trustedDeviceToken com o mesmo sha256 de antes', shaValor(depoisCred.trustedDeviceToken) === hTdtAntes);
  afirma('(a) claudeAiOauth da reserva foi para a pasta', shaValor(depoisCred.claudeAiOauth) === shaValor(antesEntra.claudeAiOauth));
  afirma('(a) claudeAiOauth da pasta foi para a reserva de saída', shaValor(depoisSai.claudeAiOauth) === shaValor(antesCred.claudeAiOauth));
  afirma('(a) reserva de entrada ficou sem claudeAiOauth', !('claudeAiOauth' in depoisEntra));
  afirma('(a) oauthAccount do .claude.json = dono', JSON.stringify(depoisClaude.oauthAccount) === JSON.stringify(DONO));
  afirma('(a) prefixos devolvidos batem com os refreshToken', r.entrou === crypto.createHash('sha256').update(antesEntra.claudeAiOauth.refreshToken).digest('hex').slice(0, 12) && r.saiu === crypto.createHash('sha256').update(antesCred.claudeAiOauth.refreshToken).digest('hex').slice(0, 12));
}

// (b) arquivo alterado entre leitura e gravação
{
  const { pasta, arqs } = cenario('b');
  const hCred = shaBytes(arqs.cred), hEntra = shaBytes(arqs.entra), hSai = shaBytes(arqs.sai);
  console.log(`   sha256 antes: credenciais=${hCred} entra=${hEntra} sai=${hSai}`);

  // Na segunda leitura do .claude.json (a releitura antes de gravar), o arquivo muda em disco.
  const original = fs.readFileSync;
  let leiturasClaude = 0;
  fs.readFileSync = function (arq, ...resto) {
    if (path.resolve(String(arq)) === path.resolve(arqs.claude) && ++leiturasClaude === 2) {
      const atual = JSON.parse(original.call(fs, arq, 'utf8'));
      atual.numStartups = 99;
      fs.writeFileSync(arq, JSON.stringify(atual, null, 2) + '\n');
    }
    return original.call(fs, arq, ...resto);
  };
  let r;
  try {
    r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  } finally {
    fs.readFileSync = original;
  }
  console.log(`   sha256 depois: credenciais=${shaBytes(arqs.cred)} entra=${shaBytes(arqs.entra)} sai=${shaBytes(arqs.sai)}`);

  afirma('(b) arquivo alterado devolve motivo mudou', r.ok === false && r.motivo === 'mudou');
  afirma('(b) .credentials.json com o mesmo sha256 de antes', shaBytes(arqs.cred) === hCred);
  afirma('(b) reserva de entrada com o mesmo sha256 de antes', shaBytes(arqs.entra) === hEntra);
  afirma('(b) reserva de saída com o mesmo sha256 de antes', shaBytes(arqs.sai) === hSai);
}

// (c) reserva que entra igual ao login da pasta é recusada e nada muda
{
  const { pasta, arqs } = cenario('c');
  // A reserva de entrada passa a ter o MESMO login (mesmo refreshToken) que a pasta.
  escrever(arqs.entra, { claudeAiOauth: credencial('pasta').claudeAiOauth, trustedDeviceToken: 'falso-tdt-entra' });
  const hs = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);
  console.log(`   sha256 antes: ${hs.join(' ')}`);

  const r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  const depois = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);
  console.log(`   sha256 depois: ${depois.join(' ')}`);

  afirma('reserva que entra igual ao login da pasta é recusada e nada muda: motivo duplicada', r.ok === false && r.motivo === 'duplicada');
  afirma('reserva que entra igual ao login da pasta é recusada e nada muda: arquivos intactos', depois.every((h, i) => h === hs[i]));
}

// (d) erro de gravação no meio desfaz as anteriores: a 2ª chamada de renameSync
// (gravação do .credentials.json) lança; sai já gravou e tem de voltar ao original.
{
  const { pasta, arqs } = cenario('d');
  const hs = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);
  console.log(`   sha256 antes: ${hs.join(' ')}`);

  const renomear = fs.renameSync;
  let chamadas = 0;
  fs.renameSync = function (...args) {
    if (++chamadas === 2) throw Object.assign(new Error('EPERM simulado'), { code: 'EPERM' });
    return renomear.apply(fs, args);
  };
  let r;
  try {
    r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  } finally {
    fs.renameSync = renomear;
  }
  const depois = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);
  console.log(`   sha256 depois: ${depois.join(' ')}`);

  afirma('erro de gravação no meio desfaz as anteriores', r.ok === false && r.motivo === 'gravacao' && depois.every((h, i) => h === hs[i]));
}

// (e) reserva de saída já com login é recusada e nada muda
{
  const { pasta, arqs } = cenario('e');
  escrever(arqs.sai, credencial('sai'));
  const hs = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);
  console.log(`   sha256 antes: ${hs.join(' ')}`);

  const r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  const depois = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);
  console.log(`   sha256 depois: ${depois.join(' ')}`);

  afirma('reserva de saída ocupada é recusada e nada muda', r.ok === false && r.motivo === 'saida_ocupada' && depois.every((h, i) => h === hs[i]));
}

// (f) caminho temporário já existente (plantado) não é seguido nem apagado: a gravação falha e
// o arquivo plantado fica intacto. O tmp tem pid e Date.now; fixa-se o relógio para plantar o nome.
{
  const { pasta, arqs } = cenario('f');
  const hs = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);
  const tmpSai = path.join(path.dirname(arqs.sai), `.${path.basename(arqs.sai)}.${process.pid}.424242.tmp`);
  fs.writeFileSync(tmpSai, 'PLANTADO');

  const agora = Date.now;
  let r;
  try {
    Date.now = () => 424242;
    r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  } finally {
    Date.now = agora;
  }
  const depois = [arqs.cred, arqs.claude, arqs.entra, arqs.sai].map(shaBytes);

  afirma('tmp já existente: a gravação falha, o arquivo plantado fica intacto e nada muda',
    r.ok === false && r.motivo === 'gravacao' && fs.readFileSync(tmpSai, 'utf8') === 'PLANTADO'
    && depois.every((h, i) => h === hs[i]));
  fs.rmSync(tmpSai, { force: true });
}

// (g) a gravação do .credentials.json falha (2ª rename) e uma gravação do próprio desfazer também
// (3ª rename, a restauração de sai): nada lança, devolve desfazer_falhou com o que não voltou.
{
  const { pasta, arqs } = cenario('g');
  const renomear = fs.renameSync;
  let chamadas = 0;
  fs.renameSync = function (...args) {
    if (++chamadas === 2 || chamadas === 3) throw Object.assign(new Error('EPERM simulado'), { code: 'EPERM' });
    return renomear.apply(fs, args);
  };
  let r, lancou = false;
  try {
    r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  } catch {
    lancou = true;
  } finally {
    fs.renameSync = renomear;
  }
  afirma('desfazer que falha não lança e devolve desfazer_falhou',
    !lancou && r && r.ok === false && r.motivo === 'desfazer_falhou'
    && Array.isArray(r.pendentes) && r.pendentes.length === 1 && path.resolve(r.pendentes[0]) === path.resolve(arqs.sai));
}

// (g) rodada 5, achado 5: uma chave alheia muda no .claude.json entre a conferência e a gravação dele (sessão viva).
// A alteração entra no ponto da troca em que a reserva de saída acabou de ser gravada, antes da vez do .claude.json:
// o oauthAccount tem de ser o do dono, e a chave alheia tem de sobreviver.
{
  const { pasta, arqs } = cenario('g');
  const renomear = fs.renameSync;
  let injetou = false;
  fs.renameSync = function (de, para, ...resto) {
    if (!injetou && path.resolve(String(para)) === path.resolve(arqs.sai)) {
      injetou = true;
      const atual = ler(arqs.claude);
      atual.chaveAlheia = 'alterada-na-janela';
      escrever(arqs.claude, atual);
    }
    return renomear.call(fs, de, para, ...resto);
  };
  let r;
  try {
    r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  } finally {
    fs.renameSync = renomear;
  }
  const depois = ler(arqs.claude);
  afirma('(g) a alteração de chave alheia entrou na janela, antes da gravação do .claude.json', injetou === true);
  afirma('(g) a troca sai ok com a chave alheia alterada na janela', r.ok === true);
  afirma('(g) a chave alheia alterada na janela sobrevive, e o oauthAccount é o do dono',
    depois.chaveAlheia === 'alterada-na-janela' && JSON.stringify(depois.oauthAccount) === JSON.stringify(DONO));
}

// (h) rodada 6, achado 4: a falha vem DEPOIS da escrita do .claude.json (a leitura final da reserva de saída
// lança). O desfazer tem de devolver o oauthAccount ORIGINAL (ANTIGO, não o do dono) e manter a chave alheia.
{
  const { pasta, arqs } = cenario('h');
  escrever(arqs.claude, { numStartups: 3, oauthAccount: ANTIGO, projects: {}, chaveAlheia: 'preservada-antes' });
  const hs = [arqs.cred, arqs.entra, arqs.sai].map(shaBytes);
  const renomear = fs.renameSync;
  const lerArq = fs.readFileSync;
  let claudeGravado = false;
  let falhou = false;
  fs.renameSync = function (de, para, ...resto) {
    if (path.resolve(String(para)) === path.resolve(arqs.claude)) claudeGravado = true;
    return renomear.call(fs, de, para, ...resto);
  };
  fs.readFileSync = function (arq, ...resto) {
    if (claudeGravado && path.resolve(String(arq)) === path.resolve(arqs.sai)) {
      falhou = true;
      throw Object.assign(new Error('falha simulada na leitura final da reserva de saída'), { code: 'EIO' });
    }
    return lerArq.call(fs, arq, ...resto);
  };
  let r;
  try {
    r = mover({ pasta, reservaEntra: arqs.entra, reservaSai: arqs.sai, dono: DONO });
  } finally {
    fs.renameSync = renomear;
    fs.readFileSync = lerArq;
  }
  const depois = ler(arqs.claude);
  afirma('(h) a falha entrou depois da gravação do .claude.json', falhou === true);
  afirma('(h) a falha pós-gravação devolve gravacao', r.ok === false && r.motivo === 'gravacao');
  afirma('(h) credenciais e reserva de entrada/saída com o mesmo sha256 de antes',
    [arqs.cred, arqs.entra, arqs.sai].map(shaBytes).every((h, i) => h === hs[i]));
  afirma('(h) o oauthAccount volta ao ORIGINAL (ANTIGO), não ao do dono',
    JSON.stringify(depois.oauthAccount) === JSON.stringify(ANTIGO));
  afirma('(h) a chave alheia e numStartups sobrevivem ao desfazer',
    depois.chaveAlheia === 'preservada-antes' && depois.numStartups === 3);
}

console.log(`ok: ${ok}   falhou: ${falhas}`);
process.exit(falhas ? 1 : 0);
JS
