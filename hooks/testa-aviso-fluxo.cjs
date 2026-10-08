#!/usr/bin/env node
/**
 * Bateria de testes para aviso-fluxo.cjs
 *
 * Cria sandboxes git reais com ou sem fluxo rainforest/protheus e verifica o
 * comportamento do hook em cada caso. Desde #430 (design 2026-10-08-fluxo-pulado-bloqueio)
 * o hook bloqueia (exit 2, mensagem em stderr) em vez de avisar. Os casos de bloqueio
 * e de passe estão na bateria testa-bloqueio-fluxo.cjs; aqui ficam os vizinhos.
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
  return {
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    status: result.status,
  };
}

// Dois ramos: bloqueio (exit 2 + stderr) e passe (exit 0 + saída vazia).
function bloqueou(result, trecho) {
  if (result.status !== 2) return `esperado exit 2, obtido ${result.status}: ${result.stdout}${result.stderr}`;
  if (trecho && !result.stderr.includes(trecho)) return `stderr sem "${trecho}": ${result.stderr}`;
  return null;
}

function passou(result) {
  if (result.status !== 0) return `esperado exit 0, obtido ${result.status}: ${result.stderr}`;
  if (result.stdout !== '' || result.stderr !== '') return `esperado saida vazia: ${result.stdout}${result.stderr}`;
  return null;
}

// ============================================================================
// CASOS DE TESTE
// ============================================================================

const casos = {};

casos['rainforest sem fluxo aberto: bloqueia na primeira edicao'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar diretório de estado vazio (repo tem fluxo, mas nenhum aberto)
    criarDirEstadoVazio(sandbox);

    // Criar branch e arquivo de código
    criarBranch(sandbox, 'test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      session_id: 'sess-1',
      cwd: sandbox,
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' },
    };
    const erro = bloqueou(rodarHook(payload, sandbox), 'fluxo rainforest');
    if (erro) throw new Error(erro);
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
    const payload = { session_id: 'sess-cfg', cwd: sandbox, hook_event_name: 'PreToolUse', tool_name: 'Edit', tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' } };
    const erro = passou(rodarHook(payload, sandbox));
    if (erro) throw new Error(`config false: ${erro}`);
  } finally {
    limparSandbox(sandbox);
  }
};

casos['segunda edicao de codigo na mesma sessao tambem bloqueia (D8)'] = function () {
  const sandbox = criarSandbox();
  try {
    criarDirEstadoVazio(sandbox);
    criarBranch(sandbox, 'test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      session_id: 'sess-2',
      cwd: sandbox,
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' },
    };

    const erro1 = bloqueou(rodarHook(payload, sandbox), 'fluxo rainforest');
    if (erro1) throw new Error(`primeira edição: ${erro1}`);

    // Segunda chamada, mesma sessão: continua bloqueando (a memória não decide mais)
    const erro2 = bloqueou(rodarHook(payload, sandbox), 'fluxo rainforest');
    if (erro2) throw new Error(`segunda edição: ${erro2}`);
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
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: mdPath, old_string: 'a', new_string: 'b' },
    };
    const erro1 = passou(rodarHook(payload1, sandbox));
    if (erro1) throw new Error(`arquivo .md: ${erro1}`);

    // Arquivo sob docs/
    const docsPath = path.join(sandbox, 'docs', 'design', 'x.cjs');
    fs.mkdirSync(path.dirname(docsPath), { recursive: true });
    fs.writeFileSync(docsPath, 'console.log("test");\n', 'utf8');

    const payload2 = {
      session_id: 'sess-4',
      cwd: sandbox,
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: docsPath, old_string: 'a', new_string: 'b' },
    };
    const erro2 = passou(rodarHook(payload2, sandbox));
    if (erro2) throw new Error(`arquivo em docs/: ${erro2}`);
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
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' },
    };
    const erro = passou(rodarHook(payload, sandbox));
    if (erro) throw new Error(`fluxo aberto: ${erro}`);
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
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' },
    };
    const erro = passou(rodarHook(payload, sandbox));
    if (erro) throw new Error(`com agent_id: ${erro}`);
  } finally {
    limparSandbox(sandbox);
  }
};

casos['protheus: bloqueia nomeando o trilho e skill'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar gates.json protheus com mtime > 24h (para simular fluxo não ativo)
    criarGatesJsonProtheus(sandbox, true);

    // Arquivo de código (já em main, que foi criado em criarSandbox)
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    const payload = {
      session_id: 'sess-7',
      cwd: sandbox,
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' },
    };
    const erro = bloqueou(rodarHook(payload, sandbox), '/protheus:trabalhar');
    if (erro) throw new Error(`protheus: ${erro}`);
    const erroTrilho = bloqueou(rodarHook(payload, sandbox), 'protheus');
    if (erroTrilho) throw new Error(`protheus sem o nome do trilho: ${erroTrilho}`);
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
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' },
    };
    const erro = passou(rodarHook(payload, sandbox));
    if (erro) throw new Error(`sem fluxo nenhum: ${erro}`);
  } finally {
    limparSandbox(sandbox);
  }
};

casos['payload vazio e silencio'] = function () {
  const sandbox = criarSandbox();
  try {
    criarDirEstadoVazio(sandbox);

    const erro = passou(rodarHook({}, sandbox));
    if (erro) throw new Error(`payload vazio: ${erro}`);
  } finally {
    limparSandbox(sandbox);
  }
};

casos['sem session_id: bloqueia tambem sem memoria'] = function () {
  const sandbox = criarSandbox();
  try {
    // Criar diretório de estado vazio
    criarDirEstadoVazio(sandbox);

    criarBranch(sandbox, 'test');
    const scriptPath = path.join(sandbox, 'scripts', 'x.cjs');
    fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
    fs.writeFileSync(scriptPath, 'console.log("test");\n', 'utf8');

    // Sem session_id: a memória por sessão não existe, e o bloqueio vale do mesmo jeito
    const payload1 = {
      cwd: sandbox,
      hook_event_name: 'PreToolUse',
      tool_name: 'Edit',
      tool_input: { file_path: scriptPath, old_string: 'a', new_string: 'b' },
    };
    const erro1 = bloqueou(rodarHook(payload1, sandbox), 'fluxo');
    if (erro1) throw new Error(`sem session_id primeira: ${erro1}`);

    const erro2 = bloqueou(rodarHook(payload1, sandbox), 'fluxo');
    if (erro2) throw new Error(`sem session_id segunda: ${erro2}`);
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
