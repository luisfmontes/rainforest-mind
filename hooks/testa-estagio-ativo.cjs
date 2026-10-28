#!/usr/bin/env node
/**
 * Bateria de testes para o resolver de estágio ativo.
 *
 * Cria sandboxes git reais e verifica cada caso.
 * Saída: "todos os casos: OK" (exit 0) ou nome do caso com erro (exit 1)
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');
const { resolver, diagnosticar } = require('./lib/estagio-ativo.cjs');

// ============================================================================
// UTILITÁRIOS
// ============================================================================

function criarSandbox() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'estagio-ativo-'));

  // Inicializar repositório git
  execSync('git init', { cwd: tmpDir, stdio: 'ignore' });
  execSync('git config user.email "test@test"', { cwd: tmpDir, stdio: 'ignore' });
  execSync('git config user.name "Test"', { cwd: tmpDir, stdio: 'ignore' });

  // Criar branch inicial
  execSync('git checkout -b main', { cwd: tmpDir, stdio: 'ignore' });

  // Fazer commit inicial para que HEAD exista
  const readmeFile = path.join(tmpDir, 'README.md');
  fs.writeFileSync(readmeFile, 'test\n', 'utf8');
  execSync('git add README.md', { cwd: tmpDir, stdio: 'ignore' });
  execSync('git commit -m "init"', { cwd: tmpDir, stdio: 'ignore' });

  return tmpDir;
}

function lerEstado(slug, sandbox) {
  const filePath = path.join(sandbox, 'docs', 'rainforest', 'estado', `${slug}.json`);
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function gravarEstado(slug, sandbox, estado) {
  const dirEstado = path.join(sandbox, 'docs', 'rainforest', 'estado');
  fs.mkdirSync(dirEstado, { recursive: true });
  const filePath = path.join(dirEstado, `${slug}.json`);
  fs.writeFileSync(filePath, JSON.stringify(estado, null, 2) + '\n', 'utf8');
}

function criarBranch(sandbox, branchName) {
  execSync(`git checkout -b ${branchName}`, { cwd: sandbox, stdio: 'ignore' });
}

function limparSandbox(sandbox) {
  try {
    // Remover recursivamente — usa rmdir em Windows, rm em Unix
    const isWindows = process.platform === 'win32';
    if (isWindows) {
      execSync(`rmdir /s /q "${sandbox}"`, { stdio: 'ignore', shell: true });
    } else {
      execSync(`rm -rf "${sandbox}"`, { stdio: 'ignore' });
    }
  } catch (_) {
    // Falhar silenciosamente se não conseguir
  }
}

function novoEstado(slug, titulo) {
  return {
    slug,
    titulo: titulo || slug,
    criado_em: '2026-08-30',
    arqueologia: { status: 'pendente' },
    design: { status: 'pendente' },
    plano: { status: 'pendente' },
    executar: { status: 'pendente' },
    revisar: { status: 'pendente' },
    verificar: { status: 'pendente' },
    fechar: { status: 'pendente' },
  };
}

// ============================================================================
// CASOS DE TESTE
// ============================================================================

const casos = {};

casos['(a) um único estado aberto casando com a branch'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar estado com slug `2026-01-01-x` e branch `x`
    const estado = novoEstado('2026-01-01-x', 'Teste');
    gravarEstado('2026-01-01-x', sandbox, estado);

    // Criar branch `x`
    criarBranch(sandbox, 'x');

    const resultado = resolver({ cwd: sandbox });

    if (!resultado || resultado.slug !== '2026-01-01-x' || resultado.estagio !== 'design') {
      throw new Error(
        `esperado { slug: '2026-01-01-x', estagio: 'design' }, ` +
        `obtido ${JSON.stringify(resultado)}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['(b) dois estados com slug pós-data colido na mesma branch'] = function () {
  const sandbox = criarSandbox();
  try {
    // Dois estados: 2026-01-01-x.json e 2026-02-02-x.json
    // Ambos com slug pós-data `x`, ambos com estágio aberto
    const estado1 = novoEstado('2026-01-01-x', 'Teste 1');
    const estado2 = novoEstado('2026-02-02-x', 'Teste 2');

    gravarEstado('2026-01-01-x', sandbox, estado1);
    gravarEstado('2026-02-02-x', sandbox, estado2);

    // Branch `x`
    criarBranch(sandbox, 'x');

    const resultado = resolver({ cwd: sandbox });

    // Deve ser null (ambiguidade)
    if (resultado !== null) {
      throw new Error(`esperado null (ambiguidade), obtido ${JSON.stringify(resultado)}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['(c) nenhum estado'] = function () {
  const sandbox = criarSandbox();
  try {
    // Apenas criar a branch, nenhum estado
    criarBranch(sandbox, 'x');

    const resultado = resolver({ cwd: sandbox });

    if (resultado !== null) {
      throw new Error(`esperado null, obtido ${JSON.stringify(resultado)}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['(d) JSON inválido no diretório'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar um estado válido
    const estado = novoEstado('2026-01-01-x', 'Teste');
    gravarEstado('2026-01-01-x', sandbox, estado);

    // Criar um JSON inválido (deve ser ignorado)
    const dirEstado = path.join(sandbox, 'docs', 'rainforest', 'estado');
    fs.mkdirSync(dirEstado, { recursive: true });
    fs.writeFileSync(path.join(dirEstado, 'invalido.json'), 'não é JSON{', 'utf8');

    // Branch `x`
    criarBranch(sandbox, 'x');

    const resultado = resolver({ cwd: sandbox });

    // Deve encontrar o estado válido e ignorar o inválido
    if (!resultado || resultado.slug !== '2026-01-01-x' || resultado.estagio !== 'design') {
      throw new Error(
        `esperado { slug: '2026-01-01-x', estagio: 'design' }, ` +
        `obtido ${JSON.stringify(resultado)}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['(e) estado com plano.status "pendente"'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar estado com design fechado (aprovado) e plano pendente
    const estado = novoEstado('2026-01-01-x', 'Teste');
    estado.design.status = 'aprovado'; // Fecha design
    estado.plano.status = 'pendente'; // Plano aberto

    gravarEstado('2026-01-01-x', sandbox, estado);

    // Branch `x`
    criarBranch(sandbox, 'x');

    const resultado = resolver({ cwd: sandbox });

    // Deve retornar `estagio === 'plano'` (próximo estágio aberto)
    if (!resultado || resultado.estagio !== 'plano') {
      throw new Error(
        `esperado estagio: 'plano', ` +
        `obtido ${JSON.stringify(resultado)}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['(f) slug com numeracao de fluxo casa a branch sem ela'] = function () {
  // O caso REAL deste repositorio, medido em 2026-09-01: o estado do fluxo 9 se
  // chama `fluxo-9-portaria.json` e a branch dele e `fluxo/portaria`. A
  // convencao `<data>-<branch>` da regra 11 nao previa a numeracao, e sem esta
  // tolerancia o `resolver` devolvia `null` na branch de verdade — o que faz a
  // portaria, que e fail-closed, negar TODO despacho no repositorio que a
  // implementa. `fluxo-11-conselho` / `fluxo/conselho` tem a mesma forma.
  const sandbox = criarSandbox();
  try {
    const estado = novoEstado('fluxo-9-portaria', 'Fluxo 9');
    gravarEstado('fluxo-9-portaria', sandbox, estado);

    criarBranch(sandbox, 'fluxo/portaria');

    const resultado = resolver({ cwd: sandbox });

    if (!resultado || resultado.slug !== 'fluxo-9-portaria' || resultado.estagio !== 'design') {
      throw new Error(
        `esperado { slug: 'fluxo-9-portaria', estagio: 'design' }, ` +
        `obtido ${JSON.stringify(resultado)}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['(g) numeracao de fluxo nao afrouxa a ambiguidade'] = function () {
  // A tolerancia da (f) cria uma segunda forma de casar, e por isso ela tem de
  // ser exercida contra a trava que existe: `fluxo-9-portaria` e `portaria`
  // casam a MESMA branch, viram dois candidatos, e ambiguidade nega. Sem este
  // caso, a (f) poderia ter sido implementada trocando a igualdade por um
  // `includes` e ninguem veria.
  const sandbox = criarSandbox();
  try {
    gravarEstado('fluxo-9-portaria', sandbox, novoEstado('fluxo-9-portaria', 'Fluxo 9'));
    gravarEstado('2026-01-01-portaria', sandbox, novoEstado('2026-01-01-portaria', 'Outro'));

    criarBranch(sandbox, 'fluxo/portaria');

    const resultado = resolver({ cwd: sandbox });

    if (resultado !== null) {
      throw new Error(`esperado null (ambiguidade), obtido ${JSON.stringify(resultado)}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

// Issue #613/#610 (D2): branch de tarefa paralela `fluxo/<slug>-t<n>`.
// Estado com design aprovado e plano ok: o próximo estágio aberto é `executar`.
function novoEstadoExecutar(slug) {
  const estado = novoEstado(slug, slug);
  estado.design.status = 'aprovado';
  estado.plano.status = 'ok';
  return estado;
}

casos['branch fluxo/<slug>-t2 resolve para o fluxo <slug>'] = function () {
  const sandbox = criarSandbox();
  try {
    gravarEstado('2026-10-26-ficha-centralizada', sandbox, novoEstadoExecutar('2026-10-26-ficha-centralizada'));
    criarBranch(sandbox, 'fluxo/ficha-centralizada-t2');

    const resultado = resolver({ cwd: sandbox });

    if (!resultado || resultado.slug !== '2026-10-26-ficha-centralizada' || resultado.estagio !== 'executar') {
      throw new Error(
        `esperado { slug: '2026-10-26-ficha-centralizada', estagio: 'executar' }, ` +
        `obtido ${JSON.stringify(resultado)}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['branch fluxo/<slug>-t12 (dois digitos) resolve para o mesmo fluxo'] = function () {
  const sandbox = criarSandbox();
  try {
    gravarEstado('2026-10-26-ficha-centralizada', sandbox, novoEstadoExecutar('2026-10-26-ficha-centralizada'));
    criarBranch(sandbox, 'fluxo/ficha-centralizada-t12');

    const resultado = resolver({ cwd: sandbox });

    if (!resultado || resultado.slug !== '2026-10-26-ficha-centralizada' || resultado.estagio !== 'executar') {
      throw new Error(`esperado o fluxo ficha-centralizada em executar, obtido ${JSON.stringify(resultado)}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['branch fluxo/outro-t1 sem fluxo aberto com esse nome: null'] = function () {
  const sandbox = criarSandbox();
  try {
    gravarEstado('2026-10-26-ficha-centralizada', sandbox, novoEstadoExecutar('2026-10-26-ficha-centralizada'));
    criarBranch(sandbox, 'fluxo/outro-t1');

    const resultado = resolver({ cwd: sandbox });

    if (resultado !== null) {
      throw new Error(`esperado null (nenhum fluxo outro), obtido ${JSON.stringify(resultado)}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['branch com sufixo -t sem digitos ou -tx nao casa tarefa: null'] = function () {
  const sandbox = criarSandbox();
  try {
    gravarEstado('2026-10-26-ficha-centralizada', sandbox, novoEstadoExecutar('2026-10-26-ficha-centralizada'));
    for (const branchNome of ['fluxo/ficha-centralizada-tx', 'fluxo/ficha-centralizada-t']) {
      criarBranch(sandbox, branchNome);
      const resultado = resolver({ cwd: sandbox });
      if (resultado !== null) {
        throw new Error(`branch ${branchNome}: esperado null, obtido ${JSON.stringify(resultado)}`);
      }
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['fluxos x e x-t1 abertos, branch fluxo/x-t1: casamento exato vence (slug x-t1)'] = function () {
  const sandbox = criarSandbox();
  try {
    gravarEstado('x', sandbox, novoEstado('x', 'x'));
    gravarEstado('x-t1', sandbox, novoEstado('x-t1', 'x-t1'));
    criarBranch(sandbox, 'fluxo/x-t1');

    const resultado = resolver({ cwd: sandbox });

    if (!resultado || resultado.slug !== 'x-t1') {
      throw new Error(`esperado slug 'x-t1' (casamento exato), obtido ${JSON.stringify(resultado)}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['branch fluxo/<slug> sem sufixo continua resolvendo o fluxo (vizinho)'] = function () {
  const sandbox = criarSandbox();
  try {
    gravarEstado('2026-10-26-ficha-centralizada', sandbox, novoEstadoExecutar('2026-10-26-ficha-centralizada'));
    criarBranch(sandbox, 'fluxo/ficha-centralizada');

    const resultado = resolver({ cwd: sandbox });

    if (!resultado || resultado.slug !== '2026-10-26-ficha-centralizada' || resultado.estagio !== 'executar') {
      throw new Error(`esperado o fluxo ficha-centralizada em executar, obtido ${JSON.stringify(resultado)}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['diagnosticar: branch de tarefa conta o fluxo e cita a forma -t<n> no esperado'] = function () {
  const sandbox = criarSandbox();
  try {
    gravarEstado('2026-10-26-ficha-centralizada', sandbox, novoEstadoExecutar('2026-10-26-ficha-centralizada'));
    criarBranch(sandbox, 'fluxo/ficha-centralizada-t1');

    const diag = diagnosticar({ cwd: sandbox });

    if (!diag || diag.casados !== 1 || diag.abertos.length !== 1) {
      throw new Error(`esperado casados 1 e 1 aberto, obtido ${JSON.stringify(diag)}`);
    }
    if (!diag.abertos[0].esperado.includes('fluxo/ficha-centralizada-t<n>')) {
      throw new Error(`esperado esperado com a forma -t<n>, obtido '${diag.abertos[0].esperado}'`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

// ============================================================================
// EXECUTAR TESTES
// ============================================================================

function main() {
  const nomes = Object.keys(casos);
  let sucesso = 0;
  let falha = 0;

  for (const nome of nomes) {
    try {
      casos[nome]();
      sucesso++;
      console.log(`  ok   ${nome}`);
    } catch (err) {
      console.error(`ERRO em ${nome}:`);
      console.error(`  ${err.message}`);
      falha++;
    }
  }

  console.log('');
  console.log(`Casos executados: ${sucesso + falha}`);
  console.log(`Sucesso: ${sucesso}, Falha: ${falha}`);

  if (falha === 0) {
    console.log('todos os casos: OK');
    process.exit(0);
  } else {
    process.exit(1);
  }
}

main();
