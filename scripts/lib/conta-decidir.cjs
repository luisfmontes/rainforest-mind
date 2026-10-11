// Decisão pura da troca automática de conta Claude (plano 2026-10-10-troca-de-conta, tarefa 1).
// Sem I/O: quem lê o uso, as reservas e o relógio é o chamador (T4, scripts/conta.cjs).
//
// decidir({ pastas, usos, reservas, config, agora }) -> [{ tipo, pasta, conta, motivo }]
//
//   pastas:   { trabalho: P, pessoal: P }
//             P = {
//               casa:      'team' | 'pessoal'   conta cujo login é o próprio desta pasta,
//               conta:     'team' | 'pessoal'   conta em uso agora (igual a casa = não trocada),
//               manual:    boolean              troca manual (D8): nunca recebe ação automática,
//               travouPor: { limite: 'five_hour' | 'seven_day', resetsAt: ISO } | null,
//               expiresAt: ISO | ms             validade do access token em uso
//               estacionado: { expiresAt } | undefined  login da pasta guardado enquanto ela
//                                               está fora de casa (estacionado-<pasta>.json)
//             }
//   usos:     { team: U, pessoal: U }
//             U = resposta de /api/oauth/usage: { five_hour: { utilization, resets_at, ... },
//                                                 seven_day: { utilization, resets_at, ... } }
//             utilization é percentual (0 a 100). Conta sem dado = esperar, nunca chute.
//   reservas: { team: R | undefined, pessoal: R | undefined }
//             R = { expiresAt: ISO | ms }. Ausente = conta sem reserva pronta (D9).
//             Reserva só entra na TROCA (a conta de destino). A VOLTA não usa reserva: usa o
//             estacionado da própria pasta.
//   config:   { trocarEm: 97, destinoMax5h: 60, destinoMaxSemana: 85 }   (D4)
//   agora:    ms ou ISO
//
// Regras (D1, D3, D4, D8, D11):
//   - pasta manual nunca recebe ação automática;
//   - pasta em casa: troca para a outra conta quando a em uso chega a trocarEm (>=) na
//     five_hour OU na seven_day, SÓ se a outra está abaixo de destinoMax5h (<) na 5 h E
//     abaixo de destinoMaxSemana (<) na semana, E tem reserva;
//   - pasta em casa não troca enquanto outra pasta está fora de casa: evita as duas presas
//     (cada volta pede a reserva que está na outra, e nenhuma das duas volta);
//   - pasta trocada: volta à conta de casa quando agora passou do resetsAt do limite que
//     travou (estritamente depois) E a pasta tem login estacionado; sem estacionado, esperar.
//     Pasta trocada não recebe nova troca nesta função: a troca seguinte fica para quando a
//     volta acontecer;
//   - ação que move credencial (da pasta ou da reserva de entrada) com menos de 30 min de
//     vida até expiresAt sai como 'esperar' (D11).

const MIN_VIDA_MS = 30 * 60 * 1000;
const LIMITES = ['five_hour', 'seven_day'];

const ms = (x) => (typeof x === 'number' ? x : Date.parse(x));
const outraConta = (conta) => (conta === 'team' ? 'pessoal' : 'team');
const dadosCompletos = (uso) => Boolean(uso && uso.five_hour && uso.seven_day);
const esperar = (nome, conta, motivo) => ({ tipo: 'esperar', pasta: nome, conta, motivo });

function decidir({ pastas, usos, reservas, config, agora }) {
  const agoraMs = ms(agora);
  const acoes = [];
  for (const nome of Object.keys(pastas)) {
    const pasta = pastas[nome];
    if (pasta.manual) continue;
    const acao = pasta.conta === pasta.casa
      ? decidirEmCasa(nome, pasta, pastas, usos, reservas, config, agoraMs)
      : decidirVolta(nome, pasta, agoraMs);
    if (acao) acoes.push(acao);
  }
  return acoes;
}

function decidirVolta(nome, pasta, agoraMs) {
  const t = pasta.travouPor;
  // !(agora > resetsAt) também cobre resetsAt inválido: sem data confiável, não volta.
  if (!t || !(agoraMs > ms(t.resetsAt))) return null;
  const destino = pasta.casa;
  if (!pasta.estacionado) return esperar(nome, destino, 'volta sem login estacionado');
  return checarVida(nome, destino, pasta, pasta.estacionado.expiresAt, agoraMs, 'voltar',
    `${t.limite} zerou em ${t.resetsAt}`);
}

function decidirEmCasa(nome, pasta, pastas, usos, reservas, config, agoraMs) {
  const uso = usos[pasta.conta];
  if (!dadosCompletos(uso)) return esperar(nome, pasta.conta, `sem dado de uso de ${pasta.conta}`);
  const limite = LIMITES.find((l) => uso[l].utilization >= config.trocarEm);
  if (!limite) return null;
  const outraFora = Object.keys(pastas).some((k) => k !== nome && pastas[k].conta !== pastas[k].casa);
  if (outraFora) return null;
  const destino = outraConta(pasta.conta);
  if (!dadosCompletos(usos[destino])) return esperar(nome, destino, `sem dado de uso de ${destino}`);
  const d = usos[destino];
  const folga = d.five_hour.utilization < config.destinoMax5h
    && d.seven_day.utilization < config.destinoMaxSemana;
  if (!folga || !reservas[destino]) return null;
  const motivo = `${limite} de ${pasta.conta} em ${uso[limite].utilization}% (>= ${config.trocarEm})`;
  return checarVida(nome, destino, pasta, reservas[destino].expiresAt, agoraMs, 'trocar', motivo);
}

// expiraEntra: validade do login que entra na pasta (reserva na troca, estacionado na volta).
function checarVida(nome, destino, pasta, expiraEntra, agoraMs, tipo, motivo) {
  const vidas = [pasta.expiresAt, expiraEntra];
  if (vidas.some((v) => !(ms(v) - agoraMs >= MIN_VIDA_MS))) {
    return esperar(nome, destino, `${tipo} adiada: access token com menos de 30 min de vida`);
  }
  return { tipo, pasta: nome, conta: destino, motivo };
}

module.exports = { decidir, MIN_VIDA_MS };
