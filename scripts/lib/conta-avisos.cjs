// Avisos de conta (D5 e D6 da Issue #693, plano conta-reserva-avisa, tarefa 4).
// Lê o log de eventos (<dados>/contas/eventos.jsonl), decide quais problemas estão abertos e
// monta a seção de contexto da sessão. Sem rede e sem child_process. O expiresAt dos logins e o
// mtime de vigia-ok entram por injeção: quem lê o disco é o chamador.
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { resolverRaiz } = require('../../hooks/lib/raiz.cjs');

const RENOVAR_ANTES_MS = 60 * 60 * 1000; // única fonte: scripts/conta.cjs importa daqui
const JANELA_DIAS = 7;
const DIA_MS = 24 * 60 * 60 * 1000;
const MAX_LINHA = 200;
const MAX_PROBLEMAS = 5;
const PASTAS = ['trabalho', 'pessoal'];
const CONTAS = new Set(['team', 'pessoal']);
const NOME_CONTA = { team: 'trabalho', pessoal: 'pessoal' };
const LIMITE_LEGIVEL = { seven_day: 'semana', five_hour: 'janela de 5 h' };
const ORDEM = ['vigia_falhou', 'pasta_sem_credencial', 'renovacao_falhou', 'uso_ilegivel', 'manual_no_limite'];
const TIPOS_COM_PASTA = new Set(['pasta_sem_credencial', 'pasta_com_credencial', 'uso_ilegivel', 'manual_no_limite']);
const RESOLVEM = new Set(['trocar', 'voltar', 'reconciliado']);
const RE_FALHA = /^([\w-]+): (.*)$/;
const RE_RESERVA = /^reserva-(team|pessoal)$/;
const RE_MOTIVO_MANUAL = /^(seven_day|five_hour) de (team|pessoal) em ([\d.,]{1,6}%)(?: \(>= [\d.,]+\))?$/;

// Caminho de dados igual ao dadosDir de scripts/conta.cjs:78-86: RFM_CONTA_DADOS vence; senão a
// raiz resolvida a partir do home (sem o projeto atual). Sem raiz, devolve null.
function dadosDir({ env = process.env, home = os.homedir(), plugin = path.resolve(__dirname, '..', '..') } = {}) {
  if (env.RFM_CONTA_DADOS) return env.RFM_CONTA_DADOS;
  return resolverRaiz({ env, cwd: home, plugin }).raiz || null;
}

// Eventos do log, na ordem do arquivo. Linha que não é objeto JSON com `em` numérico é pulada;
// arquivo ausente vale lista vazia; outro erro de leitura sobe.
function lerEventosArq(arq) {
  let bruto;
  try {
    bruto = fs.readFileSync(arq, 'utf8');
  } catch (e) {
    if (e.code === 'ENOENT') return [];
    throw e;
  }
  const eventos = [];
  for (const linha of bruto.split('\n')) {
    if (!linha.trim()) continue;
    let ev;
    try {
      ev = JSON.parse(linha);
    } catch {
      continue;
    }
    if (ev && typeof ev === 'object' && !Array.isArray(ev) && Number.isFinite(ev.em)) eventos.push(ev);
  }
  return eventos;
}

// Mesmo critério de falhasDeRenovacao (scripts/conta.cjs:595-613): falha aberta enquanto o login
// existe e vence em menos de 1 h. Sem expiresAt (arquivo ausente) não há falha aberta.
const precisaRenovar = (exp, agora) => Number.isFinite(exp) && exp - agora < RENOVAR_ANTES_MS; // D5 (conta-reserva-avisa)

// Última falha de cada login, enquanto ele ainda precisa renovar.
function falhasDeRenovacao(eventos, expiraEm, agora) {
  const ultima = new Map();
  for (const ev of eventos) {
    if (ev.tipo !== 'renovacao_falhou' || typeof ev.motivo !== 'string') continue;
    const m = RE_FALHA.exec(ev.motivo);
    if (m) ultima.set(m[1], { nome: m[1], em: ev.em, erro: m[2] });
  }
  return [...ultima.values()].filter((f) => precisaRenovar(expiraEm(f.nome), agora));
}

const ultimo = (lista) => lista.reduce((a, b) => (b.em >= a.em ? b : a));

// Campo presente e fora do conjunto conhecido invalida o evento; pasta é obrigatória nos tipos que
// a exigem. Renovação não tem pasta, de ou para, e passa.
function valido(ev) {
  if (ev.pasta != null && !PASTAS.includes(ev.pasta)) return false;
  if (TIPOS_COM_PASTA.has(ev.tipo) && !PASTAS.includes(ev.pasta)) return false;
  if (ev.de != null && !CONTAS.has(ev.de)) return false;
  if (ev.para != null && !CONTAS.has(ev.para)) return false;
  return true;
}

const item = (chave, tipo, em, campos = {}) => ({
  chave,
  tipo,
  em,
  pasta: undefined,
  nome: undefined,
  motivo: undefined,
  causa: undefined,
  de: undefined,
  para: undefined,
  ...campos,
});

// Problemas abertos, um por chave, ordenados por tipo e depois do mais recente para o mais antigo.
function problemasAbertos(eventos, { agora, expiraEm, vigiaOkEm }) {
  const recentes = eventos.filter((ev) => agora - ev.em <= JANELA_DIAS * DIA_MS && valido(ev));
  const itens = [];

  const vigia = recentes.filter((ev) => ev.tipo === 'vigia_falhou');
  if (vigia.length) {
    const u = ultimo(vigia);
    if (vigiaOkEm == null || vigiaOkEm <= u.em) itens.push(item('vigia_falhou', 'vigia_falhou', u.em, { motivo: u.motivo }));
  }

  for (const pasta of PASTAS) {
    const cred = recentes.filter(
      (ev) => ev.pasta === pasta && (ev.tipo === 'pasta_sem_credencial' || ev.tipo === 'pasta_com_credencial'),
    );
    if (!cred.length) continue;
    const u = ultimo(cred);
    if (u.tipo === 'pasta_sem_credencial') {
      itens.push(item(`pasta_sem_credencial:${pasta}`, 'pasta_sem_credencial', u.em, { pasta }));
    }
  }

  for (const f of falhasDeRenovacao(recentes, expiraEm, agora)) {
    if (f.nome.length > 20) continue;
    itens.push(item(`renovacao_falhou:${f.nome}`, 'renovacao_falhou', f.em, { nome: f.nome, motivo: f.erro }));
  }

  for (const pasta of PASTAS) {
    const uso = recentes.filter((ev) => ev.tipo === 'uso_ilegivel' && ev.pasta === pasta);
    if (uso.length) {
      const u = ultimo(uso);
      const resolvido = recentes.some((ev) => ev.pasta === pasta && RESOLVEM.has(ev.tipo) && ev.em > u.em);
      if (!resolvido && CONTAS.has(u.de)) {
        itens.push(item(`uso_ilegivel:${pasta}`, 'uso_ilegivel', u.em, { pasta, de: u.de }));
      }
    }
    const manual = recentes.filter((ev) => ev.tipo === 'manual_no_limite' && ev.pasta === pasta);
    if (manual.length) {
      const u = ultimo(manual);
      const resolvido = recentes.some((ev) => ev.pasta === pasta && RESOLVEM.has(ev.tipo) && ev.em > u.em);
      if (!resolvido && CONTAS.has(u.de) && CONTAS.has(u.para)) {
        itens.push(
          item(`manual_no_limite:${pasta}`, 'manual_no_limite', u.em, {
            pasta,
            de: u.de,
            para: u.para,
            motivo: u.motivo,
            causa: u.causa,
          }),
        );
      }
    }
  }

  return itens.sort((a, b) => ORDEM.indexOf(a.tipo) - ORDEM.indexOf(b.tipo) || b.em - a.em);
}

const dataUtc = (em) => new Date(em).toISOString().slice(0, 16).replace('T', ' ');

// Trecho livre do log: quebra e controle viram espaço, sequência de espaços vira um. O orçamento é
// o que sobra de 200 depois do texto fixo (entre 20 e 80), e o corte termina em "…" dentro dele.
function comTrecho(prefixo, sufixo, trecho) {
  const texto = String(trecho ?? '')
    .replace(/[\x00-\x1f\x7f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const orcamento = Math.min(80, Math.max(20, MAX_LINHA - (prefixo + sufixo).length));
  const corte = texto.length > orcamento ? `${texto.slice(0, orcamento - 1)}…` : texto;
  return (prefixo + corte + sufixo).slice(0, MAX_LINHA);
}

function linhaManual(p) {
  const conta = NOME_CONTA[p.de];
  const para = NOME_CONTA[p.para];
  // O motivo do evento não é trecho livre: só entra o limite e a porcentagem que casam o formato.
  const m = RE_MOTIVO_MANUAL.exec(String(p.motivo ?? ''));
  const parentese = m ? ` (${LIMITE_LEGIVEL[m[1]]} da conta ${conta} em ${m[3]})` : '';
  const inicio = `- pasta ${p.pasta}: na conta ${conta}, no limite${parentese}; `;
  if (p.causa === 'sem_login_guardado') {
    return `${inicio}não há login guardado da conta ${para}: faça /login dela na pasta ${p.pasta}.`;
  }
  return `${inicio}sem volta automática (casa sem folga ou sem dado). Devolver: /conta ${para} --pasta ${p.pasta}`;
}

function linhaDoProblema(p) {
  if (p.tipo === 'vigia_falhou') {
    return comTrecho(
      `- vigia: a rodada do vigia de troca de conta abortou em ${dataUtc(p.em)} UTC e a troca automática ficou sem decidir. Diagnóstico: node scripts/conta.cjs status (log: "`,
      '")',
      p.motivo,
    );
  }
  if (p.tipo === 'pasta_sem_credencial') {
    return `- pasta ${p.pasta}: sem .credentials.json; o vigia a deixa fora da decisão e decide só pela outra pasta. Refaça o /login dela, ou renomeie a pasta se ela não é mais usada.`;
  }
  if (p.tipo === 'renovacao_falhou') {
    const reserva = RE_RESERVA.exec(p.nome);
    if (reserva) {
      return comTrecho(
        `- login guardado ${p.nome}: a renovação falhou em ${dataUtc(p.em)} UTC; se o servidor recusa, refaça com: node scripts/conta.cjs preparar ${NOME_CONTA[reserva[1]]} --refazer (log: "`,
        '")',
        p.motivo,
      );
    }
    return comTrecho(
      `- login guardado ${p.nome}: a renovação falhou em ${dataUtc(p.em)} UTC; veja: node scripts/conta.cjs status (log: "`,
      '")',
      p.motivo,
    );
  }
  if (p.tipo === 'uso_ilegivel') {
    return `- pasta ${p.pasta}: o uso da conta ${NOME_CONTA[p.de]} está ilegível há mais de 30 min; sem ele a volta e o aviso de limite não disparam. Veja: node scripts/conta.cjs status`;
  }
  return linhaManual(p);
}

// Seção do contexto (D6): vazia sem problema; senão o cabeçalho, até 5 linhas e um resumo do excedente.
function montarSecao(problemas) {
  if (!problemas.length) return '';
  const linhas = ['## Conta (regra 14)'];
  for (const p of problemas.slice(0, MAX_PROBLEMAS)) linhas.push(linhaDoProblema(p));
  if (problemas.length > MAX_PROBLEMAS) {
    linhas.push(`... e mais ${problemas.length - MAX_PROBLEMAS}: node scripts/conta.cjs status`);
  }
  return linhas.join('\n');
}

module.exports = {
  RENOVAR_ANTES_MS,
  JANELA_DIAS,
  dadosDir,
  lerEventosArq,
  falhasDeRenovacao,
  problemasAbertos,
  montarSecao,
};
