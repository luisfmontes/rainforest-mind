#!/usr/bin/env node
"use strict";
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

// -- Configuração -----------------------------------------------------------

const ARGS = { hash: null, exige: [] };
let i = 2;
while (i < process.argv.length) {
  const arg = process.argv[i];
  if (arg === "--hash") {
    ARGS.hash = process.argv[++i];
  } else if (arg === "--exige") {
    if (i + 1 >= process.argv.length) {
      falha(2, "--exige exige um caminho");
    }
    ARGS.exige.push(process.argv[++i]);
  } else {
    falha(2, "Flag desconhecida: " + arg);
  }
  i++;
}

if (!ARGS.hash) {
  falha(2, "--hash é obrigatório");
}

// -- Funções ----------------------------------------------------------------

function falha(exitCode, mensagem) {
  console.error(`Erro: ${mensagem}`);
  process.exit(exitCode);
}

function gitSync(cwd, ...args) {
  try {
    const r = spawnSync("git", args, {
      cwd,
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
    });
    if (r.error && r.error.code === "ENOENT") {
      return { status: 69, stdout: "", stderr: "nao-verificavel: git nao encontrado" };
    }
    return { status: r.status, stdout: r.stdout.trim(), stderr: r.stderr.trim() };
  } catch (err) {
    return { status: 69, stdout: "", stderr: "nao-verificavel: erro ao chamar git" };
  }
}

function getGitDir(cwd) {
  const r = gitSync(cwd, "rev-parse", "--git-dir");
  return r.status === 0 ? r.stdout : null;
}

function getGitCommonDir(cwd) {
  const r = gitSync(cwd, "rev-parse", "--git-common-dir");
  return r.status === 0 ? r.stdout : null;
}

function getTopLevel(cwd) {
  const r = gitSync(cwd, "rev-parse", "--show-toplevel");
  return r.status === 0 ? r.stdout : null;
}

function getCurrentHead(cwd) {
  const r = gitSync(cwd, "rev-parse", "HEAD");
  return r.status === 0 ? r.stdout : null;
}

// -- Verificações ----------------------------------------------------------

// (a) Recusa se não é worktree linkado
const cwd = process.cwd();
const gitdir = getGitDir(cwd);
if (!gitdir) {
  falha(69, "nao-verificavel: não é um repositório git");
}

const gitcommondir = getGitCommonDir(cwd);
if (!gitcommondir) {
  falha(69, "nao-verificavel: não conseguiu obter git-common-dir");
}

const normalizedGitdir = path.resolve(cwd, gitdir);
const normalizedCommondir = path.resolve(cwd, gitcommondir);

if (normalizedGitdir === normalizedCommondir) {
  falha(1, "não é um worktree linkado");
}

const toplevel = getTopLevel(cwd);
if (!toplevel) {
  falha(69, "nao-verificavel: não conseguiu obter toplevel");
}

// (b) Resolve H com git rev-parse --verify H^{commit}
const rVerify = gitSync(cwd, "rev-parse", "--verify", `${ARGS.hash}^{commit}`);
if (rVerify.status !== 0) {
  falha(1, "não conseguiu resolver '" + ARGS.hash + "' como commit");
}
const hashResolvido = rVerify.stdout;

// (c) HEAD == H: segue; senão faz git merge-base --is-ancestor HEAD H
const headAtual = getCurrentHead(cwd);
if (!headAtual) {
  falha(69, "nao-verificavel: não conseguiu obter HEAD");
}

// Cada --exige tem de existir no worktree. Roda em TODA saida de sucesso,
// inclusive a de "HEAD ja contem" (revisao 2: ali o --exige era ignorado).
function conferirExige() {
  for (const arquivo of ARGS.exige) {
    const alvo = path.resolve(cwd, arquivo);
    const rel = path.relative(toplevel, alvo);
    if (rel === "") {
      falha(2, "--exige aponta para a raiz do worktree: '" + arquivo + "'");
    }
    if (rel === ".." || rel.startsWith(".." + path.sep) || path.isAbsolute(rel)) {
      falha(2, "--exige fora do worktree: '" + arquivo + "'");
    }
    if (!fs.existsSync(alvo)) {
      falha(1, "arquivo exigido não existe: '" + arquivo + "'");
    }
  }
}

if (headAtual !== hashResolvido) {
  // Verificar se H é ancestral de HEAD (trabalho já foi feito/reexecução)
  const rAncestorCheckReexec = gitSync(cwd, "merge-base", "--is-ancestor", hashResolvido, headAtual);
  if (rAncestorCheckReexec.status === 0) {
    // H é ancestral de HEAD - trabalho já foi feito
    conferirExige(); // rota ja-contem tambem confere
    const headShort = headAtual.substring(0, 12);
    console.log(`base-ok: HEAD ja contem ${headShort} (trabalho commitado em cima)`);
    process.exit(0);
  }

  // Verificar se HEAD é ancestral de H (pode fazer merge)
  const rAncestor = gitSync(cwd, "merge-base", "--is-ancestor", headAtual, hashResolvido);
  const ancestral = rAncestor.status === 0;

  if (!ancestral) falha(1, "divergencia real: HEAD nao e ancestral do hash do briefing");

  // faz git merge --ff-only
  const rMerge = gitSync(cwd, "merge", "--ff-only", hashResolvido);
  if (rMerge.status !== 0) {
    falha(1, "falha no merge --ff-only: " + rMerge.stderr);
  }
}

// (d) Relê HEAD e exige == H
const headNovoAtual = getCurrentHead(cwd);
if (!headNovoAtual) {
  falha(69, "nao-verificavel: não conseguiu obter HEAD após merge");
}

if (headNovoAtual !== hashResolvido) {
  falha(1, "HEAD após merge ('" + headNovoAtual + "') não bate com esperado ('" + hashResolvido + "')");
}

// (e) Cada --exige tem de existir no worktree
conferirExige();

// -- Sucesso ----------------------------------------------------------------
const hash12 = hashResolvido.substring(0, 12);
console.log(`base-ok ${hash12} ${toplevel}`);
process.exit(0);
