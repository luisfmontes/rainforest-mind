#!/usr/bin/env node
"use strict";
/* Edição literal com contagem e asserção. Substitui `de` por `para` em um arquivo.
 *
 * POR QUE EXISTE: String.replace com $ ou $` no texto novo corrompe o arquivo
 * (registrado em memória do usuário). Este script usa busca byte a byte em Buffer
 * e conta ocorrências antes e depois para garantir atomicidade sem decodificação.
 *
 * INTERFACE:
 *   node scripts/substituir.cjs --arquivo <F> --de <arquivo-de> --para <arquivo-para> [--ocorrencias N]
 *
 * Argumentos:
 *   --arquivo <F>:        arquivo a ser modificado (recusa symlink)
 *   --de <arquivo-de>:    caminho do arquivo contendo o texto a substituir (bytes)
 *   --para <arquivo-para>: caminho do arquivo contendo o texto novo (bytes)
 *   --ocorrencias N:      número esperado de ocorrências (padrão: 1)
 *
 * Saídas:
 *   0  sucesso
 *   1  contagem divergente (arquivo não é alterado)
 *   2  erro de uso (flag ausente, arquivo inexistente, symlink, etc)
 */

const fs = require("fs");
const path = require("path");

const OPCOES = {
  help: { dest: "help", flag: true },
  arquivo: { dest: "arquivo", exige: true },
  de: { dest: "de", exige: true },
  para: { dest: "para", exige: true },
  ocorrencias: { dest: "ocorrencias", padrao: "1" },
};

function falha(codigo, msg) {
  console.error(`erro: ${msg}`);
  process.exit(codigo);
}

function erroArgs(msg) {
  console.error(`erro: ${msg}`);
  ajuda();
  process.exit(2);
}

function parseArgs(argv) {
  const a = { arquivo: "", de: "", para: "", ocorrencias: "1", help: false };
  let i = 0;
  while (i < argv.length) {
    const tok = argv[i];
    if (!tok.startsWith("--")) erroArgs(`argumento inesperado: ${tok}`);
    const o = OPCOES[tok.slice(2)];
    if (!o) erroArgs(`opcao desconhecida: ${tok}`);
    if (o.flag) {
      a[o.dest] = true;
      i += 1;
      continue;
    }
    const val = argv[i + 1];
    if (val === undefined) erroArgs(`opcao ${tok} exige valor`);
    a[o.dest] = val;
    i += 2;
  }
  for (const [chave, o] of Object.entries(OPCOES)) {
    if (o.exige && !a[o.dest]) erroArgs(`opcao obrigatoria faltando: --${chave}`);
  }
  return a;
}

function ajuda() {
  console.error(`uso: node scripts/substituir.cjs [opcoes]

Opcoes obrigatorias:
  --arquivo <F>         arquivo a ser modificado (recusa symlink)
  --de <arquivo-de>     arquivo contendo o texto a substituir (bytes)
  --para <arquivo-para> arquivo contendo o texto novo (bytes)

Opcoes opcionais:
  --ocorrencias N   número esperado de ocorrências (padrão: 1)
  --help            exibe esta ajuda

Exit codes:
  0  sucesso
  1  contagem divergente (arquivo não alterado)
  2  erro de uso (symlink, arquivo inexistente, validação falhou antes de gravar)
`);
}

function main() {
  const a = parseArgs(process.argv.slice(2));

  if (a.help) {
    ajuda();
    return 0;
  }

  const esperado = parseInt(a.ocorrencias, 10);
  if (isNaN(esperado) || esperado < 0) {
    falha(2, "--ocorrencias deve ser um número não-negativo");
  }

  // Valida arquivo alvo: não pode ser symlink
  let st;
  try {
    st = fs.lstatSync(a.arquivo);
  } catch (e) {
    falha(2, `arquivo '${a.arquivo}' inexistente ou inacessível`);
  }
  if (st.isSymbolicLink()) {
    falha(2, `arquivo '${a.arquivo}' é um symlink (recusado)`);
  }
  const modoBits = st.mode & 0o7777;

  // Lê `de` como Buffer, remove um 0x0A final se houver
  let de;
  try {
    de = fs.readFileSync(a.de);
  } catch (e) {
    falha(2, `arquivo '${a.de}' inexistente ou ilegível`);
  }
  if (de.length > 0 && de[de.length - 1] === 0x0A) {
    de = de.slice(0, -1);
  }
  if (de.length === 0) {
    falha(2, "--de vazio");
  }

  // Lê `para` como Buffer, remove um 0x0A final se houver
  let para;
  try {
    para = fs.readFileSync(a.para);
  } catch (e) {
    falha(2, `arquivo '${a.para}' inexistente ou ilegível`);
  }
  if (para.length > 0 && para[para.length - 1] === 0x0A) {
    para = para.slice(0, -1);
  }

  // Lê arquivo alvo como Buffer (operações byte a byte)
  let conteudo;
  try {
    conteudo = fs.readFileSync(a.arquivo);
  } catch (e) {
    falha(2, `arquivo '${a.arquivo}' inexistente ou ilegível`);
  }

  // Conta ocorrências de `de` em `conteudo` (varredura não-sobreposta, esquerda→direita)
  let ocorrencias = 0;
  let pos = 0;
  while ((pos = conteudo.indexOf(de, pos)) !== -1) {
    ocorrencias++;
    pos += de.length;
  }

  // Valida contagem
  if (ocorrencias !== esperado) falha(1, "contagem divergente");

  // Realiza substituição byte a byte
  let novoConteudo = conteudo;
  pos = 0;
  while ((pos = novoConteudo.indexOf(de, pos)) !== -1) {
    novoConteudo = Buffer.concat([
      novoConteudo.slice(0, pos),
      para,
      novoConteudo.slice(pos + de.length)
    ]);
    pos += para.length;
  }

  // ANTES DE GRAVAR: valida asserções no Buffer resultante
  // Asserção 1: `para` está presente no resultado. `--para` vazio é apagar
  // o trecho: não há texto novo a procurar, e a asserção 2 cobre o resíduo.
  if (para.length > 0 && novoConteudo.indexOf(para) === -1) {
    falha(2, "texto novo não encontrado no resultado");
  }

  // Asserção 2: resíduo falso (se novo não contém antigo, antigo não pode estar no resultado)
  if (para.indexOf(de) === -1 && novoConteudo.indexOf(de) !== -1) {
    falha(2, "substituição criaria nova ocorrência de --de por junção");
  }

  // TUDO OK: grava em arquivo temporário no MESMO DIRETÓRIO do alvo
  const alvoDir = path.dirname(a.arquivo);
  const tempFile = path.join(alvoDir, `.substituir-${process.pid}-${Date.now()}.tmp`);

  try {
    fs.writeFileSync(tempFile, novoConteudo);
  } catch (e) {
    falha(2, `não foi possível gravar arquivo temporário: ${e.message}`);
  }

  // Preserva permissões
  try {
    fs.chmodSync(tempFile, modoBits);
  } catch (e) {
    // Tenta limpar temp se chmod falhar
    try {
      fs.unlinkSync(tempFile);
    } catch {}
    falha(2, `não foi possível preservar permissões: ${e.message}`);
  }

  // Rename atômico
  try {
    fs.renameSync(tempFile, a.arquivo);
  } catch (e) {
    // Limpa arquivo temporário se rename falhar
    try {
      fs.unlinkSync(tempFile);
    } catch {}
    falha(2, `não foi possível renomear arquivo: ${e.message}`);
  }

  return 0;
}

process.exitCode = main();
