"use strict";
/**
 * Duas leituras, uma decisão (#736, D4 de docs/rainforest/design/2026-11-25-zerar-issues-18.md).
 *
 * A leitura nova de `segmentosComAspas` (escape, `$'...'` e comentário pelo dialeto)
 * junta texto que a antiga separava, e cada rodada de revisão achou uma forma em que
 * a antiga barrava e a nova deixava passar. Em vez de enumerar formas, o gate roda
 * duas vezes: primeiro com a leitura nova; se ela libera (exit 0), de novo com a
 * antiga, que é a da base de antes do #736. Barra se qualquer das duas barrar.
 *
 * Mecânica: a entrada (stdin) é lida uma vez e servida às duas passadas, e o
 * `process.exit(0)` da primeira passada dispara a segunda em vez de sair. Exit
 * diferente de 0 sai na hora. A segunda passada só roda quando o comando tem algum
 * caractere em que as leituras podem divergir (contrabarra, crase, `#`, CR, `$'`):
 * sem eles as duas produzem os mesmos segmentos.
 */
const fs = require("fs");
const { definirLeituraAntiga } = require("./cwd-efetivo.cjs");

const DIVERGE = /[\\`#\r]|\$'/;

function precisaDaSegunda(entrada) {
  try {
    const ev = JSON.parse(entrada || "{}");
    const cmd = ev && ev.tool_input && ev.tool_input.command;
    return typeof cmd === "string" && DIVERGE.test(cmd);
  } catch {
    return false;
  }
}

function rodarComDuasLeituras(main) {
  let entrada = "";
  try { entrada = fs.readFileSync(0, "utf8"); } catch {}
  const lerOriginal = fs.readFileSync;
  fs.readFileSync = function (alvo, ...resto) {
    if (alvo === 0) return entrada;
    return lerOriginal.call(fs, alvo, ...resto);
  };
  const sairOriginal = process.exit;
  let segunda = false;
  const sair = (codigo) => {
    const c = codigo === undefined ? (process.exitCode || 0) : codigo;
    if (!segunda && c === 0 && precisaDaSegunda(entrada)) {
      segunda = true;
      definirLeituraAntiga(true);
      main();
      sairOriginal.call(process, 0);
    }
    sairOriginal.call(process, c);
  };
  process.exit = sair;
  main();
  sair(0);
}

module.exports = { rodarComDuasLeituras, precisaDaSegunda };
