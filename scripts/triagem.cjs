#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/**
 * Normaliza uma linha para contagem de repetição:
 * - Substitui literais entre aspas duplas por "S"
 * - Substitui literais entre aspas simples por 'S'
 * - Colapsa espaços múltiplos em um
 * - Remove espaços nas extremidades
 */
function normalizeLine(line) {
  return line
    .replace(/"[^"]*"/g, '"S"')
    .replace(/'[^']*'/g, "'S'")
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Testa se uma linha (com o texto normalizado) aparece 5+ vezes no arquivo
 */
function countOccurrences(normalized, allNormalized) {
  return allNormalized.filter(n => n === normalized).length;
}

/**
 * Calcula o repRatio: proporção de linhas não-vazias cuja forma normalizada
 * aparece 5 vezes ou mais no arquivo
 */
function calculateRepRatio(lines) {
  const nonEmptyLines = lines.filter(line => line.trim() !== '');
  if (nonEmptyLines.length === 0) return 0;

  const normalizedLines = nonEmptyLines.map(normalizeLine);
  const repeatedCount = normalizedLines.filter(
    normalized => countOccurrences(normalized, normalizedLines) >= 5
  ).length;

  return repeatedCount / nonEmptyLines.length;
}

/**
 * Extrai funções usando regex ancorada
 * Regex: /^[ \t]*(?:(?:user|static)[ \t]+)*function[ \t]+([A-Za-z_]\w*)/i
 */
function extractFunctions(lines) {
  const functionRegex = /^[ \t]*(?:(?:user|static)[ \t]+)*function[ \t]+([A-Za-z_]\w*)/i;
  const functions = [];
  let currentIndex = 0;

  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(functionRegex);
    if (match) {
      functions.push({
        index: currentIndex,
        lineNumber: i,
        nome: match[1]
      });
      currentIndex = i;
    }
  }

  // Calcular tamanho de cada função (linhas até a próxima função ou fim do arquivo)
  const funciones = functions.map((func, idx) => {
    const nextFuncLine = idx + 1 < functions.length ? functions[idx + 1].lineNumber : lines.length;
    const tamanho = nextFuncLine - func.lineNumber;
    return {
      nome: func.nome,
      inicio: func.lineNumber + 1, // 1-based line number
      tamanho
    };
  });

  return funciones;
}

/**
 * Classifica o arquivo com base em repRatio e densidade
 */
function classify(repRatio, density) {
  if (repRatio >= 0.6 || density >= 300) {
    return 'dado-como-codigo';
  }
  if (repRatio < 0.4) {
    return 'logica';
  }
  return 'indefinido';
}

/**
 * Processa um arquivo e retorna as métricas
 */
function triageFile(filePath) {
  try {
    // Ler arquivo em latin1 (CP-1252)
    const content = fs.readFileSync(filePath, 'latin1');
    const lines = content.split(/\r?\n/);
    const bytes = Buffer.byteLength(content, 'latin1');

    // Contar linhas
    const nLinhas = lines.length;

    // Extrair funções
    const funcoes = extractFunctions(lines);
    const nfunc = funcoes.length;

    // Calcular repRatio
    const repRatio = calculateRepRatio(lines);

    // Calcular densidade (linhas / nfunc)
    const densidade = nfunc === 0 ? Infinity : nLinhas / nfunc;

    // Calcular hash SHA1 do conteúdo bruto
    const hash = crypto.createHash('sha1').update(content, 'latin1').digest('hex');

    // Classificar
    const classe = classify(repRatio, densidade);

    return {
      arquivo: filePath,
      linhas: nLinhas,
      bytes,
      nfunc,
      funcoes,
      repRatio: parseFloat(repRatio.toFixed(3)),
      densidade: densidade === Infinity ? 'Infinity' : parseFloat(densidade.toFixed(2)),
      hash,
      classe
    };
  } catch (error) {
    throw new Error(`Erro ao processar ${filePath}: ${error.message}`);
  }
}

/**
 * Formata a saída legível
 */
function formatReadable(results) {
  const lines = [];
  results.forEach(result => {
    lines.push(`Arquivo: ${result.arquivo}`);
    lines.push(`  Linhas: ${result.linhas}`);
    lines.push(`  Bytes: ${result.bytes}`);
    lines.push(`  Funções: ${result.nfunc}`);
    lines.push(`  Densidade (lin/func): ${result.densidade}`);
    lines.push(`  Repetição: ${(result.repRatio * 100).toFixed(1)}%`);
    lines.push(`  Hash: ${result.hash}`);
    lines.push(`  Classe: ${result.classe}`);
    if (result.duplicataDe) {
      lines.push(`  Duplicata de: ${result.duplicataDe}`);
    }
    lines.push('');
  });
  return lines.join('\n');
}

/**
 * Main
 */
async function main() {
  const args = process.argv.slice(2);
  let outputJson = false;
  const filePaths = [];

  // Parse arguments
  for (const arg of args) {
    if (arg === '--json') {
      outputJson = true;
    } else {
      filePaths.push(arg);
    }
  }

  if (filePaths.length === 0) {
    console.error('Uso: node scripts/triagem.cjs <arquivo|dir> [--json]');
    process.exit(1);
  }

  try {
    const results = [];
    const hashMap = new Map(); // hash -> primeiro caminho alfabéticamente

    // Processar cada arquivo
    for (const filePath of filePaths) {
      const stats = fs.statSync(filePath);
      let files = [];

      if (stats.isDirectory()) {
        // Se for diretório, processar todos os .prw, .tlpp, .prx
        const allFiles = fs.readdirSync(filePath, { recursive: true });
        files = allFiles
          .filter(f => /\.(prw|tlpp|prx)$/i.test(f))
          .map(f => path.join(filePath, f));
      } else {
        files = [filePath];
      }

      // Processar arquivos
      for (const file of files) {
        const result = triageFile(file);

        // Verificar duplicata
        if (hashMap.has(result.hash)) {
          const canonicalPath = hashMap.get(result.hash);
          if (canonicalPath < file) {
            // Caminho existente é canônico
            result.duplicataDe = canonicalPath;
          } else {
            // Novo caminho é canônico, marcar o antigo
            const prevResult = results.find(r => r.arquivo === canonicalPath);
            if (prevResult) {
              prevResult.duplicataDe = file;
            }
            hashMap.set(result.hash, file);
          }
        } else {
          hashMap.set(result.hash, file);
        }

        results.push(result);
      }
    }

    // Ordenar por arquivo
    results.sort((a, b) => a.arquivo.localeCompare(b.arquivo));

    // Output
    if (outputJson) {
      // Output JSON: array de objetos
      const jsonResults = results.map(r => ({
        arquivo: r.arquivo,
        linhas: r.linhas,
        bytes: r.bytes,
        nfunc: r.nfunc,
        repRatio: r.repRatio,
        densidade: r.densidade === 'Infinity' ? Infinity : r.densidade,
        hash: r.hash,
        classe: r.classe,
        ...(r.duplicataDe && { duplicataDe: r.duplicataDe })
      }));
      console.log(JSON.stringify(jsonResults, null, 2));
    } else {
      console.log(formatReadable(results));
    }
  } catch (error) {
    console.error('Erro:', error.message);
    process.exit(1);
  }
}

main();
