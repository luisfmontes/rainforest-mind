// Aviso da troca de conta Claude (plano 2026-10-10-troca-de-conta, tarefa 8; design D6).
// Logica pura: so valores, sem `$`. O modulo que liga os eventos e ./conta.ts.
// Os eventos chegam de `scripts/conta.cjs eventos --desde <ms>`, com `de`/`para` nos nomes
// internos (team/pessoal); aqui viram os nomes que o Luis usa (trabalho/pessoal).

import { escolherExecutavel, localizadores } from './pr-puro.mjs';

const NOME = { team: 'trabalho', pessoal: 'pessoal' };
// Casa fixa de cada pasta, nos nomes internos: trocar uma pasta para a casa dela e uma volta.
const CASA = { trabalho: 'team', pessoal: 'pessoal' };
const nomeConta = (c) => NOME[c] ?? c;

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
  if (e.tipo === 'falhou') return 'Conta: a troca da pasta ' + e.pasta + ' foi desfeita (' + e.motivo + ').';
  return '';
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
