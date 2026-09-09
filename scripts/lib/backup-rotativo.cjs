/**
 * Rodízio compartilhado de backups — teto de cópias, deletando a mais antiga.
 *
 * Exported: gravarBackup(arquivoOrigem, pastaBackups, options)
 *   - arquivoOrigem: caminho do arquivo a fazer backup
 *   - pastaBackups: diretório onde os backups ficam
 *   - options.teto: máximo de cópias a guardar (padrão 10)
 *   - options.prefixo: prefixo do nome do arquivo (ex: 'ideias', 'foco-', 'divergencias-')
 *
 * O rodízio:
 *   1. Cria um carimbo (timestamp YYYYMMDD-HHMMSS-zzz)
 *   2. Se arquivo com esse carimbo já existe (mesmo ms), adiciona -2, -3, etc.
 *   3. Copia o arquivo original para pastaBackups/prefixo-carimbo.ext
 *   4. Lista backups que casam com o padrão nome (prefixo + carimbo + extensão)
 *   5. Enquanto houver mais de teto cópias, deleta a mais antiga
 */

const fs = require('fs');
const path = require('path');

function pad(n, len = 2) {
  return String(n).padStart(len, '0');
}

function carimboAgora() {
  const d = new Date();
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}-` +
    `${pad(d.getMilliseconds(), 3)}`
  );
}

/**
 * Faz backup de arquivoOrigem para pastaBackups, implementando rodízio (deletando
 * o mais antigo quando houver excesso).
 *
 * @param {string} arquivoOrigem caminho do arquivo a fazer backup
 * @param {string} pastaBackups diretório destino dos backups
 * @param {object} options configuração
 * @param {number} [options.teto=10] máximo de cópias a guardar
 * @param {string} [options.prefixo='backup'] prefixo do arquivo (sem hífen)
 * @throws {Error} se arquivoOrigem não existir ou copy falhar
 */
function gravarBackup(arquivoOrigem, pastaBackups, options = {}) {
  const teto = options.teto || 10;
  const prefixo = options.prefixo || 'backup';

  if (!fs.existsSync(arquivoOrigem)) {
    throw new Error(`arquivoOrigem não existe: ${arquivoOrigem}`);
  }

  // Cria diretório de backup se não existir
  fs.mkdirSync(pastaBackups, { recursive: true });

  // Gera nome do backup com desempate em caso de mesmo milissegundo
  const ext = path.extname(arquivoOrigem);
  let alvoBackup = path.join(pastaBackups, `${prefixo}-${carimboAgora()}${ext}`);
  for (let n = 2; fs.existsSync(alvoBackup); n++) {
    alvoBackup = path.join(pastaBackups, `${prefixo}-${carimboAgora()}-${n}${ext}`);
  }

  // Copia para backup
  fs.copyFileSync(arquivoOrigem, alvoBackup);

  // Rodízio: deleta o mais antigo se houver excesso
  // Regex que reconhece APENAS arquivos com a forma esperada (prefixo-YYYYMMDD-HHMMSS-zzz, opcionalmente -N)
  // O arquivo pode ter extensão .empty (arquivo vazio temporário) ou a extensão esperada
  const padraoNome = new RegExp(`^${prefixo.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-\\d{8}-\\d{6}-\\d{3}(-\\d+)?(\\${ext}|.empty)$`);
  const listar = () => fs
    .readdirSync(pastaBackups)
    .filter((f) => padraoNome.test(f))
    .sort();

  let candidatos = listar();
  while (candidatos.length > teto) {
    fs.unlinkSync(path.join(pastaBackups, candidatos[0]));
    candidatos = listar();
  }

  return { backup: alvoBackup, totalBackups: candidatos.length };
}

module.exports = { gravarBackup };
