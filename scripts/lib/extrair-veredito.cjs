/**
 * Extração e validação de veredito de uma linha, a partir da saída de um
 * modelo (parecer completo em prosa livre + última linha com o veredito).
 *
 * Por que existe: `scripts/segunda-opiniao.cjs` já fazia essa extração
 * (última linha com conteúdo, trim, lowercase, contra vocabulário fechado
 * `concordo|discordo`) — este módulo isola o mecanismo para ser reaproveitado
 * por outros contratos de veredito de uma linha (D2 do design
 * `docs/rainforest/design/2026-09-23-contrato-de-veredito.md`), cujo
 * vocabulário é outro (`veredito: ok|veredito: reprovado`).
 *
 * Exported:
 *   - extrairUltimaLinha(texto): última linha não vazia de `texto`, com
 *     trim, remoção de marcação (`*`, `_` ou crase) só nas pontas da linha
 *     e lowercase aplicados — aceita `**VEREDITO: ok**`, `__VEREDITO: ok__`
 *     e `` `VEREDITO: ok` `` (D2/D4 do design
 *     `docs/rainforest/design/2026-09-25-veredito-fora-da-linha.md`); texto
 *     depois do veredito dentro da marcação (ex.: `**VEREDITO: reprovado —
 *     4 bloqueantes**`) não vira vocabulário válido, porque só as pontas são
 *     tocadas. Não valida vocabulário.
 *   - validarVocabulario(linha, vocabulario): true se `linha` está no array
 *     `vocabulario` (comparação exata, sem normalização adicional — quem
 *     chama já deve ter passado `linha` por `extrairUltimaLinha`).
 */

function extrairUltimaLinha(texto) {
  const parecer = texto.trim();
  const linhas = parecer.split('\n');
  const ultima = linhas[linhas.length - 1].trim();
  return ultima.replace(/^[*_`]+|[*_`]+$/g, '').trim().toLowerCase();
}

function validarVocabulario(linha, vocabulario) {
  return vocabulario.includes(linha);
}

module.exports = { extrairUltimaLinha, validarVocabulario };
