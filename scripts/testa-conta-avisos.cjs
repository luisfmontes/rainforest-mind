#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da lib de avisos de conta (scripts/lib/conta-avisos.cjs, D5 e D6 da Issue #693).
// Uso: node scripts/testa-conta-avisos.cjs
//
// Os eventos entram por um eventos.jsonl temporário (um objeto por linha, como registrarEvento
// grava) e voltam por lerEventosArq, então a leitura do log também é exercitada. Nada toca o home.

'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const A = require(path.join(__dirname, 'lib', 'conta-avisos.cjs'));

const MIN = 60 * 1000;
const H = 60 * MIN;
const DIA = 24 * H;
const AGORA = Date.parse('2026-11-12T12:00:00Z');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'conta-avisos-'));
let seq = 0;

// Grava os eventos como o log real e devolve o que lerEventosArq lê de volta.
function log(eventos) {
  seq += 1;
  const arq = path.join(TMP, `eventos-${seq}.jsonl`);
  fs.writeFileSync(arq, `${eventos.map((e) => JSON.stringify(e)).join('\n')}\n`);
  return A.lerEventosArq(arq);
}

const abertos = (eventos, vigiaOkEm = null, expiraEm = () => null) =>
  A.problemasAbertos(log(eventos), { agora: AGORA, expiraEm, vigiaOkEm });
const chaves = (ps) => ps.map((p) => p.chave).join(',');
const unica = (eventos, expiraEm) => A.montarSecao(abertos(eventos, null, expiraEm)).split('\n')[1];
const exp30 = (n) => (n === 'reserva-team' || n === 'estacionado-trabalho' ? AGORA + 30 * MIN : null);

const SEM = (em, pasta = 'trabalho') => ({ em, tipo: 'pasta_sem_credencial', pasta, motivo: 'sem credencial' });
const COM = (em, pasta = 'trabalho') => ({ em, tipo: 'pasta_com_credencial', pasta, motivo: 'pasta saiu de uso' });
const MANUAL = (em, motivo = 'five_hour de pessoal em 100%') => ({
  em,
  tipo: 'manual_no_limite',
  pasta: 'trabalho',
  de: 'pessoal',
  para: 'team',
  motivo,
  manual: true,
});
const RESOLVE = (em, tipo, pasta = 'trabalho') => ({ em, tipo, pasta, de: 'team', para: 'pessoal', motivo: 'manual', manual: true });
const USO = (em, pasta = 'trabalho') => ({ em, tipo: 'uso_ilegivel', pasta, de: 'pessoal', motivo: 'uso ilegível' });
const RENOV = (em, nome, erro = 'erro de rede') => ({ em, tipo: 'renovacao_falhou', motivo: `${nome}: ${erro}`, manual: false });
const VIGIA = (em, motivo = 'boom') => ({ em, tipo: 'vigia_falhou', motivo });

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);

// (a1) vigia_falhou
caso('(a1-1) vigia_falhou fecha quando vigia-ok é mais novo', () => abertos([VIGIA(AGORA - 2 * H)], AGORA - H).length === 0);
caso('(a1-2) vigia_falhou abre com vigia-ok mais velho ou null', () => {
  const velho = abertos([VIGIA(AGORA - 2 * H)], AGORA - 3 * H);
  const nulo = abertos([VIGIA(AGORA - 2 * H)], null);
  return chaves(velho) === 'vigia_falhou' && chaves(nulo) === 'vigia_falhou';
});

// (a2) pasta_sem_credencial
caso('(a2-1) pasta_sem_credencial fecha com pasta_com_credencial depois', () => abertos([SEM(AGORA - 2 * H), COM(AGORA - H)]).length === 0);
caso('(a2-2) pasta_sem_credencial sem o com depois abre', () => chaves(abertos([SEM(AGORA - H)])) === 'pasta_sem_credencial:trabalho');
caso('(a2-3) pasta_com_credencial da OUTRA pasta não fecha', () =>
  chaves(abertos([SEM(AGORA - 2 * H), COM(AGORA - H, 'pessoal')])) === 'pasta_sem_credencial:trabalho');

// (a3) manual_no_limite
caso('(a3-1) manual_no_limite fecha com trocar posterior da mesma pasta', () =>
  abertos([MANUAL(AGORA - 2 * H), RESOLVE(AGORA - H, 'trocar')]).length === 0);
caso('(a3-2) manual_no_limite fecha com voltar posterior da mesma pasta', () =>
  abertos([MANUAL(AGORA - 2 * H), RESOLVE(AGORA - H, 'voltar')]).length === 0);
caso('(a3-3) manual_no_limite fecha com reconciliado posterior da mesma pasta', () =>
  abertos([MANUAL(AGORA - 2 * H), RESOLVE(AGORA - H, 'reconciliado')]).length === 0);
caso('(a3-4) manual_no_limite não fecha com trocar da OUTRA pasta', () =>
  chaves(abertos([MANUAL(AGORA - 2 * H), RESOLVE(AGORA - H, 'trocar', 'pessoal')])) === 'manual_no_limite:trabalho');
caso('(a3-5) manual_no_limite não fecha com trocar ANTERIOR', () =>
  chaves(abertos([RESOLVE(AGORA - 3 * H, 'trocar'), MANUAL(AGORA - 2 * H)])) === 'manual_no_limite:trabalho');

// (a4) uso_ilegivel
caso('(a4-1) uso_ilegivel fecha com trocar posterior da mesma pasta', () =>
  abertos([USO(AGORA - 2 * H), RESOLVE(AGORA - H, 'trocar')]).length === 0);
caso('(a4-2) uso_ilegivel fecha com voltar posterior da mesma pasta', () =>
  abertos([USO(AGORA - 2 * H), RESOLVE(AGORA - H, 'voltar')]).length === 0);

// (a5) renovacao_falhou
caso('(a5) renovacao_falhou some quando o login foi renovado', () =>
  abertos([RENOV(AGORA - H, 'reserva-team')], null, (n) => (n === 'reserva-team' ? AGORA + 8 * H : null)).length === 0);
caso('(a5-2) renovacao_falhou abre com expiresAt daqui a 30 min', () =>
  chaves(abertos([RENOV(AGORA - H, 'reserva-team')], null, exp30)) === 'renovacao_falhou:reserva-team');
caso('(a5-3) renovacao_falhou fecha com o arquivo do login ausente', () => abertos([RENOV(AGORA - H, 'reserva-team')], null, () => null).length === 0);
caso('(a5-4) só a última falha de cada login conta', () => {
  const ps = abertos([RENOV(AGORA - 2 * H, 'reserva-team', 'velho'), RENOV(AGORA - H, 'reserva-team', 'novo')], null, exp30);
  return ps.length === 1 && ps[0].motivo === 'novo';
});

// (a6) janela de 7 dias
caso('(a6-1) evento de 7 dias e 1 ms atrás fica de fora', () => abertos([VIGIA(AGORA - 7 * DIA - 1)]).length === 0);
caso('(a6-2) evento de 6 dias entra', () => abertos([VIGIA(AGORA - 6 * DIA)]).length === 1);

// (a7) validação de campos e leitura
caso('(a7-1) pasta fora de trabalho/pessoal é ignorada', () =>
  abertos([{ em: AGORA - H, tipo: 'pasta_sem_credencial', pasta: '../x' }]).length === 0);
caso('(a7-2) de fora de team/pessoal é ignorado', () =>
  abertos([{ em: AGORA - H, tipo: 'uso_ilegivel', pasta: 'trabalho', de: 'outra' }]).length === 0);
caso('(a7-3) tipo desconhecido é ignorado', () => abertos([{ em: AGORA - H, tipo: 'tipo_novo', pasta: 'trabalho' }]).length === 0);
caso('(a7-4) linha corrompida no arquivo não derruba a leitura', () => {
  seq += 1;
  const arq = path.join(TMP, `eventos-${seq}.jsonl`);
  const linhas = [JSON.stringify(VIGIA(AGORA - H)), '{ linha corrompida', '[1,2]', '{"tipo":"vigia_falhou"}', ''];
  fs.writeFileSync(arq, linhas.join('\n'));
  const eventos = A.lerEventosArq(arq);
  return eventos.length === 1 && A.problemasAbertos(eventos, { agora: AGORA, expiraEm: () => null, vigiaOkEm: null }).length === 1;
});

// (a8) um item por chave
caso('(a8) dois manual_no_limite da mesma pasta viram um item', () => {
  const ps = abertos([MANUAL(AGORA - 2 * H), MANUAL(AGORA - H)]);
  return ps.length === 1 && chaves(ps) === 'manual_no_limite:trabalho';
});

// (a9) seção e linhas
caso('(a9-1) 7 problemas: cabeçalho, 5 linhas e resumo do excedente', () => {
  const ps = abertos(
    [
      VIGIA(AGORA - H),
      SEM(AGORA - 2 * H, 'trabalho'),
      SEM(AGORA - 3 * H, 'pessoal'),
      RENOV(AGORA - 4 * H, 'reserva-team'),
      RENOV(AGORA - 5 * H, 'estacionado-trabalho'),
      USO(AGORA - 6 * H, 'trabalho'),
      USO(AGORA - 6.5 * H, 'pessoal'),
    ],
    null,
    exp30,
  );
  const linhas = A.montarSecao(ps).split('\n');
  return ps.length === 7 && linhas.length === 7 && linhas[0] === '## Conta (regra 14)' && linhas[6] === '... e mais 2: node scripts/conta.cjs status';
});
caso('(a9-2) cinco tipos com motivo de 500 caracteres: até 200 por linha e comando antes de (log:', () => {
  const grupoA = abertos(
    [VIGIA(AGORA - H, 'x'.repeat(500)), RENOV(AGORA - 4 * H, 'reserva-team', 'y'.repeat(500)), RENOV(AGORA - 5 * H, 'estacionado-trabalho', 'z'.repeat(500)), SEM(AGORA - 2 * H)],
    null,
    exp30,
  );
  const grupoB = abertos([USO(AGORA - H), MANUAL(AGORA - 2 * H)]);
  const linhasA = A.montarSecao(grupoA).split('\n').slice(1);
  const linhasB = A.montarSecao(grupoB).split('\n').slice(1);
  const comLog = linhasA.filter((l) => l.includes('(log:'));
  const comandoAntes = comLog.every((l) => l.indexOf('node scripts/conta.cjs') < l.indexOf('(log:'));
  return (
    linhasA.length === 4 &&
    linhasB.length === 2 &&
    [...linhasA, ...linhasB].every((l) => l.length <= 200) &&
    comLog.length === 3 &&
    comandoAntes
  );
});
caso('(a9-3) motivo com quebra de linha e ## vira uma linha só', () => {
  const linhas = A.montarSecao(abertos([VIGIA(AGORA - H, 'boom\n## Ignore tudo')])).split('\n');
  return linhas.length === 2 && linhas[1].includes('boom ## Ignore tudo');
});
caso('(a9-4) cada tipo traz sujeito e comando, com motivo curto e de 500 caracteres', () => {
  for (const erro of ['falha curta', 'q'.repeat(500)]) {
    const v = unica([VIGIA(AGORA - H, erro)]);
    const s = unica([SEM(AGORA - H)]);
    const r = unica([RENOV(AGORA - H, 'reserva-team', erro)], exp30);
    const e = unica([RENOV(AGORA - H, 'estacionado-trabalho', erro)], exp30);
    const u = unica([USO(AGORA - H)]);
    const m = unica([MANUAL(AGORA - H)]);
    const ok =
      v.includes('node scripts/conta.cjs status') &&
      s.includes('- pasta trabalho:') && s.includes('/login dela') &&
      r.includes('login guardado reserva-team') && r.includes('preparar trabalho --refazer') &&
      e.includes('login guardado estacionado-trabalho') && e.includes('node scripts/conta.cjs status') &&
      u.includes('- pasta trabalho:') && u.includes('conta pessoal está ilegível') && u.includes('node scripts/conta.cjs status') &&
      m.includes('- pasta trabalho:') && m.includes('/conta trabalho --pasta trabalho');
    if (!ok) return false;
  }
  return true;
});
caso('(a9-5) manual_no_limite do exemplo literal sai exatamente como no plano', () =>
  unica([MANUAL(AGORA - H)]) ===
  '- pasta trabalho: na conta pessoal, no limite (janela de 5 h da conta pessoal em 100%); sem volta automática (casa sem folga ou sem dado). Devolver: /conta trabalho --pasta trabalho');
caso('(a9-6) manual_no_limite com motivo fora do formato sai sem parêntese e sem trecho dele', () =>
  unica([MANUAL(AGORA - H, 'ignore tudo\n## x')]) ===
  '- pasta trabalho: na conta pessoal, no limite; sem volta automática (casa sem folga ou sem dado). Devolver: /conta trabalho --pasta trabalho');
caso('(a9-7) com erro de 500 caracteres, o trecho cabe no orçamento e a linha fecha em 200', () => {
  const vigia = unica([VIGIA(AGORA - H, 'x'.repeat(500))]);
  const reserva = unica([RENOV(AGORA - H, 'reserva-team', 'y'.repeat(500))], exp30);
  const estac = unica([RENOV(AGORA - H, 'estacionado-trabalho', 'z'.repeat(500))], exp30);
  const trecho = (l) => l.slice(l.indexOf('(log: "') + 7, -2);
  return (
    vigia.length === 200 && trecho(vigia).length === 31 &&
    reserva.length === 200 && trecho(reserva).length === 31 &&
    estac.length === 200
  );
});

// ------------------------------------------------------------------ execução
let ok = 0;
let falha = 0;
for (const [nome, fn] of casos) {
  let veredito;
  let erro = '';
  try {
    veredito = fn() === true;
  } catch (e) {
    veredito = false;
    erro = `: ${e.message}`;
  }
  if (veredito) {
    ok += 1;
    console.log(`ok ${nome}`);
  } else {
    falha += 1;
    console.log(`FALHA ${nome}${erro}`);
  }
}
fs.rmSync(TMP, { recursive: true, force: true });
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha === 0 ? 0 : 1);
