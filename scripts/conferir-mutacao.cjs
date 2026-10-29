#!/usr/bin/env node
// @categoria: sensor
/**
 * Catraca de mutação: inverte um comportamento no fonte e EXIGE que a bateria
 * fique VERMELHA. Bateria que continua verde com o comportamento invertido não
 * prova nada — e é o defeito mais reincidente deste acervo.
 *
 * POR QUE EXISTE, com data e número. Não é zelo teórico: é a família 2 do design
 * de 2026-08-21 ("bateria que não sabe falhar", 8 registros), medida três vezes:
 *
 *   - 2026-08-17, `obs-2026-08-17-dez-baterias-que-nao-sabiam-falhar`: **10 de 18**
 *     entregas trouxeram bateria que passava contra o código defeituoso.
 *   - 2026-08-19, `relatorios/2026-08-19-bateria-que-passa-com-o-defeito-presente.md`:
 *     em **4** entregas seguidas de um mesmo fluxo a bateria nova saía `exit=0`
 *     contra o commit anterior ao conserto. O critério "bateria que passa nos dois
 *     lados não prova nada" estava escrito na tarefa, e os quatro agentes
 *     relataram ✅ mesmo assim.
 *   - 2026-08-21: um agente cumpriu todos os critérios falsificáveis do briefing,
 *     colou saída de mutação e entregou 49/49 verde — com a trava recusando o
 *     caminho feliz SEMPRE.
 *
 * O que separa isso de texto de skill é o exit code. Quem roda este script não
 * consegue relatar "mutei e ficou vermelho" sem que tenha ficado.
 *
 * A GUARDA DO PADRÃO QUE NÃO CASA (D11) é o coração do script, e existe porque o
 * modo de falha dela já foi visto: em 2026-08-19 o alvo do `sed` de uma mutação
 * estava errado, a bateria ficou vermelha por outro motivo, e o resultado teria
 * sido lido como prova. Veredito certo pelo motivo errado é pior que veredito
 * errado, porque ninguém volta a olhar. Precedente literal do texto
 * `MUTACAO NAO APLICADA`: `scripts/testa-conferir-publicacao.sh:126`.
 *
 * STDIN FECHADO E TETO DE TEMPO existem pelo incidente da seção 6 do relatório de
 * 2026-08-19: uma bateria que lia payload do stdin pendurou o terminal por dez
 * minutos sem sinal nenhum, e só passou despercebida porque quem a escreveu
 * rodava com `</dev/null`. Aqui o filho nasce sem stdin e com teto — pendurar
 * deixaria o fonte MUTADO na árvore por tempo indeterminado.
 *
 * NOVA TENTATIVA (flaky-teto, D4, D7, D8): bateria instável decide por acaso, e
 * a catraca existe para não deixar o acaso decidir. Por isso os exits 2 e 4 só
 * saem DEPOIS de uma nova tentativa (nunca 1, 3, 5, 6 e 69, que não são acaso),
 * e o exit 0 só sai com a bateria vermelha em DUAS rodadas pós-mutação (vermelho
 * por acaso é aprovação falsa). Rodada mista (verde e vermelho em qualquer
 * ordem) sai 2 e imprime `FLAKE: baseline` ou `FLAKE: pos-mutacao`; com
 * `--slug` e `--tarefa` o flake é gravado no estado do fluxo (`estado.cjs
 * registrar-flake`) e falhar ao gravar é só aviso, nunca muda o exit. Com
 * `--raiz-estado <pasta>` (#498) o estado é gravado na pasta dada, e não na
 * `--raiz` da bateria (tarefa com `raiz:` grava na pasta do app, que não tem estado).
 *
 * Uso:
 *   node scripts/conferir-mutacao.cjs --arquivo <caminho> --de <trecho> \
 *        --para <trecho> --bateria <comando> [--raiz <pasta>] [--no-lugar] [--timeout <ms>] \
 *        [--slug <slug> --tarefa <n> [--raiz-estado <pasta>]]
 *
 * Exit:
 *   0  mutação casou E bateria VERMELHA nas duas rodadas — a bateria sabe falhar
 *   2  mutação casou e bateria VERDE (depois da nova tentativa, ou vermelho e verde
 *      misturados) — recusa: a bateria não mede o conserto
 *   3  MUTACAO NAO APLICADA              — o trecho `--de` não existe no fonte
 *   4  não dá para MEDIR                  — recusa antes de mutar: a bateria já falha
 *                                          no fonte íntegro (baseline não-verde,
 *                                          morta por sinal, ou estourou o teto), ou
 *                                          `--de` casa mais de uma vez e a inversão
 *                                          fica ambígua; com `--no-lugar`, também o
 *                                          alvo sujo, não rastreado ou ignorado no git,
 *                                          `git` que falha ou não vê um `.git` acima, editado
 *                                          durante o baseline, ou backup de outra
 *                                          execução (viva ou órfã) para o mesmo alvo
 *   5  suspeita de corte de shell         — pós-mutação desproporcionalmente curta
 *                                          (< 10% do baseline ou < 1 s), sugerindo
 *                                          que a bateria morreu antes de medir.
 *                                          Confirme rodando-a à mão: se sair 0,
 *                                          ignorar; se >= 1 s, aumentar piso absoluto
 *   6  bateria colapsou                  — zero asserção sobreviveu à mutação (ou
 *                                          ela parou de imprimir o próprio placar):
 *                                          o mecanismo de teste morreu antes de
 *                                          exercitar qualquer comportamento
 *   1  erro de uso, ou bateria sem veredito (estouro de tempo / sinal) pós-mutação,
 *      ou (com `--no-lugar`) restauração que não confere, ou arquivo editado durante
 *      a bateria pós-mutação (não é sobrescrito; os bytes originais ficam no backup)
 *   69 nao-verificavel — AMBIENTE, nao conteudo (D5, 2026-09-12): o comando da
 *                                          bateria nao pode nem SER EXECUTADO no
 *                                          baseline (`spawnSync` devolve `.error`,
 *                                          tipicamente ENOENT do shell) — diferente
 *                                          do 4, que e' "rodou e nao mediu nada".
 *                                          Tambem sai 69 quando a copia da raiz
 *                                          falha (ex.: junction quebrada, #378).
 *                                          Primeira linha do stderr:
 *                                          "nao-verificavel: <motivo>".
 *
 * O 2, 3, 4, 5 e 69 são códigos DIFERENTES de propósito: quem chama este script de
 * dentro de outra checagem precisa poder distinguir "a bateria é fraca" (2) de
 * "a declaração de mutação está errada" (3) de "a bateria já está quebrada" (4)
 * de "suspeita de falha de shell" (5) de "nao consegui nem rodar" (69) sem
 * depender de ler a mensagem.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

const TIMEOUT_PADRAO = 300000; // 5 min
const LIMITE_ORFAO_MS = 24 * 60 * 60 * 1000; // 24h (tarefa 6, Issue #294.2)

const USO = `uso: node scripts/conferir-mutacao.cjs --arquivo <caminho> --de <trecho> --para <trecho> --bateria <comando>

  --arquivo  <caminho>  fonte a mutar (relativo a --raiz, ou absoluto)
  --de       <trecho>   trecho LITERAL a inverter — precisa casar no fonte
  --para     <trecho>   o que entra no lugar (aceita '' para apagar o trecho)
  --bateria  <comando>  linha de comando da bateria, rodada via shell
  --raiz     <pasta>    diretório de trabalho da bateria (padrão: cwd)
  --no-lugar            sem cópia: muta o arquivo real, roda a bateria na própria --raiz e
                        restaura byte a byte (runtime vivo, ex. editor Unity aberto); recusa
                        alvo com mudança não commitada e outra execução viva no mesmo arquivo
  --timeout  <ms>       teto de tempo da bateria (padrão: ${TIMEOUT_PADRAO})
  --slug     <slug>     fluxo onde gravar o flake (junto de --tarefa; os dois ou nenhum)
  --tarefa   <n>        tarefa do plano a que o flake pertence
  --raiz-estado <pasta> onde o estado do fluxo está (padrão: --raiz); só vale com --slug
  --baseline-para <arq> grava o baseline verde ({status, duracao, stdout, stderr}) em JSON
  --baseline-de  <arq>  repassa um baseline já medido: a Fase 1 não roda a bateria (sai 4 se
                        o arquivo for ilegível ou o status não for 0). Mutuamente exclusivas,
                        e nenhuma das duas vale com --no-lugar

exit (2 e 4 só valem depois de uma nova tentativa; 0 exige vermelho em duas rodadas):
     0 mutação casou e bateria VERMELHA | 2 bateria VERDE | 3 MUTACAO NAO APLICADA |
     4 não dá para medir (baseline não-verde, ou --de ambíguo; com --no-lugar, alvo
     fora do estado limpo no git, ou editado no baseline, ou backup de outra execução)
     | 5 corte de shell (pós-mutação < 10% do baseline ou < 1 s) | 6 bateria colapsou
     (zero asserção sobreviveu à mutação, ou ela parou de imprimir o próprio placar) |
     1 erro de uso, ou restauração no lugar que não confere | 69 nao-verificavel (o comando da bateria nao executa — ambiente, nao
     conteudo)

Git Bash (MSYS) come uma barra de argumento que COMEÇA com \`//\`: \`// coment\`
chega aqui como \`/ coment\` e não casa. Medido em 2026-08-21 ao mutar um
comentário. Inclua um caractere antes das barras, ou exporte MSYS_NO_PATHCONV=1.

Bateria: esperado rodar via shell. No Unix é /bin/sh; no Windows, roda via bash -c quando
Git Bash está no PATH (sem bash: recusa bateria com ;, &&, ||). Python: a bateria
roda com PYTHONDONTWRITEBYTECODE=1 para evitar bytecode mutado.`;

function erroUso(msg) {
  console.error(`erro: ${msg}`);
  console.error('');
  console.error(USO);
  process.exit(1);
}

/**
 * Lê `--nome valor`. Devolve `null` quando a flag não veio, e a string vazia
 * quando veio vazia — a diferença importa: `--para ''` (apagar o trecho) é uma
 * mutação legítima, e um `if (!valor)` a recusaria.
 */
function ler(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  if (i === -1) return null;
  if (i + 1 >= process.argv.length) erroUso(`--${nome} veio sem valor`);
  return process.argv[i + 1];
}

// Falha da copia da raiz: bloqueio de ambiente, o mesmo 69 do "nao executa".
const EXIT_COPIA_FALHOU = 69;

// Marcas de caso vermelho na saida da bateria (Issue #378): as linhas que as
// contem saem inteiras, mesmo quando o trecho geral e truncado.
const MARCAS_FALHA = ['FALHA', '✖', '(fail)', 'not ok'];

function linhasVermelhas(texto) {
  return String(texto || '').split(/\r?\n/).filter((l) => MARCAS_FALHA.some((m) => l.includes(m)));
}

function ultimasLinhas(texto, n) {
  const linhas = String(texto || '').replace(/\s+$/, '').split(/\r?\n/);
  if (linhas.length <= n) return linhas.join('\n');
  return [`... (${linhas.length - n} linha(s) acima omitida(s))`, ...linhas.slice(-n)].join('\n');
}

// ============================================== Limpeza da cópia temporária
//
// A mutação (e as duas rodadas da bateria) rodam numa CÓPIA descartável da
// árvore, nunca no fonte real (Issue #266): lockfile só barra outra mutação
// concorrente, mas quem não consulta o lock — outra sessão, outro agente,
// `varrer-baterias.sh` — continuaria lendo o fonte mutado durante a janela de
// execução. Copiando a árvore inteira essa janela deixa de existir: o fonte
// real nunca é tocado, em NENHUM caminho de saída (verdicto normal, exceção,
// estouro de tempo, Ctrl-C). Por isso a limpeza da cópia usa o mesmo
// mecanismo de `process.on('exit'/sinal)` que antes restaurava o byte
// original, só que agora apaga o diretório inteiro.

let limpar = () => {};
// Emenda 2026-09-17 (tarefa 22): alem da copia, o git-dir/common-dir de um
// worktree vinculado moram num diretorio-irmao PROPRIO (fora da copia) — ver
// `materializarGit`. `registrarLimpeza` deixa esse irmao entrar na mesma
// varredura de saida, sem duplicar o mecanismo de `process.on`.
let alvosLimpeza = [];

function armarLimpeza(raizExecucao) {
  alvosLimpeza = raizExecucao ? [raizExecucao] : [];
  let feito = false;
  limpar = () => {
    if (feito) return;
    feito = true;
    restaurarNoLugar();
    for (const alvo of alvosLimpeza) {
      try {
        fs.rmSync(alvo, { recursive: true, force: true });
      } catch (err) {
        // Última linha de defesa: se nem apagar dá, o humano precisa saber
        // exatamente qual diretório temporário sobrou.
        console.error(`FALHA AO LIMPAR CÓPIA TEMPORÁRIA ${alvo}: ${err.message}`);
        console.error('Apague manualmente esse diretório temporário.');
      }
    }
  };
  // 'exit' cobre saída normal e exceção não tratada; sinal não dispara 'exit'
  // sozinho, daí os handlers explícitos abaixo.
  process.on('exit', () => limpar());
  for (const sinal of ['SIGINT', 'SIGTERM', 'SIGHUP', 'SIGBREAK']) {
    try {
      process.on(sinal, () => {
        limpar();
        process.exit(1);
      });
    } catch { /* sinal inexistente nesta plataforma */ }
  }
}

function registrarLimpeza(caminho) {
  alvosLimpeza.push(caminho);
}

// ============================================ Modo no lugar (#527, #569)
//
// Com `--no-lugar` não há cópia: baseline, mutação e bateria rodam na própria
// `--raiz`, porque o runtime da bateria é um processo vivo sobre a árvore real
// (editor Unity aberto trava `Temp/`, e `unity command run_tests` só fala com o
// editor da pasta original). Isso traz de volta o risco da #266 (quem ler o
// fonte durante a bateria lê o mutante), e por isso o modo só vale pedido.
//
// O arquivo volta aos bytes originais em toda saída, pelo mesmo `limpar` da
// cópia. Antes de mutar, os bytes originais vão para um backup no temporário:
// se o processo morrer sem rodar o `limpar` (máquina desligada, kill -9), a
// próxima execução encontra o backup de PID morto e restaura.

const PREFIXO_BACKUP = 'conferir-mutacao-nolugar-';

// Descreve a restauração pendente: `{ caminho, original, backup, hashMutado }`.
let restauro = null;

function sha256(buf) {
  return require('crypto').createHash('sha256').update(buf).digest('hex');
}

function caminhoBackup(alvoAbs) {
  const chave = process.platform === 'win32' ? alvoAbs.toLowerCase() : alvoAbs;
  const hash = require('crypto').createHash('sha1').update(chave).digest('hex');
  return path.join(os.tmpdir(), `${PREFIXO_BACKUP}${hash}.json`);
}

function pidVivo(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

function lerBackup(caminho) {
  try {
    const j = JSON.parse(fs.readFileSync(caminho, 'utf8'));
    if (typeof j.caminho !== 'string' || typeof j.original !== 'string' || typeof j.hashMutado !== 'string') return null;
    return j;
  } catch {
    return null;
  }
}

function falhaAoRestaurar(motivo, conselho) {
  console.error(`FALHA AO RESTAURAR ${restauro.caminho}: ${motivo}.`);
  console.error(`  Os bytes originais estão no backup ${restauro.backup} (campo original, base64).`);
  console.error(`  ${conselho}`);
  restauro = null;
  process.exitCode = 1;
}

function restaurarNoLugar() {
  if (!restauro) return;
  let atual = null;
  try { atual = fs.readFileSync(restauro.caminho); } catch { atual = null; }
  // Nada a desfazer: a escrita do mutante não chegou a acontecer (alvo somente
  // leitura, por exemplo). O backup sai sem alarde.
  if (atual && atual.equals(restauro.original)) {
    try { fs.rmSync(restauro.backup, { force: true }); } catch { /* backup sobra, a abertura vê */ }
    restauro = null;
    return;
  }
  // Nem o mutante nem o original: alguém editou o arquivo durante a bateria.
  // Escrever o original por cima apagaria essa edição.
  if (atual && sha256(atual) !== restauro.hashMutado) {
    falhaAoRestaurar('o arquivo mudou durante a bateria (não é o mutante nem o original: editado, ou escrita incompleta do mutante)',
      'Não escrevi nada por cima. Confira a edição e restaure o que falta à mão.');
    return;
  }
  let confere = false;
  let motivo = 'os bytes não conferem com o original';
  try {
    fs.writeFileSync(restauro.caminho, restauro.original);
    confere = fs.readFileSync(restauro.caminho).equals(restauro.original);
  } catch (err) {
    motivo = err.message;
  }
  if (confere) {
    try { fs.rmSync(restauro.backup, { force: true }); } catch { /* backup sobra, a abertura vê */ }
    restauro = null;
    return;
  }
  falhaAoRestaurar(motivo, 'Restaure o arquivo pelo git ou pelo backup antes de rodar de novo.');
}

// Abertura: backup de PID morto cujo arquivo ainda tem os bytes mutados volta
// ao original. Arquivo que mudou depois da mutação fica intocado, e o backup
// fica onde está, com aviso: sobrescrever seria apagar trabalho de alguém.
//
// Só o backup do PRÓPRIO alvo desta execução, e só se for do usuário corrente:
// o temporário pode ser compartilhado, e restaurar qualquer backup que aparecesse
// lá seria escrever onde um JSON plantado mandasse.
function backupConfiavel(arquivoBackup) {
  let st;
  try { st = fs.lstatSync(arquivoBackup); } catch { return false; }
  if (!st.isFile()) return false;
  if (typeof process.getuid === 'function' && st.uid !== process.getuid()) return false;
  return true;
}

function restaurarOrfaos(alvoReal) {
  for (const arquivoBackup of [caminhoBackup(alvoReal)]) {
    if (!fs.existsSync(arquivoBackup)) continue;
    if (!backupConfiavel(arquivoBackup)) {
      console.error(`AVISO: ignorei ${arquivoBackup}: não é arquivo comum do usuário corrente.`);
      continue;
    }
    const backup = lerBackup(arquivoBackup);
    if (!backup || path.resolve(backup.caminho) !== alvoReal) continue;
    if (pidVivo(Number(backup.pid))) continue;
    const original = Buffer.from(backup.original, 'base64');
    let atual = null;
    try { atual = fs.readFileSync(backup.caminho); } catch { atual = null; }
    // O arquivo já tem os bytes originais (a mutação nunca chegou a ser escrita):
    // o backup é resto sem conteúdo a proteger.
    if (atual && atual.equals(original)) {
      try { fs.rmSync(arquivoBackup, { force: true }); } catch { /* sobra; o conferirNoLugar avisa */ }
      continue;
    }
    const hashAtual = atual ? sha256(atual) : null;
    if (hashAtual === backup.hashMutado) {
      try {
        fs.writeFileSync(backup.caminho, original);
        if (fs.readFileSync(backup.caminho).equals(original)) {
          fs.rmSync(arquivoBackup, { force: true });
          console.error(`AVISO: restaurei ${backup.caminho}, que uma execução anterior no lugar deixou mutado (PID ${backup.pid} morto).`);
          continue;
        }
      } catch { /* cai no aviso abaixo */ }
      console.error(`AVISO: não consegui restaurar ${backup.caminho}; os bytes originais estão em ${arquivoBackup}.`);
    } else {
      console.error(`AVISO: backup órfão em ${arquivoBackup} (PID ${backup.pid} morto), mas ${backup.caminho} mudou depois da mutação.`);
      console.error('  Não toquei no arquivo. Confira-o e apague o backup quando estiver certo.');
    }
  }
}

// Guarda-corpo antes de qualquer bateria no lugar: o alvo precisa estar limpo no
// git (para `git checkout -- <arquivo>` sempre desfazer), e nenhuma outra execução
// pode estar com o mesmo arquivo mutado.
function temGitAcima(dir) {
  for (let d = path.resolve(dir); ; d = path.dirname(d)) {
    if (fs.existsSync(path.join(d, '.git'))) return true;
    if (path.dirname(d) === d) return false;
  }
}

function conferirNoLugar(raizExecucao, alvo) {
  const git = (args) => spawnSync(caminhoExecutavel('git'), args, { cwd: raizExecucao, encoding: 'utf8', stdio: 'pipe', env: { ...process.env, LC_ALL: 'C', LANGUAGE: 'C' } });
  const dentro = git(['rev-parse', '--is-inside-work-tree']);
  // Só é fora de repo o "not a git repository" sem `.git` em pasta nenhuma acima.
  // Git que falha por outro motivo, ou que não reconhece um `.git` que existe
  // (`.git/HEAD` corrompido), não sabe dizer se o alvo está limpo.
  const naoERepo = !dentro.error && dentro.status !== 0
    && /not a git repository/i.test(dentro.stderr || '') && !temGitAcima(raizExecucao);
  if (!naoERepo && (dentro.error || dentro.status !== 0)) {
    const porque = dentro.error ? dentro.error.message : (dentro.stderr || '').trim() || `exit ${dentro.status}`;
    console.error(`RECUSADO: git rev-parse falhou — ${porque}.`);
    console.error('  Sem o git não dá para saber se ele desfaz a mutação. Conserte o repositório (há um `.git`');
    console.error('  numa pasta acima que o git não reconhece, ou GIT_CEILING_DIRECTORIES o esconde) e rode de novo.');
    process.exit(4);
  }
  const foraDeRepo = naoERepo || (dentro.stdout || '').trim() !== 'true';
  let sujoNoGit = false;
  if (!foraDeRepo) {
    // `--ignored`: arquivo ignorado também não se desfaz com `git checkout --`.
    // `--untracked-files=normal`: repo de dotfiles costuma ter `status.showUntrackedFiles=no`,
    // e o alvo não rastreado sumiria do status.
    const st = git(['status', '--porcelain', '--ignored', '--untracked-files=normal', '--', alvo]);
    if (st.error || st.status !== 0) {
      const porque = st.error ? st.error.message : (st.stderr || '').trim() || `exit ${st.status}`;
      console.error(`RECUSADO: git status falhou dentro do repositório — ${porque}.`);
      console.error('  Sem ele não dá para saber se o git desfaz a mutação. Conserte o repositório e rode de novo.');
      process.exit(4);
    }
    sujoNoGit = (st.stdout || '').trim() !== '';
  }
  if (sujoNoGit) {
    console.error(`RECUSADO: ${alvo} tem mudança não commitada (ou não é rastreado, ou é ignorado).`);
    console.error('  No modo no lugar a mutação entra no arquivo real; sem o arquivo limpo no git, não há');
    console.error('  como desfazer pelo git se a restauração falhar. Commite (ou descarte) e rode de novo.');
    process.exit(4);
  }
  if (foraDeRepo) {
    console.error(`AVISO: ${raizExecucao} não é repositório git; no modo no lugar não há conferência`);
    console.error('  pelo git, e o backup no temporário é a única rede se a restauração falhar.');
  }
  const arquivoBackup = caminhoBackup(alvo);
  if (fs.existsSync(arquivoBackup)) {
    const backup = (backupConfiavel(arquivoBackup) && lerBackup(arquivoBackup)) || { pid: null };
    if (pidVivo(backup.pid)) {
      console.error(`RECUSADO: outra execução no lugar (PID ${backup.pid}) está com ${alvo} mutado agora.`);
      console.error(`  Espere ela acabar. Backup dela: ${arquivoBackup}.`);
      process.exit(4);
    }
    console.error(`RECUSADO: há um backup órfão de ${alvo} que a abertura não restaurou: ${arquivoBackup}.`);
    console.error('  Confira o arquivo contra o backup, apague o backup e rode de novo.');
    process.exit(4);
  }
}

// Grava o backup e arma a restauração ANTES de escrever o mutante.
function armarRestauro(alvo, original, mutado) {
  const arquivoBackup = caminhoBackup(alvo);
  const conteudo = JSON.stringify({
    caminho: alvo,
    original: original.toString('base64'),
    hashMutado: sha256(mutado),
    pid: process.pid,
  });
  fs.writeFileSync(arquivoBackup, conteudo, { mode: 0o600, flag: 'wx' });
  restauro = { caminho: alvo, original, backup: arquivoBackup, hashMutado: sha256(mutado) };
}

// ======================================= Repositório git na cópia (tarefa 20)
//
// A tarefa 7 excluía `.git` da cópia para nunca compartilhar índice, HEAD ou
// refs com a árvore real — e quebrou toda bateria que consulta git (achado da
// integração da tarefa 6, medido em 2026-09-16: `bash
// hooks/testa-contexto-sessao.sh` sai `ok: 293 falhou: 0` na árvore real e
// `ok: 292 falhou: 1` dentro da cópia sem `.git` — o `git show
// 14c471ed...:hooks/lib/contexto-sessao.cjs` daquela bateria falha em
// silêncio sem repositório).
//
// Conserto: materializar um `.git` PRÓPRIO na cópia. NUNCA o arquivo-ponteiro
// de um worktree vinculado apontando pro gitdir da árvore REAL — proibido
// pela D5. Em vez disso: HEAD/index/config/refs copiados (arquivos novos,
// fisicamente separados dos originais) mais `objects/info/alternates`
// apontando pro object-store real só para LEITURA — o mesmo mecanismo que já
// torna `git worktree` seguro (histórico imutável compartilhado, HEAD/index/
// refs próprios de cada worktree). A mutação desta ferramenta escreve num
// arquivo da árvore de trabalho, nunca num objeto git, então não existe
// caminho de escrita cruzada passando pelo alternates.
//
// Tarefa 22 (achado do verificar, 2026-09-16): quando `raiz` é worktree
// VINCULADO (git-dir != git-common-dir), o código anterior misturava HEAD/
// index do worktree com config/refs do commondir num ÚNICO diretório
// `.git` — e o resultado tinha git-dir == git-common-dir na cópia, ou seja,
// a cópia de um worktree vinculado virava CHECKOUT PRINCIPAL (branch
// `estado.cjs iniciar` recusa por ver "checkout principal fora da branch
// padrão"). Conserto: quando vinculado, a cópia ganha DOIS diretórios
// próprios, nunca compartilhando nada gravável com o repo real:
//   - `.git-comum` (commonDirCopia): config, packed-refs, refs copiados,
//     `objects/info/alternates` apontando pros objects reais — como antes.
//   - `.git-privado` (gitDirCopia): HEAD e index PRÓPRIOS deste worktree,
//     mais os dois arquivos que amarram um git-dir de worktree ao seu
//     common-dir: `commondir` (aponta pra `.git-comum`) e `gitdir` (aponta
//     de volta pro `.git` de `raizExecucao`, convenção de
//     `git worktree add`).
//   - `raizExecucao/.git` vira um ARQUIVO `gitdir: <gitDirCopia>` — nunca o
//     gitdir real, sempre a cópia.
//
// Emenda do verificar (2026-09-17): os dois diretórios moravam DENTRO de
// `raizExecucao` — e isso fazia `conferir-duplicacao.cjs` achar os metadados
// git copiados como "arquivos duplicados" (DUP2) e uma execução aninhada
// (bateria que copia a árvore de novo e roda `testa-conferir-mutacao.sh`
// dentro dela) reprovar B/C/D/controle/DUP2, porque a segunda cópia via os
// `.git-*` da primeira como parte da árvore. Conserto: quando vinculado, os
// dois diretórios passam a morar num diretório-irmão PRÓPRIO, fora de
// `raizExecucao` (`fs.mkdtempSync` separado) — exatamente como um worktree
// real (`.git/worktrees/<nome>` nunca fica dentro da árvore de trabalho).
// `raizExecucao/.git` continua sendo só o arquivo-ponteiro. A limpeza desse
// irmão é registrada em `registrarLimpeza`, coberta pelo mesmo mecanismo de
// saída/sinal de `armarLimpeza` — nenhum mecanismo de limpeza novo, só mais
// um alvo na lista existente.
function materializarGit(raiz, raizExecucao) {
  const gitDirRes = spawnSync(caminhoExecutavel('git'), ['rev-parse', '--git-dir'], { cwd: raiz, encoding: 'utf8', stdio: 'pipe' });
  if (gitDirRes.status !== 0) return; // raiz nao e repositorio git: copia fica sem .git (comportamento da tarefa 7)
  const commonDirRes = spawnSync(caminhoExecutavel('git'), ['rev-parse', '--git-common-dir'], { cwd: raiz, encoding: 'utf8', stdio: 'pipe' });
  if (commonDirRes.status !== 0) return;

  let gitDir, commonDir;
  try {
    gitDir = fs.realpathSync(path.resolve(raiz, gitDirRes.stdout.trim()));
    commonDir = fs.realpathSync(path.resolve(raiz, commonDirRes.stdout.trim()));
  } catch {
    return; // caminho de git-dir/common-dir nao resolve: copia fica sem .git
  }

  const vinculado = gitDir !== commonDir;

  const destGit = path.join(raizExecucao, '.git');
  // Nao-vinculado (checkout principal): o common-dir da copia E o `.git` da
  // copia, exatamente como antes (dentro de `raizExecucao`, um diretorio de
  // verdade). Vinculado: `.git-comum`/`.git-privado` moram num diretorio
  // TEMPORARIO IRMAO, fora de `raizExecucao` — nunca dentro da copia, para
  // nao aparecerem como "arquivo da arvore" pra quem varre a copia (DUP2,
  // execucao aninhada). `registrarLimpeza` cobre a remocao desse irmao.
  const metaDir = vinculado ? fs.mkdtempSync(path.join(os.tmpdir(), 'conferir-mutacao-git-')) : null;
  if (metaDir) registrarLimpeza(metaDir);
  const commonDirCopia = vinculado ? path.join(metaDir, '.git-comum') : destGit;
  fs.mkdirSync(commonDirCopia, { recursive: true });

  // config e refs sao compartilhados por definicao entre worktrees do mesmo
  // repositorio, e vem sempre do commonDir real.
  for (const nome of ['config', 'packed-refs']) {
    const origem = path.join(commonDir, nome);
    if (fs.existsSync(origem)) fs.copyFileSync(origem, path.join(commonDirCopia, nome));
  }
  if (fs.existsSync(path.join(commonDir, 'refs'))) {
    fs.cpSync(path.join(commonDir, 'refs'), path.join(commonDirCopia, 'refs'), { recursive: true });
  }
  fs.mkdirSync(path.join(commonDirCopia, 'objects', 'info'), { recursive: true });
  fs.writeFileSync(
    path.join(commonDirCopia, 'objects', 'info', 'alternates'),
    `${path.join(commonDir, 'objects').replace(/\\/g, '/')}\n`,
  );

  if (!vinculado) {
    // HEAD e index moram no MESMO diretorio que config/refs (checkout principal).
    for (const nome of ['HEAD', 'index']) {
      const origem = path.join(gitDir, nome);
      if (fs.existsSync(origem)) fs.copyFileSync(origem, path.join(destGit, nome));
    }
    return;
  }

  // Vinculado: git-dir PROPRIO do worktree (HEAD e index deste worktree, nao
  // do checkout principal), amarrado ao commonDirCopia por `commondir`/`gitdir`
  // — a mesma convencao que `git worktree add` usa de verdade, so que os DOIS
  // lados (`gitDirCopia` e `commonDirCopia`) sao copias, nunca os originais.
  const gitDirCopia = path.join(metaDir, '.git-privado');
  fs.mkdirSync(gitDirCopia, { recursive: true });
  for (const nome of ['HEAD', 'index']) {
    const origem = path.join(gitDir, nome);
    if (fs.existsSync(origem)) fs.copyFileSync(origem, path.join(gitDirCopia, nome));
  }
  fs.writeFileSync(path.join(gitDirCopia, 'commondir'), `${commonDirCopia.replace(/\\/g, '/')}\n`);
  fs.writeFileSync(path.join(gitDirCopia, 'gitdir'), `${destGit.replace(/\\/g, '/')}\n`);
  fs.writeFileSync(destGit, `gitdir: ${gitDirCopia.replace(/\\/g, '/')}\n`);
}

// ==================== Varredura de órfãos na abertura (tarefa 6, Issue #294.2)
//
// `armarLimpeza` apaga a cópia ao FIM de uma execução normal. Mas saída
// anormal — processo morto por um sinal que os handlers acima não cobrem,
// máquina desligada no meio, `--timeout` matando o processo pai antes do
// `exit` disparar — deixa `conferir-mutacao-*` (e `conferir-mutacao-git-*`,
// o diretório-irmão de metadados de `materializarGit`) para trás em
// `os.tmpdir()`. `limparTemporariosOrfaos` varre isso na ABERTURA da PRÓXIMA
// execução, antes de criar a cópia desta: só diretórios, só o prefixo
// `conferir-mutacao-`, só mtime acima de `LIMITE_ORFAO_MS` — nunca o
// diretório que esta própria execução está prestes a criar, que nasce com
// mtime de agora e sempre fica de fora do corte de 24h. Erro de leitura ou
// remoção é SILENCIOSO e nunca muda o exit: isto é limpeza de melhor
// esforço, nunca pode derrubar o veredito da catraca.
function limparTemporariosOrfaos() {
  let entradas;
  try {
    entradas = fs.readdirSync(os.tmpdir(), { withFileTypes: true });
  } catch {
    return;
  }
  for (const entrada of entradas) {
    if (!entrada.isDirectory()) continue;
    if (!entrada.name.startsWith('conferir-mutacao-')) continue;
    const caminho = path.join(os.tmpdir(), entrada.name);
    let st;
    try {
      st = fs.statSync(caminho);
    } catch {
      continue;
    }
    if (Date.now() - st.mtimeMs < LIMITE_ORFAO_MS) continue;
    try {
      fs.rmSync(caminho, { recursive: true, force: true });
    } catch {
      // melhor esforço: sobrar um órfão não pode falhar esta execução
    }
  }
}

// ============================== Flake gravado no estado do fluxo (D4)

/**
 * Grava no estado do fluxo que (tarefa, gate) só passou na nova tentativa.
 * Sem `--slug` não faz nada. Falhar ao gravar é AVISO no stderr e nunca muda o
 * exit da catraca: o veredito da bateria não depende do estado do fluxo.
 */
function gravarFlake(slug, tarefa, gate, raiz, raizEstado) {
  if (slug === null) return;
  // #498: `raizEstado` (de `--raiz-estado`) vai SÓ para este filho, como RFM_ESTADO_ROOT.
  // Sem ela, o ambiente segue como veio (env undefined = herdado), como antes.
  const env = raizEstado === null ? undefined : { ...process.env, RFM_ESTADO_ROOT: raizEstado };
  const r = spawnSync(process.execPath, [
    path.join(__dirname, 'estado.cjs'), 'registrar-flake',
    '--slug', slug, '--tarefa', tarefa, '--gate', gate,
  ], { cwd: raiz, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (r.stdout) process.stdout.write(r.stdout);
  if (r.error || r.status !== 0) {
    const motivo = r.error ? r.error.message : `exit ${r.status}: ${String(r.stderr || '').trim()}`;
    console.error(`aviso: nao consegui registrar o flake no estado de ${slug} — ${motivo}`);
  }
}

// ============================== Comando da bateria (D24, D25)

/**
 * Monta o comando e argumentos para rodar a bateria, considerando a plataforma.
 *
 * D24: No Windows, roda via bash -c quando Git Bash está no PATH; sem Git Bash,
 * recusa bateria que contenha ;, && ou ||, porque cmd.exe não separa comandos.
 *
 * D25: A bateria roda com PYTHONDONTWRITEBYTECODE=1 no ambiente para evitar
 * que Python deixe bytecode mutado na árvore (que a catraca restaura tarde).
 *
 * @param {string} bateria - comando da bateria
 * @returns {{cmd: string, args: string[], shell: boolean}} comando, argumentos e modo de shell
 */
function comandoDaBateria(bateria) {
  if (process.platform === 'win32') {
    // Tenta resolver 'bash' via PATH para testar se existe
    const caminhoDoShell = caminhoExecutavel('bash');
    // Verifica se o bash resolvido é do WSL (em System32 ou WindowsApps)
    if (caminhoDoShell && /\\(system32|windowsapps)\\/i.test(caminhoDoShell)) {
      process.stderr.write(`nao-verificavel: bash do WSL — ${caminhoDoShell}\n`);
      console.error(`RECUSADO: bash resolvido é do WSL, não pode rodar bateria`);
      process.exit(69);
    }
    // Se achou um bash válido (não WSL), tenta executar para confirmar
    if (caminhoDoShell) {
      try {
        const r = spawnSync(caminhoDoShell, ['-c', 'exit 0'], { shell: false });
        // Se funcionou (exit 0 ou qualquer outro exit, não error), bash existe
        if (!r.error) {
          return { cmd: caminhoDoShell, args: ['-c', bateria], shell: false };
        }
      } catch { /* bash não conseguiu executar */ }
    }

    // Windows, sem bash: rejeita bateria com encadeamento de shell
    if (/[;&|]/.test(bateria)) {
      console.error('erro: bateria com encadeamento de shell e cmd.exe não separa comandos — instale o Git Bash ou remova o encadeamento');
      process.exit(1);
    }
  }

  // Unix ou Windows com bash não disponível: shell padrão
  return { cmd: bateria, args: [], shell: true };
}

// ================================ Execução, com baseline verde

function rodaBateria(bateria, raiz, timeout, qual) {
  const inicio = Date.now();
  const { cmd, args, shell } = comandoDaBateria(bateria);
  // D25: Remove PYTHONDONTWRITEBYTECODE do process.env antes de fazer spread,
  // para que a mutação que remove a atribuição no code deixe o env limpo.
  const novaEnv = Object.assign({}, process.env);
  delete novaEnv.PYTHONDONTWRITEBYTECODE;
  const r = spawnSync(cmd, args, {
    shell,
    cwd: raiz,
    encoding: 'utf8',
    // stdin fechado: bateria que lê payload do stdin recebe EOF em vez de
    // pendurar (relatório de 2026-08-19, seção 6).
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout,
    maxBuffer: 32 * 1024 * 1024,
    env: { ...novaEnv, PYTHONDONTWRITEBYTECODE: '1', },
  });
  const duracao = Date.now() - inicio;
  return { r, duracao, qual };
}

// `--baseline-de` (D6, #606): o baseline já medido por quem chama (conferir-fluxo
// `mutacoes`) vira `baselineRes` sem rodar a bateria de novo. Só entra o que foi
// gravado verde: status diferente de 0 é recusa, e o arquivo ilegível também.
// Devolve o mesmo formato de `rodaBateria`, porque a detecção de corte e a de colapso
// leem estes campos e não podem saber de onde vieram.
function lerBaselineRepassado(arquivo) {
  const recusa = (motivo) => {
    console.error('RECUSADO: baseline repassado ilegivel');
    console.error(`  ${motivo}`);
    process.exit(4);
  };
  let obj;
  try {
    obj = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
  } catch (err) {
    recusa(`não consegui ler ${arquivo} como JSON — ${err.message}`);
  }
  if (!obj || typeof obj !== 'object') recusa(`${arquivo} não é um objeto JSON`);
  if (obj.status !== 0) recusa(`${arquivo} tem status ${JSON.stringify(obj.status)}, não 0: só baseline verde é repassado`);
  if (!Number.isFinite(obj.duracao)) recusa(`${arquivo} não tem duracao numérica`);
  return {
    r: { status: 0, signal: null, error: undefined, stdout: String(obj.stdout ?? ''), stderr: String(obj.stderr ?? '') },
    duracao: obj.duracao,
    qual: 'baseline (repassado)',
  };
}

// O piso e a razao moram AQUI, e nao dentro do main(), porque o que precisa ser
// provado e a REGRA — piso de 1 s, razao de 10%, e onde ficam as fronteiras — e
// regra se prova com entrada, nao com cronometro.
//
// Ate 2026-08-26 os dois casos da bateria que exercitavam esta decisao montavam
// fixtures cuja DURACAO definia o veredito esperado: `sleep 2` de um lado,
// `sleep 0.1` do outro. Sob carga da maquina o spawn de processo no Git Bash
// empurrava as medidas para o outro lado da fronteira, e a bateria da catraca de
// mutacao — o instrumento pelo qual todas as outras entregas provam que os
// testes medem alguma coisa — ficava vermelha sem defeito nenhum. Issue #121:
// duas varreduras completas da mesma arvore, uma com essa bateria vermelha e
// outra com zero vermelhas.
//
// NAO existe variavel de ambiente para ajustar estes numeros, e isso e escolha:
// um PISO_ABSOLUTO_MS sobrescrivivel e uma chave para desligar a heuristica em
// producao sem querer.
const PISO_ABSOLUTO_MS = 1000;
const RAZAO_DE_CORTE = 0.1;

/**
 * A pos-mutacao foi desproporcionalmente curta a ponto de sugerir que a bateria
 * morreu antes de medir?
 *
 * Duas condicoes, e as duas importam:
 *   - o baseline precisa ser tempo suficiente (>= 1 s) para a razao distinguir
 *     sinal de ruido de spawn;
 *   - a pos-mutacao precisa ficar abaixo de 10% dele.
 */
function suspeitaDeCorte(baselineDuracao, posDuracao) {
  return baselineDuracao >= PISO_ABSOLUTO_MS && posDuracao < baselineDuracao * RAZAO_DE_CORTE;
}

/**
 * A saida pos-mutacao prova que a bateria MEDIU e encontrou falha? Issue #475: o corte de
 * shell e suspeita por tempo, e tempo sob carga mente — a bateria de `node --test` da secao
 * 13c de testa-conferir-fluxo.sh teve baseline frio acima de 1 s e pos-mutacao rapida, e a
 * mutacao legitima saiu `pulada (suspeita de corte de shell)` na CI. Placar com falha (qualquer
 * forma de `extrairPlacar`, libtest do Rust incluido: `test result: FAILED. 0 passed; 1 failed`,
 * Issue #589) ou o resumo do `node --test` (`# fail N` / `ℹ fail N`, N > 0) e prova de que a
 * bateria chegou a medir: nao e corte.
 */
function mediuEFalhou(saida) {
  if (!saida) return false;
  const placar = extrairPlacar(saida);
  if (placar && placar.falhou > 0) return true;
  return /^\s*(?:#|ℹ)\s*fail\s+[1-9]\d*\s*$/m.test(saida);
}

// A palavra da falha nas formas do repo: `falhou`, `falha`, `falhas`, `falha(s)`.
const FALHA = 'falhou|falhas?|falha\\(s\\)';

/**
 * Extrai o placar (ok e falhou) da saída da bateria. Formas reconhecidas, todas
 * sem distinguir caixa (`gi`), com a palavra da falha em FALHA:
 *   - "ok: 34   falhou: 0" (espaços variáveis; também "ok: N FALHA: M")
 *   - "34 ok, 0 falhou"    (vírgula opcional: "34 ok   0 falha(s)")
 *   - "ok=34 falhou=0"
 *   - libtest do Rust: "test result: FAILED. 0 passed; 1 failed" — uma linha por
 *     binário de teste; ok = soma dos passed, falhou = soma dos failed. Só entra
 *     quando nenhuma forma do repo casa.
 *   - vitest: "Tests  1 failed | 14 passed (15)" — uma linha `Tests` por comando,
 *     somada; ok = passed, falhou = failed (#602). Só entra quando nem o repo nem
 *     o libtest casam.
 *
 * Entre as formas do repo vale a ULTIMA ocorrencia por posicao, qualquer que
 * seja a forma. Retorna { ok: número, falhou: número } ou null se não encontrar
 * placar reconhecível.
 */
function extrairPlacar(saida) {
  if (!saida) return null;

  // O placar de uma bateria e a ULTIMA ocorrencia, nao a primeira: bateria que
  // ecoa a saida de uma sub-bateria (fixture, caso e2e) carrega placares
  // aninhados no meio do stdout, e o primeiro deles e o da fixture. Medido em
  // 2026-09-09 na propria testa-conferir-mutacao.sh: primeira ocorrencia deu
  // ok=100 no baseline e ok=0 na mutacao, com a linha final dizendo 96/4.
  // A posicao vale entre as formas: a ultima linha do stdout e a que conta.
  const formas = [
    new RegExp(`ok:\\s*(\\d+)\\s+(?:${FALHA}):\\s*(\\d+)`, 'gi'),
    new RegExp(`(\\d+)\\s+ok,?\\s*(\\d+)\\s+(?:${FALHA})`, 'gi'),
    new RegExp(`ok=(\\d+)\\s+(?:${FALHA})=(\\d+)`, 'gi'),
  ];
  let melhor = null;
  for (const re of formas) {
    for (const m of saida.matchAll(re)) {
      if (melhor === null || m.index > melhor.index) {
        melhor = { index: m.index, ok: parseInt(m[1], 10), falhou: parseInt(m[2], 10) };
      }
    }
  }
  if (melhor !== null) return { ok: melhor.ok, falhou: melhor.falhou };

  // Placar do libtest: um "test result:" por binário de teste, somados.
  let achou = false;
  let ok = 0;
  let falhou = 0;
  for (const m of saida.matchAll(/test result: \w+\. (\d+) passed; (\d+) failed/g)) {
    achou = true;
    ok += parseInt(m[1], 10);
    falhou += parseInt(m[2], 10);
  }
  if (achou) return { ok, falhou };

  // Placar do vitest (#602): `Tests  1 failed | 14 passed (15)`, um por comando, somados.
  // Lido por segmento, nao por regex com `passed` obrigatorio: mutacao que derruba todos
  // os testes imprime `Tests  1 failed (1)`, e sem placar a pos-mutacao viraria colapso.
  // `Test Files` conta arquivos, nao testes, e fica de fora; `Tests  no tests` (import
  // quebrado) nao tem placar, e e colapso como deve.
  for (const m of saida.matchAll(/^[ \t]*Tests[ \t]+(.+?)[ \t]*\(\d+\)[ \t]*\r?$/gm)) {
    for (const seg of m[1].split('|')) {
      const s = /^\s*(\d+)\s+(failed|passed|skipped|todo)\s*$/.exec(seg);
      if (!s) continue;
      achou = true;
      if (s[2] === 'passed') ok += parseInt(s[1], 10);
      if (s[2] === 'failed') falhou += parseInt(s[1], 10);
    }
  }
  return achou ? { ok, falhou } : null;
}

// A GUARDA DO COLAPSO mede algo diferente de "a bateria caiu X%": ela mede se a
// mutação IMPEDIU a bateria de medir qualquer coisa, em vez de medir e
// discordar. As duas caras se PARECEM (posExit != 0, placar caiu) mas só uma
// delas prova que o teste pegou o defeito — a outra prova que o MECANISMO
// quebrou antes de chegar perto do comportamento.
//
// ATÉ 2026-09-11 a medida era proporção fixa: recusar quando `base.ok -
// pos.ok` passasse de 20% de `base.ok`. Isso pega bem o incidente que fundou a
// guarda (bateria inteira derrubada por ReferenceError, ver o topo do
// arquivo), mas pune bateria PEQUENA e FOCADA. Medido na tarefa 12 do plano
// `zerar-issues`, 2026-09-11: `hooks/testa-principal-atrasado.sh` tem 13
// asserções; a mutação declarada (`if (atras > 0)` → `if (atras > 999999)` em
// `hooks/lib/principal-atrasado.cjs`) derruba exatamente as 3 que medem o
// comportamento mutado, e as outras 10 continuam VERDES — a prova de que o
// mecanismo de teste NÃO quebrou. 3/13 = 23%, e a proporção fixa recusava
// (exit 6) o caso que devia aprovar. Numa bateria de 13 asserções qualquer
// mutação eficaz derruba mais de 20% do total: o caminho mais curto para o
// exit 0 vira inflar a bateria com asserções irrelevantes até a proporção
// caber — uma trava que premia teste inflado trabalha contra o que ela existe
// para defender.
//
// O critério novo mede o nome da guarda ao pé da letra: a bateria virou TODA
// vermelha (nada sobrou), ou ela só ficou parcialmente vermelha (o normal)?
//
//   - placarPos com ok=0 E falhou=0: nenhuma asserção foi sequer TENTADA — é
//     o que o fixture do caso 14 simula (`echo "ok: 0   falhou: 0"`). Isso é
//     diferente de ok=0 falhou=N (N asserções rodaram e TODAS legitimamente
//     falharam): uma bateria de UMA asserção só, cuja única asserção mede
//     exatamente o comportamento mutado, tem essa cara — e precisa APROVAR,
//     não colapsar.
//   - placarPos ausente (a bateria parou de imprimir o próprio placar) com
//     placarBase presente: mesmo sinal por outra via. A bateria sabe
//     reportar (imprimiu no baseline) e parou de reportar — só acontece
//     quando ela morre no meio (ReferenceError, exceção não tratada) antes do
//     fim. É o "ReferenceError que impede a bateria de subir" que a guarda
//     original também precisa continuar pegando.
//   - Sem placar dos DOIS lados, ou baseline sem nenhuma asserção: a bateria
//     não reporta nesse formato, ou não havia nada para perder — devolve
//     false, como sempre devolveu.
/**
 * A bateria pós-mutação COLAPSOU — parou de medir, em vez de medir e discordar?
 */
function bateriaColapsou(placarBase, placarPos) {
  if (!placarBase) return false;
  const baseTotal = placarBase.ok + placarBase.falhou;
  if (baseTotal === 0) return false; // nao havia asserção nenhuma para perder
  if (!placarPos) return true; // parou de imprimir o próprio placar: sinal de crash
  return placarPos.ok === 0 && placarPos.falhou === 0;
}

/**
 * RECUSADO por colapso, comum à primeira rodada pós-mutação e à confirmação
 * do vermelho (D7): sai 6. `rodada` nomeia a rodada no diagnóstico.
 */
function recusaColapso(placarBase, placarRodada, rodada) {
  console.error('RECUSADO: a bateria colapsou — não mediu nada.');
  console.error(`  Baseline: ok=${placarBase.ok} falhou=${placarBase.falhou}`);
  console.error(placarRodada
    ? `  ${rodada}: ok=${placarRodada.ok} falhou=${placarRodada.falhou}`
    : `  ${rodada}: placar ausente — a bateria parou de se reportar.`);
  console.error('  Isto não é "a bateria discordou" (isso seria vermelha normal, exit 0)');
  console.error('  — é o mecanismo de teste morrendo antes de exercitar qualquer');
  console.error('  comportamento (ReferenceError, exceção não tratada). Refine a mutação');
  console.error('  ou a bateria.');
  process.exit(6);
}

// Topo do repositório git que contém `dir` (`git rev-parse --show-toplevel` com
// cwd em `dir`), ou `null` quando `dir` não está em repositório git.
function toplevelDe(dir) {
  const res = spawnSync(caminhoExecutavel('git'), ['rev-parse', '--show-toplevel'], { cwd: dir, encoding: 'utf8', stdio: 'pipe' });
  if (res.status !== 0) return null;
  return res.stdout.trim();
}

function copiarRaiz(raiz) {
  // D7 (#609): com `raiz` dentro de um repositório git, copia o TOPO inteiro e a
  // bateria roda na pasta de `raiz` dentro dessa cópia — o app que importa uma
  // pasta irmã (`../lib/x.js`) precisa dela. Fora de git, `origem` é a própria
  // `raiz` e a cópia é só da raiz, como sempre.
  const origem = toplevelDe(raiz) || raiz;
  // Cópia descartável de toda a árvore: baseline, mutação e bateria
  // pós-mutação rodam AQUI, nunca em `raiz`. Só o `.git` de TOPO fica de
  // fora — `.git` aninhado em alguma fixture não é excluído (D5, Issue #266).
  const copia = fs.mkdtempSync(path.join(os.tmpdir(), 'conferir-mutacao-'));
  armarLimpeza(copia);
  //
  // Link simbolico/junction (tipicamente `node_modules` de worktree, Issue
  // #378): `cpSync` o recriaria com `symlinkSync` sem tipo, e no Windows isso
  // exige privilegio (EPERM). O filter pula o link e o script o recria depois:
  // junction para diretorio (nao exige privilegio), copia para arquivo.
  const links = [];
  let origemReal;
  let relRaiz;
  try {
    // Temp do Windows vem em nome 8.3 (RUNNER~1): compara-se o caminho real.
    origemReal = fs.realpathSync.native(origem);
    relRaiz = path.relative(origemReal, fs.realpathSync.native(raiz));
    fs.cpSync(origemReal, copia, {
      recursive: true,
      filter: (p) => {
        if (path.relative(origemReal, p) === '.git') return false;
        if (p === origemReal) return true;
        if (fs.lstatSync(p).isSymbolicLink()) { links.push(p); return false; }
        return true;
      },
    });
    for (const p of links) {
      const destino = path.join(copia, path.relative(origemReal, p));
      const real = fs.realpathSync(p);
      if (fs.statSync(real).isDirectory()) fs.symlinkSync(real, destino, 'junction');
      else fs.copyFileSync(real, destino);
    }
  } catch (e) {
    // Ambiente, nao conteudo (regra 14): nao ha bateria para medir, entao sai
    // 69 com uma linha, nao com stack trace e exit 1 (Issue #378).
    process.stderr.write(`nao-verificavel: copia da raiz falhou — ${e.message}\n`);
    process.exit(EXIT_COPIA_FALHOU);
  }
  materializarGit(origem, copia);
  return path.join(copia, relRaiz);
}

// D5 (plano colheita-pos-2-1-0, tarefa 4): antes de tudo que depende do tmpdir,
// prova que `os.tmpdir()` aceita a criação de uma pasta. Se não aceitar, o
// ambiente falhou — sai como nao-verificavel (exit 69), nunca como vermelho.
function conferirTmpdirGravavel() {
  const dir = os.tmpdir();
  let criada;
  try {
    criada = fs.mkdtempSync(path.join(dir, 'conferir-mutacao-preflight-'));
  } catch {
    process.stderr.write(`nao-verificavel: TMPDIR não gravável — ${dir}\n`);
    process.exit(69);
  }
  // Melhor esforço: antivírus ou indexador segurando a pasta recém-criada (EBUSY/EPERM)
  // não é motivo para derrubar a catraca; a pasta já provou o que tinha de provar.
  try { fs.rmSync(criada, { recursive: true, force: true }); } catch { /* sobra para limparTemporariosOrfaos */ }
}

function main() {
  if (process.argv.length <= 2) {
    console.error(USO);
    process.exit(1);
  }

  const raiz = ler('raiz') || process.cwd();
  const noLugar = process.argv.includes('--no-lugar');
  const rel = ler('arquivo');
  const de = ler('de');
  const para = ler('para');
  const bateria = ler('bateria');
  const slug = ler('slug');
  const tarefa = ler('tarefa');
  if ((slug === null) !== (tarefa === null)) erroUso('--slug e --tarefa vão juntos: os dois ou nenhum');
  const raizEstadoArg = ler('raiz-estado');
  const raizEstado = raizEstadoArg === null ? null : path.resolve(raizEstadoArg);

  if (rel === null) erroUso('falta --arquivo');
  if (de === null) erroUso('falta --de');
  if (para === null) erroUso('falta --para');
  if (bateria === null) erroUso('falta --bateria');
  if (de === '') erroUso('--de vazio casaria em qualquer lugar e não inverte nada');
  if (bateria.trim() === '') erroUso('--bateria vazio');
  if (de === para) erroUso('--de e --para são iguais: isso não inverte comportamento nenhum');

  // Baseline repassado entre tarefas (D6, #606): gravar e repassar não se combinam, e o
  // modo no lugar não repassa nada — o fonte real é reconferido entre tarefas.
  const baselinePara = ler('baseline-para');
  const baselineDe = ler('baseline-de');
  if (baselinePara === '') erroUso('--baseline-para vazio');
  if (baselineDe === '') erroUso('--baseline-de vazio');
  if (baselinePara !== null && baselineDe !== null) erroUso('--baseline-para e --baseline-de são mutuamente exclusivas');
  if (noLugar && (baselinePara !== null || baselineDe !== null)) erroUso('--baseline-para e --baseline-de não valem com --no-lugar');

  const timeout = Number(ler('timeout') ?? TIMEOUT_PADRAO);
  if (!Number.isFinite(timeout) || timeout <= 0) erroUso('--timeout precisa ser um número de ms positivo');

  if (!fs.existsSync(raiz) || !fs.statSync(raiz).isDirectory()) {
    console.error(`erro: --raiz não é uma pasta: ${raiz}`);
    process.exit(1);
  }

  conferirTmpdirGravavel();

  // Varredura de órfãos de execuções anteriores (tarefa 6, Issue #294.2) —
  // antes de criar a cópia desta execução, para não apagar a própria.
  limparTemporariosOrfaos();
  restaurarOrfaos(path.resolve(raiz, rel));

  // Com `--no-lugar` a raiz de execução é a própria `--raiz` (ver "Modo no lugar").
  const raizExecucao = noLugar ? path.resolve(raiz) : copiarRaiz(raiz);
  if (noLugar) armarLimpeza(null);

  const alvo = path.resolve(raizExecucao, rel);
  if (!fs.existsSync(alvo) || !fs.statSync(alvo).isFile()) {
    console.error(`erro: --arquivo não existe: ${alvo}`);
    process.exit(1);
  }

  if (noLugar) conferirNoLugar(raizExecucao, alvo);

  const original = fs.readFileSync(alvo);
  const texto = original.toString('utf8');
  const pedacos = texto.split(de);
  const ocorrencias = pedacos.length - 1;

  console.log(`arquivo : ${alvo}`);
  console.log(`de      : ${JSON.stringify(de)}`);
  console.log(`para    : ${JSON.stringify(para)}`);
  console.log(`raiz    : ${raiz}${noLugar ? ' (no lugar, sem cópia)' : ''}`);
  console.log(`bateria : ${bateria}`);
  console.log('');

  // ========================================================== Fase 1: baseline
  // Roda a bateria no fonte ÍNTEGRO. Se não sair 0, a prova não será válida,
  // porque qualquer alteração pode deixar a bateria vermelha sem relação com
  // o comportamento que você quer testar. D11 estendido.
  // Com `--baseline-de` a bateria não roda aqui: o baseline vem do arquivo (D6, #606).
  let baselineRes = baselineDe === null
    ? rodaBateria(bateria, raizExecucao, timeout, 'baseline')
    : lerBaselineRepassado(baselineDe);
  const baselineExit = baselineRes.r.status;
  let baselineDuracao = baselineRes.duracao;

  const baselineSaida = ultimasLinhas(`${baselineRes.r.stdout || ''}${baselineRes.r.stderr || ''}`, 20);
  console.log(baselineDe === null
    ? `--- bateria baseline (fonte íntegro) em ${baselineDuracao} ms ---`
    : `--- bateria baseline (repassado de ${baselineDe}) em ${baselineDuracao} ms ---`);
  if (baselineSaida) console.log(baselineSaida);
  console.log('---------------------------------');
  console.log('');

  // Verificação de baseline: a bateria tem que sair 0 no fonte íntegro.
  if (baselineRes.r.error && baselineRes.r.error.code === 'ETIMEDOUT') {
    console.error(`RECUSADO: baseline estourou o teto de ${timeout} ms.`);
    console.error('  A bateria não consegue rodar no fonte íntegro sem pendurar.');
    console.error('  Arrume o comando da bateria ou aumente o timeout.');
    process.exit(4);
  }
  if (baselineRes.r.error) {
    // Ambiente, nao conteudo (D5, 2026-09-12): `spawnSync` nao conseguiu nem
    // ISSO — nao e' a bateria que falhou, e' o proprio shell/comando que nao
    // pode ser lancado (tipicamente ENOENT). Diferente do 4 (baseline rodou e
    // nao ficou verde): aqui nada rodou, entao "bateria fraca" seria veredito
    // sobre o que nunca aconteceu.
    process.stderr.write(`nao-verificavel: bateria nao executa — ${baselineRes.r.error.message}\n`);
    console.error(`RECUSADO: baseline não consegui executar — ${baselineRes.r.error.message}`);
    process.exit(69);
  }
  if (baselineRes.r.status === null) {
    console.error(`RECUSADO: baseline morta pelo sinal ${baselineRes.r.signal}, sem exit code.`);
    process.exit(4);
  }
  if (baselineRes.r.status === 126 || baselineRes.r.status === 127) {
    process.stderr.write(`nao-verificavel: bateria nao executa — comando não encontrado (exit ${baselineExit})\n`);
    console.error(`RECUSADO: baseline com exit ${baselineExit} (comando não encontrado).`);
    console.error('  O comando da bateria não pode ser executado no baseline.');
    console.error('  Conserte o caminho do comando ou o PATH antes de invocar esta catraca.');
    process.exit(69);
  }
  if (baselineExit !== 0) {
    // Nova tentativa (D8): baseline vermelho pode ser acaso. Roda UMA vez mais, na
    // mesma cópia, ainda sem mutar. Verde agora = flake do baseline e a catraca
    // segue; vermelho de novo (ou rodada sem exit) = a recusa 4 de sempre.
    const nova = rodaBateria(bateria, raizExecucao, timeout, 'baseline (nova tentativa)');
    if (!nova.r.error && nova.r.status === 0) {
      console.log(`--- baseline: exit ${baselineExit} na 1a rodada e exit 0 na nova tentativa ---`);
      console.log('FLAKE: baseline');
      gravarFlake(slug, tarefa, `catraca: ${bateria}`, raiz, raizEstado);
      baselineRes = nova;
      baselineDuracao = nova.duracao;
    } else {
      console.error(`RECUSADO: baseline NAO-VERDE (exit ${baselineExit}; nova tentativa: ${nova.r.error ? nova.r.error.message : `exit ${nova.r.status}`}).`);
      console.error('  A bateria não sai 0 no fonte íntegro. Qualquer mutação pode deixá-la');
      console.error('  vermelha por motivo diverso do comportamento que você quer medir.');
      // Superfície humana (tarefa 20): a bateria roda dentro da CÓPIA temporária
      // (Issue #266, D5), não no fonte real — se falhar aqui por motivo de
      // ambiente (ex.: git ausente da cópia), quem lê não pode confundir com
      // bateria quebrada no fonte de `--raiz`.
      if (!noLugar) console.error(`  A falha foi NA CÓPIA temporária (${raizExecucao}), não em ${raiz}.`);
      console.error('  Conserte a bateria ou o source antes de invocar esta catraca.');
      process.exit(4);
    }
  }

  console.log(`ok: baseline VERDE (exit 0 após ${baselineDuracao} ms).`);
  console.log('');

  // `--baseline-para` (D6, #606): grava o verde para as tarefas seguintes da mesma bateria.
  // Depois do verde, inclusive o verde da nova tentativa do flake (baselineRes já é ela).
  if (baselinePara !== null) {
    try {
      fs.writeFileSync(baselinePara, JSON.stringify({
        status: 0,
        duracao: baselineDuracao,
        stdout: baselineRes.r.stdout || '',
        stderr: baselineRes.r.stderr || '',
      }));
    } catch (err) {
      console.error(`RECUSADO: não consegui gravar o baseline em ${baselinePara} — ${err.message}`);
      process.exit(1);
    }
  }

  // ====================================================== Fase 2: conferência
  // D11 — antes de escrever qualquer byte. Se o padrão não casa, NÃO há mutação.
  if (ocorrencias === 0) {
    console.error('MUTACAO NAO APLICADA');
    console.error(`  arquivo: ${alvo}`);
    console.error(`  o trecho --de não existe no fonte: ${JSON.stringify(de)}`);
    console.error('  a bateria NAO foi executada, e nada aqui é veredito sobre ela.');
    console.error('  conserte o trecho declarado; um padrão errado que deixa a bateria');
    console.error('  vermelha por outro motivo é veredito certo pelo motivo errado.');
    if (/^\/[^/]/.test(de)) {
      // Pista para o tropeço de 2026-08-21: no Git Bash, `--de '// x'` chega
      // com uma barra só. O sintoma é este exato --de, e sem esta linha o
      // humano procura o defeito no fonte, que está certo.
      console.error('  ATENÇÃO: o --de começa com UMA barra. No Git Bash, `//` vira `/`');
      console.error('  na passagem do argumento — veja a nota no texto de uso.');
    }
    process.exit(3);
  }

  // Recusa múltiplas ocorrências: o split deixa de ser um-para-um.
  if (ocorrencias > 1) {
    console.error(`RECUSADO: --de casa ${ocorrencias} vez(es), não 1.`);
    console.error('  Múltiplas ocorrências deixam a mutação ambígua. Refine o padrão');
    console.error('  para casar uma só, ou use --de e --para com delimitadores únicos.');
    process.exit(4);
  }

  console.log(`casou   : ${ocorrencias} ocorrência — inversão aplicável`);
  console.log('');

  // ======================================================== Fase 3: mutação
  // A limpeza da cópia temporária já está armada desde a criação de
  // `raizExecucao` — cobre este caminho de erro sem precisar rearmar.
  let temErroEscrita = false;
  const mutado = Buffer.from(pedacos.join(para), 'utf8');
  if (noLugar) {
    // O baseline roda entre a leitura do original e a mutação (no Unity, minutos
    // de recompilação). Arquivo editado nesse meio não se muta: a restauração
    // devolveria o original lido antes e apagaria a edição.
    const relido = fs.readFileSync(alvo);
    if (!relido.equals(original)) {
      console.error(`RECUSADO: ${alvo} mudou durante o baseline; nada foi mutado.`);
      console.error('  Alguém editou o arquivo enquanto a bateria rodava. Rode de novo com ele parado.');
      process.exit(4);
    }
  }
  try {
    if (noLugar) armarRestauro(alvo, original, mutado);
    fs.writeFileSync(alvo, mutado);
  } catch (err) {
    temErroEscrita = true;
    console.error(`ERRO AO MUTAR: ${err.message}`);
    if (err.code === 'EACCES') {
      console.error('  Arquivo somente-leitura ou sem permissão de escrita.');
    }
    limpar();
    process.exit(1);
  }

  // ============================================ Fase 4: bateria pós-mutação
  if (noLugar) {
    console.error(`AVISO: modo no lugar — ${alvo} fica MUTADO no fonte real até a bateria acabar;`);
    console.error('  quem ler esse arquivo agora (outra sessão, outro agente) lê o mutante.');
  }
  const posRes = rodaBateria(bateria, raizExecucao, timeout, 'pós-mutação');
  const posExit = posRes.r.status;
  const posDuracao = posRes.duracao;

  const posSaida = ultimasLinhas(`${posRes.r.stdout || ''}${posRes.r.stderr || ''}`, 20);
  console.log(`--- bateria pós-mutação em ${posDuracao} ms ---`);
  if (posSaida) console.log(posSaida);
  console.log('---------------------------------');
  console.log('');
  const vermelhas = linhasVermelhas(`${posRes.r.stdout || ''}${posRes.r.stderr || ''}`);
  if (vermelhas.length > 0) {
    console.log('--- casos vermelhos ---');
    for (const l of vermelhas) console.log(l);
    console.log('---------------------------------');
    console.log('');
  }

  // A cópia temporária NÃO é apagada aqui: o exit 2 (nova tentativa) e a
  // confirmação do vermelho (D7) rodam a bateria de novo, na mesma cópia mutada.
  // O `process.on('exit')` de `armarLimpeza` a apaga em todo caminho de saída, e
  // o fonte real nunca esteve mutado (Issue #266).

  // ============================================== Fase 5: veredito final
  const estourou = posRes.r.error && posRes.r.error.code === 'ETIMEDOUT';
  if (estourou) {
    console.error(`BATERIA SEM VEREDITO: estourou o teto de ${timeout} ms e foi morta.`);
    console.error('  Sem exit code da bateria não há prova nenhuma.');
    process.exit(1);
  }
  if (posRes.r.error) {
    console.error(`BATERIA SEM VEREDITO: não consegui executar o comando — ${posRes.r.error.message}`);
    process.exit(1);
  }
  if (posRes.r.status === null) {
    console.error(`BATERIA SEM VEREDITO: morta pelo sinal ${posRes.r.signal}, sem exit code.`);
    process.exit(1);
  }

  if (posExit === 0) {
    // Nova tentativa (D8): verde pós-mutação pode ser acaso. Roda UMA vez mais e
    // sai 2 em qualquer resultado; vermelho agora é rodada MISTA (flake).
    const nova = rodaBateria(bateria, raizExecucao, timeout, 'pós-mutação (nova tentativa)');
    if (!nova.r.error && nova.r.status !== null && nova.r.status !== 0) {
      console.log(`--- pós-mutação: exit 0 na 1a rodada e exit ${nova.r.status} na nova tentativa ---`);
      console.log('FLAKE: pos-mutacao');
      gravarFlake(slug, tarefa, `catraca: ${bateria}`, raiz, raizEstado);
    }
    console.error('RECUSADO: bateria VERDE com o comportamento invertido (exit 0).');
    console.error('  A mutação casou e foi aplicada — o fonte estava se comportando ao');
    console.error('  contrário enquanto a bateria rodava, e ela aprovou assim mesmo.');
    console.error('  Esta bateria não mede o conserto. Escreva o caso que o defeito quebrava.');
    process.exit(2);
  }

  // Verificação de colapso: a mutação pode ter impedido a bateria de medir
  // qualquer coisa, em vez de medir e discordar (ver o comentário acima de
  // `bateriaColapsou` — o critério NÃO é proporção, é "sobrou alguma asserção
  // viva?").
  const placarBase = extrairPlacar(`${baselineRes.r.stdout || ''}${baselineRes.r.stderr || ''}`);
  const placarPos = extrairPlacar(`${posRes.r.stdout || ''}${posRes.r.stderr || ''}`);
  if (bateriaColapsou(placarBase, placarPos)) recusaColapso(placarBase, placarPos, 'Pós-mutação');

  // Verificação de corte de shell: suspeita quando pós-mutação é desproporcionalmente
  // curta (< 10% do baseline), sugerindo que a bateria morreu antes de medir.
  // Só aplica quando o baseline é tempo suficiente (>= 1 s) para distinguir de ruído.
  //
  // A ORDEM importa e não é estética: este bloco vem DEPOIS do `posExit === 0`
  // de propósito. Bateria que saiu VERDE já tem veredito próprio — o 2 — e ele
  // vale independente da duração. Antes desta ordem, uma pós-mutação verde e
  // rápida saía 5 com a mensagem "a bateria saiu com exit != 0", que é falsa
  // sobre o que acabou de acontecer. Veredito certo pelo motivo errado é o
  // defeito que este script inteiro existe para não cometer.
  if (suspeitaDeCorte(baselineDuracao, posDuracao)
      && !mediuEFalhou(`${posRes.r.stdout || ''}${posRes.r.stderr || ''}`)) {
    const percentual = Math.round((posDuracao / baselineDuracao) * 100);
    console.error(`SUSPEITA DE CORTE DE SHELL: pós-mutação ${posDuracao} ms (${percentual}% do baseline).`);
    console.error(`  Baseline: ${baselineDuracao} ms | Pós-mutação: ${posDuracao} ms`);
    console.error(`  A bateria saiu ${posExit}, mas desproporcionalmente rápido.`);
    console.error('  Suspeita: erro no shell (unbound variable, comando não encontrado).');
    console.error('  Confirme rodando a bateria pós-mutação à mão e olhando o tempo/erro.');
    console.error('  Se ela chegar a imprimir placar, o vermelho é legítimo e o piso');
    console.error('  absoluto é que está baixo demais para esta bateria.');
    process.exit(5);
  }

  // Confirmação do vermelho (D7): vermelho por acaso é aprovação falsa. Só sai 0
  // com a bateria vermelha também numa segunda rodada pós-mutação; verde agora é
  // rodada MISTA (flake) e sai 2. Estouro de tempo ou sinal na segunda rodada é
  // sem veredito (1), como na primeira.
  const confRes = rodaBateria(bateria, raizExecucao, timeout, 'pós-mutação (confirmação)');
  const confirmouVermelho = !confRes.r.error && confRes.r.status !== null && confRes.r.status !== 0;
  // A confirmação passa pela mesma checagem de colapso da primeira rodada: crash
  // sem placar não é vermelho confirmado (exit 6). Sinal ou estouro não tem exit
  // numérico, não entra aqui e segue para o BATERIA SEM VEREDITO (exit 1).
  const placarConf = extrairPlacar(`${confRes.r.stdout || ''}${confRes.r.stderr || ''}`);
  if (confirmouVermelho && bateriaColapsou(placarBase, placarConf)) recusaColapso(placarBase, placarConf, 'Confirmação');
  if (!confirmouVermelho) {
    if (confRes.r.error || confRes.r.status === null) {
      const porque = confRes.r.error ? confRes.r.error.message : `morta pelo sinal ${confRes.r.signal}`;
      console.error(`BATERIA SEM VEREDITO: a segunda rodada pós-mutação não terminou — ${porque}.`);
      process.exit(1);
    }
    console.log(`--- pós-mutação: exit ${posExit} na 1a rodada e exit 0 na confirmação ---`);
    console.log('FLAKE: pos-mutacao');
    gravarFlake(slug, tarefa, `catraca: ${bateria}`, raiz, raizEstado);
    console.error('RECUSADO: o vermelho pós-mutação não se repetiu (vermelho e depois verde).');
    console.error('  Vermelho que a segunda rodada desmente pode ser acaso, e aprovar por acaso');
    console.error('  é aprovação falsa. A bateria é instável ou não mede o conserto.');
    process.exit(2);
  }

  console.log(`ok: bateria VERMELHA com o comportamento invertido (exit ${posExit}), confirmada em duas rodadas.`);
  console.log(`    Baseline: ${baselineDuracao} ms (exit 0) → Mutação: ${posDuracao} ms (exit ${posExit})`);
  // A restauração do modo no lugar roda na saída, depois desta linha: aqui não se afirma.
  console.log('    A bateria sabe falhar.');
  process.exit(0);
}

if (require.main === module) main();

module.exports = { rodaBateria, suspeitaDeCorte, mediuEFalhou, PISO_ABSOLUTO_MS, RAZAO_DE_CORTE, extrairPlacar, bateriaColapsou, gravarFlake };
