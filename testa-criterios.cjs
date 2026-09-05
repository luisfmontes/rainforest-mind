#!/usr/bin/env node
/**
 * Testa os 9 critérios de sucesso para o gate-agente-em-voo
 */

const { execSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const cwd = process.cwd();
const hook = path.join(cwd, 'hooks', 'gate-agente-em-voo.cjs');

let testes_OK = 0;
let testes_FALHARAM = 0;

function teste(n, descricao, fn) {
  console.log(`\n【${n}】 ${descricao}`);
  try {
    fn();
    console.log(`  ✓ PASSOU`);
    testes_OK++;
  } catch (e) {
    console.log(`  ✗ FALHOU: ${e.message}`);
    testes_FALHARAM++;
  }
}

function runHook(payload) {
  const proc = spawnSync('node', [hook], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  return { exit: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

function assertEquals(actual, expected, msg) {
  if (actual !== expected) {
    throw new Error(`${msg}: esperado ${expected}, obtido ${actual}`);
  }
}

// ============================================================================
// TESTE 1
// ============================================================================
teste(1, 'Estado marcado com em_voo + stop_hook_active=false → exit 2 com mensagem', () => {
  // Garante que o estado tem em_voo
  execSync(`node scripts/estado.cjs marcar --slug 2026-09-04-worktree-agent-ad251062fd468da54 --estagio revisar --status parcial --json '{"em_voo":[{"agente":"revisor-teste","tarefa":"test","desde":"2026-09-04T10:00:00Z"}]}'`, {stdio: 'ignore'});

  const result = runHook({ cwd, stop_hook_active: false });
  assertEquals(result.exit, 2, 'exit code');
  if (!result.stderr.includes('revisor-teste')) {
    throw new Error('mensagem não nomeia agente revisor-teste');
  }
  if (!result.stderr.includes('revisar')) {
    throw new Error('mensagem não nomeia estágio revisar');
  }
});

// ============================================================================
// TESTE 2
// ============================================================================
teste(2, 'Mesmo payload com stop_hook_active=true → exit 0', () => {
  const result = runHook({ cwd, stop_hook_active: true });
  assertEquals(result.exit, 0, 'exit code');
});

// ============================================================================
// TESTE 3
// ============================================================================
teste(3, 'Depois de marcar ok, em_voo desaparece e exit 0', () => {
  execSync(`node scripts/estado.cjs marcar --slug 2026-09-04-worktree-agent-ad251062fd468da54 --estagio revisar --status ok --json '{"achados":0}'`, {stdio: 'ignore'});

  // Verifica que em_voo saiu do JSON
  const estado = JSON.parse(fs.readFileSync(
    path.join(cwd, 'docs', 'rainforest', 'estado', '2026-09-04-worktree-agent-ad251062fd468da54.json'),
    'utf8'
  ));

  if (estado.revisar && estado.revisar.em_voo) {
    throw new Error('em_voo ainda está no bloco revisar');
  }

  // Verifica que hook retorna exit 0
  const result = runHook({ cwd, stop_hook_active: false });
  assertEquals(result.exit, 0, 'exit code sem em_voo');
});

// ============================================================================
// TESTE 4
// ============================================================================
teste(4, 'Payload vazio → exit 0', () => {
  const result = runHook({});
  assertEquals(result.exit, 0, 'exit code');
});

// ============================================================================
// TESTE 5
// ============================================================================
teste(5, 'Payload ilegível → exit 0', () => {
  const proc = spawnSync('node', [hook], {
    input: 'isto nao e json',
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  assertEquals(proc.status, 0, 'exit code');
});

// ============================================================================
// TESTE 6
// ============================================================================
teste(6, 'RAINFOREST_GATE_OFF=1 libera → exit 0', () => {
  // Recoloca em_voo para testar
  execSync(`node scripts/estado.cjs marcar --slug 2026-09-04-worktree-agent-ad251062fd468da54 --estagio revisar --status parcial --json '{"em_voo":[{"agente":"teste","tarefa":"test","desde":"2026-09-04"}]}'`, {stdio: 'ignore'});

  const proc = spawnSync('node', [hook], {
    input: JSON.stringify({ cwd, stop_hook_active: false }),
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, RAINFOREST_GATE_OFF: '1' },
  });
  assertEquals(proc.status, 0, 'exit code com RAINFOREST_GATE_OFF');
});

// ============================================================================
// TESTE 7
// ============================================================================
teste(7, '.rainforest-gate-off libera → exit 0', () => {
  const gateOff = path.join(cwd, '.rainforest-gate-off');
  fs.writeFileSync(gateOff, '');

  try {
    const result = runHook({ cwd, stop_hook_active: false });
    assertEquals(result.exit, 0, 'exit code com .rainforest-gate-off');
  } finally {
    fs.rmSync(gateOff);
  }
});

// ============================================================================
// TESTE 8
// ============================================================================
teste(8, 'Repositório sem fluxo aberto → exit 0', () => {
  // Temporariamente renomeia o arquivo de estado
  const caminho = path.join(cwd, 'docs', 'rainforest', 'estado', '2026-09-04-worktree-agent-ad251062fd468da54.json');
  const backup = caminho + '.backup';
  fs.renameSync(caminho, backup);

  try {
    const result = runHook({ cwd, stop_hook_active: false });
    assertEquals(result.exit, 0, 'exit code sem estado');
  } finally {
    fs.renameSync(backup, caminho);
  }
});

// ============================================================================
// TESTE 9 - BONUS: Testar que hook bloqueia UMA VEZ (primeira vez)
// ============================================================================
teste(9, 'Hook bloqueia uma vez só (primeira) — segunda com stop_hook_active=true passa', () => {
  // Recoloca em_voo
  execSync(`node scripts/estado.cjs marcar --slug 2026-09-04-worktree-agent-ad251062fd468da54 --estagio revisar --status parcial --json '{"em_voo":[{"agente":"teste","tarefa":"test","desde":"2026-09-04"}]}'`, {stdio: 'ignore'});

  // Primeira chamada com false → bloqueia
  const result1 = runHook({ cwd, stop_hook_active: false });
  assertEquals(result1.exit, 2, 'primeira chamada com false → exit 2');

  // Segunda chamada com true → passa
  const result2 = runHook({ cwd, stop_hook_active: true });
  assertEquals(result2.exit, 0, 'segunda chamada com true → exit 0');
});

// ============================================================================
// Resultado final
// ============================================================================

console.log(`\n${'═'.repeat(60)}`);
console.log(`Total: ${testes_OK + testes_FALHARAM} testes`);
console.log(`✓ ${testes_OK} passou`);
if (testes_FALHARAM > 0) {
  console.log(`✗ ${testes_FALHARAM} falhou`);
  process.exit(1);
} else {
  console.log(`✓ Todos os critérios passaram!`);
  process.exit(0);
}
