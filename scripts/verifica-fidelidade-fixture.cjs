const fs = require('fs');
const path = require('path');

function lerJSONL(caminhoArquivo) {
  if (!fs.existsSync(caminhoArquivo)) {
    return [];
  }
  const conteudo = fs.readFileSync(caminhoArquivo, 'utf8');
  const linhas = conteudo.split('\n').filter(l => l.trim());
  const eventos = [];
  for (const linha of linhas) {
    try {
      eventos.push(JSON.parse(linha));
    } catch (e) {
      // skip malformed lines
    }
  }
  return eventos;
}

function encontrarTranscritoReal() {
  const configDir = process.env.CLAUDE_CONFIG_DIR;
  if (!configDir) {
    return null;
  }

  const projectsDir = path.join(configDir, 'projects');
  if (!fs.existsSync(projectsDir)) {
    return null;
  }

  const pastas = fs.readdirSync(projectsDir).filter(f =>
    fs.statSync(path.join(projectsDir, f)).isDirectory()
  );

  for (const pasta of pastas) {
    const arquivos = fs.readdirSync(path.join(projectsDir, pasta))
      .filter(f => f.endsWith('.jsonl'));
    if (arquivos.length > 0) {
      return path.join(projectsDir, pasta, arquivos[0]);
    }
  }

  return null;
}

function main() {
  const args = process.argv.slice(2);
  let caminhoFixture = null;
  let caminhoReal = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--real') {
      caminhoReal = args[i + 1];
      i++;
    } else if (!caminhoFixture) {
      caminhoFixture = args[i];
    }
  }

  if (!caminhoFixture) {
    console.error('Uso: node verifica-fidelidade-fixture.cjs <fixture.jsonl> [--real <real.jsonl>]');
    process.exit(1);
  }

  const fixture = lerJSONL(caminhoFixture);
  if (fixture.length === 0) {
    console.error('AVISO: fixture esta vazio ou nao parseavel');
    process.exit(0);
  }

  if (!caminhoReal) {
    caminhoReal = encontrarTranscritoReal();
  }

  if (!caminhoReal || !fs.existsSync(caminhoReal)) {
    console.error('AVISO: Sem transcrito real disponivel para comparacao.');
    console.error('Fixture nao pode ser validado como ok sem transcrito real.');
    process.exit(1);
  }

  const real = lerJSONL(caminhoReal);
  if (real.length === 0) {
    console.error('AVISO: transcrito real esta vazio');
    process.exit(1);
  }

  console.log('[fidelidade] Fixture: ' + caminhoFixture + ' (' + fixture.length + ' eventos)');
  console.log('[fidelidade] Real:    ' + caminhoReal + ' (' + real.length + ' eventos)');
  console.log('');

  const erros = [];

  // 1. Check event types
  const tiposReal = new Set(real.map(e => e.type).filter(t => t));
  const tiposFixture = new Set(fixture.map(e => e.type).filter(t => t));

  for (const tipo of tiposFixture) {
    if (!tiposReal.has(tipo)) {
      erros.push(
        'DIVERGENCIA: Fixture tem type="' + tipo + '" que nao aparece no real. ' +
        'Tipos no real: [' + Array.from(tiposReal).join(', ') + ']'
      );
    }
  }

  // 2. Check top-level fields
  const chavasReal = new Set();
  for (const evento of real) {
    Object.keys(evento).forEach(k => chavasReal.add(k));
  }

  for (const evento of fixture) {
    for (const chave of Object.keys(evento)) {
      if (!chavasReal.has(chave)) {
        erros.push(
          'DIVERGENCIA: Fixture tem campo topo "' + chave + '" que nao aparece no real. ' +
          'Campos reais: [' + Array.from(chavasReal).sort().join(', ') + ']'
        );
        break;
      }
    }
  }

  // 3. Check message structure
  const eventosComMessage = fixture.filter(e => 'message' in e);
  if (eventosComMessage.length > 0) {
    const eventosRealComMessage = real.filter(e => 'message' in e);
    if (eventosRealComMessage.length === 0) {
      erros.push(
        'DIVERGENCIA: Fixture tem eventos com message, mas real nao tem. ' +
        'Schema real nao inclui campo message.'
      );
    }
  }

  // ====== RESULTADO ======

  if (erros.length > 0) {
    console.log('');
    console.log('FALHA: Fixture nao eh fiel ao schema real.');
    for (const erro of erros) {
      console.log('  - ' + erro);
    }
    console.log('');
    process.exit(1);
  }

  console.log('ok    Fixture eh fiel ao schema real.');
  process.exit(0);
}

if (require.main === module) {
  main();
}

module.exports = { lerJSONL, encontrarTranscritoReal };
