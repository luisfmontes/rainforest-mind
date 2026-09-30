#!/usr/bin/env node
// @categoria: teste

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function hashArquivos(dir) {
  let conteudoTotal = '';

  function lerDir(d) {
    const itens = fs.readdirSync(d);
    for (const item of itens) {
      const p = path.join(d, item);
      const stat = fs.statSync(p);
      if (stat.isDirectory()) {
        lerDir(p);
      } else {
        conteudoTotal += fs.readFileSync(p, 'utf8');
      }
    }
  }

  lerDir(dir);
  return crypto.createHash('sha256').update(conteudoTotal).digest('hex');
}

function testar() {
  let ok = 0;
  let falhas = 0;

  const fixtureDir = path.join(__dirname, 'fixtures', 'corpus', 'projetos');
  const extractorPath = path.join(__dirname, 'extrair-corpus-comandos.cjs');

  console.log('  Teste 1: comando liberado e subagente');
  try {
    const output = execSync(`node "${extractorPath}" --raiz "${fixtureDir}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });

    const linhas = output.trim().split('\n').filter(l => l.trim());
    const candidatos = linhas.map(l => {
      try {
        return JSON.parse(l);
      } catch {
        return null;
      }
    }).filter(c => c !== null);

    const cmds = candidatos.map(c => c.comando);

    if (cmds.includes('ls -la')) {
      const c = candidatos.find(x => x.comando === 'ls -la');
      if (c.contexto === 'principal') {
        console.log('    ok   comando liberado vira candidato com contexto principal');
        ok++;
      }
    }

    if (cmds.includes('cd /tmp && pwd')) {
      const c = candidatos.find(x => x.comando === 'cd /tmp && pwd');
      if (c.contexto === 'subagente') {
        console.log('    ok   comando do arquivo de subagente vem com contexto subagente');
        ok++;
      }
    }
  } catch (e) {
    console.log('    FALHA: ' + e.message);
    falhas++;
  }

  console.log('  Teste 2: bloqueados e ignorados');
  try {
    const output = execSync(`node "${extractorPath}" --raiz "${fixtureDir}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });

    const linhas = output.trim().split('\n').filter(l => l.trim());
    const candidatos = linhas.map(l => {
      try {
        return JSON.parse(l);
      } catch {
        return null;
      }
    }).filter(c => c !== null);

    const cmds = candidatos.map(c => c.comando);

    if (!cmds.includes('git add scripts/estado.cjs')) {
      console.log('    ok   comando bloqueado por hook nao vira candidato');
      ok++;
    }

    if (!cmds.includes('echo sem resultado')) {
      console.log('    ok   Bash sem tool_result nao vira candidato');
      ok++;
    }

    if (!cmds.some(c => c.includes('package.json'))) {
      console.log('    ok   outra ferramenta e ignorada');
      ok++;
    }
  } catch (e) {
    console.log('    FALHA: ' + e.message);
    falhas++;
  }

  console.log('  Teste 3: deduplicação');
  try {
    // Criar arquivo com comando duplicado
    const tempFile = path.join(__dirname, 'fixtures', 'corpus', 'projetos', 'p1', 'dup.jsonl');
    fs.writeFileSync(tempFile,
      '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"dup-1","name":"Bash","input":{"command":"ls -la"}}],"stop_reason":"tool_use"}}\n' +
      '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"dup-1","content":"teste","is_error":false}]}}\n'
    );

    const output = execSync(`node "${extractorPath}" --raiz "${fixtureDir}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });

    const linhas = output.trim().split('\n').filter(l => l.trim());
    const candidatos = linhas.map(l => {
      try {
        return JSON.parse(l);
      } catch {
        return null;
      }
    }).filter(c => c !== null);

    const lsCount = candidatos.filter(c => c.comando === 'ls -la').length;
    if (lsCount === 1) {
      console.log('    ok   mesmo comando duas vezes sai uma so');
      ok++;
    }

    fs.unlinkSync(tempFile);
  } catch (e) {
    console.log('    FALHA: ' + e.message);
    falhas++;
  }

  console.log('  Teste 4: somente leitura');
  try {
    const hashAntes = hashArquivos(fixtureDir);

    execSync(`node "${extractorPath}" --raiz "${fixtureDir}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });

    const hashDepois = hashArquivos(fixtureDir);

    if (hashAntes === hashDepois) {
      console.log('    ok   somente leitura: hash de todos os arquivos da raiz igual antes e depois');
      ok++;
    }
  } catch (e) {
    console.log('    FALHA: ' + e.message);
    falhas++;
  }

  // Resumo
  console.log(`ok: ${ok}   falhou: ${falhas}`);

  process.exit(falhas > 0 ? 1 : 0);
}

testar();
