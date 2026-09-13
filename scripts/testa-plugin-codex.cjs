#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createHash, randomBytes } = require('node:crypto');
const { spawnSync } = require('node:child_process');

const RAIZ = path.resolve(__dirname, '..');
const MANIFESTO_CODEX = path.join(RAIZ, '.codex-plugin', 'plugin.json');
const MANIFESTO_CLAUDE = path.join(RAIZ, '.claude-plugin', 'plugin.json');
const MARKETPLACE = path.join(RAIZ, '.agents', 'plugins', 'marketplace.json');
const CAMINHO_HOOK_CODEX = './hooks/codex-gate-staging-total.json';
const HOOK_COMPARTILHADO = path.join(RAIZ, 'hooks', 'gate-staging-total.cjs');
const HOOK_ADAPTADOR_CODEX = path.join(RAIZ, 'hooks', 'codex-gate-staging-total.cjs');
const COMANDO_HOOK_CODEX = 'node "${PLUGIN_ROOT}/hooks/codex-gate-staging-total.cjs"';
const COMANDO_CORE_DIRETO = 'node "${PLUGIN_ROOT}/hooks/gate-staging-total.cjs"';
const MOTIVO_FALHA_SEGURA =
  'Falha interna do gate de staging; comando recusado por seguranca.';
const DOCUMENTOS_DO_FLUXO = new Set([
  'docs/rainforest/design/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/planos/2026-09-12-multihost-sobre-1-11.md',
  'docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json',
  'docs/rainforest/portoes/2026-09-12-multihost-sobre-1-11.md',
]);

// Corpos na base 4028a28513d6ecc7247fe3d76c673a0928a0dd09,
// medidos antes da normalizacao exclusiva do frontmatter.
const ANCORA_CORPOS_SKILLS = {
  fechar: { bytes: 7654, sha256: '28277e22ad12f08604e3666f6466e7d50d66fe3313d86ab173ca87bf60ab7966' },
  'modo-dev': { bytes: 13268, sha256: '23693addf6004160f1fb993b0b842273bf6954166609981e755b173b19b3464d' },
  'montar-corpus': { bytes: 2935, sha256: 'f21d9af8be400bd8222f272b98ece70c1d01c92865e41f418340410b69bb11ab' },
  regua: { bytes: 13394, sha256: '6022ac66fddd981592838ad6006e57ea3057a60fcbfad835b228d4fa4cfe9484' },
};

class FalhaContrato extends Error {}

function falha(mensagem) {
  throw new FalhaContrato(mensagem);
}

function exige(condicao, mensagem) {
  if (!condicao) falha(mensagem);
}

function lerJson(arquivo, nome) {
  let texto;
  try {
    texto = fs.readFileSync(arquivo, 'utf8');
  } catch (erro) {
    falha(`${nome} ilegivel: ${erro.message}`);
  }
  try {
    return JSON.parse(texto);
  } catch (erro) {
    falha(`${nome} nao e JSON valido: ${erro.message}`);
  }
}

function caminhoInterno(valor, campo) {
  exige(typeof valor === 'string' && valor.startsWith('./'), `${campo} deve comecar com ./`);
  exige(!valor.includes('\\'), `${campo} deve usar barras /`);
  const resolvido = path.resolve(RAIZ, valor);
  const relativo = path.relative(RAIZ, resolvido);
  exige(relativo !== '..' && !relativo.startsWith(`..${path.sep}`) && !path.isAbsolute(relativo),
    `${campo} escapa da raiz do plugin`);
  return resolvido;
}

function valorYamlEscalar(cru) {
  if (cru.startsWith('"')) {
    try {
      const valor = JSON.parse(cru);
      return { ok: typeof valor === 'string', valor };
    } catch {
      return { ok: false };
    }
  }
  if (cru.startsWith("'")) {
    if (!cru.endsWith("'") || cru.length < 2) return { ok: false };
    return { ok: true, valor: cru.slice(1, -1).replace(/''/g, "'") };
  }
  if (/:\s/.test(cru) || /\s#/.test(cru)) return { ok: false };
  if (cru === 'false') return { ok: true, valor: false };
  if (cru === 'true') return { ok: true, valor: true };
  return { ok: true, valor: cru };
}

function diagnosticarFrontmatter(conteudo) {
  const linhas = String(conteudo).replace(/\r\n/g, '\n').split('\n');
  if (linhas[0] !== '---') return 'frontmatter ausente';
  const fim = linhas.indexOf('---', 1);
  if (fim === -1) return 'frontmatter nao fechado';

  const campos = {};
  let bloco = null;
  for (const linha of linhas.slice(1, fim)) {
    if (linha.trim() === '') continue;
    if (/^\s/.test(linha)) {
      if (!bloco) return 'YAML invalido';
      campos[bloco] += `${campos[bloco] ? '\n' : ''}${linha.trim()}`;
      continue;
    }
    bloco = null;
    const casamento = linha.match(/^([A-Za-z0-9_-]+):(?:\s*(.*))?$/);
    if (!casamento || Object.hasOwn(campos, casamento[1])) return 'YAML invalido';
    const [, chave, cru = ''] = casamento;
    if (/^[>|][+-]?$/.test(cru)) {
      campos[chave] = '';
      bloco = chave;
      continue;
    }
    if (cru === '') {
      campos[chave] = null;
      continue;
    }
    const escalar = valorYamlEscalar(cru);
    if (!escalar.ok) return 'YAML invalido';
    campos[chave] = escalar.valor;
  }

  if (typeof campos.name !== 'string' || campos.name.trim() === '') return 'name ausente';
  if (typeof campos.description !== 'string' || campos.description.trim() === '') {
    return 'description ausente';
  }
  const desabilitada = campos['disable-model-invocation'] ?? campos.disable_model_invocation;
  if (desabilitada !== undefined && desabilitada !== false) {
    return 'disable-model-invocation deve ser false';
  }
  return null;
}

function descobrirSkills(skillsDir) {
  return fs.readdirSync(skillsDir, { withFileTypes: true })
    .filter((entrada) => entrada.isDirectory())
    .filter((entrada) => fs.existsSync(path.join(skillsDir, entrada.name, 'SKILL.md')))
    .map((entrada) => entrada.name)
    .sort();
}

function extrairCorpoSkill(conteudo, nome) {
  const eol = conteudo.subarray(0, 5).equals(Buffer.from('---\r\n')) ? '\r\n' : '\n';
  const abertura = Buffer.from(`---${eol}`);
  const separador = Buffer.from(`${eol}---${eol}${eol}`);
  exige(conteudo.subarray(0, abertura.length).equals(abertura),
    `frontmatter binario ausente em ${nome}`);
  const fim = conteudo.indexOf(separador, abertura.length);
  exige(fim !== -1, `frontmatter binario nao fechado em ${nome}`);
  return conteudo.subarray(fim + separador.length);
}

function validarCorposSkillsNormalizadas(skillsDir, { silencioso = false } = {}) {
  for (const nome of Object.keys(ANCORA_CORPOS_SKILLS).sort()) {
    const esperado = ANCORA_CORPOS_SKILLS[nome];
    const conteudo = fs.readFileSync(path.join(skillsDir, nome, 'SKILL.md'));
    const corpo = extrairCorpoSkill(conteudo, nome);
    const sha256 = createHash('sha256').update(corpo).digest('hex');
    exige(corpo.length === esperado.bytes && sha256 === esperado.sha256,
      `corpo ${nome} diverge da ancora binaria: ${corpo.length} bytes sha256 ${sha256}`);
    if (!silencioso) console.log(`ok ancora corpo ${nome}: ${corpo.length} bytes sha256 ${sha256}`);
  }
}

function validarSkillsCodex(skillsDir, { silencioso = false } = {}) {
  const skills = descobrirSkills(skillsDir);
  exige(skills[0] !== undefined, 'nenhuma skill compartilhada descoberta');
  const invalidas = skills.map((nome) => ({
    nome,
    motivo: diagnosticarFrontmatter(fs.readFileSync(path.join(skillsDir, nome, 'SKILL.md'), 'utf8')),
  })).filter((item) => item.motivo);
  exige(invalidas.length === 0,
    `skills Codex invalidas: ${invalidas.map((item) => `${item.nome} (${item.motivo})`).join(', ')}`);
  validarCorposSkillsNormalizadas(skillsDir, { silencioso });
  if (!silencioso) {
    for (const nome of skills) console.log(`ok skill descoberta: skills/${nome}/SKILL.md`);
    console.log(`ok frontmatter Codex: ${skills.length} skills descobertas dinamicamente`);
  }
  return skills;
}

function validarInterface(manifesto) {
  exige(manifesto.interface && typeof manifesto.interface === 'object'
    && !Array.isArray(manifesto.interface), 'interface Codex ausente');
  for (const campo of ['displayName', 'shortDescription', 'longDescription', 'developerName', 'category']) {
    exige(typeof manifesto.interface[campo] === 'string' && manifesto.interface[campo].trim() !== '',
      `interface.${campo} ausente`);
  }
  exige(Array.isArray(manifesto.interface.capabilities)
    && manifesto.interface.capabilities.every((valor) => typeof valor === 'string' && valor.trim() !== ''),
  'interface.capabilities invalida');
  exige(Array.isArray(manifesto.interface.defaultPrompt)
    && manifesto.interface.defaultPrompt.length > 0
    && manifesto.interface.defaultPrompt.every((valor) => typeof valor === 'string' && valor.trim() !== ''),
  'interface.defaultPrompt invalido');
}

function validarManifesto({ silencioso = false } = {}) {
  const codex = lerJson(MANIFESTO_CODEX, 'manifesto Codex');
  const claude = lerJson(MANIFESTO_CLAUDE, 'manifesto Claude');
  exige(codex && typeof codex === 'object' && !Array.isArray(codex), 'manifesto Codex deve ser objeto');
  exige(typeof codex.name === 'string' && /^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/.test(codex.name),
    'name Codex invalido');
  exige(typeof codex.version === 'string'
    && /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(codex.version),
  'version Codex invalida');
  exige(codex.name === claude.name, 'name Codex diverge do manifesto Claude');
  exige(codex.version === claude.version, 'version Codex diverge do manifesto Claude');
  exige(codex.description === claude.description, 'description Codex diverge do manifesto Claude');
  exige(JSON.stringify(codex.author) === JSON.stringify(claude.author),
    'author Codex diverge do manifesto Claude');
  exige(codex.skills === './skills/', 'skills Codex deve ser ./skills/');
  exige(codex.hooks === CAMINHO_HOOK_CODEX, 'hooks Codex deve declarar o adaptador dedicado');
  validarInterface(codex);

  const skillsDir = caminhoInterno(codex.skills, 'skills');
  const hooksPath = caminhoInterno(codex.hooks, 'hooks');
  exige(fs.existsSync(skillsDir) && fs.statSync(skillsDir).isDirectory(), 'diretorio de skills ausente');
  exige(fs.existsSync(hooksPath) && fs.statSync(hooksPath).isFile(), 'arquivo de hooks Codex ausente');
  const skills = validarSkillsCodex(skillsDir, { silencioso });
  if (!silencioso) {
    console.log('ok manifesto Codex: metadados name/version/description/author iguais ao manifesto Claude');
    console.log(`ok skills compartilhadas descobertas: ${skills.length}`);
  }
  return hooksPath;
}

function validarHookSeletivo(hooksPath, { silencioso = false } = {}) {
  const config = lerJson(hooksPath, 'hook seletivo Codex');
  exige(config && typeof config === 'object' && !Array.isArray(config)
    && Object.keys(config).join(',') === 'hooks', 'arquivo Codex deve conter apenas hooks');
  const eventos = config.hooks && typeof config.hooks === 'object' && !Array.isArray(config.hooks)
    ? Object.keys(config.hooks) : [];
  exige(eventos.length === 1 && eventos[0] === 'PreToolUse',
    `eventos Codex devem conter somente PreToolUse: ${eventos.join(', ') || 'nenhum'}`);
  const grupos = config.hooks.PreToolUse;
  exige(Array.isArray(grupos) && grupos.length === 1, 'PreToolUse Codex deve conter um grupo');
  exige(grupos[0].matcher === '^Bash$', 'matcher Codex deve ser ^Bash$');
  const handlers = Array.isArray(grupos[0].hooks) ? grupos[0].hooks : [];
  exige(handlers.length === 1, `hook seletivo: ${handlers.length}`);
  exige(handlers[0] && handlers[0].type === 'command', 'handler Codex deve ter type command');
  exige(handlers[0].command !== COMANDO_CORE_DIRETO, 'handler Codex chama core direto');
  exige(handlers[0].command === COMANDO_HOOK_CODEX, 'handler Codex nao chama o adaptador fino');
  exige(fs.existsSync(HOOK_ADAPTADOR_CODEX), 'adaptador Codex ausente');
  exige(fs.existsSync(HOOK_COMPARTILHADO), 'gate compartilhado ausente');
  if (!silencioso) console.log('ok hook seletivo Codex: PreToolUse/Bash, 1 adaptador');
}

function validarAdaptadorFino({ silencioso = false } = {}) {
  const fonte = fs.readFileSync(HOOK_ADAPTADOR_CODEX, 'utf8');
  exige(fonte.split("path.join(__dirname, 'gate-staging-total.cjs')").length - 1 === 1,
    'adaptador Codex deve chamar o core compartilhado uma vez');
  exige(fonte.includes('input: payload'), 'adaptador Codex nao encaminha o stdin original ao core');
  for (const politica of ['git add', 'commit -a', '--all']) {
    exige(!fonte.includes(politica), `adaptador Codex duplicou politica: ${politica}`);
  }
  if (!silencioso) console.log('ok adaptador fino: stdin encaminhado ao core sem politica duplicada');
}

function rodar(arquivo, args, opcoes = {}) {
  return spawnSync(arquivo, args, { encoding: 'utf8', ...opcoes });
}

function git(cwd, args) {
  const resultado = rodar('git', args, { cwd });
  exige(!resultado.error && resultado.status === 0,
    `git ${args.join(' ')} falhou: ${resultado.error ? resultado.error.message : (resultado.stderr || '').trim()}`);
  return (resultado.stdout || '').trim();
}

function payloadCodex(cwd, command) {
  return {
    session_id: 'sessao-codex-contrato',
    transcript_path: path.join(cwd, 'transcript.jsonl'),
    cwd,
    hook_event_name: 'PreToolUse',
    model: 'gpt-5.6-sol',
    turn_id: 'turno-codex-contrato',
    tool_name: 'Bash',
    tool_use_id: 'tool-codex-contrato',
    tool_input: { command },
  };
}

function executarAdaptador(cwd, input, dados, arquivo = HOOK_ADAPTADOR_CODEX) {
  const env = { ...process.env, RFM_ROOT: dados, CLAUDE_PROJECT_DIR: cwd };
  delete env.RAINFOREST_GATE_OFF;
  return rodar(process.execPath, [arquivo], { cwd, input, env });
}

function validarDenyOficial(resultado, motivoEsperado = null) {
  exige(!resultado.error, `adaptador Codex nao iniciou: ${resultado.error && resultado.error.message}`);
  exige(resultado.status === 0, `adaptador Codex deny deve sair 0: ${resultado.status}`);
  exige((resultado.stderr || '') === '', 'adaptador Codex deny escreveu stderr');
  let saida;
  try { saida = JSON.parse((resultado.stdout || '').trim()); } catch { falha('adaptador Codex deny nao devolveu JSON valido'); }
  const especifica = saida && saida.hookSpecificOutput;
  exige(especifica && especifica.hookEventName === 'PreToolUse',
    'adaptador Codex deny sem hookEventName PreToolUse');
  exige(especifica.permissionDecision === 'deny', 'adaptador Codex deny sem permissionDecision deny');
  exige(typeof especifica.permissionDecisionReason === 'string'
    && especifica.permissionDecisionReason.trim() !== '',
  'adaptador Codex deny sem permissionDecisionReason');
  if (motivoEsperado !== null) exige(especifica.permissionDecisionReason === motivoEsperado,
    'adaptador Codex alterou motivo do core');
  return especifica.permissionDecisionReason;
}

function validarAllow(resultado) {
  exige(!resultado.error, `adaptador Codex nao iniciou: ${resultado.error && resultado.error.message}`);
  exige(resultado.status === 0, `adaptador Codex allow deve sair 0: ${resultado.status}`);
  exige((resultado.stderr || '') === '', 'adaptador Codex allow escreveu stderr');
  exige((resultado.stdout || '') === '', 'adaptador Codex allow devolveu decisao');
}

function comRepositorioTemporario(fn) {
  const caixa = fs.mkdtempSync(path.join(os.tmpdir(), 'rainforest-codex-adapter-'));
  const token = randomBytes(24).toString('hex');
  const marcador = path.join(caixa, '.rainforest-codex-owner');
  fs.writeFileSync(marcador, token, { encoding: 'utf8', flag: 'wx' });
  try {
    const repo = path.join(caixa, 'repo');
    const dados = path.join(caixa, 'dados');
    fs.mkdirSync(repo);
    fs.mkdirSync(dados);
    git(repo, ['init', '--quiet']);
    fs.writeFileSync(path.join(repo, 'a.txt'), 'inicial\n', 'utf8');
    git(repo, ['add', '--', 'a.txt']);
    fs.writeFileSync(path.join(repo, 'a.txt'), 'modificado\n', 'utf8');
    return fn({ caixa, repo, dados });
  } finally {
    exige(fs.readFileSync(marcador, 'utf8') === token, 'marcador temporario divergiu');
    fs.rmSync(caixa, { recursive: true, force: true });
  }
}

function testarMutacaoHandler(hooksPath) {
  const original = fs.readFileSync(hooksPath);
  let filho;
  try {
    const config = JSON.parse(original.toString('utf8'));
    config.hooks.PreToolUse[0].hooks[0].command = COMANDO_CORE_DIRETO;
    fs.writeFileSync(hooksPath, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
    filho = rodar(process.execPath, [__filename, '--interno-adaptador-hook'], { cwd: RAIZ });
  } finally {
    fs.writeFileSync(hooksPath, original);
  }
  exige(fs.readFileSync(hooksPath).equals(original), 'mutacao nao restaurou hooks Codex');
  exige(!filho.error && filho.status === 1, `mutacao handler deveria sair 1: ${filho.status}`);
  exige((filho.stdout || '').replace(/\r\n/g, '\n') === 'FALHA handler Codex chama core direto\n',
    `mutacao handler falhou pelo motivo errado: ${(filho.stdout || '').trim()}`);
  console.log('ok mutacao handler Codex -> core direto: vermelho e bytes restaurados');
}

function validarComportamentoAdaptador() {
  comRepositorioTemporario(({ caixa, repo, dados }) => {
    const allowPayload = JSON.stringify(payloadCodex(repo, 'git status --short'));
    validarAllow(executarAdaptador(repo, allowPayload, dados));
    console.log('ok adaptador Codex: allow exit 0 e stdout vazio');

    const denyPayload = JSON.stringify(payloadCodex(repo, 'git add -A'));
    const core = rodar(process.execPath, [HOOK_COMPARTILHADO], {
      cwd: repo, input: denyPayload, env: { ...process.env, RFM_ROOT: dados, CLAUDE_PROJECT_DIR: repo },
    });
    exige(core.status === 2 && (core.stderr || '').trim() !== '', 'core nao produziu recusa exit 2 com motivo');
    validarDenyOficial(executarAdaptador(repo, denyPayload, dados), (core.stderr || '').trim());
    console.log('ok adaptador Codex: deny oficial preserva motivo do core');

    const fixtureDir = path.join(caixa, 'fixture-adaptador');
    fs.mkdirSync(fixtureDir);
    const adaptadorFixture = path.join(fixtureDir, 'codex-gate-staging-total.cjs');
    fs.copyFileSync(HOOK_ADAPTADOR_CODEX, adaptadorFixture);
    fs.writeFileSync(path.join(fixtureDir, 'gate-staging-total.cjs'),
      "process.stderr.write('falha fixture inesperada\\n'); process.exit(7);\n", 'utf8');
    validarDenyOficial(executarAdaptador(repo, allowPayload, dados, adaptadorFixture), MOTIVO_FALHA_SEGURA);
    console.log('ok adaptador Codex: falha inesperada vira deny seguro');

    const spawnDir = path.join(caixa, 'fixture-spawn');
    fs.mkdirSync(spawnDir);
    const adaptadorSpawn = path.join(spawnDir, 'codex-gate-staging-total.cjs');
    const fonteAdaptador = fs.readFileSync(HOOK_ADAPTADOR_CODEX, 'utf8');
    const chamadaSpawn = 'spawnSync(process.execPath,';
    exige(fonteAdaptador.split(chamadaSpawn).length - 1 === 1,
      'fixture de spawn nao encontrou chamada unica do core');
    fs.writeFileSync(adaptadorSpawn, fonteAdaptador.replace(
      chamadaSpawn,
      "spawnSync(path.join(__dirname, 'node-inexistente'),",
    ), 'utf8');
    validarDenyOficial(executarAdaptador(repo, allowPayload, dados, adaptadorSpawn), MOTIVO_FALHA_SEGURA);
    console.log('ok adaptador Codex: falha de spawn vira deny seguro');

    const segredo = 'segredo-sentinela-nao-vazar';
    const malformado = executarAdaptador(repo, `{"secret":"${segredo}"`, dados);
    validarDenyOficial(malformado, MOTIVO_FALHA_SEGURA);
    exige(!`${malformado.stdout || ''}${malformado.stderr || ''}`.includes(segredo),
      'JSON malformado vazou payload sensivel');
    console.log('ok adaptador Codex: JSON malformado vira deny seguro sem ecoar payload');
  });
}

function contratoAdaptadorHook({ mutacao = true } = {}) {
  const hooksPath = validarManifesto({ silencioso: true });
  validarHookSeletivo(hooksPath);
  validarAdaptadorFino();
  validarComportamentoAdaptador();
  if (mutacao) testarMutacaoHandler(hooksPath);
}

function validarMarketplace() {
  exige(fs.existsSync(MARKETPLACE), 'marketplace local ausente');
  const marketplace = lerJson(MARKETPLACE, 'marketplace local');
  exige(marketplace && typeof marketplace === 'object' && !Array.isArray(marketplace),
    'marketplace local deve ser objeto');
  exige(marketplace.name === 'rainforest-mind-local',
    'marketplace deve se chamar rainforest-mind-local');
  exige(Array.isArray(marketplace.plugins) && marketplace.plugins.length === 1,
    'marketplace deve conter uma unica entrada');
  const entrada = marketplace.plugins[0];
  exige(entrada && entrada.name === 'rainforest-mind',
    'entrada marketplace deve ser rainforest-mind');
  exige(entrada.source && entrada.source.source === 'local',
    'marketplace source deve ser local');
  exige(entrada.policy && entrada.policy.installation === 'AVAILABLE',
    'marketplace policy.installation deve ser AVAILABLE');
  exige(entrada.policy.authentication === 'ON_INSTALL',
    'marketplace policy.authentication deve ser ON_INSTALL');
  exige(typeof entrada.category === 'string' && entrada.category.trim() !== '',
    'marketplace category ausente');

  const raizDistribuida = caminhoInterno(entrada.source.path, 'source.path');
  const contemClaude = fs.existsSync(path.join(raizDistribuida, '.claude-plugin', 'plugin.json'));
  const contemCodex = fs.existsSync(path.join(raizDistribuida, '.codex-plugin', 'plugin.json'));
  if (raizDistribuida !== RAIZ || !contemClaude || !contemCodex) {
    falha('source.path nao resolve o manifesto deste repo');
  }
  console.log('ok marketplace rainforest-mind: source.path ./ resolve a raiz com manifestos Claude e Codex');
}

function ehArtefatoGemini(arquivo) {
  const minusculo = arquivo.replace(/\\/g, '/').toLowerCase();
  const segmentos = minusculo.split('/').filter(Boolean);
  const temGemini = segmentos.some((segmento) =>
    /(^|[._-])gemini([._-]|$)/.test(segmento));
  const temTermoDeHost = segmentos.some((segmento) =>
    /(^|[._-])(adapter|adapters|adaptador|adaptadores|hook|hooks|manifest|manifesto|plugin|payload)([._-]|$)/.test(segmento));
  return temGemini && temTermoDeHost;
}

function validarDetectorGemini() {
  const proibidos = [
    'gemini/plugin.json',
    'adapters/gemini/manifest.json',
    'hooks/gemini/pre-tool-use.json',
    'test/fixtures/gemini/payload.json',
    '.gemini-plugin/plugin.json',
  ];
  const permitidos = [
    'scripts/fixtures/conselho/membro-gemini-fake.cjs',
    'referencias/notas-gemini.md',
  ];
  for (const documento of DOCUMENTOS_DO_FLUXO) {
    exige(!ehArtefatoGemini(documento), `detector Gemini confundiu documento do fluxo: ${documento}`);
  }
  for (const arquivo of proibidos) {
    exige(ehArtefatoGemini(arquivo), `detector Gemini deixou passar ${arquivo}`);
  }
  for (const arquivo of permitidos) {
    exige(!ehArtefatoGemini(arquivo), `detector Gemini recusou ${arquivo}`);
  }
}

function validarGeminiAdiado() {
  const listagem = rodar('git', ['ls-files', '-z'], { cwd: RAIZ });
  exige(!listagem.error, `git ls-files nao iniciou: ${listagem.error && listagem.error.message}`);
  exige(listagem.status === 0, `git ls-files saiu ${listagem.status}`);
  const arquivos = (listagem.stdout || '').split('\0').filter(Boolean)
    .map((arquivo) => arquivo.replace(/\\/g, '/'));
  const artefatos = arquivos.filter((arquivo) =>
    !DOCUMENTOS_DO_FLUXO.has(arquivo) && ehArtefatoGemini(arquivo));
  exige(artefatos.length === 0, `Gemini recebeu artefato de host: ${artefatos.join(', ')}`);
  console.log('ok Gemini adiado: caminhos rastreados nao contem manifesto, hook, adaptador ou fixture de payload Gemini fora dos documentos do fluxo');
}

function contratoMarketplace() {
  validarMarketplace();
}

function contratoGemini() {
  validarDetectorGemini();
  validarGeminiAdiado();
}

function executarModo() {
  const [modo] = process.argv.slice(2);
  if (modo === '--contrato-manifesto') {
    validarManifesto();
    return;
  }
  if (modo === '--contrato-skills') {
    validarSkillsCodex(path.join(RAIZ, 'skills'));
    return;
  }
  if (modo === '--contrato-adaptador-hook') {
    contratoAdaptadorHook();
    return;
  }
  if (modo === '--contrato-marketplace') {
    contratoMarketplace();
    return;
  }
  if (modo === '--contrato-gemini') {
    contratoGemini();
    return;
  }
  if (modo === '--interno-adaptador-hook') {
    contratoAdaptadorHook({ mutacao: false });
    return;
  }
  exige(modo === undefined, `modo desconhecido: ${modo}`);
  validarManifesto();
  validarMarketplace();
  contratoGemini();
}

try {
  executarModo();
} catch (erro) {
  const mensagem = erro instanceof FalhaContrato
    ? erro.message
    : `erro inesperado: ${erro && erro.message ? erro.message : String(erro)}`;
  console.log(`FALHA ${mensagem}`);
  process.exitCode = 1;
}
