#!/usr/bin/env node
/**
 * Bateria de testes para aviso-fluxo.cjs
 *
 * Cria sandboxes git reais com ou sem fluxo rainforest/protheus,
 * e verifica o comportamento do hook em cada caso.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync, spawnSync } = require('child_process');

// ============================================================================
// UTILITÁRIOS
// ============================================================================

function criarSandbox() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aviso-fluxo-'));

  // Inicializar repositório git
  execSync('git init', { cwd: tmpDir, stdio: 'ignore' });
  execSync('git config user.email "test@test"', { cwd: tmpDir, stdio: 'ignore' });
  execSync('git config user.name "Test"', { cwd: tmpDir, stdio: 'ignore' });

  // Criar branch inicial
  execSync('git checkout -b main', { cwd: tmpDir, stdio: 'ignore' });

  // Fazer commit inicial
  const readmeFile = path.join(tmpDir, 'README.md');
  fs.writeFileSync(readmeFile, 'test\n', 'utf8');
  execSync('git add README.md', { cwd: tmpDir, stdio: 'ignore' });
  execSync('git commit -m "init"', { cwd: tmpDir, stdio: 'ignore' });

  return tmpDir;
}

function limparSandbox(sandbox) {
  try {
    const isWindows = process.platform === 'win32';
    if (isWindows) {
      execSync(`rmdir /s /q "${sandbox}"`, { stdio: 'ignore', shell: true });
    } else {
      execSync(`rm -rf "${sandbox}"`, { stdio: 'ignore' });
    }
  } catch (_) {}
}

function criarBranch(sandbox, branchName) {
  execSync(`git checkout -b ${branchName}`, { cwd: sandbox, stdio: 'ignore' });
}

function novoEstadoRainforest(slug) {
  return {
    slug,
    titulo: slug,
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

function gravarEstadoRainforest(slug, sandbox, estado) {
  const dirEstado = path.join(sandbox, 'docs', 'rainforest', 'estado');
  fs.mkdirSync(dirEstado, { recursive: true });
  const filePath = path.join(dirEstado, `${slug}.json`);
  fs.writeFileSync(filePath, JSON.stringify(estado, null, 2) + '\n', 'utf8');
}

function criarGatesJsonProtheus(sandbox, backdate = false) {
  const dirPlans = path.join(sandbox, 'docs', 'plans');
  fs.mkdirSync(dirPlans, { recursive: true });
  const gatesPath = path.join(dirPlans, 'x.gates.json');
  fs.writeFileSync(gatesPath, JSON.stringify({ gates: [] }, null, 2) + '\n', 'utf8');

  // Se backdate = true, mover mtime para > 24h atrás
  if (backdate) {
    const umDiaEm_s = 24 * 3600;
    const old = (Date.now() / 1000) - (2 * umDiaEm_s); // 2 dias atrás
    fs.utimesSync(gatesPath, old, old);
  }

  return gatesPath;
}

function criarDirEstadoVazio(sandbox) {
  const dirEstado = path.join(sandbox, 'docs', 'rainforest', 'estado');
  fs.mkdirSync(dirEstado, { recursive: true });
}

function rodarHook(payload, cwd) {
  const hookPath = path.join(__dirname, 'aviso-fluxo.cjs');
  // process.execPath, nunca 'node' cru (#382); RFM_ROOT de caixa para o config
  // do usuario real nao decidir o caso.
  const result = spawnSync(process.execPath, [hookPath], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    cwd,
    env: { ...process.env, CLAUDE_PROJECT_DIR: cwd, RFM_ROOT: path.join(cwd, '.dados-teste') },
  });
  if (result.status !== 0) {
    throw new Error(`hook saiu ${result.status}, stderr: ${result.stderr}`);
  }
  return {
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    status: result.status,
  };
}

function extrairAdditionalContext(jsonString) {
  try {
    const obj = JSON.parse(jsonString);
    return obj?.hookSpecificOutput?.additionalContext || null;
  } catch {
    return null;
  }
}

// ============================================================================
// CASOS DE TESTE
// ============================================================================

const casos = {};

casos['rainforest sem fluxo aberto: aviso na primeira edicao'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar diretório de estado vazio (repo tem fluxo, mas nenhum aberto)
    criarDirEstadoVazio(sandbox);

    // Criar branch e arquivo de código
    criarBranch(sandbox, 'test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    // Rodar hook com Edit de scripts/x.cjs
    const payload = {
      session_id: 'sess-1',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath },
    };
    const result = rodarHook(payload, sandbox);

    // Deve conter "fluxo rainforest"
    const ctx = extrairAdditionalContext(result.stdout);
    if (!ctx || !ctx.includes('fluxo rainforest')) {
      throw new Error(
        `esperado contexto com "fluxo rainforest", obtido: ${result.stdout}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['config aviso-fluxo false e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    criarDirEstadoVazio(sandbox);
    criarBranch(sandbox, 'test');
    fs.mkdirSync(path.join(sandbox, '.rainforest'), { recursive: true });
    fs.writeFileSync(path.join(sandbox, '.rainforest', 'config.json'), JSON.stringify({ 'aviso-fluxo': false }));
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');
    const payload = { session_id: 'sess-cfg', cwd: sandbox, tool_name: 'Edit', tool_input: { file_path: scriptPath } };
    const result = rodarHook(payload, sandbox);
    if (result.stdout.trim() !== '') {
      throw new Error(`config false: esperado vazio, obtido: ${result.stdout}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['segunda edicao de codigo na mesma sessao e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar diretório de estado vazio (repo tem fluxo rainforest, mas nenhum aberto)
    criarDirEstadoVazio(sandbox);

    criarBranch(sandbox, 'test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      session_id: 'sess-2',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath },
    };

    // Primeira chamada: deve avisar
    const result1 = rodarHook(payload, sandbox);
    const ctx1 = extrairAdditionalContext(result1.stdout);
    if (!ctx1 || !ctx1.includes('fluxo')) {
      throw new Error(`primeira edição: esperado aviso, obtido vazio`);
    }

    // Segunda chamada com mesma sessão: deve estar silencioso
    const result2 = rodarHook(payload, sandbox);
    const ctx2 = extrairAdditionalContext(result2.stdout);
    if (ctx2) {
      throw new Error(`segunda edição: esperado vazio, obtido: ${result2.stdout}`);
    }

    // Verificar que a memória foi gravada em <git-dir>/rainforest-aviso-fluxo.json
    const gitDirPath = path.join(sandbox, '.git');
    const memoriaPath = path.join(gitDirPath, 'rainforest-aviso-fluxo.json');
    if (!fs.existsSync(memoriaPath)) {
      throw new Error(`memória não gravada em ${memoriaPath}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['.md ou arquivo sob docs/ e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar diretório de estado vazio (repo tem fluxo rainforest, mas nenhum aberto)
    criarDirEstadoVazio(sandbox);

    criarBranch(sandbox, 'test');

    // Arquivo .md
    const mdPath = path.join(sandbox, 'README.md');
    fs.writeFileSync(mdPath, '# Test\n', 'utf8');

    const payload1 = {
      session_id: 'sess-3',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: mdPath },
    };
    const result1 = rodarHook(payload1, sandbox);
    const ctx1 = extrairAdditionalContext(result1.stdout);
    if (ctx1) {
      throw new Error(`arquivo .md: esperado vazio, obtido: ${result1.stdout}`);
    }

    // Arquivo sob docs/
    const docsPath = path.join(sandbox, 'docs', 'design', 'x.cjs');
    fs.mkdirSync(path.dirname(docsPath), { recursive: true });
    fs.writeFileSync(docsPath, 'console.log("test");\n', 'utf8');

    const payload2 = {
      session_id: 'sess-4',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: docsPath },
    };
    const result2 = rodarHook(payload2, sandbox);
    const ctx2 = extrairAdditionalContext(result2.stdout);
    if (ctx2) {
      throw new Error(`arquivo em docs/: esperado vazio, obtido: ${result2.stdout}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['fluxo aberto na branch e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar estado com estágio ABERTO casando a branch (fluxo ativo)
    const estado = novoEstadoRainforest('2026-01-01-test');
    // Deixar com estagio pendente (design) para resolver retornar non-null
    gravarEstadoRainforest('2026-01-01-test', sandbox, estado);

    // Criar branch fluxo/test que casa com o slug 'test'
    criarBranch(sandbox, 'fluxo/test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      session_id: 'sess-5',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath },
    };
    const result = rodarHook(payload, sandbox);
    const ctx = extrairAdditionalContext(result.stdout);
    if (ctx) {
      throw new Error(`fluxo fechado: esperado vazio, obtido: ${result.stdout}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['agent_id presente e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar diretório de estado vazio (repo tem fluxo rainforest, mas nenhum aberto)
    criarDirEstadoVazio(sandbox);

    criarBranch(sandbox, 'test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      agent_id: 'subagent-123',
      session_id: 'sess-6',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath },
    };
    const result = rodarHook(payload, sandbox);
    const ctx = extrairAdditionalContext(result.stdout);
    if (ctx) {
      throw new Error(`com agent_id: esperado vazio, obtido: ${result.stdout}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['protheus: aviso nomeando o trilho e skill'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar gates.json protheus com mtime > 24h (para simular fluxo não ativo)
    const gatesPath = criarGatesJsonProtheus(sandbox, true);

    // Arquivo de código (já em main, que foi criado em criarSandbox)
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      session_id: 'sess-7',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath },
    };
    const result = rodarHook(payload, sandbox);

    const ctx = extrairAdditionalContext(result.stdout);
    if (!ctx || !ctx.includes('protheus') || !ctx.includes('/protheus:trabalhar')) {
      throw new Error(
        `protheus: esperado contexto com "protheus" e "/protheus:trabalhar", obtido: ${result.stdout}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['sem rainforest nem protheus e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    // Não criar nem rainforest nem protheus
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      session_id: 'sess-8',
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath },
    };
    const result = rodarHook(payload, sandbox);
    const ctx = extrairAdditionalContext(result.stdout);
    if (ctx) {
      throw new Error(
        `sem fluxo nenhum: esperado vazio, obtido: ${result.stdout}`
      );
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['payload vazio e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    criarDirEstadoVazio(sandbox);

    const result = rodarHook({}, sandbox);
    const ctx = extrairAdditionalContext(result.stdout);
    if (ctx) {
      throw new Error(`payload vazio: esperado vazio, obtido: ${result.stdout}`);
    }
  } finally {
    limparSandbox(sandbox);
  }
};

casos['sem session_id: avisa mas nao memoriza'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar diretório de estado vazio
    criarDirEstadoVazio(sandbox);

    criarBranch(sandbox, 'test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    // Primeira chamada sem session_id
    const payload1 = {
      cwd: sandbox,
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath },
    };
    const result1 = rodarHook(payload1, sandbox);
    const ctx1 = extrairAdditionalContext(result1.stdout);
    if (!ctx1 || !ctx1.includes('fluxo')) {
      throw new Error(`sem session_id primeira: esperado aviso`);
    }

    // Segunda chamada também sem session_id (não memoriza, então avisa novamente)
    const result2 = rodarHook(payload1, sandbox);
    const ctx2 = extrairAdditionalContext(result2.stdout);
    if (!ctx2 || !ctx2.includes('fluxo')) {
      throw new Error(`sem session_id segunda: esperado aviso (sem memória)`);
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
      console.log(`ok: ${nome}`);
      sucesso++;
    } catch (err) {
      console.error(`falha: ${nome}`);
      console.error(`  ${err.message}`);
      falha++;
    }
  }

  console.log('');
  console.log(`${sucesso} ok, ${falha} falha(s)`);

  if (falha === 0) {
    process.exit(0);
  } else {
    process.exit(1);
  }
}

main();
