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
 * Exit codes:
 *   0  Manifesto íntegro e formato válido.
 *   1  Manifesto alterado OU formato inválido.
 *   2  Slug inexistente, uso errado, ou git falhou.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const EXIT_RECUSA = 1;

function arg(nome) {
  const i = process.argv.indexOf(`--${nome}`);
  return (i === -1 || i + 1 >= process.argv.length) ? null : process.argv[i + 1];
}

function uso() {
  console.error(`uso: node scripts/conferir-regua.cjs conferir --slug <slug>`);
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

  if (res.error) {
    return null;
  }
  if (res.status !== 0) {
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
 * Retorna { valido: true } se tudo ok.
 * Retorna { valido: false, exitCode: 1 ou 2 } se há erro.
 * Nunca faz process.exit para que a tarefa 2 possa usar a função.
 */
function exigirAncoraEFormato(slug) {
  const caminhoManifesto = `docs/rainforest/reguas/${slug}.md`;

  // Verifica se o arquivo existe na árvore de trabalho
  if (!fs.existsSync(caminhoManifesto)) {
    console.error(`arquivo não encontrado: ${caminhoManifesto}`);
    return { valido: false, exitCode: 2 };
  }

  // Resolve a âncora
  const ancora = ancoraDe(slug);
  if (!ancora) {
    console.error(`manifesto nunca foi commitado: ${caminhoManifesto}`);
    return { valido: false, exitCode: EXIT_RECUSA };
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
    return { valido: false, exitCode: EXIT_RECUSA };
  }

  const conteudoCommit = resShow.stdout;
  const conteudoArquivo = fs.readFileSync(caminhoManifesto, 'utf8');

  // Compara conteudo
  if (conteudoCommit !== conteudoArquivo) {
    console.error(`manifesto editado na arvore de trabalho: ${caminhoManifesto}`);
    return { valido: false, exitCode: EXIT_RECUSA };
  }

  // Valida formato
  // Remove \r para lidar com CRLF no Windows
  const linhas = conteudoCommit.replace(/\r/g, '').split('\n');

  // Procura pela secao "## Freios"
  const temFreios = linhas.some(linha => linha === '## Freios');
  if (!temFreios) {
    console.error(`secao obrigatoria ausente: ## Freios (${caminhoManifesto})`);
    return { valido: false, exitCode: EXIT_RECUSA };
  }

  // Procura por cabecalhos ### M<n>
  const regexM = /^### M(\d+)(?:\s|$)/;
  const numerosM = [];

  for (const linha of linhas) {
    const match = linha.match(regexM);
    if (match) {
      numerosM.push(parseInt(match[1], 10));
    }
  }

  // Valida: 5 a 7 mecanismos
  if (numerosM.length < 5 || numerosM.length > 7) {
    console.error(`quantidade invalida de mecanismos: ${numerosM.length} (esperado 5-7) (${caminhoManifesto})`);
    return { valido: false, exitCode: EXIT_RECUSA };
  }

  // Valida: sequencial a partir de 1, sem buraco e sem repetido
  for (let i = 0; i < numerosM.length; i++) {
    if (numerosM[i] !== i + 1) {
      console.error(`mecanismos nao sequenciais ou com buraco: ${numerosM.join(', ')} (${caminhoManifesto})`);
      return { valido: false, exitCode: EXIT_RECUSA };
    }
  }

  return { valido: true };
}

// ============== Main

const subcomando = process.argv[2];
const slug = arg('slug');

if (subcomando === 'conferir') {
  if (!slug) {
    uso();
    process.exit(2);
  }

  const resultado = exigirAncoraEFormato(slug);
  if (resultado.valido) {
    process.exit(0);
  } else {
    process.exit(resultado.exitCode);
  }
} else {
  uso();
  process.exit(2);
}
