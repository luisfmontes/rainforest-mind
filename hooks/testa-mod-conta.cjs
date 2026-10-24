#!/usr/bin/env node
// @categoria: bateria
// rainforest-gate: dados-de-exemplo — credenciais FALSAS no formato do .credentials.json e timestamps de teste; nenhum valor real.
//
// Bateria do aviso da troca de conta (hooks/conta-puro.mjs; plano 2026-10-10-troca-de-conta, tarefa 8).
// Gera eventos REAIS rodando o scripts/conta.cjs desta árvore em pastas temporárias, com o servidor
// de fixture, e confere as frases que o aviso mostraria.
// Uso: node hooks/testa-mod-conta.cjs

'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

const SRC = path.resolve(__dirname, '..');
const CONTA = path.join(SRC, 'scripts', 'conta.cjs');
const SERVIDOR = path.join(SRC, 'scripts', 'fixtures', 'conta', 'servidor.cjs');
const PURO = pathToFileURL(path.join(SRC, 'hooks', 'conta-puro.mjs')).href;

const VIDA = 4102444800000;
const TOKENS = {
  'falso-team-pasta': { email: 'team@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000a', uso: 'team' },
  'falso-team-reserva': { email: 'team@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000a', uso: 'team' },
  'falso-pessoal-pasta': { email: 'pessoal@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000b', uso: 'pessoal' },
  'falso-pessoal-reserva': { email: 'pessoal@exemplo.invalid', uuid: '00000000-0000-0000-0000-00000000000b', uso: 'pessoal' },
};
const OAUTH = {
  team: { accountUuid: '00000000-0000-0000-0000-00000000000a', emailAddress: 'team@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa Team' },
  pessoal: { accountUuid: '00000000-0000-0000-0000-00000000000b', emailAddress: 'pessoal@exemplo.invalid', organizationUuid: '00000000-0000-0000-0000-000000000000', displayName: 'Conta Falsa Pessoal' },
};

function cred(tok, refresh) {
  return {
    mcpOAuth: { 'servidor-falso': { accessToken: 'falso-mcp-' + tok, refreshToken: 'falso-mcp-refresh-' + tok, expiresAt: 1, scope: 'a b' } },
    claudeAiOauth: { accessToken: tok, refreshToken: refresh, expiresAt: VIDA, refreshTokenExpiresAt: VIDA, scopes: ['user:inference', 'user:profile'], subscriptionType: 'max', rateLimitTier: 'default_claude_max_20x' },
    trustedDeviceToken: 'falso-tdt-' + tok,
  };
}

const escrever = (arq, obj) => {
  fs.mkdirSync(path.dirname(arq), { recursive: true });
  fs.writeFileSync(arq, JSON.stringify(obj, null, 2) + '\n');
};

// .claude.json da pasta de trabalho: fica fora da pasta, como em ~/.claude.json. A bateria aponta para ele
// por RFM_CONTA_CLAUDE_JSON; sem a variável, o conta.cjs recusa (nunca cai no home de quem roda).
const claudeJsonDoCaso = (caso) => path.join(path.dirname(caso.trabalho), '.claude.json');

// Arranjo: duas pastas no formato real, duas reservas e o estado inicial (troca automática ligada).
function semear(raiz) {
  const caso = {
    trabalho: path.join(raiz, 'trabalho', '.claude'),
    pessoal: path.join(raiz, 'pessoal', '.claude-personal'),
    dados: path.join(raiz, 'dados'),
  };
  escrever(path.join(caso.trabalho, '.credentials.json'), cred('falso-team-pasta', 'falso-refresh-team-pasta'));
  // Formato real: o .claude.json da pasta padrão mora no home, fora da pasta (~/.claude.json).
  escrever(claudeJsonDoCaso(caso), { numStartups: 3, oauthAccount: OAUTH.team, projects: {} });
  escrever(path.join(caso.pessoal, '.credentials.json'), cred('falso-pessoal-pasta', 'falso-refresh-pessoal-pasta'));
  escrever(path.join(caso.pessoal, '.claude.json'), { numStartups: 3, oauthAccount: OAUTH.pessoal, projects: {} });
  escrever(path.join(caso.dados, 'contas', 'reserva-team.json'), { claudeAiOauth: cred('falso-team-reserva', 'falso-refresh-team-reserva').claudeAiOauth });
  escrever(path.join(caso.dados, 'contas', 'reserva-pessoal.json'), { claudeAiOauth: cred('falso-pessoal-reserva', 'falso-refresh-pessoal-reserva').claudeAiOauth });
  escrever(path.join(caso.dados, 'contas', 'estado.json'), { automatico: true });
  return caso;
}

function iniciarServidor(raiz) {
  const mapa = path.join(raiz, 'mapa.json');
  escrever(mapa, { tokens: TOKENS });
  return new Promise((resolve, reject) => {
    const filho = spawn(process.execPath, [SERVIDOR], {
      env: { ...process.env, RFM_CONTA_SERVIDOR_MAPA: mapa, RFM_CONTA_SERVIDOR_CONTROLE: path.join(raiz, 'segurar') },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let buf = '';
    filho.stdout.on('data', (d) => {
      buf += d;
      const n = buf.indexOf('\n');
      if (n >= 0) resolve({ filho, api: 'http://127.0.0.1:' + buf.slice(0, n).trim() });
    });
    filho.on('error', reject);
    filho.on('exit', (code) => reject(new Error('servidor de fixture saiu com código ' + code)));
  });
}

function conta(caso, api, args, extraEnv = {}) {
  const r = spawnSync(process.execPath, [CONTA, ...args], {
    cwd: SRC,
    encoding: 'utf8',
    timeout: 60000,
    env: {
      ...process.env,
      ...extraEnv,
      RFM_TEST: '1',
      RFM_CONTA_PASTA_TRABALHO: caso.trabalho,
      RFM_CONTA_PASTA_PESSOAL: caso.pessoal,
      RFM_CONTA_CLAUDE_JSON: claudeJsonDoCaso(caso),
      RFM_CONTA_DADOS: caso.dados,
      RFM_CONTA_API: api,
    },
  });
  return { rc: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

const linhasEventos = (caso) => {
  const arq = path.join(caso.dados, 'contas', 'eventos.jsonl');
  if (!fs.existsSync(arq)) return [];
  return fs.readFileSync(arq, 'utf8').split('\n').filter((l) => l.trim());
};

let ok = 0;
let falha = 0;
const afirma = (nome, cond, detalhe) => {
  if (cond) {
    ok++;
    console.log('ok    ' + nome);
  } else {
    falha++;
    console.log('FALHA ' + nome + (detalhe ? '\n      ' + detalhe : ''));
  }
};

async function main() {
  const { frase, novos, motivoLegivel } = await import(PURO);
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-conta-'));
  let servidor = null;
  try {
    servidor = await iniciarServidor(raiz);
    const caso = semear(raiz);
    const api = servidor.api;

    // 1. Troca automática: vigiar com a conta team em 97% na semana (fixture do servidor).
    const r1 = conta(caso, api, ['vigiar']);
    const ev1 = linhasEventos(caso);
    const e1 = ev1.map((l) => JSON.parse(l));
    const f1 = e1.length ? frase(e1[0]) : '';
    console.log('frase automatica: ' + f1);
    afirma('troca automática vigiar sai 0 e grava 1 evento', r1.rc === 0 && e1.length === 1, r1.out);
    afirma('troca automática: frase diz a pasta, a conta de origem e a de destino',
      /^Conta: a pasta trabalho passou da conta trabalho para a conta pessoal \(/.test(f1),
      'frase: ' + f1);
    afirma('troca automática: frase nunca usa nome interno (team) nem o texto cru do motivo (seven_day, >=)',
      !/\b(team|seven_day|five_hour)\b|>=/.test(f1), 'frase: ' + f1);
    afirma('troca automática: motivo em português e hora da volta',
      /\(semana da conta trabalho em \d+%\)\. Volta às \d\d:\d\d\.$/.test(f1), 'frase: ' + f1);

    // 2. Volta automática: o limite zerou (resetsAt vencido, arranjado no estado) e o vigiar devolve a pasta.
    const estadoArq = path.join(caso.dados, 'contas', 'estado.json');
    const estado = JSON.parse(fs.readFileSync(estadoArq, 'utf8'));
    estado.pastas.trabalho.travouPor.resetsAt = new Date(Date.now() - 3600 * 1000).toISOString();
    escrever(estadoArq, estado);
    const r2 = conta(caso, api, ['vigiar']);
    const e2 = linhasEventos(caso).map((l) => JSON.parse(l)).slice(1);
    const f2 = e2.length ? frase(e2[0]) : '';
    console.log('frase volta: ' + f2);
    afirma('volta automática vigiar sai 0 e grava o evento voltar', r2.rc === 0 && e2.length === 1 && e2[0].tipo === 'voltar', r2.out);
    afirma('evento de volta vira aviso com a pasta e a conta', f2 === 'Conta: a pasta trabalho voltou para a conta trabalho.', 'frase: ' + f2);

    // 3. Troca manual: trocar pessoal --pasta trabalho.
    const r3 = conta(caso, api, ['trocar', 'pessoal', '--pasta', 'trabalho']);
    const e3 = linhasEventos(caso).map((l) => JSON.parse(l)).slice(2);
    const f3 = e3.length ? frase(e3[0]) : '';
    console.log('frase manual: ' + f3);
    afirma('troca manual sai 0 e grava o evento', r3.rc === 0 && e3.length === 1, r3.out);
    afirma('troca manual vira aviso com a pasta, a conta e a marca de manual',
      f3 === 'Conta: a pasta trabalho passou da conta trabalho para a conta pessoal (troca manual; não volta sozinha).', 'frase: ' + f3);

    // 4. Volta manual: trocar trabalho --pasta trabalho (de volta para a casa).
    const r4 = conta(caso, api, ['trocar', 'trabalho', '--pasta', 'trabalho']);
    const e4 = linhasEventos(caso).map((l) => JSON.parse(l)).slice(3);
    const f4 = e4.length ? frase(e4[0]) : '';
    console.log('frase volta manual: ' + f4);
    afirma('volta manual sai 0 e grava o evento', r4.rc === 0 && e4.length === 1, r4.out);
    afirma('volta manual (trocar --pasta) vira aviso de volta com a pasta, a conta e a marca de troca manual',
      f4 === 'Conta: a pasta trabalho voltou para a conta trabalho (troca manual).', 'frase: ' + f4);
    afirma('motivo com porcentagem fracionada (utilization cru do conta-decidir) sai em português, sem o limiar',
      motivoLegivel('seven_day de team em 97.5% (>= 97)') === 'semana da conta trabalho em 97.5%', 'motivoLegivel: ' + motivoLegivel('seven_day de team em 97.5% (>= 97)'));
    afirma('motivo desconhecido passa como veio, só com os nomes internos trocados',
      motivoLegivel('algo de team') === 'algo de trabalho', 'motivoLegivel: ' + motivoLegivel('algo de team'));

    // 5. novos(): só o que é depois de `desde`.
    const todas = linhasEventos(caso);
    const maior = Math.max(...todas.map((l) => JSON.parse(l).em));
    afirma('eventos com em anterior ou igual a desde não geram aviso',
      novos(todas, maior).length === 0 && novos(todas, 0).length === todas.length,
      'novos(todas, maior)=' + novos(todas, maior).length + ' novos(todas, 0)=' + novos(todas, 0).length);

    // 6. Troca que falha e não consegue se desfazer. O evento é REAL: um preload faz o rename para
    // .claude.json falhar (a quarta gravação do mover) e o segundo rename para .credentials.json
    // também (o desfazer da segunda gravação). O aviso tem de dizer que a troca ficou pela metade
    // e nomear o arquivo que não voltou, sem caminho; não pode dizer que a troca foi desfeita.
    const raiz2 = path.join(raiz, 'metade');
    fs.mkdirSync(raiz2, { recursive: true });
    const caso2 = semear(raiz2);
    const preload = path.join(raiz2, 'falha-gravacao.cjs');
    fs.writeFileSync(preload, [
      "const fs = require('fs');",
      "const path = require('path');",
      'const original = fs.renameSync;',
      'let credenciais = 0;',
      'fs.renameSync = function renameSync(de, para) {',
      '  const alvo = path.basename(String(para));',
      "  const erro = () => Object.assign(new Error('EPERM simulado'), { code: 'EPERM' });",
      "  if (alvo === '.claude.json') throw erro();",
      "  if (alvo === '.credentials.json' && ++credenciais === 2) throw erro();",
      '  return original.apply(this, arguments);',
      '};',
      '',
    ].join('\n'));
    const rm = conta(caso2, api, ['vigiar'], { NODE_OPTIONS: '--require=' + preload.replace(/\\/g, '/') });
    const em = linhasEventos(caso2).map((l) => JSON.parse(l));
    const evM = em.find((x) => x.tipo === 'falhou');
    const fm = evM ? frase(evM) : '';
    console.log('frase metade: ' + fm);
    afirma('troca que falha e não se desfaz sai 1 e grava o evento falhou com desfazer_falhou e os pendentes',
      rm.rc === 1 && !!evM && evM.motivo === 'desfazer_falhou'
        && Array.isArray(evM.pendentes) && evM.pendentes.join(',') === '.credentials.json',
      'rc=' + rm.rc + ' evento=' + JSON.stringify(evM) + ' saida=' + rm.out);
    afirma('desfazer_falhou avisa troca pela metade com os arquivos',
      /ficou pela metade/.test(fm) && fm.includes('.credentials.json'), 'frase: ' + fm);
    afirma('desfazer_falhou: o aviso não diz que a troca foi desfeita, nem traz caminho de pasta',
      !/foi desfeita/.test(fm) && !/[\\/]/.test(fm), 'frase: ' + fm);
    afirma('desfazer_falhou: a saída do vigiar nomeia o arquivo pendente',
      rm.out.includes('arquivos pendentes: .credentials.json'), 'saida: ' + rm.out);

    // 7. Os eventos de diagnóstico do vigia viram aviso (antes a frase era vazia e a falha era invisível).
    const fr = frase({ em: 1, tipo: 'renovacao_falhou', motivo: 'reserva-team: token HTTP 400', manual: false });
    afirma('renovacao_falhou vira aviso com o login e o caminho para refazer',
      /^Conta: .*reserva-trabalho: token HTTP 400/.test(fr) && /--refazer/.test(fr), 'frase: ' + fr);
    const fd = frase({ em: 1, tipo: 'credencial_duplicada', motivo: 'login ab12cd34ef56 em pasta-trabalho e reserva-team', manual: false });
    afirma('credencial_duplicada vira aviso com os dois arquivos',
      /dois arquivos/.test(fd) && fd.includes('pasta-trabalho e reserva-trabalho'), 'frase: ' + fd);
    const fi = frase({ em: 1, tipo: 'identidade_divergente', pasta: 'trabalho', motivo: 'a pasta trabalho está em casa (conta trabalho) mas o login dela é de outra conta', manual: false });
    afirma('identidade_divergente vira aviso com o motivo',
      /^Conta: a pasta trabalho está em casa/.test(fi), 'frase: ' + fi);
    // #584: o aviso da pasta manual no limite diz a pasta, a conta em uso, o quanto e como devolver.
    const fml = frase({ em: 1, tipo: 'manual_no_limite', pasta: 'trabalho', de: 'pessoal', para: 'team', motivo: 'seven_day de pessoal em 100%', manual: true, voltaEm: '2026-10-25T11:00:00Z' });
    afirma('manual_no_limite diz a pasta, a conta, o percentual e o comando que devolve, com --pasta',
      fml.includes('pasta trabalho') && fml.includes('conta pessoal') && fml.includes('100%') && fml.includes('/conta trabalho --pasta trabalho'), 'frase: ' + fml);
    const fmls = frase({ em: 1, tipo: 'manual_no_limite', pasta: 'trabalho', de: 'pessoal', para: 'team', motivo: 'seven_day de pessoal em 100%', manual: true, voltaEm: '2026-10-25T11:00:00Z', causa: 'sem_login_guardado' });
    afirma('manual_no_limite sem login guardado manda refazer o /login, não o /conta',
      fmls.includes('/login da conta trabalho') && !fmls.includes('/conta trabalho --pasta'), 'frase: ' + fmls);
    const frm = frase({ em: 1, tipo: 'reconciliado', pasta: 'trabalho', de: 'team', para: 'pessoal', motivo: 'estado alinhado ao login da pasta; sem_login_guardado', manual: true });
    afirma('reconciliado para fora de casa sem login guardado diz para refazer o /login da casa',
      frm.includes('fora de casa') && frm.includes('/login da conta trabalho') && !frm.includes('sem_login_guardado'), 'frase: ' + frm);
    const frna = frase({ em: 1, tipo: 'reconciliado', pasta: 'trabalho', de: 'pessoal', para: 'team', motivo: 'não consegui arquivar o login guardado antigo (EPERM)', manual: false });
    afirma('reconciliado que não arquivou o órfão avisa que a próxima troca falha',
      frna.includes('Não consegui arquivar') && frna.includes('EPERM') && frna.includes('próxima troca'), 'frase: ' + frna);
    // #585: o reconciliado diz a pasta, a conta de antes e a de agora, e que nenhum login foi movido.
    const frc = frase({ em: 1, tipo: 'reconciliado', pasta: 'trabalho', de: 'pessoal', para: 'team', motivo: 'login guardado antigo arquivado em estacionado-trabalho.orfao-20261023-101500.json', manual: false });
    afirma('reconciliado diz a pasta, as duas contas, que nada foi movido e o arquivo arquivado',
      frc.includes('pasta trabalho') && frc.includes('conta pessoal') && frc.includes('conta trabalho')
        && frc.includes('nenhum login foi movido') && frc.includes('estacionado-trabalho.orfao-20261023-101500.json'), 'frase: ' + frc);
    // Revisão 2: nova tentativa de arquivar (de === para) não diz que o estado divergia.
    const frt = frase({ em: 1, tipo: 'reconciliado', pasta: 'trabalho', de: 'team', para: 'team', motivo: 'login guardado antigo arquivado em estacionado-trabalho.orfao-20261023-103000.json', manual: false });
    afirma('nova tentativa que arquivou o órfão diz o arquivo e que a troca volta a funcionar',
      frt.includes('estacionado-trabalho.orfao-20261023-103000.json') && frt.includes('volta a funcionar') && !frt.includes('o estado dizia'), 'frase: ' + frt);
    const frtf = frase({ em: 1, tipo: 'reconciliado', pasta: 'trabalho', de: 'team', para: 'team', motivo: 'não consegui arquivar o login guardado antigo (EBUSY)', manual: false });
    afirma('nova tentativa que falhou de novo diz o código e que a próxima troca falha',
      frtf.includes('ainda não consegui arquivar') && frtf.includes('EBUSY') && frtf.includes('próxima troca') && !frtf.includes('o estado dizia'), 'frase: ' + frtf);
    afirma('falhou comum segue dizendo que a troca foi desfeita',
      frase({ em: 1, tipo: 'falhou', pasta: 'trabalho', motivo: 'saida_ocupada' }) === 'Conta: a troca da pasta trabalho foi desfeita (saida_ocupada).');
    const fnd = frase({ em: 1, tipo: 'falhou', pasta: 'trabalho', de: 'team', para: 'pessoal', motivo: 'servidor confirmou a@exemplo.invalid, esperado b@exemplo.invalid; desfeito=false' });
    afirma('falhou com desfeito=false não diz que a troca foi desfeita',
      !/foi desfeita/.test(fnd) && /não pôde ser desfeita/.test(fnd) && /\/conta/.test(fnd) && /pasta trabalho/.test(fnd)
        && !/desfeito=false/.test(fnd), 'frase: ' + fnd);
    const fdt = frase({ em: 1, tipo: 'falhou', pasta: 'trabalho', de: 'team', para: 'pessoal', motivo: 'servidor confirmou a@exemplo.invalid, esperado b@exemplo.invalid; desfeito=true' });
    afirma('falhou com desfeito=true segue dizendo que a troca foi desfeita',
      /^Conta: a troca da pasta trabalho foi desfeita \(/.test(fdt) && !/\/conta/.test(fdt), 'frase: ' + fdt);
    afirma('desfazer_falhou sem pendentes (evento antigo) ainda avisa pela metade, sem lista',
      /ficou pela metade/.test(frase({ em: 1, tipo: 'falhou', pasta: 'trabalho', motivo: 'desfazer_falhou' }))
        && !/não restaurados/.test(frase({ em: 1, tipo: 'falhou', pasta: 'trabalho', motivo: 'desfazer_falhou' })));
    afirma('pendentes com caminho no evento saem só como nome de arquivo',
      !/[\\/]/.test(frase({ em: 1, tipo: 'falhou', pasta: 'trabalho', motivo: 'desfazer_falhou', pendentes: ['C:\\x\\y\\.credentials.json', '/a/b/reserva-pessoal.json'] })));
  } finally {
    if (servidor) servidor.filho.kill();
    fs.rmSync(raiz, { recursive: true, force: true });
  }
  console.log(`${ok} ok, ${falha} falha(s)`);
  if (falha) process.exit(1);
}

main().catch((e) => {
  console.error('erro: ' + e.message);
  process.exit(1);
});
