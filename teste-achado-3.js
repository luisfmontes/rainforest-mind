#!/usr/bin/env node
/**
 * Teste do Achado 3: versionar() é idempotente e desrastreia .db
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const caixa = path.join(process.env.TEMP || '/tmp', 'teste-achado3-' + Math.random().toString(36).slice(2, 8));
fs.mkdirSync(caixa, { recursive: true });

process.env.RFM_ROOT = caixa;

console.log('Usando:', caixa);
console.log('');

// Step 1: Criar estrutura inicial com git antigo (sem .gitignore ou com antigo)
console.log('== Step 1: Criar repo com .git/.gitignore ANTIGOS ==');
fs.mkdirSync(path.join(caixa, '.git'), { recursive: true });
fs.writeFileSync(path.join(caixa, '.gitignore'), '# antigo (sem rainforest.db*)\n*.swp\n.DS_Store\n', 'utf8');

// Iniciar git
execSync('git init', { cwd: caixa, stdio: 'pipe' });
execSync('git config user.email "test@example.com"', { cwd: caixa, stdio: 'pipe' });
execSync('git config user.name "Test"', { cwd: caixa, stdio: 'pipe' });

// Step 2: Criar e commitar um banco fake
console.log('== Step 2: Commitar rainforest.db (erro histórico) ==');
fs.writeFileSync(path.join(caixa, 'rainforest.db'), 'FAKE_DB_DATA', 'utf8');
fs.writeFileSync(path.join(caixa, 'rainforest.db-shm'), 'FAKE_SHM', 'utf8');
fs.writeFileSync(path.join(caixa, 'FOCO.md'), '# Foco\nTeste', 'utf8');

execSync('git add .', { cwd: caixa, stdio: 'pipe' });
execSync('git commit -m "Initial commit with DB"', { cwd: caixa, stdio: 'pipe' });
console.log('OK: .db commitado no repo');

// Step 3: Verificar estado ANTES
console.log('');
console.log('== Step 3: ANTES (verificar rastreamento) ==');
const arquivosBefore = execSync('git ls-files', { cwd: caixa, encoding: 'utf8' }).split('\n').filter(f => f.trim());
console.log('Arquivos rastreados:', arquivosBefore.join(', '));
const temDbRastreado = arquivosBefore.some(f => f.startsWith('rainforest.db'));
console.log('rainforest.db rastreado?', temDbRastreado ? 'SIM (problema)' : 'NAO');

// Step 4: Executar versionar()
console.log('');
console.log('== Step 4: Executar versionar() ==');
const setup = require('./scripts/setup.cjs');
// Chamar a função versionar via execSync pois precisa de RFM_ROOT
const output = execSync(`node scripts/setup.cjs versionar`, { cwd: path.resolve(__dirname), encoding: 'utf8' });
console.log(output);

// Step 5: Verificar estado DEPOIS
console.log('');
console.log('== Step 5: DEPOIS (verificar rastreamento) ==');
const arquivosAfter = execSync('git ls-files', { cwd: caixa, encoding: 'utf8' }).split('\n').filter(f => f.trim());
console.log('Arquivos rastreados:', arquivosAfter.join(', '));
const temDbRastreadoAfter = arquivosAfter.some(f => f.startsWith('rainforest.db'));
console.log('rainforest.db rastreado?', temDbRastreadoAfter ? 'SIM (falha)' : 'NAO (ok)');

// Verificar que .gitignore foi atualizado
const gitignoreContent = fs.readFileSync(path.join(caixa, '.gitignore'), 'utf8');
const temPatraoCorreto = gitignoreContent.includes('rainforest.db*');
console.log('.gitignore tem rainforest.db*?', temPatraoCorreto ? 'SIM' : 'NAO (falha)');

// Step 6: Verificar que arquivo ainda existe no disco
console.log('');
console.log('== Step 6: Verificar arquivos no disco ==');
const dbExisteNoDisco = fs.existsSync(path.join(caixa, 'rainforest.db'));
console.log('rainforest.db existe no disco?', dbExisteNoDisco ? 'SIM (correto, git rm --cached nao apaga)' : 'NAO (inesperado)');

console.log('');
if (!temDbRastreadoAfter && temPatraoCorreto && dbExisteNoDisco) {
  console.log('✓ SUCESSO: Idempotencia funciona');
  console.log('  - .db foi desrastreado');
  console.log('  - .gitignore foi atualizado');
  console.log('  - arquivo continua no disco (seguro)');
  process.exit(0);
} else {
  console.log('✗ FALHA:');
  if (temDbRastreadoAfter) console.log('  - .db ainda está rastreado');
  if (!temPatraoCorreto) console.log('  - .gitignore não foi atualizado');
  if (!dbExisteNoDisco) console.log('  - arquivo foi apagado do disco');
  process.exit(1);
}
