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
const { resolver } = require('./lib/estagio-ativo.cjs');

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
