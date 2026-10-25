#!/usr/bin/env node
"use strict";
/* Escolhe as baterias locais pelo diff entre base e head: as testa-* que o diff
 * toca, sem rodar a varredura inteira.
 *
 * Uso: node scripts/baterias-do-diff.cjs --base <ref> [--head <ref>] [--raiz <dir>]
 *   --head padrão HEAD; --raiz padrão o diretório atual (a raiz do repo).
 *
 * Por arquivo alterado:
 *   - testa-* de scripts/ ou hooks/ entra na lista;
 *   - .md e arquivo sob docs/ nunca geram dúvida, mas as baterias que citam o nome-base entram;
 *   - bateria apagada entre base e head não entra (o diff sai com --name-status);
 *   - arquivo de hooks/lib/ ou scripts/lib/ é dúvida "biblioteca compartilhada"
 *     (quebra quem não cita), e as baterias que o citam continuam na lista;
 *   - os demais entram com as baterias que citam o nome-base; nenhuma citando é dúvida.
 *
 * Saída: uma bateria por linha, ordenada e sem repetição. Com dúvida, uma linha
 * `rodar tudo: <arquivo> — <motivo>` por dúvida e exit 3: a seleção não é
 * confiável e a varredura completa é o caminho. Sem dúvida, exit 0.
 * Exit 2 é uso errado; exit 1, git que não consegue ler o diff.
 *
 * POR QUE EXISTE. Escolher bateria à mão deixou passar vermelhas que só a
 * varredura completa achou (lote 1). A evidência incerta vira "rodar tudo", com
 * motivo: a seleção nunca estreita sem dizer por quê. A leitura de citação é a de
 * lib/baterias-vizinhas.cjs (o mesmo D25 do conferir-entrega).
 */
const path = require("path");
const { execFileSync } = require("child_process");
const { bateriasQueCitam } = require(path.join(__dirname, "lib", "baterias-vizinhas.cjs"));
const { caminhoExecutavel } = require(path.join(__dirname, "..", "hooks", "lib", "resolver-executavel.cjs"));

const BATERIA = /^(scripts|hooks)\/testa-[^/]*\.(sh|cjs)$/;
const BIBLIOTECA = /^(hooks|scripts)\/lib\//;
const DOCUMENTO = /^docs\/|\.md$/;

function uso(msg) {
  process.stderr.write(
    "uso: node scripts/baterias-do-diff.cjs --base <ref> [--head <ref>] [--raiz <dir>]\n" +
      (msg ? `${msg}\n` : "")
  );
  process.exit(2);
}

function lerArgs(argv) {
  const a = { base: null, head: "HEAD", raiz: process.cwd() };
  const com = new Set(["--base", "--head", "--raiz"]);
  for (let i = 0; i < argv.length; i++) {
    const chave = argv[i];
    if (!com.has(chave)) uso(`argumento desconhecido: ${chave}`);
    const valor = argv[++i];
    if (valor === undefined || valor.startsWith("--")) uso(`${chave} pede um valor`);
    a[chave.slice(2)] = valor;
  }
  if (!a.base) uso("--base é obrigatório");
  return a;
}

// -z: caminho sai cru, sem aspas nem \303, e separado por \0. --name-status:
// caminho apagado vem marcado com D. Renomeação vira apagado no nome antigo e
// alterado no novo.
function arquivosAlterados(a) {
  let saida;
  try {
    saida = execFileSync(
      caminhoExecutavel("git"),
      ["-c", "core.quotePath=false", "diff", "--name-status", "-z", `${a.base}..${a.head}`, "--"],
      { cwd: a.raiz, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    );
  } catch (e) {
    process.stderr.write(`nao-verificavel: git diff falhou em ${a.base}..${a.head}\n`);
    if (e.stderr) process.stderr.write(String(e.stderr));
    process.exit(1);
  }
  const campos = saida.split("\0");
  const itens = [];
  for (let i = 0; i < campos.length; i++) {
    const status = campos[i];
    if (!status) continue;
    if (status[0] === "R" || status[0] === "C") {
      const antigo = campos[++i];
      const novo = campos[++i];
      if (status[0] === "R") itens.push({ arquivo: antigo, apagado: true });
      itens.push({ arquivo: novo, apagado: false });
    } else {
      itens.push({ arquivo: campos[++i], apagado: status[0] === "D" });
    }
  }
  return itens;
}

function principal(argv) {
  const a = lerArgs(argv);
  const baterias = new Set();
  const duvidas = [];

  for (const { arquivo, apagado } of arquivosAlterados(a)) {
    if (BATERIA.test(arquivo)) {
      if (!apagado) baterias.add(arquivo);
      continue;
    }

    const citam = bateriasQueCitam(a.raiz, arquivo);
    for (const c of citam) baterias.add(c);
    if (DOCUMENTO.test(arquivo)) continue;
    if (BIBLIOTECA.test(arquivo)) {
      duvidas.push({ arquivo, motivo: "biblioteca compartilhada" });
      continue;
    }
    if (citam.length === 0) duvidas.push({ arquivo, motivo: 'nenhuma bateria cita' });
  }

  for (const b of [...baterias].sort()) process.stdout.write(`${b}\n`);
  for (const d of duvidas) process.stdout.write(`rodar tudo: ${d.arquivo} — ${d.motivo}\n`);
  process.exitCode = duvidas.length > 0 ? 3 : 0;
}

principal(process.argv.slice(2));
