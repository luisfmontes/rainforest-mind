#!/usr/bin/env node
// @categoria: sensor
/**
 * Conferidor de régua selada — valida que o manifesto não foi alterado
 * desde sua adição ao repo, e que tem o formato exigido.
 *
 * POR QUE EXISTE. Em karpathy/autoresearch, o juiz (`evaluate_bpb` em
 * `prepare.py`) é protegido só por uma linha de markdown — a régua deste repo
 * também era. Este script selada a régua por construção: git é o selo, não
 * hash próprio (D1). O crítico da régua é um agente novo a cada rodada e não
 * herda contexto da conversa — o que não estiver em disco não chega nele.
 *
 * NENHUMA PROTECAO CONTRA: orquestrador que não chama o script, rebase do
 * commit de adição, semântica vazia de seção "Freios" ou cabeçalhos M<n>
 * (validamos presença, não conteúdo).
 *
 * Uso:
 *   node scripts/conferir-regua.cjs conferir --slug <slug>
 *     Valida que o manifesto <slug> não foi alterado e tem formato válido.
 *     Exit 0: tudo ok. Exit 1: veredito negativo. Exit 2: uso errado ou
 *             arquivo inexistente.
 *
 *   node scripts/conferir-regua.cjs mostrar --slug <slug>
 *     Valida que o manifesto <slug> não foi alterado e tem formato válido.
 *     Se válido, imprime o conteúdo do commit-âncora em stdout.
 *     Exit 0: tudo ok. Exit 1: manifesto alterado ou formato inválido.
 *             Exit 2: slug inexistente ou git falhou.
 *
 * Exit codes:
 *   0  Manifesto íntegro e formato válido (conferir: sucesso; mostrar: imprimiu conteúdo).
 *   1  Manifesto alterado OU formato inválido.
 *   2  Slug inexistente, uso errado, ou git falhou.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const EXIT_RECUSA = 1;
const EXIT_GIT_FALHOU = 2;

/**
 * Normaliza fins de linha: reduz \r\n e \r a \n.
 * Necessário para comparar conteúdo entre git (sempre LF) e arquivo
 * em disco (pode ser CRLF com core.autocrlf=true).
 */
function normalizarEol(texto) {
  return texto.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return (i === -1 || i + 1 >= process.argv.length) ? null : process.argv[i + 1];
}

function uso() {
  console.error(`uso: node scripts/conferir-regua.cjs conferir --slug <slug>`);
  console.error(`      node scripts/conferir-regua.cjs mostrar --slug <slug>`);
}

/**
 * Resolve a âncora do manifesto: commit em que foi adicionado.
 * Devolve a string do hash SHA1, ou null se não encontrado.
 */
function ancoraDe(slug) {
  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;

  const res = spawnSync('git', [
    'log',
    '--diff-filter=A',
    '--format=%H',
    '--',
    caminhoManifesto,
  ], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  // AMBIENTE (2) vs. VEREDITO (1), e a distincao nao se faz por texto de erro.
  // `git log` sai != 0 em DOIS casos muito diferentes: o git nao executou, e o
  // repositorio nao tem commit nenhum ainda. O segundo e "manifesto nunca
  // commitado", que e veredito legitimo sobre o trabalho. Quem separa os dois e
  // um `git rev-parse --git-dir`: se ELE responde, o git existe e estamos num
  // repositorio, entao a falha do `log` so pode ser ausencia de commit.
  if (res.error || res.status !== 0) {
    const sonda = spawnSync('git', ['rev-parse', '--git-dir'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (sonda.error || sonda.status !== 0) {
      console.error(`git indisponivel ou fora de repositorio ao resolver a ancora de ${slug}`);
      process.exit(EXIT_GIT_FALHOU);
    }
    return null;
  }

  const linhas = res.stdout.trim().split(/\r?\n/).filter(Boolean);
  if (linhas.length === 0) {
    return null;
  }

  return linhas[linhas.length - 1];
}

/**
 * Resolve a âncora, valida que existe, valida o formato do manifesto.
 * Retorna a string do hash (âncora) se tudo ok.
 * Faz process.exit(1 ou 2) se há erro. Nunca retorna em caso de falha.
 */
function exigirAncoraEFormato(slug) {
  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;

  // Verifica se o arquivo existe na árvore de trabalho
  if (!fs.existsSync(caminhoManifesto)) {
    console.error(`arquivo não encontrado: ${caminhoManifesto}`);
    process.exit(2);
  }

  // Resolve a âncora
  const ancora = ancoraDe(slug);
  if (!ancora) {
    console.error(`manifesto nunca foi commitado: ${caminhoManifesto}`);
    process.exit(EXIT_RECUSA);
  }

  // Lê o conteúdo do commit
  const resShow = spawnSync('git', [
    'show',
    `${ancora}:${caminhoManifesto}`,
  ], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, MSYS_NO_PATHCONV: '1' },
  });

  if (resShow.error || resShow.status !== 0) {
    console.error(`erro ao ler conteudo do commit ${ancora}: ${caminhoManifesto}`);
    process.exit(EXIT_GIT_FALHOU);
  }

  const conteudoCommit = resShow.stdout;
  const conteudoArquivo = fs.readFileSync(caminhoManifesto, 'utf8');

  // Compara conteudo (normalizado para EOL)
  if (normalizarEol(conteudoCommit) !== normalizarEol(conteudoArquivo)) {
    console.error(`manifesto editado na arvore de trabalho: ${caminhoManifesto}`);
    process.exit(EXIT_RECUSA);
  }

  // Valida formato (normaliza EOL primeiro)
  const linhas = normalizarEol(conteudoCommit).split('\n');

  // Procura pela secao "## Freios"
  const temFreios = linhas.some(linha => linha === '## Freios');
  if (!temFreios) {
    console.error(`secao obrigatoria ausente: ## Freios (${caminhoManifesto})`);
    process.exit(EXIT_RECUSA);
  }

  // Procura por cabecalhos ### M<n>
  const regexM = /^### M(\d+)(?:\s|$)/;
  const regexMQualquer = /^### M/;
  const numerosM = [];
  let primeiraLinhaOffensora = null;

  for (const linha of linhas) {
    const match = linha.match(regexM);
    if (match) {
      numerosM.push(parseInt(match[1], 10));
    } else if (regexMQualquer.test(linha)) {
      // Tem "### M" mas não casa o padrão
      if (!primeiraLinhaOffensora) {
        primeiraLinhaOffensora = linha;
      }
    }
  }

  // Valida: 5 a 7 mecanismos, com formato correto
  if (numerosM.length < 5 || numerosM.length > 7) {
    if (numerosM.length === 0 && primeiraLinhaOffensora) {
      // Tem "### M" mas formato errado
      console.error(`cabecalho de mecanismo fora do formato '### M<n> ': ${primeiraLinhaOffensora} (${caminhoManifesto})`);
    } else {
      console.error(`quantidade invalida de mecanismos: ${numerosM.length} (esperado 5-7) (${caminhoManifesto})`);
    }
    process.exit(EXIT_RECUSA);
  }

  // Valida: sequencial a partir de 1, sem buraco e sem repetido
  for (let i = 0; i < numerosM.length; i++) {
    if (numerosM[i] !== i + 1) {
      console.error(`mecanismos nao sequenciais ou com buraco: ${numerosM.join(', ')} (${caminhoManifesto})`);
      process.exit(EXIT_RECUSA);
    }
  }

  return ancora;
}

// ============== Main

const subcomando = process.argv[2];
const slug = arg('slug');

if (subcomando === 'conferir') {
  if (!slug) {
    uso();
    process.exit(2);
  }

  exigirAncoraEFormato(slug);
  process.exit(0);
} else if (subcomando === 'mostrar') {
  if (!slug) {
    uso();
    process.exit(2);
  }

  const ancora = exigirAncoraEFormato(slug);
  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;

  const resShow = spawnSync('git', [
    'show',
    `${ancora}:${caminhoManifesto}`,
  ], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, MSYS_NO_PATHCONV: '1' },
  });

  if (resShow.error || resShow.status !== 0) {
    process.exit(EXIT_GIT_FALHOU);
  }

  process.stdout.write(resShow.stdout);
  process.exit(0);
} else {
  uso();
  process.exit(2);
}
