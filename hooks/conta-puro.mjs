// Aviso da troca de conta Claude (plano 2026-10-10-troca-de-conta, tarefa 8; design D6).
// Logica pura: so valores, sem `$`. O modulo que liga os eventos e ./conta.ts.
// Os eventos chegam de `scripts/conta.cjs eventos --desde <ms>`, com `de`/`para` nos nomes
// internos (team/pessoal); aqui viram os nomes que o Luis usa (trabalho/pessoal).

import { escolherExecutavel, localizadores } from './pr-puro.mjs';

const NOME = { team: 'trabalho', pessoal: 'pessoal' };
// Casa fixa de cada pasta, nos nomes internos: trocar uma pasta para a casa dela e uma volta.
const CASA = { trabalho: 'team', pessoal: 'pessoal' };
const nomeConta = (c) => NOME[c] ?? c;
// Mesmo texto que scripts/conta.cjs grava quando a pasta não tem login guardado da casa (#585).
const SEM_LOGIN_GUARDADO = 'sem_login_guardado';

// HH:MM na hora local. Aceita o ISO do limite (voltaEm vem como texto) ou ms; vazio se nao der.
const hhmm = (valor) => {
  if (valor === null || valor === undefined || valor === '') return '';
  const d = new Date(valor);
  if (Number.isNaN(d.getTime())) return '';
  const dois = (n) => String(n).padStart(2, '0');
  return `${dois(d.getHours())}:${dois(d.getMinutes())}`;
};

const JANELA = { seven_day: 'semana', five_hour: 'janela de 5 h' };

// Motivo do conta-decidir ("seven_day de team em 97% (>= 97)") em portugues: a janela, a conta
// pelo nome que o Luis usa e a porcentagem, sem o limiar. Motivo que nao casa passa como veio,
// so com os nomes internos trocados.
export function motivoLegivel(motivo) {
  const texto = String(motivo ?? '');
  const m = /^(seven_day|five_hour) de (\w+) em ([\d.,]+%)(?: \(>= [\d.,]+\))?$/.exec(texto.trim());
  if (m) return JANELA[m[1]] + ' da conta ' + nomeConta(m[2]) + ' em ' + m[3];
  return texto.replace(/\b(team|pessoal)\b/g, (c) => NOME[c]);
}

export function frase(ev) {
  const tipo = ev.tipo === 'trocar' && ev.para === CASA[ev.pasta] ? 'voltar' : ev.tipo;
  const manual = !!ev.manual || ev.motivo === 'manual';
  const e = { ...ev, tipo, manual, para: nomeConta(ev.para), de: nomeConta(ev.de), motivo: motivoLegivel(ev.motivo) };
  if (e.tipo === 'trocar' && e.manual) {
    return 'Conta: a pasta ' + e.pasta + ' passou da conta ' + e.de + ' para a conta ' + e.para + ' (troca manual; não volta sozinha).';
  }
  if (e.tipo === 'trocar') {
    const volta = hhmm(e.voltaEm);
    const base = 'Conta: a pasta ' + e.pasta + ' passou da conta ' + e.de + ' para a conta ' + e.para + ' (' + e.motivo + ').';
    return volta === '' ? base : base + ' Volta às ' + volta + '.';
  }
  if (e.tipo === 'voltar' && e.manual) return 'Conta: a pasta ' + e.pasta + ' voltou para a conta ' + e.para + ' (troca manual).';
  if (e.tipo === 'voltar') return 'Conta: a pasta ' + e.pasta + ' voltou para a conta ' + e.para + '.';
  if (e.tipo === 'falhou') {
    // Motivo cru do mover (e.motivo já passou por motivoLegivel).
    const r = { motivo: ev.motivo };
    if (r.motivo === 'desfazer_falhou') return fraseMetade(ev);
    if (/desfeito=false/.test(String(ev.motivo || ''))) return fraseNaoDesfeita(e);
    return 'Conta: a troca da pasta ' + e.pasta + ' foi desfeita (' + e.motivo + ').';
  }
  if (e.tipo === 'renovacao_falhou') {
    return 'Conta: não consegui renovar um login guardado (' + e.motivo + '). Se o servidor recusar de novo, a reserva morreu: refaça com "preparar <conta> --refazer".';
  }
  if (e.tipo === 'credencial_duplicada') {
    return 'Conta: o mesmo login está em dois arquivos (' + e.motivo + '); a troca automática não move nem renova nada até você separar.';
  }
  // #584: a pasta trocada na mão não volta sozinha (D8); o aviso diz onde ela está e como devolver.
  // O comando leva --pasta: o aviso aparece em toda sessão aberta, e /conta sem --pasta troca a pasta
  // da sessão que o roda, não a do aviso.
  if (e.tipo === 'manual_no_limite') {
    const base = 'Conta: a pasta ' + e.pasta + ' está na conta ' + e.de + ', que chegou ao limite (' + e.motivo + '). A troca foi manual e não volta sozinha: ';
    if (ev.causa === SEM_LOGIN_GUARDADO) {
      return base + 'não há login guardado da conta ' + e.para + ' para devolver, então faça /login da conta ' + e.para + ' na pasta ' + e.pasta + '.';
    }
    return base + '/conta ' + e.para + ' --pasta ' + e.pasta + ' devolve a pasta à conta dela.';
  }
  // #585: o estado foi alinhado ao login real da pasta (um /login por fora, ou um desfazer que falhou).
  if (e.tipo === 'reconciliado') {
    const cru = String(ev.motivo || '');
    const arquivado = /arquivado em (\S+)$/.exec(cru);
    // Nova tentativa de arquivar o órfão de uma reconciliação anterior: o estado já estava certo.
    if (e.de === e.para) {
      return arquivado
        ? 'Conta: o login guardado antigo da pasta ' + e.pasta + ' foi arquivado em ' + arquivado[1] + '; a troca dela volta a funcionar.'
        : 'Conta: ainda não consegui arquivar o login guardado antigo da pasta ' + e.pasta + ' (' + cru.replace(/^.*\(|\)$/g, '') + '): até ele sair, a próxima troca dela falha.';
    }
    let frase = 'Conta: o estado dizia que a pasta ' + e.pasta + ' estava na conta ' + e.de + ', mas o login dela é da conta ' + e.para + '; o estado foi alinhado ao login e nenhum login foi movido.';
    if (arquivado) frase += ' O login guardado antigo da pasta foi arquivado em ' + arquivado[1] + '.';
    if (/não consegui arquivar/.test(cru)) frase += ' Não consegui arquivar o login guardado antigo da pasta (' + cru.replace(/^.*\(|\)$/g, '') + '): até ele sair, a próxima troca dela falha.';
    if (e.manual) {
      const casa = nomeConta(CASA[ev.pasta]);
      frase += cru.includes(SEM_LOGIN_GUARDADO)
        ? ' A pasta fica fora de casa e não há login guardado da conta ' + casa + ': para voltar, faça /login da conta ' + casa + ' nela.'
        : ' A pasta fica fora de casa (troca manual): /conta ' + casa + ' --pasta ' + e.pasta + ' a devolve.';
    }
    return frase;
  }
  if (e.tipo === 'identidade_divergente') {
    return 'Conta: ' + e.motivo + '; nada foi gravado.';
  }
  return '';
}

// Troca que parou no meio e não conseguiu se desfazer: arquivos de credencial ficaram divergentes.
// Só nomes de arquivo (o evento já os traz sem caminho; o que sobrar de caminho é cortado aqui).
function fraseMetade(ev) {
  const nomes = Array.isArray(ev.pendentes)
    ? ev.pendentes.map((p) => String(p).split(/[\\/]/).pop()).filter((n) => n !== '')
    : [];
  const quais = nomes.length ? ' Arquivos não restaurados: ' + nomes.join(', ') + '.' : '';
  return 'Conta: a troca da pasta ' + ev.pasta + ' ficou pela metade (o desfazer também falhou).' + quais
    + ' Confira esses arquivos antes de trocar de novo.';
}

// A conferência no servidor não bateu e o desfazer não restaurou (desfeito=false no motivo): a pasta
// pode ter ficado com o login de outra conta. Nunca "foi desfeita": o aviso manda conferir no /conta.
function fraseNaoDesfeita(e) {
  const motivo = String(e.motivo).replace(/;?\s*desfeito=false/, '');
  return 'Conta: a troca da pasta ' + e.pasta + ' não pôde ser desfeita (' + motivo + '); a pasta pode ter ficado com o login de outra conta. Confira com /conta antes de trocar de novo.';
}

// Localizador do node, UM so para o relogio (mod.tsx) e o aviso de conta (conta.ts): os dois leem
// os mesmos atoms (nodeCaminho, nodeFalhouEm), entao o node achado vale para os dois e uma falha
// de um vale para o outro. Depois de uma falha, ninguem procura de novo antes de 5 min.
// Os valores de estado e os `$` ficam com quem chama: aqui entram so funcoes.
export const NODE_FALHA_TTL_MS = 300_000;

export async function acharNode({ guardado, falhouEm, agora, lerCwd, lerRaiz, rodar, gravarCaminho, gravarFalha }) {
  if (guardado !== '') return guardado;
  if (falhouEm > 0 && agora - falhouEm < NODE_FALHA_TTL_MS) return null;
  const cwd = await lerCwd();
  for (const argv of localizadores('node', await lerRaiz())) {
    try {
      const r = await rodar(argv);
      if (r.exitCode !== 0) continue;
      const achado = escolherExecutavel(r.stdout, cwd);
      if (achado !== null) {
        await gravarCaminho(achado);
        return achado;
      }
    } catch {
      // este localizador nao existe nesta maquina; o outro tenta
    }
  }
  await gravarFalha(agora);
  return null;
}

// Eventos (linhas JSON) com `em` depois de `desde`. Linha ilegivel e pulada, nao derruba as outras.
export function novos(linhas, desde) {
  const saida = [];
  for (const linha of linhas) {
    if (!linha || !linha.trim()) continue;
    let ev;
    try {
      ev = JSON.parse(linha);
    } catch {
      continue;
    }
    if (ev && ev.em > desde) saida.push(ev);
  }
  return saida;
}
