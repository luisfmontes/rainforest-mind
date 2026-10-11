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
const { decidir, avaliarVida } = require('./lib/conta-decidir.cjs');
const { spawnSync } = require('node:child_process');
const { mover, gravarAtomico: gravarCred, prefixo: prefixoDoLogin } = require('./lib/conta-mover.cjs');
const { acharExecutavelClaude } = require('./lib/achar-executavel-claude.cjs');
const API = require('./lib/conta-api.cjs');

// Padrão dos limiares (D4). Vale o que o arquivo <dados>/contas/config.json diz, chave a chave.
const PADRAO_CONFIG = { trocarEm: 97, destinoMax5h: 60, destinoMaxSemana: 85 };
const TAREFA = '\\ClaudeVigias\\troca-de-conta';
const TRAVA_MS = 5 * 60 * 1000;
const GUARDA_MS = 30 * 1000;
const ESPERA_TRAVA_MS = 30 * 1000;
const RECUO_MS = 15 * 60 * 1000;
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

// A pasta de dados da conta é SEMPRE a do usuário. A resolução padrão do plugin prefere
// <projeto>/.rainforest quando o projeto tem FOCO.md: um /conta num projeto assim gravaria
// credencial dentro do repositório dele, separada da que o vigia agendado lê. Por isso o
// "projeto" aqui é o home (nível 2 e 3 da cadeia coincidem em ~/.rainforest).
function dadosDir() {
  if (process.env.RFM_CONTA_DADOS) return process.env.RFM_CONTA_DADOS;
  const raiz = require('../hooks/lib/raiz.cjs').resolverRaiz({
    cwd: os.homedir(),
    plugin: path.resolve(__dirname, '..'),
  }).raiz;
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

// Texto de erro que pode ir para stderr, evento ou log. O `e.message` de um JSON.parse carrega um
// trecho do texto lido, e o texto pode ser um arquivo de credencial editado à mão: nunca sai.
function msgSegura(e) {
  return e instanceof SyntaxError ? 'JSON inválido' : e.message;
}

function lerJson(arq, padrao) {
  try {
    return JSON.parse(fs.readFileSync(arq, 'utf8'));
  } catch (e) {
    if (e.code === 'ENOENT' && padrao !== undefined) return padrao;
    // Só o nome do arquivo: a mensagem do JSON.parse traz um trecho do conteúdo (talvez um token).
    if (e instanceof SyntaxError) throw new Error(`JSON inválido em ${path.basename(arq)}`);
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

const donoDaTrava = () => JSON.stringify({ pid: process.pid, em: Date.now() });

// Trava com dono pelo PID e validade de 5 min. O arquivo fica fechado depois de gravado.
function pegarTrava(lock) {
  try {
    fs.writeFileSync(lock, donoDaTrava(), { flag: 'wx' });
    return true;
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
  }
  return travaVencida(lock) && tomarVencida(lock);
}

// Trava vencida só sai do lugar por quem está DENTRO da guarda `<lock>.tomada`, criada com wx (um
// processo só por vez): dentro dela a validade é conferida de novo, e só então a trava velha é
// apagada e a nova criada com wx. A leitura "vencida" de antes da guarda pode ser velha (outro
// processo já tomou e recriou a trava) e não decide nada; sem a guarda, quem apagava a trava nova
// de outro a devolvia depois com um link, e nessa janela um terceiro criava a sua: dois donos.
// A guarda dura milissegundos; a que ficou para trás (processo morto dentro dela) vence em 30 s e é
// recolhida pela rodada seguinte.
function tomarVencida(lock) {
  const guarda = `${lock}.tomada`;
  try {
    fs.writeFileSync(guarda, donoDaTrava(), { flag: 'wx' });
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    if (travaVencida(guarda, GUARDA_MS)) fs.rmSync(guarda, { force: true });
    return false;
  }
  try {
    if (!travaVencida(lock)) return false;
    fs.rmSync(lock, { force: true });
    fs.writeFileSync(lock, donoDaTrava(), { flag: 'wx' });
    return true;
  } catch (e) {
    if (e.code === 'EEXIST') return false;
    throw e;
  } finally {
    fs.rmSync(guarda, { force: true });
  }
}

// Para quem já gastou minutos (o login do preparar) e não quer perder o resultado por uma rodada
// curta do vigia: tenta de novo por até `ms`.
async function pegarTravaEspera(lock, ms) {
  const fim = Date.now() + ms;
  for (;;) {
    if (pegarTrava(lock)) return true;
    if (Date.now() >= fim) return false;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
}

function travaVencida(lock, validadeMs = TRAVA_MS) {
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
  return Date.now() - em > validadeMs;
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
    // Só no falhou de uma troca que ficou pela metade: nomes de arquivo (sem caminho) que o
    // desfazer não restaurou, e a causa da troca desfeita. Nunca credencial.
    pendentes: ev.pendentes,
    causa: ev.causa,
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

// Logins que dizem o uso de uma conta, na ordem de tentativa: o da primeira pasta que a tem e,
// depois, o da reserva dela. A pasta ociosa (sem sessão) não renova o próprio token e ele vence;
// a reserva a D13 mantém renovada, então o uso da conta continua legível e a troca não fica cega.
function loginsDaConta(c, estado, conta) {
  const logins = [];
  const P = PASTAS.find((p) => estado.pastas[p].conta === conta && credDaPasta(c, p));
  if (P) logins.push(credDaPasta(c, P).claudeAiOauth);
  const r = reservaPronta(c, conta);
  if (r) logins.push(r.claudeAiOauth);
  return logins;
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
// Token vencido (pelo relógio ou por um 401) passa para o login seguinte da conta (a reserva); só o
// 401 faz isso: qualquer outra falha (500, rede) é da conta, não do token, e para por aí.
async function coletarUsos(c, estado) {
  const usos = {};
  for (const conta of CONTAS) {
    let erro = null;
    for (const login of loginsDaConta(c, estado, conta)) {
      if (!login.accessToken) continue;
      if (Number(login.expiresAt) <= Date.now()) {
        erro = new Error('login vencido');
        continue;
      }
      try {
        const r = await API.uso(conta, login.accessToken, { dados: c.dados });
        if (r.dados && !(r.idadeMs > LEITURA_MAX_MS)) usos[conta] = r.dados;
        erro = null;
        break;
      } catch (e) {
        erro = e;
        if (!/HTTP 401$/.test(e.message)) break;
      }
    }
    if (erro) process.stderr.write(`aviso: uso de ${NOME[conta]} indisponível: ${msgSegura(erro)}\n`);
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
      registrarAviso(c, { tipo: 'renovacao_falhou', motivo: `${nome.replace(/\.json$/, '')}: ${msgSegura(e)}`, manual: false });
    }
  }
}

// Pasta em casa: registra o oauthAccount na conta de casa, desde que o e-mail do .claude.json
// confira com o que o servidor diz do token. Registro existente NUNCA é sobrescrito: se o login
// da pasta "em casa" não é o registrado (ex.: um desfazer que falhou deixou o login do outro lá),
// vira o evento identidade_divergente e nada é gravado. Devolve true se registrou uma conta.
// Sem a trava (sobTrava falso) só se lê: nenhum evento, nenhuma gravação cabe ao chamador.
async function registrarCasas(c, estado, sobTrava) {
  let mudou = false;
  for (const P of PASTAS) {
    const info = estado.pastas[P];
    if (info.conta !== info.casa) continue;
    const cred = credDaPasta(c, P);
    const claude = lerJson(claudeArq(c, P), null);
    if (!cred || !claude || !claude.oauthAccount) continue;
    let d;
    try {
      d = await API.dono(cred.claudeAiOauth.accessToken);
    } catch {
      continue;
    }
    if (claude.oauthAccount.emailAddress !== d.email) continue;
    const registrada = estado.contas[info.casa];
    if (registrada && registrada.email) {
      if (registrada.email !== d.email && sobTrava) {
        registrarAviso(c, {
          tipo: 'identidade_divergente',
          pasta: P,
          motivo: `a pasta ${P} está em casa (conta ${NOME[info.casa]}) mas o login dela é de outra conta`,
          manual: false,
        });
      }
      continue;
    }
    estado.contas[info.casa] = { email: d.email, oauthAccount: claude.oauthAccount };
    mudou = true;
  }
  return mudou;
}

// Última falha de renovação de cada login guardado, enquanto ele ainda precisa renovar (vence em
// menos de 1 h): login que já foi renovado depois da falha, ou que sumiu, não aparece. Lê só os
// eventos (que não levam credencial) e o expiresAt do arquivo.
function falhasDeRenovacao(c) {
  const ultima = new Map();
  for (const { ev } of lerEventos(c)) {
    if (ev.tipo !== 'renovacao_falhou' || typeof ev.motivo !== 'string') continue;
    const m = /^([\w-]+): (.*)$/.exec(ev.motivo);
    if (m) ultima.set(m[1], { em: ev.em, erro: m[2] });
  }
  const linhas = [];
  for (const [nome, f] of ultima) {
    let login;
    try {
      login = (lerJson(path.join(c.contas, `${nome}.json`), null) || {}).claudeAiOauth;
    } catch {
      continue;
    }
    if (!login || !(Number(login.expiresAt) - Date.now() < RENOVAR_ANTES_MS)) continue;
    const conta = /^reserva-(\w+)$/.exec(nome);
    const refazer = conta && NOME[conta[1]] ? `; se o servidor recusa, refaça: preparar ${NOME[conta[1]]} --refazer` : '';
    linhas.push(`aviso: a renovação de ${nome} falhou em ${new Date(f.em).toISOString()} (${f.erro})${refazer}`);
  }
  return linhas;
}

// Todo login guardado em arquivo: as duas pastas, as duas reservas e os dois estacionados.
function loginsGuardados(c) {
  const itens = [];
  for (const P of PASTAS) {
    const cred = credDaPasta(c, P);
    if (cred) itens.push([`pasta-${P}`, cred]);
  }
  for (const conta of CONTAS) {
    const r = reservaPronta(c, conta);
    if (r) itens.push([`reserva-${conta}`, r]);
  }
  for (const P of PASTAS) {
    const e = estacionadoPronto(c, P);
    if (e) itens.push([`estacionado-${P}`, e]);
  }
  return itens;
}

// Refresh token é de uso único: o mesmo em dois arquivos é troca que falhou pela metade (ou
// processo morto entre gravações). Só o prefixo do sha256 sai daqui, nunca o token.
function credenciaisDuplicadas(c) {
  const porLogin = new Map();
  for (const [nome, cred] of loginsGuardados(c)) {
    const h = prefixoDoLogin(cred);
    if (h) porLogin.set(h, [...(porLogin.get(h) || []), nome]);
  }
  return [...porLogin].filter(([, nomes]) => nomes.length > 1).map(([h, nomes]) => ({ h, nomes }));
}

function avisarDuplicadas(c, duplicadas) {
  for (const { h, nomes } of duplicadas) {
    registrarAviso(c, { tipo: 'credencial_duplicada', motivo: `login ${h} em ${nomes.join(' e ')}`, manual: false });
  }
}

// A reserva de <conta> fica vazia enquanto uma pasta fora de casa usa aquela conta: o login
// dela está na pasta. Gravar um login novo ali faria a volta recusar a saída (saida_ocupada).
const MSG_SLOT_EM_USO = (alvo) => `a reserva de ${alvo} está em uso numa pasta trocada: volte a pasta antes de preparar`;
function slotEmUso(c, conta) {
  const estado = lerEstado(c);
  return PASTAS.some((P) => estado.pastas[P].conta === conta && estado.pastas[P].conta !== estado.pastas[P].casa);
}

// Reserva de <conta> como o preparar a vê: { obj, ilegivel }. Arquivo que não é JSON conta como
// existente e ilegível (é o caso que --refazer existe para consertar), em vez de derrubar o comando.
function reservaExistente(c, conta) {
  try {
    return { obj: reservaPronta(c, conta), ilegivel: false };
  } catch (e) {
    if (!/^JSON inválido em /.test(e.message)) throw e;
    return { obj: null, ilegivel: true };
  }
}

// Identidade da reserva existente (prefixo do refresh token, ou 'ilegivel'); null = não há reserva.
function marcaDaReserva(r) {
  if (r.obj) return prefixoDoLogin(r.obj) || 'sem-refresh';
  return r.ilegivel ? 'ilegivel' : null;
}

// Pasta trocada guarda no .claude.json o oauthAccount da conta que entrou (o mover o reescreve):
// preparar com ela fora de casa pediria o login da conta errada e gravaria a reserva errada.
const MSG_PASTA_FORA = (alvo) => `a pasta ${alvo} está fora de casa: volte a pasta antes de preparar`;
function pastaForaDeCasa(c, P) {
  const info = lerEstado(c).pastas[P];
  return info.conta !== info.casa;
}

function contaDoEmail(estado, email) {
  return CONTAS.find((conta) => estado.contas[conta] && estado.contas[conta].email === email) || null;
}

// Com os dois limites passados, a volta espera o que reseta por último: voltar quando só o de
// 5 h zerou devolve a pasta a uma conta ainda travada na semana, e a troca se repete.
function limiteQueTravou(uso, config) {
  const passaram = LIMITES
    .filter((x) => uso && uso[x] && uso[x].utilization >= config.trocarEm)
    .map((x) => ({ limite: x, resetsAt: uso[x].resets_at }));
  if (!passaram.length) return null;
  return passaram.reduce((a, b) => (Date.parse(b.resetsAt) > Date.parse(a.resetsAt) ? b : a));
}

// Depois de um falhou nesta pasta o vigia espera 15 min: sem isso, um /profile fora do ar fazia
// troca + desfazer (8 gravações e um evento) a cada minuto.
function emRecuo(c, P) {
  const agora = Date.now();
  return lerEventos(c).some(({ ev }) => ev.tipo === 'falhou' && ev.pasta === P && agora - ev.em < RECUO_MS);
}

// Move a credencial da pasta P para a conta `para` e confere no servidor. Atualiza o
// estado e registra o evento só quando a conferência bate. Usado por trocar e vigiar.
async function aplicarTroca(c, estado, { P, para, tipo, manual, travouPor, motivo, voltaEm }) {
  const de = estado.pastas[P].conta;
  // Toda troca ou volta que não acontece deixa o evento falhou (não só uma linha de stdout).
  // `pendentes` (só no desfazer_falhou): arquivos que o desfazer não restaurou, sem o caminho.
  const falhou = (motivoFalha, pendentes, causa) => {
    const extra = pendentes ? { pendentes: pendentes.map((p) => path.basename(p)), causa } : {};
    registrarEvento(c, { tipo: 'falhou', pasta: P, de, para, motivo: motivoFalha, manual: false, voltaEm: null, ...extra });
    return { ok: false, motivo: motivoFalha, ...extra };
  };
  const dono = (estado.contas[para] || {}).oauthAccount;
  if (!dono) return falhou(`conta ${NOME[para]} sem registro: rode status com ela em casa`);
  const pasta = c.pastas[P];
  const claudeAntes = lerJson(claudeArq(c, P));
  const { entra, sai } = arqsDaTroca(c, P, de, para);
  if (!fs.existsSync(sai)) gravarAtomico(sai, {});
  const r = mover({ pasta, reservaEntra: entra, reservaSai: sai, dono });
  if (!r.ok) return falhou(r.motivo, r.pendentes);

  const esperado = estado.contas[para].email;
  let confirmado;
  try {
    confirmado = (await API.dono(credDaPasta(c, P).claudeAiOauth.accessToken)).email;
  } catch (e) {
    confirmado = `erro na conferência: ${msgSegura(e)}`;
  }
  if (confirmado !== esperado) {
    // Desfaz exatamente o que foi feito: o login que saiu volta, o que entrou é esvaziado.
    const volta = mover({
      pasta,
      reservaEntra: sai,
      reservaSai: entra,
      dono: claudeAntes.oauthAccount,
    });
    const causa = `servidor confirmou ${confirmado}, esperado ${esperado}`;
    // O desfazer também falhou: a troca ficou pela metade e o aviso precisa dos arquivos pendentes.
    if (volta.motivo === 'desfazer_falhou') return falhou('desfazer_falhou', volta.pendentes, causa);
    registrarEvento(c, {
      tipo: 'falhou',
      pasta: P,
      de,
      para,
      motivo: `${causa}; desfeito=${volta.ok}`,
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

// Motivo da falha para a saída; troca pela metade diz quais arquivos ficaram sem restaurar.
function descreverFalha(r) {
  return r.pendentes && r.pendentes.length
    ? `${r.motivo} (arquivos pendentes: ${r.pendentes.join(', ')})`
    : r.motivo;
}

function pct(limite) {
  return limite && typeof limite.utilization === 'number' ? `${limite.utilization}%` : 'sem dado';
}

// Grava o estado e os eventos só com a trava; sem ela (vigia no meio de uma rodada) mostra o que
// leu e não grava nada: leitura + rede + gravação sem a trava restaurava estado velho por cima
// de uma troca do vigia.
async function status(c) {
  fs.mkdirSync(c.contas, { recursive: true });
  const sobTrava = pegarTrava(c.lock);
  try {
    return await statusLido(c, sobTrava);
  } finally {
    if (sobTrava) soltarTrava(c.lock);
  }
}

async function statusLido(c, sobTrava) {
  const estado = lerEstado(c);
  if (await registrarCasas(c, estado, sobTrava) && sobTrava) gravarEstado(c, estado);
  const duplicadas = credenciaisDuplicadas(c);
  if (sobTrava) avisarDuplicadas(c, duplicadas);
  const usos = await coletarUsos(c, estado);
  const linhas = [];
  for (const d of duplicadas) {
    linhas.push(`aviso: o mesmo login (${d.h}) está em ${d.nomes.join(' e ')}: não troque nem renove até separar`);
  }
  for (const P of PASTAS) {
    const cred = credDaPasta(c, P);
    if (!cred) {
      linhas.push(`pasta ${P}: sem credencial`);
      continue;
    }
    let d;
    try {
      d = await API.dono(cred.claudeAiOauth.accessToken);
    } catch (e) {
      linhas.push(`pasta ${P}: conta em uso desconhecida (${msgSegura(e)})`);
      continue;
    }
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
  linhas.push(...falhasDeRenovacao(c));
  linhas.push(`troca automática: ${estado.automatico ? 'ligada' : 'desligada'}`);
  const config = lerConfig(c);
  linhas.push(`limites: trocar em ${config.trocarEm}% · destino abaixo de ${config.destinoMax5h}% (5 h) e ${config.destinoMaxSemana}% (semana)`);
  console.log(linhas.join('\n'));
  return 0;
}

// Recusa da troca manual pela guarda de vida da D11; null quando pode mover. Diz qual login está
// curto e quando tentar de novo: o que entra, o vigia renova na próxima rodada; o que sai, só
// quando completa 10 min vencido (aí a pasta não tem sessão e a guarda se dispensa).
function recusaDeVida(P, de, para, volta, expiraSai, expiraEntra) {
  const curto = avaliarVida(expiraSai, expiraEntra, Date.now());
  if (!curto) return null;
  if (curto.quem === 'entra') {
    const quem = volta ? `o login estacionado da pasta ${P}` : `a reserva de ${NOME[para]}`;
    return `troca adiada: ${quem} tem menos de 30 min de vida no access token; o vigia o renova na próxima rodada, tente de novo em 1 min (se continuar recusando, /conta mostra se a renovação falhou e como refazer)`;
  }
  const depois = curto.ate === null ? '' : ` depois das ${new Date(Math.ceil(curto.ate / 60000) * 60000)
    .toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}, quando ele completa 10 min vencido`;
  return `troca adiada: o login da pasta ${P} (conta ${NOME[de]}) tem menos de 30 min de vida no access token; tente de novo${depois}`;
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
    if (await registrarCasas(c, estado, true)) gravarEstado(c, estado);
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

    // Mesma guarda de vida do vigia (D11): não move com um dos dois logins curto, e diz quando voltar.
    const credPasta = credDaPasta(c, P);
    if (!credPasta) return sair(1, `pasta ${P} sem credencial`);
    const adiada = recusaDeVida(P, de, para, volta, credPasta.claudeAiOauth.expiresAt, pronta.claudeAiOauth.expiresAt);
    if (adiada) return sair(1, adiada);

    const r = await aplicarTroca(c, estado, {
      P,
      para,
      tipo: 'trocar',
      manual: para !== casa,
      travouPor: null,
      motivo: 'manual',
      voltaEm: null,
    });
    if (!r.ok) return sair(1, `troca não feita: ${descreverFalha(r)}`);
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
    if (await registrarCasas(c, estado, true)) gravarEstado(c, estado);
    // Antes de renovar: renovar um login que está em dois arquivos mata a cópia do outro.
    const duplicadas = credenciaisDuplicadas(c);
    if (duplicadas.length) {
      avisarDuplicadas(c, duplicadas);
      return sair(1, 'o mesmo login está em dois arquivos: nada movido nem renovado');
    }
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
      if (emRecuo(c, a.pasta)) {
        console.log(`esperar ${a.pasta}: recuo de 15 min depois de uma ${a.tipo} que falhou`);
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
        console.log(`${a.tipo} ${a.pasta} não feita: ${descreverFalha(r)}`);
        codigo = 1;
      }
    }
    if (!acoes.length) console.log('sem ação');
    return sair(codigo, codigo ? 'alguma ação não foi feita' : 'rodada concluída');
  } finally {
    soltarTrava(lock);
  }
}

// Login novo para a reserva de uma conta. O e-mail esperado é o REGISTRADO da conta
// (estado.contas[conta].email, gravado sob a trava com o servidor confirmando a pasta em casa),
// nunca o .claude.json da pasta: o mover o reescreve com a conta que entrou (D10). O servidor diz
// de quem é o login que o navegador autorizou, e só então a reserva é gravada. Login de conta
// errada não grava nada.
//
// --refazer troca uma reserva que já existe quando ela está morta (o servidor recusa renovar o
// login dela, ou o arquivo nem é JSON): reserva morta não se refazia pelo CLI. Para saber, tenta
// renová-la; se renova, ela está viva: o par novo vai para o mesmo arquivo (o refresh token antigo
// já não vale) e nada é refeito.
async function preparar(c, args) {
  const alvo = args.find((a) => !a.startsWith('--'));
  const refazer = args.includes('--refazer');
  if (!Object.hasOwn(CONTA_CLI, alvo)) return sair(2, 'uso: preparar <pessoal|trabalho> [--refazer]');
  const conta = CONTA_CLI[alvo];

  // As recusas que dependem do estado rodam sob a trava, para o vigia não trocar pasta no meio.
  // O login em si (minutos de navegador) roda FORA dela: a trava vence em 5 min.
  fs.mkdirSync(c.contas, { recursive: true });
  if (!pegarTrava(c.lock)) return sair(1, 'outra rodada em curso: tente de novo em instantes');
  let esperado;
  let antes = null;
  try {
    const estado = lerEstado(c);
    if (await registrarCasas(c, estado, true)) gravarEstado(c, estado);
    if (pastaForaDeCasa(c, alvo)) return sair(1, MSG_PASTA_FORA(alvo));
    if (slotEmUso(c, conta)) return sair(1, MSG_SLOT_EM_USO(alvo));
    const velha = reservaExistente(c, conta);
    antes = marcaDaReserva(velha);
    if (antes && !refazer) {
      return sair(1, velha.ilegivel
        ? `reserva de ${alvo} ilegível (JSON inválido em ${path.basename(reservaArq(c, conta))}): use --refazer para refazê-la`
        : `reserva de ${alvo} já existe: não sobrescrevo (se ela morreu, use --refazer)`);
    }
    if (velha.obj) {
      let novo = null;
      let incerto = null;
      try {
        novo = await API.renovar(velha.obj.claudeAiOauth);
      } catch (e) {
        if (!/^token HTTP (400|401|403)$/.test(e.message)) incerto = msgSegura(e);
      }
      if (novo) {
        gravarCred(reservaArq(c, conta), JSON.stringify({ ...velha.obj, claudeAiOauth: novo }, null, 2) + '\n');
        return sair(1, `a reserva de ${alvo} está viva (renovei): nada a refazer`);
      }
      if (incerto) return sair(1, `não consegui confirmar que a reserva de ${alvo} morreu (${incerto}): tente de novo`);
    }
    esperado = (estado.contas[conta] || {}).email;
    if (!esperado) return sair(1, `conta ${alvo} sem registro: rode status com a pasta ${alvo} em casa`);
  } finally {
    soltarTrava(c.lock);
  }

  // RFM_CONTA_CLAUDE (só com RFM_TEST=1) é um script node: roda pelo node, como o CLI real.
  const exe = (process.env.RFM_TEST === '1' && process.env.RFM_CONTA_CLAUDE) || acharExecutavelClaude();
  if (!exe) return sair(1, 'claude não encontrado no PATH (defina RFM_CLAUDE_EXECUTAVEL)');
  const argsLogin = ['auth', 'login', '--claudeai', '--email', esperado];
  const opcoes = { stdio: 'inherit', env: {} };

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

    // Grava sob a trava e reconfere: durante o login o vigia pode ter trocado a pasta.
    if (!(await pegarTravaEspera(c.lock, ESPERA_TRAVA_MS))) {
      return sair(1, 'outra rodada em curso: o login não foi gravado; rode preparar de novo');
    }
    try {
      // A reserva tem de estar como estava antes do login (ausente, ou a mesma que --refazer vai trocar).
      if (pastaForaDeCasa(c, alvo) || slotEmUso(c, conta) || marcaDaReserva(reservaExistente(c, conta)) !== antes) {
        return sair(1, 'o estado mudou durante o login: nada gravado; rode preparar de novo');
      }
      gravarCred(reservaArq(c, conta), JSON.stringify({ claudeAiOauth: cred.claudeAiOauth }, null, 2) + '\n');
      const verbo = antes ? 'refeita' : 'gravada';

      const faltam = [['trabalho', 'team'], ['pessoal', 'pessoal']]
        .filter(([, k]) => !reservaPronta(c, k))
        .map(([nome]) => nome);
      if (!faltam.length) {
        const estado = lerEstado(c);
        estado.automatico = true;
        gravarEstado(c, estado);
        return sair(0, `reserva de ${alvo} ${verbo} · troca automática ligada (as duas reservas existem)`);
      }
      return sair(0, `reserva de ${alvo} ${verbo} · falta a reserva de ${faltam.join(' e ')}`);
    } finally {
      soltarTrava(c.lock);
    }
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
  for (const { ev, linha } of lerEventos(c)) {
    if (ev.em > desde) console.log(linha);
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

// A bateria da trava (scripts/testa-conta.sh) carrega este arquivo para exercitar pegarTrava em
// um só processo, com a ordem das leituras e gravações escolhida por ela.
if (require.main === module) {
  main(process.argv.slice(2)).catch((e) => {
    process.stderr.write(`erro: ${msgSegura(e)}\n`);
    process.exitCode = 1;
  });
}

module.exports = { pegarTrava, soltarTrava };
