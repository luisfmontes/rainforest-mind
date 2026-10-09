'use strict';
/**
 * Migração 7 do esquema: nome canônico de projeto (#435; design D5, D6 e D7).
 *
 * `observacoes.projeto` e `resumos.projeto` passam a ser o slug do repositório principal
 * (pela regra do harness). Nome curto só migra quando casa com exatamente um canônico.
 * Linha de pasta de worktree que colide com outra da origem ganha `:wt:<nome>:` (D7).
 *
 * Duas passadas:
 *  - Primeira (user_version < 2): backup do banco ANTES de qualquer escrita, transação
 *    única, contagens conferidas, user_version = 2 e relatório `migracao-projeto-canonico.txt`.
 *  - Passadas seguintes: mesma regra sobre as linhas que ainda estão fora do canônico
 *    (plugin antigo gravando), sem backup, sem relatório e sem nova versão.
 *
 * Módulo folha: não requer scripts/memoria.cjs (circular). O backup entra por injeção.
 * Não escreve em stdout. Nenhuma falha sai daqui como exceção: quem chama (criarSchema)
 * continua a abertura do banco.
 */
const fs = require('fs');
const path = require('path');
const {
  slugDoCaminho, ehSlugDeCaminho, canonicoDaPasta, casarCurto,
} = require('./projeto-canonico.cjs');

const VERSAO_PROJETO_CANONICO = 2;
const NOME_RELATORIO = 'migracao-projeto-canonico.txt';
// Origem de sessão: `sessao:<id>:offset:<n>`. A de linha de worktree leva `:wt:<nome>:` (D7).
const ORIGEM_SESSAO = /^sessao:([^:]+):offset:(\d+)$/;

function ehTravada(erro) {
  return /locked|busy/i.test(String((erro && erro.message) || ''));
}

function caminhoDoBanco(conexao) {
  const principal = conexao.prepare('PRAGMA database_list').all().find((r) => r.name === 'main');
  return principal && principal.file ? principal.file : null;
}

// O que nenhuma linha pode perder (design, "O que não pode quebrar").
function fotografia(conexao) {
  const contar = (tabela) => conexao.prepare(`SELECT COUNT(*) AS n FROM ${tabela}`).get().n;
  return {
    observacoes: contar('observacoes'),
    resumos: contar('resumos'),
    marca_dagua: contar('marca_dagua'),
    uso_memoria: contar('uso_memoria'),
    ids: conexao.prepare('SELECT id FROM observacoes ORDER BY id').all().map((r) => r.id).join(','),
  };
}

// Só lê. Devolve o que mudaria: movimentos de linha, colisões que ficam, nomes que ficam.
function planejar(conexao, primeira) {
  const porNome = (tabela) => new Map(
    conexao.prepare(`SELECT projeto, COUNT(*) AS n FROM ${tabela} GROUP BY projeto`).all()
      .map((r) => [r.projeto, r.n]),
  );
  const obsPorNome = porNome('observacoes');
  const resPorNome = porNome('resumos');
  const nomes = new Set([...obsPorNome.keys(), ...resPorNome.keys()]);

  // 1. Uma grafia canônica por repositório, sem diferenciar caixa.
  //    Vence a com mais observações; empate, ordem alfabética (ordinal).
  const grupos = new Map();
  for (const nome of nomes) {
    if (!ehSlugDeCaminho(nome)) continue;
    const base = slugDoCaminho(canonicoDaPasta(nome).canonico);
    const chave = base.toLowerCase();
    if (!grupos.has(chave)) grupos.set(chave, new Set());
    grupos.get(chave).add(base);
  }
  const vencedor = new Map();
  for (const [chave, grafias] of grupos) {
    // Grafia estável: a que começa por maiúscula e `--` (a que o harness grava) vence sempre;
    // só depois contam as linhas e, por fim, a ordem alfabética (ordinal).
    const forma = (g) => (/^[A-Z]--/.test(g) ? 0 : 1);
    const ordem = [...grafias].sort((a, b) => (forma(a) - forma(b))
      || ((obsPorNome.get(b) || 0) - (obsPorNome.get(a) || 0))
      || (a < b ? -1 : a > b ? 1 : 0));
    vencedor.set(chave, ordem[0]);
  }
  const canonicos = [...new Set(vencedor.values())];

  // 2. Para cada nome: aonde vai, ou por que fica.
  const destino = new Map(); // nome -> { para, motivo, worktree }
  const ficaram = [];        // curto sem correspondência
  const ambiguos = [];       // curto com mais de um candidato
  for (const nome of nomes) {
    if (ehSlugDeCaminho(nome)) {
      const pasta = canonicoDaPasta(nome);
      const para = vencedor.get(slugDoCaminho(pasta.canonico).toLowerCase());
      if (para === nome) continue;
      destino.set(nome, {
        para,
        motivo: pasta.worktree !== null ? 'pasta de worktree' : 'mesmo repositório, outra grafia',
        worktree: pasta.worktree,
      });
      continue;
    }
    // D6: nome curto só migra na passada da versão 1→2; depois disso o órfão fica onde está.
    if (!primeira) continue;
    const casamento = casarCurto(nome, canonicos);
    const contagem = { nome, obs: obsPorNome.get(nome) || 0, res: resPorNome.get(nome) || 0 };
    if (casamento.tipo === 'unico') {
      destino.set(nome, {
        para: casamento.canonico,
        motivo: 'nome curto de correspondência única',
        worktree: null,
      });
    } else if (casamento.tipo === 'ambiguo') {
      ambiguos.push({ ...contagem, candidatos: casamento.candidatos });
    } else {
      ficaram.push(contagem);
    }
  }

  // 3. Linha a linha em observacoes (UNIQUE(projeto, origem)). Colisão só sai pelo D7;
  //    o que não sai fica onde está e vai para o relatório.
  const movimentos = []; // { id, de, para, origem, antiga? }
  const colisoes = [];   // { id, de, para, origem }
  const reservadas = new Set();
  const existe = conexao.prepare('SELECT 1 AS x FROM observacoes WHERE projeto = ? AND origem = ? LIMIT 1');
  const ocupada = (para, origem) => reservadas.has(`${para}\u0000${origem}`)
    || existe.get(para, origem) !== undefined;
  const linhasDoNome = conexao.prepare('SELECT id, origem FROM observacoes WHERE projeto = ? ORDER BY id');
  for (const [de, { para, worktree }] of destino) {
    if (!obsPorNome.has(de)) continue;
    for (const { id, origem } of linhasDoNome.all(de)) {
      if (origem === null || !ocupada(para, origem)) {
        movimentos.push({ id, de, para, origem });
        if (origem !== null) reservadas.add(`${para}\u0000${origem}`);
        continue;
      }
      const m = ORIGEM_SESSAO.exec(origem);
      const reescrita = worktree !== null && m ? `sessao:${m[1]}:wt:${worktree}:offset:${m[2]}` : null;
      if (reescrita !== null && !ocupada(para, reescrita)) {
        movimentos.push({ id, de, para, origem: reescrita, antiga: origem });
        reservadas.add(`${para}\u0000${reescrita}`);
      } else {
        colisoes.push({ id, de, para, origem });
      }
    }
  }

  const resumosAMover = [...destino.keys()].filter((de) => resPorNome.has(de));
  return {
    destino, movimentos, colisoes, ficaram, ambiguos, obsPorNome, resPorNome, resumosAMover,
  };
}

function temTrabalho(plano) {
  return plano.movimentos.length > 0 || plano.resumosAMover.length > 0;
}

function aplicar(conexao, plano) {
  const moverObs = conexao.prepare('UPDATE observacoes SET projeto = ?, origem = ? WHERE id = ?');
  for (const m of plano.movimentos) moverObs.run(m.para, m.origem, m.id);
  const moverRes = conexao.prepare('UPDATE resumos SET projeto = ? WHERE projeto = ?');
  for (const de of plano.resumosAMover) moverRes.run(plano.destino.get(de).para, de);
}

// Sonda de trava: BEGIN IMMEDIATE e ROLLBACK. Trava de outra conexão = false, sem erro.
function podeEscrever(conexao) {
  try {
    conexao.exec('BEGIN IMMEDIATE');
    conexao.exec('ROLLBACK');
    return true;
  } catch (e) {
    if (ehTravada(e)) return false;
    throw e;
  }
}

function linhasDoRelatorio(plano, backup) {
  const contagemPor = (lista, chave) => {
    const mapa = new Map();
    for (const item of lista) mapa.set(item[chave], (mapa.get(item[chave]) || 0) + 1);
    return mapa;
  };
  const obsMovidasPor = contagemPor(plano.movimentos, 'de');
  const totalObs = plano.movimentos.length;
  const totalRes = plano.resumosAMover.reduce((s, de) => s + plano.resPorNome.get(de), 0);
  const linhas = [];
  linhas.push('Migração do nome de projeto para o canônico (rainforest-mind, #435)');
  linhas.push(`Gerado em: ${new Date().toISOString()}`);
  linhas.push('');
  linhas.push(`Backup do banco antes da migração: ${backup || '(nenhum: nada a mover nesta passada)'}`);
  linhas.push('Esquema: user_version 1 -> 2');
  linhas.push('');
  linhas.push(`Linhas movidas: ${totalObs} observações, ${totalRes} resumos.`);
  linhas.push('');
  linhas.push('Nomes migrados (de -> para):');
  const migrados = [...plano.destino.entries()].filter(([de]) => obsMovidasPor.has(de) || plano.resPorNome.has(de));
  if (migrados.length === 0) linhas.push('  (nenhum)');
  for (const [de, { para, motivo }] of migrados) {
    const obs = obsMovidasPor.get(de) || 0;
    const res = plano.resPorNome.get(de) || 0;
    linhas.push(`  ${de} -> ${para}: ${obs} observações, ${res} resumos (${motivo})`);
  }
  linhas.push('');
  linhas.push('Colisões reescritas (a origem recebeu o nome do worktree, D7):');
  const reescritas = plano.movimentos.filter((m) => m.antiga !== undefined);
  if (reescritas.length === 0) linhas.push('  (nenhuma)');
  for (const m of reescritas) linhas.push(`  ${m.de} (id ${m.id}): ${m.antiga} -> ${m.origem}`);
  linhas.push('');
  linhas.push('Colisões que ficaram (a linha continua no nome de origem e precisa de decisão):');
  if (plano.colisoes.length === 0) linhas.push('  (nenhuma)');
  for (const c of plano.colisoes) linhas.push(`  ${c.de} (id ${c.id}): ${c.origem}, já existe em ${c.para}`);
  linhas.push('');
  linhas.push('Curtos sem correspondência (ficam como estão):');
  if (plano.ficaram.length === 0) linhas.push('  (nenhum)');
  for (const f of plano.ficaram) linhas.push(`  ${f.nome}: ${f.obs} observações, ${f.res} resumos`);
  linhas.push('');
  linhas.push('Curtos ambíguos (ficam como estão; use o nome completo do projeto):');
  if (plano.ambiguos.length === 0) linhas.push('  (nenhum)');
  for (const a of plano.ambiguos) {
    linhas.push(`  ${a.nome}: ${a.obs} observações, ${a.res} resumos; candidatos: ${a.candidatos.join(', ')}`);
  }
  return `${linhas.join('\n')}\n`;
}

function escreverRelatorio(caminhoDb, plano, backup) {
  try {
    fs.writeFileSync(path.join(path.dirname(caminhoDb), NOME_RELATORIO), linhasDoRelatorio(plano, backup), 'utf8');
  } catch (e) {
    console.error(`AVISO: não consegui gravar ${NOME_RELATORIO} (${e.message})`);
  }
}

const TABELAS_CONTADAS = ['observacoes', 'resumos', 'marca_dagua', 'uso_memoria'];

function contagensDe(conexao) {
  const r = {};
  for (const t of TABELAS_CONTADAS) r[t] = conexao.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get().n;
  return r;
}

function contagensIguais(a, b) {
  return TABELAS_CONTADAS.every((t) => a[t] === b[t]);
}

// O backup só vale se tiver o que a conexão vê. `wal_checkpoint` ocupado (leitor concorrente)
// deixa a cópia do `.db` sem as linhas que ainda estão no WAL, sem erro nenhum.
function conferirBackup(conexao, backup) {
  const antes = contagensDe(conexao);
  let contagensDoBackup;
  try {
    const { DatabaseSync } = require('node:sqlite');
    const copia = new DatabaseSync(String(backup), { readOnly: true });
    try {
      contagensDoBackup = contagensDe(copia);
    } finally {
      copia.close();
      for (const sufixo of ['-wal', '-shm']) {
        try { fs.unlinkSync(`${backup}${sufixo}`); } catch (_) { /* não existe */ }
      }
    }
  } catch (e) {
    throw new Error(`backup incompleto (não consegui conferir a cópia: ${e.message})`);
  }
  if (!contagensIguais(antes, contagensDoBackup)) throw new Error('backup incompleto');
}

const lerVersao = (conexao) => conexao.prepare('PRAGMA user_version').get().user_version;

function executar(conexao, fazerBackup) {
  const caminhoDb = caminhoDoBanco(conexao);
  if (!caminhoDb) return { aplicada: false, motivo: 'banco sem arquivo' };

  const primeira = lerVersao(conexao) < VERSAO_PROJETO_CANONICO;
  const plano = planejar(conexao, primeira);
  const trabalho = temTrabalho(plano);
  if (!primeira && !trabalho) return { aplicada: true, movidas: 0, primeira: false };

  if (!podeEscrever(conexao)) return { aplicada: false, motivo: 'ocupado' };

  // Backup fora de transação: fazerBackupDoBanco faz VACUUM por outra conexão, e com a nossa
  // escrita aberta o VACUUM falha e a cópia sai sem o WAL.
  let backup = null;
  if (primeira && trabalho) {
    if (typeof fazerBackup !== 'function') throw new Error('backup não informado');
    backup = fazerBackup(caminhoDb);
    conferirBackup(conexao, backup);
  }

  let feito;
  let primeiraAgora;
  conexao.exec('BEGIN IMMEDIATE');
  try {
    // Outra abertura pode ter terminado a primeira passada enquanto esperávamos a trava.
    primeiraAgora = lerVersao(conexao) < VERSAO_PROJETO_CANONICO;
    const refeito = planejar(conexao, primeiraAgora);
    const antes = JSON.stringify(fotografia(conexao));
    aplicar(conexao, refeito);
    const depois = JSON.stringify(fotografia(conexao));
    if (antes !== depois) throw new Error('contagens ou ids divergem; nada foi gravado');
    if (primeiraAgora) conexao.exec(`PRAGMA user_version = ${VERSAO_PROJETO_CANONICO};`);
    conexao.exec('COMMIT');
    feito = refeito;
  } catch (e) {
    try { conexao.exec('ROLLBACK'); } catch (_) { /* transação já encerrada */ }
    throw e;
  }

  const temRelatorio = feito.movimentos.length > 0 || feito.colisoes.length > 0
    || feito.ficaram.length > 0 || feito.ambiguos.length > 0 || feito.resumosAMover.length > 0;
  if (primeiraAgora && temRelatorio) escreverRelatorio(caminhoDb, feito, backup);

  return {
    aplicada: true,
    primeira: primeiraAgora,
    movidas: feito.movimentos.length,
    colisoes: feito.colisoes.length,
    backup,
  };
}

/**
 * Aplica a migração 7 numa conexão aberta. Nunca lança: falha vira `{ aplicada: false }`
 * e um AVISO em stderr (nunca em stdout). Trava de outra conexão sai calada.
 * opcoes.fazerBackup(caminhoDb) -> caminho do backup; pode lançar (quem chama decide).
 */
function migrarProjetoCanonico(conexao, opcoes = {}) {
  try {
    return executar(conexao, opcoes.fazerBackup);
  } catch (e) {
    if (!ehTravada(e)) {
      console.error(`AVISO: migração do nome canônico não aplicada (${e.message}); o banco segue como estava`);
    }
    return { aplicada: false, motivo: e.message };
  }
}

module.exports = {
  migrarProjetoCanonico,
  VERSAO_PROJETO_CANONICO,
  NOME_RELATORIO,
};
