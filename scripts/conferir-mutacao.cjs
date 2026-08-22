#!/usr/bin/env node
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
 *     em **4** entregas seguidas de uma mesma esteira a bateria nova saía `exit=0`
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
 * `MUTACAO NAO APLICADA`: `scripts/testa-conferir-relatorio.sh:126`.
 *
 * STDIN FECHADO E TETO DE TEMPO existem pelo incidente da seção 6 do relatório de
 * 2026-08-19: uma bateria que lia payload do stdin pendurou o terminal por dez
 * minutos sem sinal nenhum, e só passou despercebida porque quem a escreveu
 * rodava com `</dev/null`. Aqui o filho nasce sem stdin e com teto — pendurar
 * deixaria o fonte MUTADO na árvore por tempo indeterminado.
 *
 * Uso:
 *   node scripts/conferir-mutacao.cjs --arquivo <caminho> --de <trecho> \
 *        --para <trecho> --bateria <comando> [--raiz <pasta>] [--timeout <ms>]
 *
 * Exit:
 *   0  mutação casou E bateria VERMELHA  — a bateria sabe falhar
 *   2  mutação casou e bateria VERDE     — recusa: a bateria não mede o conserto
 *   3  MUTACAO NAO APLICADA              — o trecho `--de` não existe no fonte
 *   1  erro de uso, ou bateria sem veredito (estouro de tempo / sinal)
 *
 * O 2 e o 3 são códigos DIFERENTES de propósito: quem chama este script de
 * dentro de outra checagem precisa poder distinguir "a bateria é fraca" de "a
 * declaração de mutação está errada" sem depender de ler a mensagem.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const TIMEOUT_PADRAO = 300000; // 5 min

const USO = `uso: node scripts/conferir-mutacao.cjs --arquivo <caminho> --de <trecho> --para <trecho> --bateria <comando>

  --arquivo  <caminho>  fonte a mutar (relativo a --raiz, ou absoluto)
  --de       <trecho>   trecho LITERAL a inverter — precisa casar no fonte
  --para     <trecho>   o que entra no lugar (aceita '' para apagar o trecho)
  --bateria  <comando>  linha de comando da bateria, rodada via shell
  --raiz     <pasta>    diretório de trabalho da bateria (padrão: cwd)
  --timeout  <ms>       teto de tempo da bateria (padrão: ${TIMEOUT_PADRAO})

exit: 0 mutação casou e bateria VERMELHA | 2 bateria VERDE | 3 MUTACAO NAO APLICADA | 1 erro de uso

Git Bash (MSYS) come uma barra de argumento que COMEÇA com \`//\`: \`// coment\`
chega aqui como \`/ coment\` e não casa. Medido em 2026-08-21 ao mutar um
comentário. Inclua um caractere antes das barras, ou exporte MSYS_NO_PATHCONV=1.`;

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

function ultimasLinhas(texto, n) {
  const linhas = String(texto || '').replace(/\s+$/, '').split(/\r?\n/);
  if (linhas.length <= n) return linhas.join('\n');
  return [`... (${linhas.length - n} linha(s) acima omitida(s))`, ...linhas.slice(-n)].join('\n');
}

// ====================================================== Restauração do fonte
//
// O fonte volta ao byte original em TODO caminho de saída: verdicto normal,
// exceção, estouro de tempo e Ctrl-C. Deixar um fonte mutado na árvore de
// trabalho é pior que qualquer veredito errado — é dano, e silencioso: o commit
// seguinte o leva junto. Por isso o original é guardado como Buffer (nada de
// re-encodar) e a restauração é idempotente.

let restaurar = () => {};

function armarRestauracao(caminho, original) {
  let feito = false;
  restaurar = () => {
    if (feito) return;
    feito = true;
    try {
      fs.writeFileSync(caminho, original);
    } catch (err) {
      // Última linha de defesa: se nem restaurar dá, o humano precisa saber
      // exatamente qual arquivo ficou mutado e com o quê.
      console.error(`FALHA AO RESTAURAR ${caminho}: ${err.message}`);
      console.error('O FONTE FICOU MUTADO. Recupere com `git checkout -- <arquivo>`.');
    }
  };
  // 'exit' cobre saída normal e exceção não tratada; sinal não dispara 'exit'
  // sozinho, daí os handlers explícitos abaixo.
  process.on('exit', () => restaurar());
  for (const sinal of ['SIGINT', 'SIGTERM', 'SIGHUP', 'SIGBREAK']) {
    try {
      process.on(sinal, () => {
        restaurar();
        process.exit(1);
      });
    } catch { /* sinal inexistente nesta plataforma */ }
  }
}

// =================================================================== Execução

function main() {
  if (process.argv.length <= 2) {
    console.error(USO);
    process.exit(1);
  }

  const raiz = ler('raiz') || process.cwd();
  const rel = ler('arquivo');
  const de = ler('de');
  const para = ler('para');
  const bateria = ler('bateria');

  if (rel === null) erroUso('falta --arquivo');
  if (de === null) erroUso('falta --de');
  if (para === null) erroUso('falta --para');
  if (bateria === null) erroUso('falta --bateria');
  if (de === '') erroUso('--de vazio casaria em qualquer lugar e não inverte nada');
  if (bateria.trim() === '') erroUso('--bateria vazio');
  if (de === para) erroUso('--de e --para são iguais: isso não inverte comportamento nenhum');

  const timeout = Number(ler('timeout') ?? TIMEOUT_PADRAO);
  if (!Number.isFinite(timeout) || timeout <= 0) erroUso('--timeout precisa ser um número de ms positivo');

  if (!fs.existsSync(raiz) || !fs.statSync(raiz).isDirectory()) {
    console.error(`erro: --raiz não é uma pasta: ${raiz}`);
    process.exit(1);
  }
  const alvo = path.resolve(raiz, rel);
  if (!fs.existsSync(alvo) || !fs.statSync(alvo).isFile()) {
    console.error(`erro: --arquivo não existe: ${alvo}`);
    process.exit(1);
  }

  const original = fs.readFileSync(alvo);
  const texto = original.toString('utf8');
  const pedacos = texto.split(de);
  const ocorrencias = pedacos.length - 1;

  // D11 — antes de escrever qualquer byte e antes de rodar qualquer bateria.
  // Se o padrão não casa, NÃO há mutação, e o resultado da bateria (qualquer
  // que fosse) não diz nada sobre o conserto.
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

  console.log(`arquivo : ${alvo}`);
  console.log(`de      : ${JSON.stringify(de)}`);
  console.log(`para    : ${JSON.stringify(para)}`);
  console.log(`casou   : ${ocorrencias} ocorrência(s) — todas invertidas`);
  console.log(`bateria : ${bateria}`);
  console.log(`raiz    : ${raiz}`);
  console.log('');

  armarRestauracao(alvo, original);
  fs.writeFileSync(alvo, pedacos.join(para), 'utf8');

  const r = spawnSync(bateria, {
    shell: true,
    cwd: raiz,
    encoding: 'utf8',
    // stdin fechado: bateria que lê payload do stdin recebe EOF em vez de
    // pendurar (relatório de 2026-08-19, seção 6).
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout,
    maxBuffer: 32 * 1024 * 1024,
  });

  // Restaura ANTES de decidir e imprimir: nenhum caminho abaixo pode escapar
  // com o fonte mutado.
  restaurar();

  const saida = ultimasLinhas(`${r.stdout || ''}${r.stderr || ''}`, 20);
  console.log('--- últimas linhas da bateria ---');
  if (saida) console.log(saida);
  console.log('---------------------------------');
  console.log('');

  const estourou = r.error && r.error.code === 'ETIMEDOUT';
  if (estourou) {
    console.error(`BATERIA SEM VEREDITO: estourou o teto de ${timeout} ms e foi morta.`);
    console.error('  fonte restaurado. Sem exit code da bateria não há prova nenhuma.');
    process.exit(1);
  }
  if (r.error) {
    console.error(`BATERIA SEM VEREDITO: não consegui executar o comando — ${r.error.message}`);
    process.exit(1);
  }
  if (r.status === null) {
    console.error(`BATERIA SEM VEREDITO: morta pelo sinal ${r.signal}, sem exit code.`);
    process.exit(1);
  }

  if (r.status === 0) {
    console.error('RECUSADO: bateria VERDE com o comportamento invertido (exit 0).');
    console.error('  A mutação casou e foi aplicada — o fonte estava se comportando ao');
    console.error('  contrário enquanto a bateria rodava, e ela aprovou assim mesmo.');
    console.error('  Esta bateria não mede o conserto. Escreva o caso que o defeito quebrava.');
    process.exit(2);
  }

  console.log(`ok: bateria VERMELHA com o comportamento invertido (exit ${r.status}).`);
  console.log('    A bateria sabe falhar, e o fonte foi restaurado.');
  process.exit(0);
}

main();
