#!/usr/bin/env node
/**
 * Bateria para gate-turno-prometido.cjs
 *
 * Testa os sete casos definidos no plano:
 * 1. promete-sem-despachar: exit 2
 * 2. promete-e-despacha: exit 0
 * 3. despacho-so-no-turno-anterior: exit 2
 * 4. promessa-antes-do-tool-result: exit 0
 * 5. espera-ci-sem-vigia: exit 2
 * 6. espera-ci-com-background: exit 0
 * 7. passado-despachei: exit 0
 * 8. promete sem despachar com stop_hook_active true: exit 0
 * 9. payload com agent_id: exit 0
 * 10. transcricao ausente ou ilegivel: exit 0
 * 11. chave desligada: exit 0
 * 12. fixtures no formato real
 * 13. testa-config.sh passa
 * 14. testa-conferir-categoria.sh passa
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');

const hookPath = path.join(__dirname, 'gate-turno-prometido.cjs');
const fixtureDir = path.join(__dirname, 'fixtures', 'turno-prometido');
const hookJsonPath = path.join(__dirname, 'hooks.json');

let ok = 0;
let falha = 0;
const tmpdirsCriados = [];

function teste(nome, fn) {
  try {
    fn();
    console.log(`  ok   ${nome}`);
    ok++;
  } catch (e) {
    console.error(`  FALHA ${nome}: ${e.message}`);
    falha++;
  }
}

function rodaGate(fixture, stop_hook_active = false, temAgentId = false, transcriptPath = null) {
  let scriptPath = hookPath;

  const payload = {
    session_id: 'test-session',
    cwd: 'C:\\Projetos\\fixture-turno-prometido',
    transcript_path: transcriptPath || path.join(fixtureDir, fixture),
    hook_event_name: 'Stop',
  };

  if (stop_hook_active) payload.stop_hook_active = true;
  if (temAgentId) payload.agent_id = 'agent-123';

  const env = { ...process.env };
  delete env.RAINFOREST_GATE_OFF;
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-gate-test-'));
  tmpdirsCriados.push(tmpDir);
  env.RFM_ROOT = tmpDir;

  const resultado = spawnSync(process.execPath, [scriptPath], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env,
    timeout: 30000,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  return resultado;
}

function assert(condicao, msg) {
  if (!condicao) throw new Error(msg);
}

// Teste (0): o comando registrado em hooks.json (com CLAUDE_PLUGIN_ROOT resolvido) barra promete-sem-despachar.jsonl: exit 2
teste('o comando registrado em hooks.json (com CLAUDE_PLUGIN_ROOT resolvido) barra promete-sem-despachar.jsonl: exit 2', () => {
  // Lê hooks.json
  const hookJson = JSON.parse(fs.readFileSync(hookJsonPath, 'utf8'));

  // Encontra o comando no grupo Stop que cita gate-turno-prometido.cjs
  let comando = null;
  const stopHooks = hookJson.hooks.Stop || [];
  for (const grupo of stopHooks) {
    if (grupo.hooks) {
      for (const hook of grupo.hooks) {
        if (hook.type === 'command' && hook.command && hook.command.includes('gate-turno-prometido.cjs')) {
          comando = hook.command;
          break;
        }
      }
    }
    if (comando) break;
  }

  assert(comando, 'comando de gate-turno-prometido não encontrado em hooks.json');

  // Resolve ${CLAUDE_PLUGIN_ROOT} para a raiz do repo (pai de __dirname)
  const repoRoot = path.resolve(__dirname, '..');
  // Converte para forma Windows com barras normalizadas
  const repoRootNormalizado = repoRoot.replace(/\\/g, '/');
  const comandoResolvido = comando.replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, repoRootNormalizado);

  // Monta o payload
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-cmd-test-'));
  tmpdirsCriados.push(tmpDir);
  const payload = {
    session_id: 'test-session',
    cwd: 'C:\\Projetos\\fixture-turno-prometido',
    transcript_path: path.join(fixtureDir, 'promete-sem-despachar.jsonl'),
    hook_event_name: 'Stop',
  };

  const env = { ...process.env };
  delete env.RAINFOREST_GATE_OFF;
  env.RFM_ROOT = tmpDir;

  // Executa por bash -c
  const resultado = spawnSync('bash', ['-c', comandoResolvido], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env,
    timeout: 30000,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  assert(resultado.status === 2, `esperado exit 2, obteve ${resultado.status}`);
  assert(resultado.stderr.includes('Razão:'), 'stderr deve incluir "Razão:"');
});

// Teste (1): promete-sem-despachar: exit 2
teste('promete sem despachar: exit 2', () => {
  const r = rodaGate('promete-sem-despachar.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('Razão:'), 'stderr deve incluir "Razão:"');
});

// Teste (2): promete-e-despacha: exit 0
teste('promete-e-despacha: exit 0', () => {
  const r = rodaGate('promete-e-despacha.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (3): despacho-so-no-turno-anterior: exit 2
teste('despacho-so-no-turno-anterior: exit 2', () => {
  const r = rodaGate('despacho-so-no-turno-anterior.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
});

// Teste (4): promessa-antes-do-tool-result: exit 0
teste('promessa-antes-do-tool-result: exit 0', () => {
  const r = rodaGate('promessa-antes-do-tool-result.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (5): espera-ci-sem-vigia: exit 2
teste('espera-ci-sem-vigia: exit 2', () => {
  const r = rodaGate('espera-ci-sem-vigia.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('aguardando máquina'), 'stderr deve mencionar aguardando máquina');
});

// Teste (6): espera-ci-com-background: exit 0
teste('espera-ci-com-background: exit 0', () => {
  const r = rodaGate('espera-ci-com-background.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (7): passado-despachei: exit 0
teste('passado-despachei: exit 0', () => {
  const r = rodaGate('passado-despachei.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Passado na mesma mensagem nao anula a promessa (os padroes de passado cancelavam o bloqueio)
teste('passado-e-promessa-na-mesma-mensagem: exit 2', () => {
  const r = rodaGate('passado-e-promessa-na-mesma-mensagem.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
});

// Teste: citação no texto não dispara (promessa em citação é descrita, não prometida)
teste('citação no texto: exit 0', () => {
  const r = rodaGate('citacao-no-texto.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste: bloco de código não dispara (promessa em bloco é código, não promessa)
teste('bloco de código: exit 0', () => {
  const r = rodaGate('bloco-de-codigo.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste: negação não dispara ("não vou despachar" é recusa, não promessa)
teste('negação de despacho: exit 0', () => {
  const r = rodaGate('negacao-de-despacho.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste: aspa ou crase solta em outro parágrafo não engole a promessa
teste('aspa solta antes da promessa: exit 2', () => {
  const r = rodaGate('aspa-solta-antes-da-promessa.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
});

teste('crase solta antes da promessa: exit 2', () => {
  const r = rodaGate('crase-solta-antes-da-promessa.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
});

// Teste: lista de estado não dispara (item de lista é relato, não promessa)
teste('lista de estado: exit 0', () => {
  const r = rodaGate('lista-de-estado.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste: aguardando a build sem vigia: exit 2
teste('aguardando a build sem vigia: exit 2', () => {
  const r = rodaGate('aguardando-a-build-sem-vigia.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('aguardando máquina'), 'stderr deve mencionar aguardando máquina');
});

// Teste: PowerShell com background: exit 0
teste('espera-ci-com-powershell-background: exit 0', () => {
  const r = rodaGate('espera-ci-com-powershell-background.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste: SendMessage é despacho válido: exit 0
teste('promete-e-envia-mensagem: exit 0', () => {
  const r = rodaGate('promete-e-envia-mensagem.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste: Workflow é despacho válido: exit 0
teste('promete-e-dispara-workflow: exit 0', () => {
  const r = rodaGate('promete-e-dispara-workflow.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (8): stop_hook_active true: exit 0
teste('promete sem despachar com stop_hook_active true: exit 0 (sem laco)', () => {
  const r = rodaGate('promete-sem-despachar.jsonl', true);
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (9): agent_id presente: exit 0
teste('payload com agent_id: exit 0', () => {
  const r = rodaGate('promete-sem-despachar.jsonl', false, true);
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (10): transcricao ausente ou ilegivel: exit 0
teste('transcricao ausente ou ilegivel: exit 0', () => {
  const r = rodaGate('promete-sem-despachar.jsonl', false, false, '/inexistente/arquivo.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
  assert(r.stderr.includes('AVISO'), 'stderr deve incluir AVISO');
});

// Teste (11): chave desligada: exit 0
teste('chave desligada: exit 0', () => {
  const sandboxDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-test-'));
  const configDir = path.join(sandboxDir, '.rainforest');
  fs.mkdirSync(configDir, { recursive: true });
  fs.writeFileSync(path.join(configDir, 'config.json'), JSON.stringify({ 'gate-turno-prometido': false }));

  const payload = {
    session_id: 'test-session',
    cwd: sandboxDir,
    transcript_path: path.join(fixtureDir, 'promete-sem-despachar.jsonl'),
    hook_event_name: 'Stop',
  };

  const env = { ...process.env };
  delete env.RAINFOREST_GATE_OFF;

  const resultado = spawnSync(process.execPath, [hookPath], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env,
    timeout: 30000,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  assert(resultado.status === 0, `esperado 0, obteve ${resultado.status}`);

  // Limpeza
  try { fs.rmSync(sandboxDir, { recursive: true }); } catch {}
});

// Teste (#364-1): aspas soltas na mesma linha
teste('#364-1 aspas soltas na mesma linha: exit 2', () => {
  const r = rodaGate('364-1-aspas-soltas-mesma-linha.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('Razão:'), 'stderr deve incluir "Razão:"');
});

// Teste (#364-1b): crases soltas na mesma linha
teste('#364-1b crases soltas na mesma linha: exit 2', () => {
  const r = rodaGate('364-1b-crases-soltas-mesma-linha.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('Razão:'), 'stderr deve incluir "Razão:"');
});

// Teste (#364-2): citação multi-linha
teste('#364-2 citacao multi-linha (promessa inteira na segunda linha)', () => {
  const r = rodaGate('364-2-citacao-multi-linha.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (#364-2b): citação em bloco
teste('#364-2b citacao em bloco: exit 0', () => {
  const r = rodaGate('364-2b-citacao-em-bloco.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (#364-2b controle): promessa fora da citação em bloco
teste('#364-2b controle promessa fora da citacao: exit 2', () => {
  const r = rodaGate('364-2b-citacao-controle.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('Razão:'), 'stderr deve incluir "Razão:"');
});

// Teste (#364-r2): citação em negrito/itálico/travessão/ponto e vírgula/barra
teste('#364-r2 citacao em negrito: exit 0', () => {
  const r = rodaGate('364-r2-citacao-em-negrito.jsonl');
  assert(r.status === 0, `esperado 0, obteve ${r.status}`);
});

// Teste (#364-r2): aspa solta atravessando duas quebras
teste('#364-r2 aspa solta em tres linhas: exit 2', () => {
  const r = rodaGate('364-r2-aspa-solta-tres-linhas.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('Razão:'), 'stderr deve incluir "Razão:"');
});

// Teste (#364-r2): aspa solta com CRLF e linhas em branco
teste('#364-r2 aspa solta crlf: exit 2', () => {
  const r = rodaGate('364-r2-aspa-solta-crlf.jsonl');
  assert(r.status === 2, `esperado 2, obteve ${r.status}`);
  assert(r.stderr.includes('Razão:'), 'stderr deve incluir "Razão:"');
});

// Teste (12): fixtures no formato real
teste('fixtures no formato real (chaves de cada linha cobrem o envelope de transcrito-sessao.jsonl)', () => {
  // Lê a fixture real para obter as chaves do envelope
  const fixtureReal = fs.readFileSync(
    path.join(__dirname, '..', 'scripts', 'fixtures', 'utilidade', 'transcrito-sessao.jsonl'),
    'utf8'
  );
  const linhasReais = fixtureReal.trim().split('\n').slice(2, 7); // linhas 3-6 (0-based = 2-6)

  // Coleta chaves por tipo de linha
  const envelopeEsperadoPorTipo = { user: new Set(), assistant: new Set(), attachment: new Set(), system: new Set() };

  for (const linha of linhasReais) {
    const obj = JSON.parse(linha);
    const tipo = obj.type || 'unknown';
    if (envelopeEsperadoPorTipo[tipo]) {
      for (const chave of Object.keys(obj)) {
        if (chave !== 'type' && chave !== 'message' && chave !== 'attachment') {
          envelopeEsperadoPorTipo[tipo].add(chave);
        }
      }
    }
  }

  // Verifica cada fixture
  for (const arquivo of fs.readdirSync(fixtureDir).filter(f => f.endsWith('.jsonl'))) {
    const conteudo = fs.readFileSync(path.join(fixtureDir, arquivo), 'utf8');
    const linhas = conteudo.trim().split('\n');

    for (const linha of linhas) {
      const obj = JSON.parse(linha);
      const tipo = obj.type || 'unknown';
      let envelopeEsperado = envelopeEsperadoPorTipo[tipo] || envelopeEsperadoPorTipo['assistant'];

      // Se é user com tool_result, não exigir promptId
      if (tipo === 'user' && obj.message && Array.isArray(obj.message.content)) {
        const temToolResult = obj.message.content.some(c => c && c.type === 'tool_result');
        if (temToolResult) {
          envelopeEsperado = new Set([...envelopeEsperado].filter(c => c !== 'promptId'));
        }
      }

      const chavesPresentes = new Set();
      for (const chave of Object.keys(obj)) {
        if (chave !== 'type' && chave !== 'message' && chave !== 'attachment') {
          chavesPresentes.add(chave);
        }
      }

      // Verifica se todas as chaves esperadas para este tipo estão presentes
      for (const chave of envelopeEsperado) {
        assert(chavesPresentes.has(chave), `${arquivo}(tipo=${tipo}): falta chave ${chave}`);
      }
    }
  }
});


// --- Categoria (c): pede licença para seguir com fluxo no meio e executar-autonomo ligada ---
// Cada caso monta um repositório git real num mkdtemp: o gate lê o toplevel do cwd, o
// estágio do fluxo (scripts/estado.cjs) e a chave em .rainforest/config.json. Nada aqui
// depende de fixture com cwd fixo, então estes casos não passam pelo rodaGate acima.

const estadoPath = path.join(__dirname, '..', 'scripts', 'estado.cjs');
const SLUG_FLUXO = '2026-10-28-turno-prometido';

function rodaGit(cwd, args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] });
  assert(r.status === 0, `git ${args.join(' ')} falhou (exit ${r.status}): ${r.stderr}`);
}

function rodaEstado(repo, args) {
  const env = { ...process.env, RFM_ESTADO_ROOT: repo, RFM_ROOT: repo };
  delete env.CLAUDE_PROJECT_DIR;
  const r = spawnSync(process.execPath, [estadoPath, ...args], {
    cwd: repo, encoding: 'utf8', env, timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'],
  });
  assert(r.status === 0, `estado.cjs ${args[0]} falhou (exit ${r.status}): ${r.stdout} ${r.stderr}`);
}

// comFluxo: roda `iniciar` (estado gravado pelo estado.cjs real)
// designAprovado: roda `marcar --estagio design --status aprovado` (próxima etapa vira plano)
// autonomia: grava .rainforest/config.json com executar-autonomo (undefined = sem arquivo)
function montarRepo({ comFluxo = true, designAprovado = true, autonomia } = {}) {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-turno-c-'));
  tmpdirsCriados.push(repo);
  rodaGit(repo, ['init', '-q', '-b', 'main']);
  rodaGit(repo, ['config', 'user.email', 'teste@rainforest.invalid']);
  rodaGit(repo, ['config', 'user.name', 'teste']);
  fs.writeFileSync(path.join(repo, 'a.txt'), 'x\n');
  rodaGit(repo, ['add', 'a.txt']);
  rodaGit(repo, ['commit', '-q', '-m', 'base']);
  if (comFluxo) {
    rodaEstado(repo, ['iniciar', '--slug', SLUG_FLUXO, '--titulo', 'teste-turno-prometido']);
    if (designAprovado) rodaEstado(repo, ['marcar', '--slug', SLUG_FLUXO, '--estagio', 'design', '--status', 'aprovado']);
  }
  rodaGit(repo, ['checkout', '-q', '-b', 'fluxo/turno-prometido']);
  if (autonomia !== undefined) {
    fs.mkdirSync(path.join(repo, '.rainforest'), { recursive: true });
    fs.writeFileSync(path.join(repo, '.rainforest', 'config.json'), JSON.stringify({ 'executar-autonomo': autonomia }));
  }
  return repo;
}

// Transcrito igual ao da fixture pede-licenca-com-autonomia.jsonl, trocando só o texto final.
function transcritoComTexto(texto) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rfm-turno-c-tr-'));
  tmpdirsCriados.push(dir);
  const linhas = fs.readFileSync(path.join(fixtureDir, 'pede-licenca-com-autonomia.jsonl'), 'utf8')
    .trim().split('\n').map((l) => JSON.parse(l));
  linhas[1].message.content[0].text = texto;
  const arquivo = path.join(dir, 'transcricao.jsonl');
  fs.writeFileSync(arquivo, linhas.map((l) => JSON.stringify(l)).join('\n') + '\n');
  return arquivo;
}

function rodaGateNoRepo(repo, transcriptPath, stop_hook_active = false) {
  const payload = {
    session_id: 'test-session',
    cwd: repo,
    transcript_path: transcriptPath,
    hook_event_name: 'Stop',
  };
  if (stop_hook_active) payload.stop_hook_active = true;
  const env = { ...process.env };
  delete env.RAINFOREST_GATE_OFF;
  env.RFM_ROOT = repo;
  return spawnSync(process.execPath, [hookPath], {
    input: JSON.stringify(payload), encoding: 'utf8', env, timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'],
  });
}

const FIXTURE_LICENCA = path.join(fixtureDir, 'pede-licenca-com-autonomia.jsonl');
const FIXTURE_LICENCA_Q = path.join(fixtureDir, 'pede-licenca-com-q.jsonl');

// C1: último texto pede licença, fluxo em plano, autonomia ligada: exit 2
teste('C1 pede licença com fluxo em plano e autonomia ligada: exit 2', () => {
  const repo = montarRepo({ autonomia: true });
  const r = rodaGateNoRepo(repo, FIXTURE_LICENCA);
  assert(r.status === 2, `esperado 2, obteve ${r.status}: ${r.stderr}`);
  assert(r.stderr.includes('pedindo licença'), `stderr deve citar a licença: ${r.stderr}`);
  assert(r.stderr.includes(`fluxo ${SLUG_FLUXO} em plano`), `stderr deve citar slug e estágio: ${r.stderr}`);
});

// C2: termina em "posso seguir?": exit 2
teste('C2 termina em "Tudo verde, posso seguir?": exit 2', () => {
  const repo = montarRepo({ autonomia: true });
  const r = rodaGateNoRepo(repo, transcritoComTexto('Revisão concluída sem achados. Tudo verde, posso seguir?'));
  assert(r.status === 2, `esperado 2, obteve ${r.status}: ${r.stderr}`);
  assert(r.stderr.includes('pedindo licença'), `stderr deve citar a licença: ${r.stderr}`);
});

// C3: termina em "Quer que eu siga" (sem ponto de interrogação): exit 2
teste('C3 termina em "Quer que eu siga": exit 2', () => {
  const repo = montarRepo({ autonomia: true });
  const r = rodaGateNoRepo(repo, transcritoComTexto('Plano fechado e revisado. Quer que eu siga'));
  assert(r.status === 2, `esperado 2, obteve ${r.status}: ${r.stderr}`);
  assert(r.stderr.includes('pedindo licença'), `stderr deve citar a licença: ${r.stderr}`);
});

// C4: mesmo texto do C1 com uma linha Q1 antes: a decisão real sobe como Q<n>, exit 0
teste('C4 mesmo texto do C1 com linha Q1 antes: exit 0', () => {
  const repo = montarRepo({ autonomia: true });
  const r = rodaGateNoRepo(repo, FIXTURE_LICENCA_Q);
  assert(r.status === 0, `esperado 0, obteve ${r.status}: ${r.stderr}`);
});

// C5: o C1 com executar-autonomo desligada: exit 0
teste('C5 o C1 com executar-autonomo desligada: exit 0', () => {
  const repo = montarRepo({ autonomia: false });
  const r = rodaGateNoRepo(repo, FIXTURE_LICENCA);
  assert(r.status === 0, `esperado 0, obteve ${r.status}: ${r.stderr}`);
});

// C6: o C1 com o fluxo ainda em design (design não aprovado): exit 0
teste('C6 o C1 com fluxo ainda em design: exit 0', () => {
  const repo = montarRepo({ autonomia: true, designAprovado: false });
  const r = rodaGateNoRepo(repo, FIXTURE_LICENCA);
  assert(r.status === 0, `esperado 0, obteve ${r.status}: ${r.stderr}`);
});

// C7: o C1 com stop_hook_active true (anti-loop): exit 0
teste('C7 o C1 com stop_hook_active true: exit 0 (sem laço)', () => {
  const repo = montarRepo({ autonomia: true });
  const r = rodaGateNoRepo(repo, FIXTURE_LICENCA, true);
  assert(r.status === 0, `esperado 0, obteve ${r.status}: ${r.stderr}`);
});

// C8: pergunta no meio do texto, não no fim: exit 0
teste('C8 "Sigo? Antes, um detalhe do log." (pergunta no meio): exit 0', () => {
  const repo = montarRepo({ autonomia: true });
  const r = rodaGateNoRepo(repo, transcritoComTexto('Sigo? Antes, um detalhe do log.'));
  assert(r.status === 0, `esperado 0, obteve ${r.status}: ${r.stderr}`);
});

// C9: o C1 em repositório sem docs/rainforest/estado/: exit 0
teste('C9 o C1 em repo sem docs/rainforest/estado: exit 0', () => {
  const repo = montarRepo({ comFluxo: false, autonomia: true });
  assert(!fs.existsSync(path.join(repo, 'docs', 'rainforest', 'estado')), 'repo de teste não pode ter estado');
  const r = rodaGateNoRepo(repo, FIXTURE_LICENCA);
  assert(r.status === 0, `esperado 0, obteve ${r.status}: ${r.stderr}`);
});

// C10-C12: o fecho formatado (negrito, emoji, parêntese) não esconde o pedido (revisão 1, achado 5).
for (const [nome, texto] of [
  ['C10 fecho em negrito "**Sigo com o executar?**": exit 2', 'Plano escrito.\n\n**Sigo com o executar?**'],
  ['C11 fecho com emoji "Sigo com o executar? 👍": exit 2', 'Plano escrito. Sigo com o executar? 👍'],
  ['C12 fecho com parêntese "Sigo com o executar? (o plano está em docs/)": exit 2', 'Plano escrito. Sigo com o executar? (o plano está em docs/)'],
]) {
  teste(nome, () => {
    const repo = montarRepo({ autonomia: true });
    const r = rodaGateNoRepo(repo, transcritoComTexto(texto));
    assert(r.status === 2, `esperado 2, obteve ${r.status}: ${r.stderr}`);
    assert(r.stderr.includes('pedindo licença'), `stderr deve citar a licença: ${r.stderr}`);
  });
}

// C13: fecho com "()" repetido 30 vezes (backtracking exponencial da regex antiga do fecho): o hook termina em menos de 3 s.
// A expectativa de exit code nao importa aqui (o texto nao termina em pergunta); mede-se so terminar no prazo.
teste('C13 fecho com "()" repetido 30 vezes termina em menos de 3 s', () => {
  const repo = montarRepo({ autonomia: true });
  const arquivo = transcritoComTexto('Sigo com o executar? ' + '()'.repeat(30) + ' fim');
  const env = { ...process.env };
  delete env.RAINFOREST_GATE_OFF;
  env.RFM_ROOT = repo;
  const payload = { session_id: 'test-session', cwd: repo, transcript_path: arquivo, hook_event_name: 'Stop' };
  const inicio = Date.now();
  const r = spawnSync(process.execPath, [hookPath], {
    input: JSON.stringify(payload), encoding: 'utf8', env, timeout: 3000, stdio: ['pipe', 'pipe', 'pipe'],
  });
  const duracao = Date.now() - inicio;
  assert(r.status !== null && r.signal === null && !r.error,
    `hook não terminou em 3 s (status ${r.status}, signal ${r.signal}, erro ${r.error ? r.error.code : 'nenhum'})`);
  assert(duracao < 3000, `levou ${duracao} ms`);
});

console.log(`ok: ${ok}   falhou: ${falha}`);

// Limpeza de tmpdirs
for (const tmpDir of tmpdirsCriados) {
  try {
    fs.rmSync(tmpDir, { recursive: true });
  } catch (e) {
    // Ignora erros de limpeza
  }
}

process.exit(falha > 0 ? 1 : 0);
