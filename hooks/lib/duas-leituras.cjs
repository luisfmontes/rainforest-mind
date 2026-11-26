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
 * diferente de 0 sai na hora. A segunda passada roda em todo comando liberado: um
 * filtro por caractere em que as leituras divergem já deixou passar `{1,2}` no
 * PowerShell (terceira volta do revisor do fluxo), e enumerar é o que a D4 evita.
 *
 * Exceção não falha aberto (revisão de segurança do commit bb6ee442). Na primeira
 * passada, quem decide passa a ser a segunda (a leitura antiga, a da base). Na
 * segunda, o gate barra: ela roda de dentro do `process.exit` da primeira, e uma
 * exceção ali subiria para um `try/catch` do gate, que seguiria com a leitura antiga
 * ligada até sair 0.
 */
const fs = require("fs");
const { definirLeituraAntiga } = require("./cwd-efetivo.cjs");

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

  const rodaSegunda = () => {
    segunda = true;
    definirLeituraAntiga(true);
    let codigo = 0;
    try {
      main();
    } catch (e) {
      process.stderr.write("[duas-leituras] a leitura antiga falhou (" + (e && e.message) + ") — bloqueado por precaução.\n");
      codigo = 2;
    }
    sairOriginal.call(process, codigo);
  };

  const sair = (codigo) => {
    const c = codigo === undefined ? (process.exitCode || 0) : codigo;
    if (!segunda && c === 0) rodaSegunda();
    sairOriginal.call(process, c);
  };
  process.exit = sair;

  try {
    main();
  } catch (e) {
    if (segunda) throw e;
    process.stderr.write("[duas-leituras] a leitura nova falhou (" + (e && e.message) + ") — decide a antiga.\n");
    rodaSegunda();
  }
  sair(0);
}

module.exports = { rodarComDuasLeituras };
