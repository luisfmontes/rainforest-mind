#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

const RAIZ = path.resolve(__dirname, '..');
const MANIFESTO_CODEX = path.join(RAIZ, '.codex-plugin', 'plugin.json');
const MANIFESTO_CLAUDE = path.join(RAIZ, '.claude-plugin', 'plugin.json');
const CAMINHO_HOOK_CODEX = './hooks/codex-gate-staging-total.json';

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

function validarManifesto() {
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
  caminhoInterno(codex.hooks, 'hooks');
  exige(fs.existsSync(skillsDir) && fs.statSync(skillsDir).isDirectory(), 'diretorio de skills ausente');
  const skills = validarSkillsCodex(skillsDir);
  console.log('ok manifesto Codex: metadados name/version/description/author iguais ao manifesto Claude');
  console.log(`ok skills compartilhadas descobertas: ${skills.length}`);
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
  exige(modo === undefined, `modo desconhecido: ${modo}`);
  validarManifesto();
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
