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

  // Teste 1: comando liberado e subagente
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

    // Verificar comando liberado principal
    const lsLa = candidatos.find(x => x.comando === 'ls -la');
    if (lsLa && lsLa.contexto === 'principal') {
      console.log('    ok   comando liberado vira candidato com contexto principal');
      ok++;
    } else {
      console.log('    FALHA: comando liberado não encontrado ou contexto errado');
      falhas++;
    }

    // Verificar comando subagente
    const pwdCmd = candidatos.find(x => x.comando === 'cd /tmp && pwd');
    if (pwdCmd && pwdCmd.contexto === 'subagente') {
      console.log('    ok   comando do arquivo de subagente vem com contexto subagente');
      ok++;
    } else {
      console.log('    FALHA: comando subagente não encontrado ou contexto errado');
      falhas++;
    }
  } catch (e) {
    console.log('    FALHA: ' + e.message);
    falhas += 2;
  }

  // Teste 2: bloqueados e ignorados
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

    // Verificar que bloqueado NÃO aparece
    if (!cmds.includes('git add scripts/estado.cjs')) {
      console.log('    ok   comando bloqueado por hook nao vira candidato');
      ok++;
    } else {
      console.log('    FALHA: comando bloqueado por hook apareceu nos resultados');
      falhas++;
    }

    // Verificar que sem resultado NÃO aparece
    if (!cmds.includes('echo sem resultado')) {
      console.log('    ok   Bash sem tool_result nao vira candidato');
      ok++;
    } else {
      console.log('    FALHA: Bash sem tool_result apareceu nos resultados');
      falhas++;
    }

    // Verificar que outra ferramenta NÃO aparece
    if (!cmds.some(c => c.includes('package.json'))) {
      console.log('    ok   outra ferramenta e ignorada');
      ok++;
    } else {
      console.log('    FALHA: outra ferramenta apareceu nos resultados');
      falhas++;
    }
  } catch (e) {
    console.log('    FALHA: ' + e.message);
    falhas += 3;
  }

  // Teste 3: deduplicação
  console.log('  Teste 3: deduplicação');
  try {
    // Copia a fixture para um temporario e acrescenta la o arquivo duplicado:
    // gravar dentro de scripts/fixtures sujaria o repo e correria com outra bateria.
    const raizDup = fs.mkdtempSync(path.join(require('os').tmpdir(), 'corpus-dup-'));
    fs.cpSync(fixtureDir, raizDup, { recursive: true });
    const tempFile = path.join(raizDup, 'p1', 'dup.jsonl');
    fs.writeFileSync(tempFile,
      '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"dup-1","name":"Bash","input":{"command":"ls -la"}}],"stop_reason":"tool_use"}}\n' +
      '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"dup-1","content":"teste","is_error":false}]}}\n'
    );

    const output = execSync(`node "${extractorPath}" --raiz "${raizDup}"`, {
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
    } else {
      console.log('    FALHA: comando apareceu ' + lsCount + ' vezes em vez de 1');
      falhas++;
    }

    fs.rmSync(raizDup, { recursive: true, force: true });
  } catch (e) {
    console.log('    FALHA: ' + e.message);
    falhas++;
  }

  // Teste 4: somente leitura
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
    } else {
      console.log('    FALHA: arquivos foram modificados durante a execução');
      falhas++;
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
