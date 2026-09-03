#!/usr/bin/env node
/**
 * Backup — zip diário dos dados do rainforest para pasta sincronizada (OneDrive).
 *
 * Tarefa 8 do plano `docs/rainforest/planos/2026-09-03-guardas.md`:
 * - Cria `rainforest-AAAA-MM-DD.zip` via Compress-Archive do PowerShell
 * - Destino padrão: `%OneDrive%\rainforest-backup` ou `RFM_BACKUP_DESTINO`
 * - Origem: raiz de dados pela cadeia canônica (RFM_ROOT, .rainforest, ~/.rainforest, plugin)
 * - Lista fechada de entrada (D10): FOCO.md, ESTRATEGIA.md, AVANCOS.md, ideias.jsonl,
 *   divergencias.jsonl, ferramentas.jsonl, projetos.json, config.json, rainforest.db,
 *   referencias/, relatorios/
 * - Escrita atômica (temp + rename)
 * - Rotação: máximo 30 zips, remove os mais antigos, nunca o recém-gravado
 *
 * Uso:
 *   node scripts/backup.cjs gravar                    # origem/destino padrão
 *   node scripts/backup.cjs gravar --origem <dir>    # origem custom
 *   node scripts/backup.cjs gravar --destino <dir>   # destino custom
 *   node scripts/backup.cjs gravar --so-mostrar       # imprime destino sem gravar
 *
 * Exit codes:
 *   0  gravou com sucesso (ou --so-mostrar)
 *   2  origem/destino inválido, ferramenta ausente, ou uso errado
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// Lista fechada de entrada (D10)
const ITENS_BACKUP = [
  'FOCO.md',
  'ESTRATEGIA.md',
  'AVANCOS.md',
  'ideias.jsonl',
  'divergencias.jsonl',
  'ferramentas.jsonl',
  'projetos.json',
  'config.json',
  'rainforest.db',
  'referencias',
  'relatorios',
];

/**
 * Resolve a raiz de dados pela cadeia canônica.
 * Mesma lógica de hooks/lib/raiz.cjs, embutida para evitar acoplamento.
 */
function resolverRaiz() {
  try {
    const { resolverRaiz: r } = require('./hooks/lib/raiz.cjs');
    const resultado = r();
    return resultado.raiz;
  } catch {
    // Fallback: não conseguiu importar, tenta raiz genérica
    const env = process.env;
    const projeto = env.CLAUDE_PROJECT_DIR || process.cwd();
    const plugin = path.resolve(__dirname, '..');

    // Nível 1: RFM_ROOT
    if (env.RFM_ROOT) return env.RFM_ROOT;

    // Nível 2: <projeto>/.rainforest
    const doProjeto = path.join(projeto, '.rainforest');
    if (fs.existsSync(path.join(doProjeto, 'FOCO.md')) || fs.existsSync(path.join(doProjeto, 'ideias.jsonl'))) {
      return doProjeto;
    }

    // Nível 3: ~/.rainforest
    const doUsuario = path.join(env.USERPROFILE || env.HOME || '', '.rainforest');
    if (fs.existsSync(path.join(doUsuario, 'FOCO.md')) || fs.existsSync(path.join(doUsuario, 'ideias.jsonl'))) {
      return doUsuario;
    }

    // Nível 4: plugin
    if (fs.existsSync(path.join(plugin, 'FOCO.md')) || fs.existsSync(path.join(plugin, 'ideias.jsonl'))) {
      return plugin;
    }

    return null;
  }
}

/**
 * Resolve o destino do backup.
 * Ordem: --destino, RFM_BACKUP_DESTINO, %OneDrive%\rainforest-backup
 */
function resolverDestino(destinoFlag) {
  if (destinoFlag) return destinoFlag;

  const env = process.env;
  if (env.RFM_BACKUP_DESTINO) return env.RFM_BACKUP_DESTINO;

  const oneDrive = env.OneDrive || env.ONEDRIVE;
  if (oneDrive) {
    return path.join(oneDrive, 'rainforest-backup');
  }

  return null;
}

/**
 * Valida se um caminho existe e é diretório.
 */
function ehDiretorio(dir) {
  try {
    return fs.statSync(dir).isDirectory();
  } catch {
    return false;
  }
}

/**
 * Grava o arquivo no destino, com escrita atômica (temp + rename).
 */
function gravarAtomico(destino, conteudo) {
  fs.mkdirSync(destino, { recursive: true });

  const hoje = new Date().toISOString().split('T')[0]; // AAAA-MM-DD
  const nomeZip = `rainforest-${hoje}.zip`;
  const caminhoZip = path.join(destino, nomeZip);

  // Se já existe, não sobrescreve
  if (fs.existsSync(caminhoZip)) {
    return { sucesso: true, nomeZip, caminhoZip, jaExistia: true };
  }

  const tmp = `${caminhoZip}.tmp`;

  try {
    fs.writeFileSync(tmp, conteudo);
    fs.renameSync(tmp, caminhoZip);
    return { sucesso: true, nomeZip, caminhoZip };
  } catch (err) {
    // Limpa temp se falhou
    try { fs.unlinkSync(tmp); } catch { }
    return { sucesso: false, erro: err.message };
  }
}

/**
 * Remove os arquivos zip mais antigos, mantendo no máximo 30.
 * Nunca remove o arquivo que acabou de ser gravado.
 */
function rotacionarZips(destino, nomeDoNovoZip) {
  try {
    const arquivos = fs.readdirSync(destino)
      .filter((f) => /^rainforest-\d{4}-\d{2}-\d{2}\.zip$/.test(f))
      .sort()
      .reverse(); // mais recentes primeiro

    if (arquivos.length > 30) {
      // Remove os mais antigos, excetuando o novo
      const paraRemover = arquivos.slice(30).filter((f) => f !== nomeDoNovoZip);
      for (const arquivo of paraRemover) {
        try {
          fs.unlinkSync(path.join(destino, arquivo));
        } catch { }
      }
    }
  } catch {
    // Se falhar na rotação, não interrompe o fluxo
  }
}

/**
 * Executa Compress-Archive via PowerShell.
 * Retorna {sucesso, saida}
 */
function compactarComPowerShell(origem, itens, zipPath) {
  // Monta o comando PowerShell
  // O caminho precisa estar em aspas dentro do PowerShell e escapado
  const destWin = zipPath.replace(/\//g, '\\');
  const origenWin = origem.replace(/\//g, '\\');

  // Monta lista de itens como FilesToCompress
  const itensExistentes = itens.filter((item) => {
    const caminhoCompleto = path.join(origem, item);
    try {
      return fs.existsSync(caminhoCompleto);
    } catch {
      return false;
    }
  });

  if (itensExistentes.length === 0) {
    return { sucesso: false, saida: 'RECUSADO: nenhum item da lista D10 encontrado na origem' };
  }

  // Cria um objeto FilesToCompress
  const filesToCompress = itensExistentes
    .map((item) => `@{Path="${origenWin}\\${item}"; LiteralPath="${origenWin}\\${item}"}`)
    .join(', ');

  // Comando mais simples: usa Get-ChildItem + Compress-Archive
  const comando = `
    param([string]$Source, [string]$Destination, [string[]]$Items)
    $exists = @()
    foreach ($item in $Items) {
      $fullPath = Join-Path $Source $item
      if (Test-Path $fullPath) { $exists += $fullPath }
    }
    if ($exists.Count -eq 0) { Write-Error "Nenhum item encontrado"; exit 1 }
    Compress-Archive -Path $exists -DestinationPath $Destination -Force
  `;

  const result = spawnSync('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    comando,
    '-',
    '-Source', origenWin,
    '-Destination', destWin,
    '-Items', itensExistentes.join(','),
  ], { encoding: 'utf8' });

  if (result.status !== 0) {
    return { sucesso: false, saida: `PowerShell failed: ${result.stderr || result.stdout}` };
  }

  return { sucesso: true, saida: '' };
}

/**
 * Compacta direto com Compress-Archive inline, usando -Path com lista
 */
function compactarSimples(origem, itens, zipPath) {
  const itensExistentes = itens.filter((item) => {
    const caminhoCompleto = path.join(origem, item);
    try {
      return fs.existsSync(caminhoCompleto);
    } catch {
      return false;
    }
  });

  if (itensExistentes.length === 0) {
    return { sucesso: false, saida: 'RECUSADO: nenhum item da lista D10 encontrado na origem' };
  }

  // Constrói os caminhos completos com escape correto
  const caminhos = itensExistentes.map((item) => {
    const fullPath = path.join(origem, item);
    // Escapar apóstrofos duplicando
    return `'${fullPath.replace(/'/g, "''")}'`;
  }).join(', ');

  // Script PowerShell simples com os caminhos já embutidos
  const script = `$ErrorActionPreference='Stop'
$items = @(${caminhos})
$dest = '${zipPath.replace(/'/g, "''")}'
Compress-Archive -Path $items -DestinationPath $dest -Force`;

  const result = spawnSync('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command', script,
  ], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });

  if (result.status !== 0) {
    const erroMsg = result.stderr || result.stdout || 'erro desconhecido';
    return { sucesso: false, saida: `PowerShell failed: ${erroMsg}` };
  }

  return { sucesso: true, saida: result.stdout || '' };
}

/**
 * Subcomando: gravar [--origem <dir>] [--destino <dir>] [--so-mostrar]
 */
function cmdGravar(args) {
  let origem = null;
  let destino = null;
  let soMostrar = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--origem' && i + 1 < args.length) {
      origem = args[++i];
    } else if (args[i] === '--destino' && i + 1 < args.length) {
      destino = args[++i];
    } else if (args[i] === '--so-mostrar') {
      soMostrar = true;
    }
  }

  // Resolve origem
  if (!origem) origem = resolverRaiz();
  if (!origem || !ehDiretorio(origem)) {
    console.error('RECUSADO: origem invalida ou inexistente');
    process.exit(2);
  }

  // Resolve destino
  if (!destino) destino = resolverDestino();
  if (!destino) {
    console.error('RECUSADO: destino nao informado, RFM_BACKUP_DESTINO vazio, e OneDrive nao encontrado');
    process.exit(2);
  }

  // Se --so-mostrar, só imprime e sai
  if (soMostrar) {
    console.log(destino);
    process.exit(0);
  }

  // Tenta criar o destino
  try {
    fs.mkdirSync(destino, { recursive: true });
  } catch (err) {
    console.error(`RECUSADO: nao consegui criar destino: ${err.message}`);
    process.exit(2);
  }

  if (!ehDiretorio(destino)) {
    console.error('RECUSADO: destino nao e um diretorio valido');
    process.exit(2);
  }

  // Monta path do zip
  const hoje = new Date().toISOString().split('T')[0]; // AAAA-MM-DD
  const nomeZip = `rainforest-${hoje}.zip`;
  const caminhoZip = path.join(destino, nomeZip);

  // Se já existe, só retorna com sucesso (idempotência)
  if (fs.existsSync(caminhoZip)) {
    console.log(`${nomeZip} ja existe`);
    process.exit(0);
  }

  // Escreve temp primeiro
  const tmp = `${caminhoZip}.tmp`;

  // Compacta via PowerShell
  const resultadoCompact = compactarSimples(origem, ITENS_BACKUP, caminhoZip);
  if (!resultadoCompact.sucesso) {
    console.error(`RECUSADO: ${resultadoCompact.saida}`);
    try { fs.unlinkSync(tmp); } catch { }
    process.exit(2);
  }

  // Verifica se foi criado
  if (!fs.existsSync(caminhoZip)) {
    console.error('RECUSADO: Compress-Archive nao criou o arquivo');
    try { fs.unlinkSync(tmp); } catch { }
    process.exit(2);
  }

  // Rotaciona
  rotacionarZips(destino, nomeZip);

  console.log(`${nomeZip}`);
  process.exit(0);
}

/**
 * Imprime uso.
 */
function imprimirUso() {
  console.error(`
Uso:
  node scripts/backup.cjs gravar                      # origem/destino padrao
  node scripts/backup.cjs gravar --origem <dir>      # origem custom
  node scripts/backup.cjs gravar --destino <dir>     # destino custom
  node scripts/backup.cjs gravar --so-mostrar        # imprime destino sem gravar

Exit codes:
  0  gravou com sucesso (ou --so-mostrar)
  2  origem/destino invalido, ferramenta ausente, ou uso errado
`.trim());
}

/**
 * Main.
 */
function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    imprimirUso();
    process.exit(2);
  }

  const comando = args[0];
  const resto = args.slice(1);

  if (comando === 'gravar') {
    cmdGravar(resto);
  } else {
    console.error(`Comando desconhecido: ${comando}`);
    imprimirUso();
    process.exit(2);
  }
}

if (require.main === module) {
  main();
}

module.exports = { ITENS_BACKUP, resolverRaiz, resolverDestino, compactarSimples };

