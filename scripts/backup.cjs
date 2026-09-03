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
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const os = require('os');
const { executar } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));

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
    const { resolverRaiz: r } = require(path.join(__dirname, '..', 'hooks', 'lib', 'raiz.cjs'));
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

  const result = executar('powershell', [
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
 * Calcula hash SHA256 de um arquivo.
 */
function calcularHashSha256(caminhoArquivo) {
  try {
    const conteudo = fs.readFileSync(caminhoArquivo);
    return crypto.createHash('sha256').update(conteudo).digest('hex');
  } catch (err) {
    return null;
  }
}

/**
 * Lista arquivos recursivamente em um diretório.
 */
function listarArquivosRecursivamente(dir) {
  const arquivos = [];

  function lerDiretorio(currentDir) {
    try {
      const items = fs.readdirSync(currentDir);
      for (const item of items) {
        const fullPath = path.join(currentDir, item);
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
          lerDiretorio(fullPath);
        } else if (stat.isFile()) {
          arquivos.push(fullPath);
        }
      }
    } catch {
      // Ignora erros ao ler diretório
    }
  }

  lerDiretorio(dir);
  return arquivos.sort();
}

/**
 * Subcomando: conferir [--destino <dir>] [--origem <dir>]
 */
function cmdConferir(args) {
  let origem = null;
  let destino = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--origem' && i + 1 < args.length) {
      origem = args[++i];
    } else if (args[i] === '--destino' && i + 1 < args.length) {
      destino = args[++i];
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
  if (!destino || !ehDiretorio(destino)) {
    console.error('RECUSADO: destino invalido ou inexistente');
    process.exit(2);
  }

  // Procura o zip mais recente no destino
  const zips = fs.readdirSync(destino)
    .filter((f) => /^rainforest-\d{4}-\d{2}-\d{2}\.zip$/.test(f))
    .sort()
    .reverse(); // mais recentes primeiro

  if (zips.length === 0) {
    console.error('nada para conferir');
    process.exit(2);
  }

  const nomeZipMaisRecente = zips[0];
  const caminhoZip = path.join(destino, nomeZipMaisRecente);

  // Extrai o zip para uma pasta temporária
  const expandDir = fs.mkdtempSync(path.join(os.tmpdir(), 'rainforest-conferir-'));
  let expandDirWin;
  try {
    expandDirWin = expandDir.replace(/\//g, '\\');
  } catch {
    expandDirWin = expandDir;
  }

  const caminhoZipWin = caminhoZip.replace(/\//g, '\\');

  const expandResult = spawnSync('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    `Expand-Archive -Path '${caminhoZipWin}' -DestinationPath '${expandDirWin}' -Force 2>&1`,
  ], { encoding: 'utf8' });

  if (expandResult.status !== 0) {
    console.error(`RECUSADO: nao consegui expandir o zip: ${expandResult.stderr || expandResult.stdout}`);
    try { fs.rmSync(expandDir, { recursive: true, force: true }); } catch { }
    process.exit(2);
  }

  // Compara arquivo por arquivo
  let arquivoDivergente = null;
  let descricaoDivergencia = null;

  try {
    const arquivosExpandidos = listarArquivosRecursivamente(expandDir);

    for (const arquivoExpandido of arquivosExpandidos) {
      // Calcula caminho relativo desde o expandDir
      const caminhoRelativo = path.relative(expandDir, arquivoExpandido);
      const caminhoOrigem = path.join(origem, caminhoRelativo);

      // Verifica se existe na origem
      if (!fs.existsSync(caminhoOrigem)) {
        arquivoDivergente = caminhoRelativo;
        descricaoDivergencia = 'arquivo nao existe na origem';
        break;
      }

      // Compara hashes
      const hashExpandido = calcularHashSha256(arquivoExpandido);
      const hashOrigem = calcularHashSha256(caminhoOrigem);

      if (hashExpandido !== hashOrigem) {
        arquivoDivergente = caminhoRelativo;
        descricaoDivergencia = `hash diverge (backup: ${hashExpandido}, origem: ${hashOrigem})`;
        break;
      }
    }

    // Direcao inversa (origem -> zip): item da lista D10 presente na origem tem
    // de estar no zip. Sem isso, um item ausente do zip passava como "intacto" —
    // a comparacao anterior so anda sobre o que JA esta no zip.
    if (!arquivoDivergente) {
      for (const item of ITENS_BACKUP) {
        const caminhoItemOrigem = path.join(origem, item);
        let statItem;
        try {
          statItem = fs.statSync(caminhoItemOrigem);
        } catch {
          continue; // item nao existe na origem: nao e esperado no zip
        }

        const esperados = statItem.isDirectory()
          ? listarArquivosRecursivamente(caminhoItemOrigem).map((a) => path.relative(origem, a))
          : [item];

        for (const relativo of esperados) {
          if (!fs.existsSync(path.join(expandDir, relativo))) {
            arquivoDivergente = relativo;
            descricaoDivergencia = 'existe na origem e nao esta no zip';
            break;
          }
        }
        if (arquivoDivergente) break;
      }
    }

    if (arquivoDivergente) {
      console.error(`${arquivoDivergente}: ${descricaoDivergencia}`);
      console.error('sincronizacao e do OneDrive, nao conferida aqui');
      try { fs.rmSync(expandDir, { recursive: true, force: true }); } catch { }
      process.exit(1);
    }

    // Tudo bateu
    const stat = fs.statSync(caminhoZip);
    const dataMtime = new Date(stat.mtime).toISOString().split('T')[0];
    console.log('intacto');
    console.log(dataMtime);
    console.log('sincronizacao e do OneDrive, nao conferida aqui');
    try { fs.rmSync(expandDir, { recursive: true, force: true }); } catch { }
    process.exit(0);
  } catch (err) {
    console.error(`RECUSADO: erro ao comparar arquivos: ${err.message}`);
    try { fs.rmSync(expandDir, { recursive: true, force: true }); } catch { }
    process.exit(2);
  }
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

  // Compacta num nome temporario no mesmo diretorio (escrita atomica: so vira o
  // nome final com o renameSync abaixo, e so no sucesso). Termina em ".zip" de
  // proposito: Compress-Archive acrescenta ".zip" quando a extensao nao e essa,
  // e um nome que ja termina em ".zip" nao sofre esse acrescimo.
  const nomeTmp = `rainforest-${hoje}.parcial.zip`;
  const caminhoTmp = path.join(destino, nomeTmp);

  // Limpa um parcial deixado por uma tentativa anterior que falhou no meio
  try { fs.unlinkSync(caminhoTmp); } catch { }

  // Compacta via PowerShell
  const resultadoCompact = compactarSimples(origem, ITENS_BACKUP, caminhoTmp);
  if (!resultadoCompact.sucesso) {
    console.error(`RECUSADO: ${resultadoCompact.saida}`);
    try { fs.unlinkSync(caminhoTmp); } catch { }
    process.exit(2);
  }

  // Verifica se foi criado
  if (!fs.existsSync(caminhoTmp)) {
    console.error('RECUSADO: Compress-Archive nao criou o arquivo');
    try { fs.unlinkSync(caminhoTmp); } catch { }
    process.exit(2);
  }

  // So agora o zip passa a existir com o nome final — atomico via rename
  try {
    fs.renameSync(caminhoTmp, caminhoZip);
  } catch (err) {
    console.error(`RECUSADO: nao consegui renomear para o nome final: ${err.message}`);
    try { fs.unlinkSync(caminhoTmp); } catch { }
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
  } else if (comando === 'conferir') {
    cmdConferir(resto);
  } else {
    console.error(`Comando desconhecido: ${comando}`);
    imprimirUso();
    process.exit(2);
  }
}

if (require.main === module) {
  main();
}

module.exports = {
  ITENS_BACKUP,
  resolverRaiz,
  resolverDestino,
  compactarSimples,
  calcularHashSha256,
  listarArquivosRecursivamente,
};

