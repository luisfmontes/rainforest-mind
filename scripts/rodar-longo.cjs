#!/usr/bin/env node
"use strict";
// Processo longo fora do teto de 10 min do Bash (D7 do design
// docs/rainforest/design/2026-10-13-executar-autonomo.md; tarefa 2 do plano).
//
//   iniciar --saida <arq> -- <comando...>   sobe o comando destacado, com
//                                           stdout e stderr no arquivo, e sai
//                                           na hora imprimindo o PID do comando.
//   estado  --saida <arq>                   imprime `rodando` (exit 3),
//                                           `exit <N>` (exit 0) ou `morto`
//                                           (exit 4).
//   vigiar  (interno)                       processo destacado que é PAI do
//                                           comando e escreve `exit <N>` quando
//                                           ele termina.
//
// POR QUE O VIGIA EXISTE: quem sai na hora não espera o filho. No Windows, um
// processo que não é filho não expõe o exit code, então quem registra o exit
// tem de ser o pai do comando. O vigia é o próprio rodar-longo.cjs relançado
// destacado, e o `iniciar` só espera o PID dele aparecer no `<arq>.pid`.
//
// O comando roda por `bash -c`, com os argumentos citados um a um. O bash é o
// que o PATH resolve primeiro (resolverExecutavel, mesma regra de
// hooks/lib/resolver-executavel.cjs), e a janela nunca abre: windowsHide.
//
// O exit vai também para `<arq>.exit`: o comando pode imprimir uma linha
// `exit N` no `<arq>`, e o estado não pode confundir as duas. Sem `.exit` e com
// o vigia do `.pid` morto, o estado diz `morto` em vez de `rodando` para sempre.
//
// Exit: 0 ok; 2 uso; 4 morto; 69 ambiente (bash ausente ou PID que não apareceu).

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const { resolverExecutavel } = require(path.join(__dirname, "..", "hooks", "lib", "resolver-executavel.cjs"));

const LIMITE_PID_MS = 1800;

function erro(codigo, mensagem) {
  process.stderr.write(`rodar-longo: ${mensagem}\n`);
  process.exit(codigo);
}

function flagsDe(argv) {
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--") break;
    if (argv[i].startsWith("--")) {
      flags[argv[i].slice(2)] = argv[i + 1];
      i++;
    }
  }
  return flags;
}

function comandoApos(argv) {
  const i = argv.indexOf("--");
  return i === -1 ? [] : argv.slice(i + 1);
}

const citar = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
const pidPath = (saida) => saida + ".pid";
const exitPath = (saida) => saida + ".exit";

function dormir(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function esperarPid(saida, limiteMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < limiteMs) {
    try {
      const d = JSON.parse(fs.readFileSync(pidPath(saida), "utf8"));
      if (Number.isInteger(d.comando)) return d.comando;
    } catch {
      // ainda não gravado (ou gravação em andamento): tenta de novo
    }
    dormir(10);
  }
  return null;
}

function iniciar(flags, comando) {
  const saida = flags.saida;
  if (!saida || comando.length === 0) erro(2, "uso: iniciar --saida <arq> -- <comando...>");
  const arq = path.resolve(saida);
  if (!resolverExecutavel("bash")) erro(69, "bash nao encontrado no PATH");

  fs.writeFileSync(arq, "");
  fs.rmSync(pidPath(arq), { force: true });
  fs.rmSync(exitPath(arq), { force: true });

  const vigia = spawn(process.execPath, [__filename, "vigiar", "--saida", arq, "--", ...comando], {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  vigia.unref();

  const pid = esperarPid(arq, LIMITE_PID_MS);
  if (pid === null) erro(69, `o PID do comando nao apareceu em ${LIMITE_PID_MS} ms`);
  process.stdout.write(`${pid}\n`);
  process.exit(0);
}

function vigiar(flags, comando) {
  const saida = flags.saida;
  const bash = resolverExecutavel("bash");
  // "w", não "a": no Windows, o handle de append herdado pelo bash não grava.
  // O iniciar já zerou o arquivo, então "w" não perde nada.
  const fd = fs.openSync(saida, "w");
  const filho = spawn(bash, ["-c", comando.map(citar).join(" ")], {
    stdio: ["ignore", fd, fd],
    windowsHide: true,
  });
  fs.closeSync(fd);

  const tmp = pidPath(saida) + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify({ vigia: process.pid, comando: filho.pid ?? null }));
  fs.renameSync(tmp, pidPath(saida));

  let feito = false;
  filho.on("error", (e) => {
    fs.appendFileSync(saida, `\n${e.message}\n`);
    registrar(127);
  });
  filho.on("exit", (code, sinal) => registrar(code ?? (sinal ? 128 : 1)));

  function registrar(codigo) {
    if (feito) return;
    feito = true;
    fs.appendFileSync(saida, `\nexit ${codigo}\n`);
    fs.writeFileSync(exitPath(saida), String(codigo));
  }
}

function estado(flags) {
  const saida = flags.saida;
  if (!saida) erro(2, "uso: estado --saida <arq>");
  const arq = path.resolve(saida);
  if (!fs.existsSync(arq)) erro(2, `saida nao existe: ${saida}`);
  const codigo = lerExit(arq);
  if (codigo !== null) {
    process.stdout.write(`exit ${codigo}\n`);
    process.exit(0);
  }
  let vigia = null;
  try {
    vigia = JSON.parse(fs.readFileSync(pidPath(arq), "utf8")).vigia;
  } catch {
    // .pid ainda não gravado: conta como rodando
  }
  if (Number.isInteger(vigia) && !vivo(vigia)) {
    // o vigia pode ter gravado o .exit entre a primeira leitura e agora
    const tardio = lerExit(arq);
    if (tardio !== null) {
      process.stdout.write(`exit ${tardio}\n`);
      process.exit(0);
    }
    process.stdout.write("morto\n");
    process.exit(4);
  }
  process.stdout.write("rodando\n");
  process.exit(3);
}

function lerExit(arq) {
  try {
    const c = fs.readFileSync(exitPath(arq), "utf8").trim();
    return /^\d+$/.test(c) ? c : null;
  } catch {
    return null;
  }
}

function vivo(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code === "EPERM";
  }
}

const sub = process.argv[2];
const flags = flagsDe(process.argv.slice(3));
const comando = comandoApos(process.argv.slice(3));

if (sub === "iniciar") iniciar(flags, comando);
else if (sub === "vigiar") vigiar(flags, comando);
else if (sub === "estado") estado(flags);
else erro(2, "uso: rodar-longo.cjs iniciar|estado ...");
