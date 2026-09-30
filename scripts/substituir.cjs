#!/usr/bin/env node
"use strict";
/* Edição literal com contagem e asserção. Substitui `de` por `para` em um arquivo.
 *
 * POR QUE EXISTE: String.replace com $ ou $` no texto novo corrompe o arquivo
 * (registrado em memória do usuário). Este script usa split/join para evitar a
 * interpolação mágica do Node e conta ocorrências antes e depois para garantir
 * atomicidade.
 *
 * INTERFACE:
 *   node scripts/substituir.cjs --arquivo <F> --de <arquivo-de> --para <arquivo-para> [--ocorrencias N]
 *
 * Argumentos:
 *   --arquivo <F>:        arquivo a ser modificado
 *   --de <arquivo-de>:    caminho do arquivo contendo o texto a substituir
 *   --para <arquivo-para>: caminho do arquivo contendo o texto novo
 *   --ocorrencias N:      número esperado de ocorrências (padrão: 1)
 *
 * Saídas:
 *   0  sucesso
 *   1  contagem divergente (arquivo não é alterado)
 *   2  erro de uso (flag ausente, arquivo inexistente, etc)
 */

const fs = require("fs");
const path = require("path");
const { tmpdir } = require("os");

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
  --arquivo <F>         arquivo a ser modificado
  --de <arquivo-de>     arquivo contendo o texto a substituir
  --para <arquivo-para> arquivo contendo o texto novo

Opcoes opcionais:
  --ocorrencias N   número esperado de ocorrências (padrão: 1)
  --help            exibe esta ajuda

Exemplo:
  node scripts/substituir.cjs \\
    --arquivo scripts/estado.cjs \\
    --de de.txt \\
    --para para.txt \\
    --ocorrencias 1

Exit codes:
  0  sucesso
  1  contagem divergente (arquivo não alterado)
  2  erro de uso
`);
}

function main() {
  const a = parseArgs(process.argv.slice(2));

  if (a.help) {
    ajuda();
    return 0;
  }

  // Lê arquivo de texto `de`
  let de;
  try {
    de = fs.readFileSync(a.de, "utf8");
  } catch (e) {
    falha(2, `arquivo '${a.de}' inexistente ou ilegível`);
  }

  // Remove um \n final se houver
  if (de.endsWith("\n")) {
    de = de.slice(0, -1);
  }

  // Valida que `de` não é vazio
  if (de.length === 0) {
    falha(2, "--de vazio");
  }

  // Lê arquivo de texto `para`
  let para;
  try {
    para = fs.readFileSync(a.para, "utf8");
  } catch (e) {
    falha(2, `arquivo '${a.para}' inexistente ou ilegível`);
  }

  // Remove um \n final se houver
  if (para.endsWith("\n")) {
    para = para.slice(0, -1);
  }

  // Lê arquivo alvo
  let conteudo;
  try {
    conteudo = fs.readFileSync(a.arquivo, "utf8");
  } catch (e) {
    falha(2, `arquivo '${a.arquivo}' inexistente ou ilegível`);
  }

  // Conta ocorrências do texto `de`
  const ocorrencias = conteudo.split(de).length - 1;
  const esperado = parseInt(a.ocorrencias, 10);

  if (isNaN(esperado) || esperado < 0) {
    falha(2, "--ocorrencias deve ser um número não-negativo");
  }

  // Valida contagem
  if (ocorrencias !== esperado) falha(1, "contagem divergente");

  // Realiza substituição usando split/join (evita problema com $ em replace)
  const novoConteudo = conteudo.split(de).join(para);

  // Grava em arquivo temporário
  const tempDir = tmpdir();
  const tempFile = path.join(tempDir, `substituir-${Date.now()}-${Math.random().toString(36).slice(2)}.tmp`);

  try {
    fs.writeFileSync(tempFile, novoConteudo, "utf8");
  } catch (e) {
    falha(2, `não foi possível gravar arquivo temporário: ${e.message}`);
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

  // Relê arquivo para validar
  let conteudoGravado;
  try {
    conteudoGravado = fs.readFileSync(a.arquivo, "utf8");
  } catch (e) {
    falha(2, `não foi possível reler arquivo após gravação: ${e.message}`);
  }

  // Confere que o texto novo está presente
  if (!conteudoGravado.includes(para)) {
    falha(2, "texto novo não encontrado no arquivo após substituição");
  }

  // Confere que o texto antigo sumiu (se não estiver contido no novo)
  if (!para.includes(de) && conteudoGravado.includes(de)) {
    falha(2, "texto antigo ainda presente no arquivo");
  }

  return 0;
}

process.exitCode = main();
