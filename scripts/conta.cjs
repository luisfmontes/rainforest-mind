#!/usr/bin/env node
// @categoria: sensor
//
// Troca de conta Claude (plano 2026-10-10-troca-de-conta, tarefa 4; design D2, D3, D5 a D8).
//
//   node scripts/conta.cjs status
//   node scripts/conta.cjs trocar <pessoal|trabalho> [--pasta trabalho|pessoal]
//   node scripts/conta.cjs vigiar
//   node scripts/conta.cjs eventos --desde <ms>
//   node scripts/conta.cjs preparar <pessoal|trabalho>
//   node scripts/conta.cjs pessoal|trabalho [--pasta trabalho|pessoal]   (atalho de trocar)
//   node scripts/conta.cjs agendar [--imprimir]  |  desagendar
//
// Nunca imprime nem grava credencial. Quem diz a conta de uma pasta é o servidor
// (conta-api.dono), nunca o .claude.json. Toda troca e volta vira uma linha em
// <dados>/contas/eventos.jsonl.
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { decidir } = require('./lib/conta-decidir.cjs');
const { spawnSync } = require('node:child_process');
const { mover, gravarAtomico: gravarCred } = require('./lib/conta-mover.cjs');
const { acharExecutavelClaude } = require('./lib/achar-executavel-claude.cjs');
const API = require('./lib/conta-api.cjs');

// Padrão dos limiares (D4). Vale o que o arquivo <dados>/contas/config.json diz, chave a chave.
const PADRAO_CONFIG = { trocarEm: 97, destinoMax5h: 60, destinoMaxSemana: 85 };
const TAREFA = '\\ClaudeVigias\\troca-de-conta';
const TRAVA_MS = 5 * 60 * 1000;
const RENOVAR_ANTES_MS = 60 * 60 * 1000;
const LEITURA_MAX_MS = 15 * 60 * 1000;
// Aviso repetido (mesmo tipo e motivo) não vira uma linha por minuto: 1 por hora.
const AVISO_REPETIDO_MS = 60 * 60 * 1000;
const CONTAS = ['team', 'pessoal'];
const PASTAS = ['trabalho', 'pessoal'];
const LIMITES = ['five_hour', 'seven_day'];
// Nome da CLI -> conta interna. A casa de cada pasta é a conta de mesmo nome.
const CONTA_CLI = { trabalho: 'team', pessoal: 'pessoal' };
// Conta interna -> nome da CLI, para a pessoa.
const NOME = { team: 'trabalho', pessoal: 'pessoal' };

function pastasDir() {
  // As sobrescritas só valem em bateria (RFM_TEST=1), como RFM_CONTA_API.
  const teste = process.env.RFM_TEST === '1';
  return {
    trabalho: (teste && process.env.RFM_CONTA_PASTA_TRABALHO) || path.join(os.homedir(), '.claude'),
    pessoal: (teste && process.env.RFM_CONTA_PASTA_PESSOAL) || path.join(os.homedir(), '.claude-personal'),
  };
}

// Pasta da sessão que chamou (D7): a do CLAUDE_CONFIG_DIR; sem ele, o Claude Code usa ~/.claude.
function pastaDaSessao() {
  const norm = (p) => path.resolve(p).split(path.sep).join('/').toLowerCase();
  const dirs = pastasDir();
  const atual = norm(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'));
  return PASTAS.find((p) => norm(dirs[p]) === atual) || 'trabalho';
}

function dadosDir() {
  if (process.env.RFM_CONTA_DADOS) return process.env.RFM_CONTA_DADOS;
  const raiz = require('../hooks/lib/ponte-corpo.cjs').raizDeDados(path.resolve(__dirname, '..'));
  if (!raiz) throw new Error('sem pasta de dados do rainforest (defina RFM_CONTA_DADOS)');
  return raiz;
}

function ctx() {
  const dados = dadosDir();
  const contas = path.join(dados, 'contas');
  return {
    dados,
    contas,
    pastas: pastasDir(),
    estado: path.join(contas, 'estado.json'),
    config: path.join(contas, 'config.json'),
    eventos: path.join(contas, 'eventos.jsonl'),
    lock: path.join(contas, 'vigia.lock'),
  };
}

const credArq = (c, P) => path.join(c.pastas[P], '.credentials.json');
const claudeArq = (c, P) => path.join(c.pastas[P], '.claude.json');
const reservaArq = (c, conta) => path.join(c.contas, `reserva-${conta}.json`);
// Login da pasta guardado enquanto ela está fora de casa: um por pasta (P = trabalho | pessoal).
const estacionadoArq = (c, P) => path.join(c.contas, `estacionado-${P}.json`);

// Quatro lugares para quatro logins: duas pastas, reserva-<conta> por conta e estacionado-<pasta>.
// Troca da pasta P (casa A) para B: entra reserva-B, sai estacionado-P.
// Volta da pasta P (hoje em B) para A: entra estacionado-P, sai reserva-B.
function arqsDaTroca(c, P, de, para) {
  return para === CONTA_CLI[P]
    ? { entra: estacionadoArq(c, P), sai: reservaArq(c, de) }
    : { entra: reservaArq(c, para), sai: estacionadoArq(c, P) };
}

function sair(codigo, msg) {
  (codigo ? process.stderr : process.stdout).write(msg + '\n');
  process.exitCode = codigo;
  return codigo;
}

function valorDe(args, flag) {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
}

function lerJson(arq, padrao) {
  try {
    return JSON.parse(fs.readFileSync(arq, 'utf8'));
  } catch (e) {
    if (e.code === 'ENOENT' && padrao !== undefined) return padrao;
    throw e;
  }
}

// Escrita atômica: tmp no mesmo diretório e rename por cima.
function gravarAtomico(arq, obj) {
  fs.mkdirSync(path.dirname(arq), { recursive: true });
  const tmp = `${arq}.${process.pid}.${Date.now()}.tmp`;
  try {
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', 'utf8');
    fs.renameSync(tmp, arq);
  } catch (e) {
    fs.rmSync(tmp, { force: true });
    throw e;
  }
}

function lerEstado(c) {
  const e = lerJson(c.estado, {});
  const pastas = {};
  for (const P of PASTAS) {
    const gravado = (e.pastas || {})[P] || {};
    pastas[P] = {
      manual: false,
      travouPor: null,
      ...gravado,
      casa: CONTA_CLI[P],
      conta: gravado.conta || CONTA_CLI[P],
    };
  }
  return { automatico: e.automatico === true, pastas, contas: e.contas || {} };
}

const gravarEstado = (c, estado) => gravarAtomico(c.estado, estado);

// Limiares em uso (D4): padrão, com as chaves do config.json por cima. Arquivo ausente ou
// ilegível = padrão. Chave que não é número de 1 a 100 = padrão, com aviso no stderr.
function lerConfig(c) {
  const config = { ...PADRAO_CONFIG };
  let bruto;
  try {
    bruto = JSON.parse(fs.readFileSync(c.config, 'utf8'));
  } catch (e) {
    if (e.code !== 'ENOENT') process.stderr.write(`aviso: ${c.config} ilegível; usando os padrões\n`);
    return config;
  }
  if (!bruto || typeof bruto !== 'object' || Array.isArray(bruto)) return config;
  for (const chave of Object.keys(PADRAO_CONFIG)) {
    if (!Object.hasOwn(bruto, chave)) continue;
    const v = bruto[chave];
    if (typeof v === 'number' && v >= 1 && v <= 100) config[chave] = v;
    else process.stderr.write(`aviso: config.json ${chave}=${JSON.stringify(v)} inválido (1 a 100); usando ${PADRAO_CONFIG[chave]}\n`);
  }
  return config;
}

// Trava com dono pelo PID e validade de 5 min. O arquivo fica fechado depois de gravado.
function pegarTrava(lock) {
  for (let tentativa = 0; tentativa < 2; tentativa++) {
    try {
      fs.writeFileSync(lock, JSON.stringify({ pid: process.pid, em: Date.now() }), { flag: 'wx' });
      return true;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      if (!travaVencida(lock)) return false;
      fs.rmSync(lock, { force: true });
    }
  }
  return false;
}

function travaVencida(lock) {
  let em;
  try {
    em = JSON.parse(fs.readFileSync(lock, 'utf8')).em;
  } catch {
    em = undefined;
  }
  if (typeof em !== 'number') {
    try {
      em = fs.statSync(lock).mtimeMs;
    } catch {
      return true;
    }
  }
  return Date.now() - em > TRAVA_MS;
}

// Só apaga a trava se o PID gravado nela é o deste processo.
function soltarTrava(lock) {
  let pid;
  try {
    pid = JSON.parse(fs.readFileSync(lock, 'utf8')).pid;
  } catch {
    return;
  }
  if (pid === process.pid) fs.rmSync(lock, { force: true });
}

function registrarEvento(c, ev) {
  fs.mkdirSync(c.contas, { recursive: true });
  const linha = {
    em: Date.now(),
    tipo: ev.tipo,
    pasta: ev.pasta,
    de: ev.de,
    para: ev.para,
    motivo: ev.motivo,
    manual: ev.manual,
    voltaEm: ev.voltaEm,
  };
  fs.appendFileSync(c.eventos, JSON.stringify(linha) + '\n', 'utf8');
}

// Eventos válidos do log, na ordem. Linha que não é JSON (ou não é um objeto com `em`) é
// pulada: uma linha ruim não pode calar o mod nem o vigia para sempre.
function lerEventos(c) {
  let bruto;
  try {
    bruto = fs.readFileSync(c.eventos, 'utf8');
  } catch (e) {
    if (e.code === 'ENOENT') return [];
    throw e;
  }
  const validos = [];
  for (const linha of bruto.split('\n')) {
    if (!linha.trim()) continue;
    try {
      const ev = JSON.parse(linha);
      if (ev && typeof ev === 'object' && typeof ev.em === 'number') validos.push({ ev, linha });
    } catch {
      // linha corrompida: pula
    }
  }
  return validos;
}

// Evento de diagnóstico que pode se repetir enquanto o problema durar.
function registrarAviso(c, ev) {
  const agora = Date.now();
  const repetido = lerEventos(c).some(({ ev: x }) => x.tipo === ev.tipo && x.motivo === ev.motivo
    && x.pasta === ev.pasta && agora - x.em < AVISO_REPETIDO_MS);
  if (!repetido) registrarEvento(c, ev);
}

function credDaPasta(c, P) {
  const cred = lerJson(credArq(c, P), null);
  return cred && cred.claudeAiOauth ? cred : null;
}

function reservaPronta(c, conta) {
  const r = lerJson(reservaArq(c, conta), null);
  return r && r.claudeAiOauth ? r : null;
}

// Conta em uso: a primeira pasta que a tem; senão, a reserva dela.
function tokenDaConta(c, estado, conta) {
  const P = PASTAS.find((p) => estado.pastas[p].conta === conta && credDaPasta(c, p));
  if (P) return credDaPasta(c, P).claudeAiOauth.accessToken;
  const r = reservaPronta(c, conta);
  if (!r) return null;
  return r.claudeAiOauth.accessToken;
}

function estacionadoPronto(c, P) {
  const r = lerJson(estacionadoArq(c, P), null);
  return r && r.claudeAiOauth ? r : null;
}

function infoPasta(c, estado, P) {
  const cred = credDaPasta(c, P);
  if (!cred) throw new Error(`pasta ${P} sem credencial`);
  const est = estacionadoPronto(c, P);
  return {
    ...estado.pastas[P],
    expiresAt: cred.claudeAiOauth.expiresAt,
    estacionado: est ? { expiresAt: est.claudeAiOauth.expiresAt } : undefined,
  };
}

// Uma conta que não responde fica sem dado (decidir espera); nunca derruba a rodada das duas.
// Leitura antiga (429 devolve a última, com a idade) também vira "sem dado": não decide troca.
async function coletarUsos(c, estado) {
  const usos = {};
  for (const conta of CONTAS) {
    const tok = tokenDaConta(c, estado, conta);
    if (!tok) continue;
    try {
      const r = await API.uso(conta, tok, { dados: c.dados });
      if (r.dados && !(r.idadeMs > LEITURA_MAX_MS)) usos[conta] = r.dados;
    } catch (e) {
      process.stderr.write(`aviso: uso de ${NOME[conta]} indisponível: ${e.message}\n`);
    }
  }
  return usos;
}

// Os logins guardados (reserva-* e estacionado-*) ninguém usa, então ninguém renova: o access
// token vence (~8 h) e a conta fica sem dado e sem volta (D13). O vigia renova os que vencem em
// menos de 1 h e grava o mesmo arquivo na hora (o refresh token antigo deixa de valer). Falha
// vira evento, nunca derruba a rodada.
async function renovarOciosos(c, _estado) {
  let nomes;
  try {
    nomes = fs.readdirSync(c.contas).sort();
  } catch {
    return;
  }
  for (const nome of nomes) {
    if (!/^(reserva|estacionado)-[\w-]+\.json$/.test(nome)) continue;
    const arq = path.join(c.contas, nome);
    try {
      const obj = lerJson(arq, null);
      const login = obj && obj.claudeAiOauth;
      if (!login || !login.refreshToken) continue;
      if (!(Number(login.expiresAt) - Date.now() < RENOVAR_ANTES_MS)) continue;
      const novo = await API.renovar(login);
      gravarCred(arq, JSON.stringify({ ...obj, claudeAiOauth: novo }, null, 2) + '\n');
    } catch (e) {
      registrarAviso(c, { tipo: 'renovacao_falhou', motivo: `${nome.replace(/\.json$/, '')}: ${e.message}`, manual: false });
    }
  }
}

// Pasta em casa: copia o oauthAccount para a conta de casa, desde que o e-mail do
// .claude.json confira com o que o servidor diz do token. Devolve true se gravou algo.
async function registrarCasas(c, estado) {
  let mudou = false;
  for (const P of PASTAS) {
    const info = estado.pastas[P];
    if (info.conta !== info.casa) continue;
    const cred = credDaPasta(c, P);
    const claude = lerJson(claudeArq(c, P), null);
    if (!cred || !claude || !claude.oauthAccount) continue;
    const d = await API.dono(cred.claudeAiOauth.accessToken);
    if (claude.oauthAccount.emailAddress !== d.email) continue;
    estado.contas[info.casa] = { email: d.email, oauthAccount: claude.oauthAccount };
    mudou = true;
  }
  return mudou;
}

function contaDoEmail(estado, email) {
  return CONTAS.find((conta) => estado.contas[conta] && estado.contas[conta].email === email) || null;
}

function limiteQueTravou(uso, config) {
  const l = LIMITES.find((x) => uso && uso[x] && uso[x].utilization >= config.trocarEm);
  return l ? { limite: l, resetsAt: uso[l].resets_at } : null;
}

// Move a credencial da pasta P para a conta `para` e confere no servidor. Atualiza o
// estado e registra o evento só quando a conferência bate. Usado por trocar e vigiar.
async function aplicarTroca(c, estado, { P, para, tipo, manual, travouPor, motivo, voltaEm }) {
  const de = estado.pastas[P].conta;
  const dono = (estado.contas[para] || {}).oauthAccount;
  if (!dono) return { ok: false, motivo: `conta ${NOME[para]} sem registro: rode status com ela em casa` };
  const pasta = c.pastas[P];
  const claudeAntes = lerJson(claudeArq(c, P));
  const { entra, sai } = arqsDaTroca(c, P, de, para);
  if (!fs.existsSync(sai)) gravarAtomico(sai, {});
  const r = mover({ pasta, reservaEntra: entra, reservaSai: sai, dono });
  if (!r.ok) return r;

  const esperado = estado.contas[para].email;
  let confirmado;
  try {
    confirmado = (await API.dono(credDaPasta(c, P).claudeAiOauth.accessToken)).email;
  } catch (e) {
    confirmado = `erro na conferência: ${e.message}`;
  }
  if (confirmado !== esperado) {
    // Desfaz exatamente o que foi feito: o login que saiu volta, o que entrou é esvaziado.
    const volta = mover({
      pasta,
      reservaEntra: sai,
      reservaSai: entra,
      dono: claudeAntes.oauthAccount,
    });
    registrarEvento(c, {
      tipo: 'falhou',
      pasta: P,
      de,
      para,
      motivo: `servidor confirmou ${confirmado}, esperado ${esperado}; desfeito=${volta.ok}`,
      manual: false,
      voltaEm: null,
    });
    return { ok: false, motivo: 'conferencia' };
  }

  estado.pastas[P] = { ...estado.pastas[P], conta: para, manual, travouPor };
  gravarEstado(c, estado);
  registrarEvento(c, { tipo, pasta: P, de, para, motivo, manual, voltaEm });
  return { ok: true };
}

function pct(limite) {
  return limite && typeof limite.utilization === 'number' ? `${limite.utilization}%` : 'sem dado';
}

async function status(c) {
  const estado = lerEstado(c);
  if (await registrarCasas(c, estado)) gravarEstado(c, estado);
  const usos = await coletarUsos(c, estado);
  const linhas = [];
  for (const P of PASTAS) {
    const cred = credDaPasta(c, P);
    if (!cred) {
      linhas.push(`pasta ${P}: sem credencial`);
      continue;
    }
    const d = await API.dono(cred.claudeAiOauth.accessToken);
    const conta = contaDoEmail(estado, d.email);
    const info = estado.pastas[P];
    let linha = `pasta ${P}: conta em uso ${conta ? NOME[conta] : 'desconhecida'} (${d.email})`;
    linha += conta === info.casa ? ' · em casa' : ` · fora de casa (casa ${NOME[info.casa]})`;
    if (info.manual) linha += ' · troca manual (sem volta automática)';
    if (info.travouPor) linha += ` · volta em ${info.travouPor.resetsAt}`;
    if (conta && usos[conta]) {
      linha += ` · 5 h ${pct(usos[conta].five_hour)} · semana ${pct(usos[conta].seven_day)}`;
    }
    linhas.push(linha);
  }
  linhas.push('contas:');
  for (const conta of CONTAS) {
    const u = usos[conta];
    linhas.push(`  ${NOME[conta]}: 5 h ${pct(u && u.five_hour)} · semana ${pct(u && u.seven_day)}`);
  }
  const res = (conta) => (reservaPronta(c, conta) ? 'presente' : 'ausente');
  linhas.push(`reservas: trabalho ${res('team')} · pessoal ${res('pessoal')}`);
  const est = (P) => (estacionadoPronto(c, P) ? 'presente' : 'ausente');
  linhas.push(`estacionados: trabalho ${est('trabalho')} · pessoal ${est('pessoal')}`);
  linhas.push(`troca automática: ${estado.automatico ? 'ligada' : 'desligada'}`);
  const config = lerConfig(c);
  linhas.push(`limites: trocar em ${config.trocarEm}% · destino abaixo de ${config.destinoMax5h}% (5 h) e ${config.destinoMaxSemana}% (semana)`);
  console.log(linhas.join('\n'));
  return 0;
}

async function trocar(c, args) {
  const alvo = args[0];
  if (!Object.hasOwn(CONTA_CLI, alvo)) {
    return sair(2, 'uso: trocar <pessoal|trabalho> [--pasta trabalho|pessoal]');
  }
  const P = valorDe(args, '--pasta') || pastaDaSessao();
  if (!PASTAS.includes(P)) return sair(2, '--pasta: use trabalho ou pessoal');
  const para = CONTA_CLI[alvo];

  const lock = c.lock;
  fs.mkdirSync(c.contas, { recursive: true });
  if (!pegarTrava(lock)) return sair(1, 'outra rodada em curso: tente de novo em instantes');
  try {
    const estado = lerEstado(c);
    if (await registrarCasas(c, estado)) gravarEstado(c, estado);
    const { casa, conta: de } = estado.pastas[P];

    if (de === para) {
      estado.pastas[P] = { ...estado.pastas[P], manual: para !== casa, travouPor: null };
      gravarEstado(c, estado);
      return sair(0, `pasta ${P} já está na conta ${NOME[para]}`);
    }
    const outra = PASTAS.find((p) => p !== P);
    if (estado.pastas[outra].conta !== estado.pastas[outra].casa) {
      return sair(1, `a pasta ${outra} está fora de casa: não troco as duas ao mesmo tempo`);
    }
    const volta = para === casa;
    const pronta = volta ? estacionadoPronto(c, P) : reservaPronta(c, para);
    if (!pronta) {
      return sair(1, volta ? `sem login estacionado da pasta ${P}` : `sem reserva de ${NOME[para]}`);
    }

    const r = await aplicarTroca(c, estado, {
      P,
      para,
      tipo: 'trocar',
      manual: para !== casa,
      travouPor: null,
      motivo: 'manual',
      voltaEm: null,
    });
    if (!r.ok) return sair(1, `troca não feita: ${r.motivo}`);
    return sair(0, `pasta ${P}: ${NOME[de]} -> ${NOME[para]} (manual)`);
  } finally {
    soltarTrava(lock);
  }
}

async function vigiar(c) {
  const lock = c.lock;
  fs.mkdirSync(c.contas, { recursive: true });
  if (!pegarTrava(lock)) return sair(0, 'outra rodada em curso');
  try {
    const estado = lerEstado(c);
    if (!estado.automatico) return sair(0, 'troca automática desligada: nada a fazer');
    if (await registrarCasas(c, estado)) gravarEstado(c, estado);
    await renovarOciosos(c, estado);

    const pastas = {};
    for (const P of PASTAS) pastas[P] = infoPasta(c, estado, P);
    const usos = await coletarUsos(c, estado);
    const reservas = {};
    for (const conta of CONTAS) {
      const r = reservaPronta(c, conta);
      if (r) reservas[conta] = { expiresAt: r.claudeAiOauth.expiresAt };
    }
    const config = lerConfig(c);
    const acoes = decidir({ pastas, usos, reservas, config, agora: Date.now() });

    let codigo = 0;
    for (const a of acoes) {
      if (a.tipo === 'esperar') {
        console.log(`esperar ${a.pasta}: ${a.motivo}`);
        continue;
      }
      const de = estado.pastas[a.pasta].conta;
      let r;
      if (a.tipo === 'trocar') {
        const travou = limiteQueTravou(usos[de], config);
        r = await aplicarTroca(c, estado, {
          P: a.pasta,
          para: a.conta,
          tipo: 'trocar',
          manual: false,
          travouPor: travou,
          motivo: a.motivo,
          voltaEm: travou ? travou.resetsAt : null,
        });
      } else {
        r = await aplicarTroca(c, estado, {
          P: a.pasta,
          para: a.conta,
          tipo: 'voltar',
          manual: false,
          travouPor: null,
          motivo: a.motivo,
          voltaEm: null,
        });
      }
      if (r.ok) console.log(`${a.tipo} ${a.pasta}: ${de} -> ${a.conta}`);
      else {
        console.log(`${a.tipo} ${a.pasta} não feita: ${r.motivo}`);
        codigo = 1;
      }
    }
    if (!acoes.length) console.log('sem ação');
    return sair(codigo, codigo ? 'alguma ação não foi feita' : 'rodada concluída');
  } finally {
    soltarTrava(lock);
  }
}

// Login novo para a reserva de uma conta. O e-mail esperado é o da pasta dona da conta
// (oauthAccount do .claude.json dela); o servidor diz de quem é o login que o navegador
// autorizou, e só então a reserva é gravada. Login de conta errada não grava nada.
async function preparar(c, args) {
  const alvo = args[0];
  if (!Object.hasOwn(CONTA_CLI, alvo)) return sair(2, 'uso: preparar <pessoal|trabalho>');
  const conta = CONTA_CLI[alvo];
  if (reservaPronta(c, conta)) return sair(1, `reserva de ${alvo} já existe: não sobrescrevo`);
  const claude = lerJson(claudeArq(c, alvo), null);
  const esperado = claude && claude.oauthAccount && claude.oauthAccount.emailAddress;
  if (!esperado) return sair(1, `pasta ${alvo} sem oauthAccount: rode status com ela em casa`);

  // RFM_CONTA_CLAUDE (só com RFM_TEST=1) é um script node: roda pelo node, como o CLI real.
  const exe = (process.env.RFM_TEST === '1' && process.env.RFM_CONTA_CLAUDE) || acharExecutavelClaude();
  if (!exe) return sair(1, 'claude não encontrado no PATH (defina RFM_CLAUDE_EXECUTAVEL)');
  const argsLogin = ['auth', 'login', '--claudeai', '--email', esperado];
  const opcoes = { stdio: 'inherit', env: {} };

  fs.mkdirSync(c.contas, { recursive: true });
  const tmp = fs.mkdtempSync(path.join(c.contas, 'login-'));
  try {
    fs.writeFileSync(path.join(tmp, '.claude.json'), '{}\n');
    opcoes.env = { ...process.env, CLAUDE_CONFIG_DIR: tmp };
    const r = /\.(c|m)?js$/i.test(exe)
      ? spawnSync(process.execPath, [exe, ...argsLogin], opcoes)
      : spawnSync(exe, argsLogin, opcoes);
    if (r.error) return sair(1, 'não consegui rodar o claude: ' + r.error.message);
    if (r.status !== 0) return sair(1, 'login não concluído: nada gravado');

    const cred = lerJson(path.join(tmp, '.credentials.json'), null);
    if (!cred || !cred.claudeAiOauth) return sair(1, 'o login não gravou credencial: nada gravado');
    const veio = await API.dono(cred.claudeAiOauth.accessToken);
    if (veio.email !== esperado) return sair(3, 'o navegador autorizou ' + veio.email);
    gravarCred(reservaArq(c, conta), JSON.stringify({ claudeAiOauth: cred.claudeAiOauth }, null, 2) + '\n');

    const faltam = [['trabalho', 'team'], ['pessoal', 'pessoal']]
      .filter(([, k]) => !reservaPronta(c, k))
      .map(([nome]) => nome);
    if (!faltam.length) {
      const estado = lerEstado(c);
      estado.automatico = true;
      gravarEstado(c, estado);
      return sair(0, `reserva de ${alvo} gravada · troca automática ligada (as duas reservas existem)`);
    }
    return sair(0, `reserva de ${alvo} gravada · falta a reserva de ${faltam.join(' e ')}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// Vigia agendado (D5): a cada 1 minuto, sem /ED (um EndBoundary vencido já matou vigias desta
// máquina em silêncio). Caminhos absolutos achados na hora.
function raizWindows() {
  return process.env.SystemRoot || process.env.windir || 'C:\\Windows';
}

function schtasksExe() {
  if (process.env.RFM_TEST === '1' && process.env.RFM_CONTA_SCHTASKS) return process.env.RFM_CONTA_SCHTASKS;
  return path.join(raizWindows(), 'System32', 'schtasks.exe');
}

// Igual ao preparar: um executável .js/.cjs (só em bateria) roda pelo node.
function chamarSchtasks(argv) {
  const exe = schtasksExe();
  const opcoes = { stdio: 'inherit' };
  return /\.(c|m)?js$/i.test(exe)
    ? spawnSync(process.execPath, [exe, ...argv], opcoes)
    : spawnSync(exe, argv, opcoes);
}

function linhaDoComando(exe, argv) {
  return [exe, ...argv].map((a) => (/[\s"]/.test(a) ? `"${a.replace(/"/g, '\\"')}"` : a)).join(' ');
}

function montarAgendamento() {
  const conhost = path.join(raizWindows(), 'System32', 'conhost.exe');
  const acao = `"${conhost}" --headless "${process.execPath}" "${__filename}" vigiar`;
  const argv = ['/Create', '/TN', TAREFA, '/SC', 'MINUTE', '/MO', '1', '/F', '/TR', acao];
  return argv;
}

function agendar(c, args) {
  const argv = montarAgendamento();
  if (args.includes('--imprimir')) {
    console.log(linhaDoComando(schtasksExe(), argv));
    return 0;
  }
  const faltam = ['team', 'pessoal'].filter((conta) => !reservaPronta(c, conta));
  if (faltam.length) {
    return sair(1, `não agendo: falta a reserva de ${faltam.map((k) => NOME[k]).join(' e ')} (rode preparar antes)`);
  }
  // O vigia roda este arquivo pelo caminho absoluto: agendado de um worktree, morre com ele.
  if (/[\\/]\.claude[\\/]worktrees[\\/]/i.test(__filename)) {
    console.error('aviso: agendado de um worktree; reagende do clone instalado antes de removê-lo');
  }
  const r = chamarSchtasks(argv);
  if (r.error) return sair(1, 'não consegui rodar o schtasks: ' + r.error.message);
  const codigo = r.status === null ? 1 : r.status;
  return sair(codigo, codigo ? 'schtasks não agendou o vigia' : 'vigia agendado: a cada 1 minuto');
}

function desagendar() {
  const r = chamarSchtasks(['/Delete', '/TN', TAREFA, '/F']);
  if (r.error) return sair(1, 'não consegui rodar o schtasks: ' + r.error.message);
  const codigo = r.status === null ? 1 : r.status;
  return sair(codigo, codigo ? 'schtasks não removeu o vigia' : 'vigia desagendado');
}

function eventos(c, args) {
  const bruto = valorDe(args, '--desde');
  const desde = Number(bruto);
  if (bruto === undefined || !Number.isFinite(desde)) return sair(2, 'uso: eventos --desde <ms>');
  if (!fs.existsSync(c.eventos)) return 0;
  for (const linha of fs.readFileSync(c.eventos, 'utf8').split('\n')) {
    if (!linha.trim()) continue;
    if (JSON.parse(linha).em > desde) console.log(linha);
  }
  return 0;
}

async function main(argv) {
  const [cmd = 'status', ...resto] = argv;
  const c = ctx();
  if (cmd === 'status') return status(c);
  if (cmd === 'trocar') return trocar(c, resto);
  // Atalho do D7: /conta pessoal e /conta trabalho são trocar <conta>, com as mesmas flags.
  if (cmd === 'pessoal' || cmd === 'trabalho') return trocar(c, [cmd, ...resto]);
  if (cmd === 'vigiar') return vigiar(c);
  if (cmd === 'eventos') return eventos(c, resto);
  if (cmd === 'preparar') return preparar(c, resto);
  if (cmd === 'agendar') return agendar(c, resto);
  if (cmd === 'desagendar') return desagendar();
  return sair(2, 'uso: conta.cjs [status | pessoal|trabalho [--pasta trabalho|pessoal] | trocar <pessoal|trabalho> [--pasta trabalho|pessoal] | vigiar | eventos --desde <ms> | preparar <pessoal|trabalho> | agendar [--imprimir] | desagendar]');
}

main(process.argv.slice(2)).catch((e) => {
  process.stderr.write(`erro: ${e.message}\n`);
  process.exitCode = 1;
});
