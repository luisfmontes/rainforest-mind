#!/usr/bin/env node
"use strict";
/* Portaria — MODO CAPTURA (Tarefa 2 do fluxo 9, D7).
 *
 * Registrado como PreToolUse em `.claude/settings.json` com matcher de
 * despacho de subagente. Neste modo ele NAO decide nada: le o payload que o
 * harness manda no stdin e grava a PRIMEIRA amostra em
 * `.rainforest/portaria/amostra.json` (relativo a raiz do projeto), para o
 * parser do nucleo (Tarefa 3) se fixar em payload REAL, nao em schema
 * imaginado — o incidente de 2026-08-19 (hook lendo `evento.project`, campo
 * que o harness nunca envia) e o motivo de a Q3 ter fechado assim.
 *
 * Primeira captura vence (D7): se a amostra ja existe, nada e sobrescrito —
 * a amostra e documentacao datada, nao estado vivo.
 *
 * Exit 0 SEMPRE: modo captura nao bloqueia despacho nenhum.
 */

const fs = require("fs");
const path = require("path");

function raizDoProjeto() {
  return process.env.CLAUDE_PROJECT_DIR || process.cwd();
}

function main() {
  let bruto = "";
  try {
    bruto = fs.readFileSync(0, "utf8");
  } catch {
    process.exit(0);
  }
  if (!bruto.trim()) process.exit(0);

  let payload;
  try {
    payload = JSON.parse(bruto);
  } catch {
    // Payload ilegivel nao vira amostra: amostra invalida fixaria o parser errado.
    process.exit(0);
  }

  const dir = path.join(raizDoProjeto(), ".rainforest", "portaria");
  const amostraPath = path.join(dir, "amostra.json");

  if (!fs.existsSync(amostraPath)) {
    try {
      fs.mkdirSync(dir, { recursive: true });
      const tmp = amostraPath + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(payload, null, 2) + "\n", "utf8");
      fs.renameSync(tmp, amostraPath);
    } catch {
      // Falha de gravacao nao pode travar a sessao do usuario.
    }
  }

  process.exit(0);
}

main();
