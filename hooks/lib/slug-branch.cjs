'use strict';
/**
 * Casamento slug do fluxo × branch, numa fonte só (D2 do design branch-datada-e-componentes).
 *
 * Quem usa: `resolver` e `diagnosticar` de hooks/lib/estagio-ativo.cjs (que reexporta esta
 * função), `casaComBranch` de hooks/lib/caminho-leve.cjs e o aviso de dono do scripts/saude.cjs.
 * Antes eram quatro cópias, e a do /saude comparava com a branch ainda com o `fluxo/`.
 *
 * `branchBase` é a branch sem o prefixo até a primeira barra (`fluxo/tema` -> `tema`). Casa
 * exato quando ela é igual ao slug inteiro (`2026-11-03-tema`, #645: a receita da regra 11 com
 * o slug datado do brainstorm), ao slug sem a data (`tema`) ou sem a data e o `fluxo-<N>-`
 * (`fluxo-9-portaria` -> `portaria`). Casa como tarefa paralela quando a branch tem o sufixo
 * `-t<n>` (#613) e, sem ele, casaria exato.
 *
 * Devolve 'exato', 'tarefa' ou null. Não lê disco nem git: módulo sem dependência, para que
 * caminho-leve.cjs o use sem passar pelo estado.cjs.
 */

function formas(slug) {
  const semData = slug.replace(/^\d{4}-\d{2}-\d{2}-/, '');
  return [slug, semData, semData.replace(/^fluxo-\d+-/, '')];
}

function casaSlugComBranch(slug, branchBase) {
  if (typeof slug !== 'string' || typeof branchBase !== 'string' || !branchBase) return null;
  const f = formas(slug);
  if (f.includes(branchBase)) return 'exato';
  const semTarefa = branchBase.replace(/-t\d+$/, '');
  if (semTarefa !== branchBase && f.includes(semTarefa)) return 'tarefa';
  return null;
}

/** A branch que casaria exato, para a mensagem da portaria: a forma mais curta. */
function branchEsperada(slug) {
  const f = formas(slug);
  return f[f.length - 1];
}

module.exports = { casaSlugComBranch, branchEsperada };
