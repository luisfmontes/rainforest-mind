'use strict';
/**
 * Move a credencial claudeAiOauth entre uma pasta de config e uma reserva.
 *
 * Exported: mover({ pasta, reservaEntra, reservaSai, dono })
 *   - pasta: pasta de config com .credentials.json e .claude.json (caminho absoluto)
 *   - reservaEntra: reserva cujo login vai para a pasta ({ claudeAiOauth: {...} })
 *   - reservaSai: reserva que recebe o login que a pasta tinha
 *   - dono: objeto oauthAccount gravado no .claude.json da pasta
 *
 * Retorno:
 *   { ok: true, entrou, saiu }            prefixos sha256(refreshToken), 12 chars
 *   { ok: false, motivo: 'mudou' }        algum arquivo mudou entre a leitura e a gravação
 *   { ok: false, motivo: 'duplicada' }    o login da reserva que entra é o da pasta
 *   { ok: false, motivo: 'gravacao' }     uma gravação não releu igual; tudo desfeito
 *   { ok: false, motivo: 'sem_credencial' } a reserva que entra não tem claudeAiOauth
 *   { ok: false, motivo: 'saida_ocupada' } a reserva que sai já tem claudeAiOauth; nada gravado
 *   { ok: false, motivo: 'desfazer_falhou', pendentes } o desfazer também falhou; pendentes = arquivos não restaurados
 *
 * Refresh token é de uso único: o login nunca pode ficar em dois arquivos ao
 * mesmo tempo. Por isso MOVER, nunca copiar. Nunca imprime token.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CHAVE = 'claudeAiOauth';

function impressao(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function prefixo(credencial) {
  return credencial && credencial[CHAVE] && credencial[CHAVE].refreshToken
    ? impressao(credencial[CHAVE].refreshToken).slice(0, 12)
    : null;
}

function conferirUnica(credenciais) {
  const hashes = [];
  for (const c of credenciais) {
    if (c && c[CHAVE] && c[CHAVE].refreshToken) hashes.push(impressao(c[CHAVE].refreshToken));
  }
  const impressoes = new Set(hashes);
  const total = hashes.length;
  if (impressoes.size !== total) throw new Error('credencial em dois lugares');
}

function comChave(obj, valor) {
  const copia = { ...obj };
  if (valor === undefined) delete copia[CHAVE];
  else copia[CHAVE] = valor;
  return copia;
}

function gravarAtomico(arq, texto) {
  const tmp = path.join(path.dirname(arq), `.${path.basename(arq)}.${process.pid}.${Date.now()}.tmp`);
  try {
    fs.writeFileSync(tmp, texto, { encoding: 'utf8', mode: 0o600, flag: 'wx' });
    fs.renameSync(tmp, arq);
  } catch (e) {
    // EEXIST: o caminho temporário já existia e não é nosso; não se apaga o que não criamos.
    if (e.code !== 'EEXIST') fs.rmSync(tmp, { force: true });
    throw e;
  }
}

function fimDeLinha(bruto) {
  return bruto.endsWith('\n') ? '\n' : '';
}

function mover({ pasta, reservaEntra, reservaSai, dono }) {
  if (!dono) throw new Error('dono ausente');
  if (path.resolve(reservaEntra) === path.resolve(reservaSai)) throw new Error('reservas iguais');

  const arqs = {
    cred: path.join(pasta, '.credentials.json'),
    claude: path.join(pasta, '.claude.json'),
    entra: reservaEntra,
    sai: reservaSai,
  };
  const ordem = ['cred', 'claude', 'entra', 'sai'];

  const lido = {};
  for (const k of ordem) lido[k] = fs.readFileSync(arqs[k], 'utf8');
  const obj = {};
  for (const k of ordem) obj[k] = JSON.parse(lido[k]);

  if (!obj.entra[CHAVE]) return { ok: false, motivo: 'sem_credencial' };
  if (obj.sai[CHAVE]) return { ok: false, motivo: 'saida_ocupada' };

  const novo = {
    cred: comChave(obj.cred, obj.entra[CHAVE]),
    sai: comChave(obj.sai, obj.cred[CHAVE]),
    entra: comChave(obj.entra, undefined),
    claude: { ...obj.claude, oauthAccount: dono },
  };

  // Recusa antes de qualquer gravação: o estado planejado não pode repetir login.
  try {
    conferirUnica([novo.cred, novo.sai, novo.entra]);
  } catch (e) {
    if (e.message !== 'credencial em dois lugares') throw e;
    return { ok: false, motivo: 'duplicada' };
  }

  // Relê tudo imediatamente antes de gravar: se algum byte mudou, não grava nada.
  for (const k of ordem) {
    if (fs.readFileSync(arqs[k], 'utf8') !== lido[k]) return { ok: false, motivo: 'mudou' };
  }

  // Ordem: a reserva de saída recebe o login antigo primeiro, a pasta depois, a
  // reserva de entrada perde o login por último. Duplicata transitória fica em
  // arquivo inerte, nunca em duas pastas vivas.
  const textos = {
    sai: JSON.stringify(novo.sai, null, 2) + fimDeLinha(lido.sai),
    cred: JSON.stringify(novo.cred, null, 2) + fimDeLinha(lido.cred),
    entra: JSON.stringify(novo.entra, null, 2) + fimDeLinha(lido.entra),
    claude: JSON.stringify(novo.claude, null, 2) + fimDeLinha(lido.claude),
  };
  const escritas = [];
  // Tenta restaurar TODAS as gravações; uma que falha não impede as outras. Devolve os arquivos
  // que não voltaram (vazio = tudo desfeito).
  const desfazer = () => {
    const pendentes = [];
    for (const e of escritas.slice().reverse()) {
      try {
        gravarAtomico(e.arq, e.original);
      } catch {
        pendentes.push(e.arq);
      }
    }
    return pendentes;
  };
  // Depois da primeira gravação o mover nunca lança: desfaz e devolve o motivo, ou
  // desfazer_falhou com os arquivos que ficaram pela metade.
  const encerrar = (motivo) => {
    const pendentes = desfazer();
    const desfeito = pendentes.length === 0;
    if (!desfeito) return { ok: false, motivo: 'desfazer_falhou', pendentes };
    return { ok: false, motivo };
  };

  // Erro de gravação (ex.: EPERM no Windows) no meio do laço: as anteriores voltam.
  let gravou = true;
  for (const k of ['sai', 'cred', 'entra', 'claude']) {
    try {
      gravarAtomico(arqs[k], textos[k]);
      escritas.push({ arq: arqs[k], original: lido[k] });
      gravou = fs.readFileSync(arqs[k], 'utf8') === textos[k];
    } catch {
      gravou = false;
    }
    if (!gravou) return encerrar('gravacao');
  }

  // Conferência final sobre o que ficou em disco.
  try {
    conferirUnica([
      JSON.parse(fs.readFileSync(arqs.cred, 'utf8')),
      JSON.parse(fs.readFileSync(arqs.sai, 'utf8')),
      JSON.parse(fs.readFileSync(arqs.entra, 'utf8')),
    ]);
  } catch (e) {
    return encerrar(e.message === 'credencial em dois lugares' ? 'duplicada' : 'gravacao');
  }

  return { ok: true, entrou: prefixo(obj.entra), saiu: prefixo(obj.cred) };
}

module.exports = { mover, gravarAtomico, prefixo };
