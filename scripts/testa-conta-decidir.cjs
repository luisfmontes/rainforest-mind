#!/usr/bin/env node
// @categoria: bateria
//
// Bateria da decisão pura da troca de conta (scripts/lib/conta-decidir.cjs).
// Uso: node scripts/testa-conta-decidir.cjs
//
// Fixture: formato da resposta de /api/oauth/usage (five_hour e seven_day com utilization,
// resets_at e os campos *_dollars/locked_reason nulos), valores medidos em 2026-10-10:
//   team:    five_hour 15, seven_day 53 (resets 2026-10-13T22:59:59.856373+00:00)
//   pessoal: five_hour 15 (resets 2026-10-11T00:20:00.194381+00:00),
//            seven_day 5 (resets 2026-10-17T11:00:00.194407+00:00)
// LACUNA declarada: o briefing não informou o resets_at da five_hour da team. O valor abaixo
// é um placeholder de fixture, NÃO medido; nenhum caso depende dele.
// Cada caso deriva da fixture trocando só utilization ou resets_at (e expiresAt quando o caso é de vida).

const path = require("node:path");
const { decidir } = require(path.join(__dirname, "lib", "conta-decidir.cjs"));

const AGORA = Date.parse("2026-10-10T12:00:00Z");
const MIN = 60 * 1000;
const VIDA_LONGA = new Date(AGORA + 8 * 60 * MIN).toISOString();
const CFG = { trocarEm: 97, destinoMax5h: 60, destinoMaxSemana: 85 };
const RESET_TEAM_7D = "2026-10-13T22:59:59.856373+00:00";

const janela = (utilization, resets_at) => ({
  utilization,
  resets_at,
  limit_dollars: null,
  used_dollars: null,
  remaining_dollars: null,
  locked_reason: null,
});

const USO_REAL = {
  team: {
    five_hour: janela(15, "2026-10-10T17:00:00.000000+00:00"), // placeholder, ver LACUNA
    seven_day: janela(53, RESET_TEAM_7D),
  },
  pessoal: {
    five_hour: janela(15, "2026-10-11T00:20:00.194381+00:00"),
    seven_day: janela(5, "2026-10-17T11:00:00.194407+00:00"),
  },
};

// Troca um único campo de um único limite de uma conta; o resto da fixture fica igual.
const deriva = (conta, limite, campo, valor, base = USO_REAL) => {
  const copia = JSON.parse(JSON.stringify(base));
  copia[conta][limite][campo] = valor;
  return copia;
};

const RESERVAS = { team: { expiresAt: VIDA_LONGA }, pessoal: { expiresAt: VIDA_LONGA } };
const pastasEmCasa = () => ({
  trabalho: { casa: "team", conta: "team", manual: false, travouPor: null, expiresAt: VIDA_LONGA },
  pessoal: { casa: "pessoal", conta: "pessoal", manual: false, travouPor: null, expiresAt: VIDA_LONGA },
});
const trocadaParaPessoal = (extra = {}) => ({
  trabalho: {
    casa: "team",
    conta: "pessoal",
    manual: false,
    travouPor: { limite: "seven_day", resetsAt: RESET_TEAM_7D },
    expiresAt: VIDA_LONGA,
    ...extra,
  },
  pessoal: { casa: "pessoal", conta: "pessoal", manual: false, travouPor: null, expiresAt: VIDA_LONGA },
});

// Validade de 8 h a partir do "agora" de cada caso: sem isso um caso em outro dia usa token já vencido.
const vidaLonga = (agora) => new Date(agora + 8 * 60 * MIN).toISOString();
const rodar = (pastas, usos, extra = {}) => {
  const agora = extra.agora || AGORA;
  const vida = vidaLonga(agora);
  const pastasComVida = JSON.parse(JSON.stringify(pastas));
  for (const p of Object.values(pastasComVida)) {
    if (p.expiresAt === VIDA_LONGA) p.expiresAt = vida;
  }
  const reservas = extra.reservas || { team: { expiresAt: vida }, pessoal: { expiresAt: vida } };
  return decidir({ pastas: pastasComVida, usos, reservas, config: extra.config || CFG, agora });
};

const casos = [];
const caso = (nome, fn) => casos.push([nome, fn]);

// (a) troca da pasta trabalho para a pessoal quando seven_day da team = 97
caso("troca a pasta trabalho para a conta pessoal quando seven_day da team = 97", () => {
  const usos = deriva("team", "seven_day", "utilization", 97);
  const r = rodar(pastasEmCasa(), usos);
  return r.length === 1 && r[0].tipo === "trocar" && r[0].pasta === "trabalho" && r[0].conta === "pessoal";
});

caso("troca a pasta trabalho quando five_hour da team = 97", () => {
  const usos = deriva("team", "five_hour", "utilization", 97);
  const r = rodar(pastasEmCasa(), usos);
  return r.length === 1 && r[0].tipo === "trocar" && r[0].conta === "pessoal";
});

caso("troca nos dois sentidos: pessoal para a conta team quando five_hour da pessoal = 97", () => {
  const usos = deriva("pessoal", "five_hour", "utilization", 97);
  const r = rodar(pastasEmCasa(), usos);
  return r.length === 1 && r[0].tipo === "trocar" && r[0].pasta === "pessoal" && r[0].conta === "team";
});

// (b) nada quando o destino (pessoal) está em 61% na 5 h; e o lado oposto (59%) troca
caso("nada quando o destino (pessoal) está em 61% na 5 h", () => {
  const usos = deriva("pessoal", "five_hour", "utilization", 61, deriva("team", "seven_day", "utilization", 97));
  const r = rodar(pastasEmCasa(), usos);
  return r.length === 0;
});

caso("troca quando o destino (pessoal) está em 59% na 5 h (lado oposto de 61%)", () => {
  const usos = deriva("pessoal", "five_hour", "utilization", 59, deriva("team", "seven_day", "utilization", 97));
  const r = rodar(pastasEmCasa(), usos);
  return r.length === 1 && r[0].tipo === "trocar" && r[0].conta === "pessoal";
});

caso("nada quando o destino (pessoal) está em 85% na semana", () => {
  const usos = deriva("pessoal", "seven_day", "utilization", 85, deriva("team", "seven_day", "utilization", 97));
  return rodar(pastasEmCasa(), usos).length === 0;
});

caso("troca quando o destino (pessoal) está em 84% na semana (lado oposto de 85%)", () => {
  const usos = deriva("pessoal", "seven_day", "utilization", 84, deriva("team", "seven_day", "utilization", 97));
  const r = rodar(pastasEmCasa(), usos);
  return r.length === 1 && r[0].tipo === "trocar";
});

caso("nada quando o destino não tem reserva pronta", () => {
  const usos = deriva("team", "seven_day", "utilization", 97);
  return rodar(pastasEmCasa(), usos, { reservas: { team: RESERVAS.team } }).length === 0;
});

caso("sem dado de uso do destino vira esperar, sem chutar", () => {
  const usos = deriva("team", "seven_day", "utilization", 97);
  delete usos.pessoal;
  const r = rodar(pastasEmCasa(), usos);
  // a pasta pessoal também fica sem dado da própria conta e recebe esperar; o caso é a trabalho
  return r.some((a) => a.tipo === "esperar" && a.pasta === "trabalho" && a.conta === "pessoal")
    && !r.some((a) => a.tipo === "trocar");
});

caso("limite de troca vem da config, não é fixo (trocarEm 50 troca a team em 53)", () => {
  const r = rodar(pastasEmCasa(), USO_REAL, { config: { ...CFG, trocarEm: 50 } });
  return r.length === 1 && r[0].tipo === "trocar" && r[0].pasta === "trabalho";
});

// (c) volta depois do resets_at do limite que travou; e antes, nada
caso("volta depois do resets_at do limite que travou", () => {
  const agora = Date.parse("2026-10-14T00:00:00Z");
  const r = rodar(trocadaParaPessoal(), USO_REAL, { agora });
  return r.length === 1 && r[0].tipo === "voltar" && r[0].pasta === "trabalho" && r[0].conta === "team";
});

caso("não volta antes do resets_at do limite que travou", () => {
  const agora = Date.parse("2026-10-13T12:00:00Z");
  const r = rodar(trocadaParaPessoal(), USO_REAL, { agora });
  return r.length === 0;
});

// (d) pasta manual: nunca recebe ação automática
caso("pasta trocada na mão não volta sozinha mesmo depois do reset", () => {
  const agora = Date.parse("2026-10-14T00:00:00Z");
  const pastas = trocadaParaPessoal({ manual: true });
  const r = rodar(pastas, USO_REAL, { agora });
  return r.length === 0;
});

caso("pasta manual em casa não troca mesmo com a conta em 97%", () => {
  const pastas = pastasEmCasa();
  pastas.trabalho.manual = true;
  const r = rodar(pastas, deriva("team", "seven_day", "utilization", 97));
  return r.length === 0;
});

// (e) esperar quando a credencial que se moveria tem menos de 30 min de vida
caso("esperar com expiresAt a 29 min", () => {
  const pastas = pastasEmCasa();
  pastas.trabalho.expiresAt = new Date(AGORA + 29 * MIN).toISOString();
  const r = rodar(pastas, deriva("team", "seven_day", "utilization", 97));
  return r.length === 1 && r[0].tipo === "esperar" && r[0].pasta === "trabalho";
});

caso("troca com expiresAt a 31 min (lado oposto de 29 min)", () => {
  const pastas = pastasEmCasa();
  pastas.trabalho.expiresAt = new Date(AGORA + 31 * MIN).toISOString();
  const r = rodar(pastas, deriva("team", "seven_day", "utilization", 97));
  return r.length === 1 && r[0].tipo === "trocar";
});

caso("esperar quando a reserva de entrada tem 29 min", () => {
  const reservas = { team: RESERVAS.team, pessoal: { expiresAt: new Date(AGORA + 29 * MIN).toISOString() } };
  const r = rodar(pastasEmCasa(), deriva("team", "seven_day", "utilization", 97), { reservas });
  return r.length === 1 && r[0].tipo === "esperar";
});

caso("esperar na volta com access token a 29 min", () => {
  const agora = Date.parse("2026-10-14T00:00:00Z");
  const pastas = trocadaParaPessoal();
  pastas.trabalho.expiresAt = new Date(agora + 29 * MIN).toISOString();
  const r = rodar(pastas, USO_REAL, { agora });
  return r.length === 1 && r[0].tipo === "esperar" && r[0].pasta === "trabalho";
});

// ------------------------------------------------------------------ execução
let ok = 0;
let falha = 0;
for (const [nome, fn] of casos) {
  let veredito;
  try {
    veredito = fn() === true;
  } catch (e) {
    veredito = false;
  }
  if (veredito) {
    ok += 1;
    console.log(`ok ${nome}`);
  } else {
    falha += 1;
    console.log(`FALHA ${nome}`);
  }
}
console.log(`${ok} ok, ${falha} falha(s)`);
process.exit(falha === 0 ? 0 : 1);
