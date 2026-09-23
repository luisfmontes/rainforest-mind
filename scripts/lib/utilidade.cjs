'use strict';
/**
 * Sinal de utilidade da memória (D1-D11 do design
 * docs/rainforest/design/2026-09-23-memoria-sinal-de-utilidade.md).
 *
 * Mede, sem mudar a seleção da abertura (D2), se o que foi injetado na sessão
 * (servida) foi de fato usado — e se a recência (que decide as 14 vagas hoje)
 * deixou de fora observação que teria sido útil (contrafactual, D6).
 *
 * Deliberadamente NÃO requer scripts/memoria.cjs — é memoria.cjs que requer
 * este módulo para orquestrar os comandos `utilidade` e `manutencao`, e um
 * require circular deixaria os exports de um dos dois lados incompletos no
 * momento do require (module.exports de memoria.cjs só é atribuído no fim do
 * arquivo). Toda conexão de banco chega já aberta por quem chama.
 *
 * hooks/memoria-session-start.cjs e hooks/lib/memoria-sessao.cjs continuam
 * intocados (a abertura é somente-leitura) — só `formatarObservacao` é
 * importada daqui (usada a partir da Tarefa 2).
 */

const fs = require('fs');

// ---- Tarefa 1: extrator do transcrito ----

/**
 * Extrai as linhas servidas (`[AAAA-MM-DD (projeto)] ...`) de UM texto de
 * `additionalContext` — o bloco entre `## Memória (corpus residentes)` e a
 * linha `mais:` (D3, D8). Função pura, sem I/O.
 *
 * @param {string} additionalContext
 * @returns {string[]} linhas servidas, já aparadas (trim), na ordem em que
 *   apareceram no bloco (mais recente primeiro — é assim que montarMemoria as
 *   grava).
 */
function extrairLinhasServidas(additionalContext) {
  const texto = String(additionalContext || '');
  const inicio = texto.indexOf('## Memória (corpus residentes)');
  if (inicio === -1) return [];
  const marcaMais = texto.indexOf('mais:', inicio);
  const fim = marcaMais === -1 ? texto.length : marcaMais;
  const bloco = texto.slice(inicio, fim);
  return bloco
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('['));
}

/**
 * Lê um transcrito (.jsonl do harness) e devolve:
 *   - `servidas`: as linhas do bloco de memória que de fato chegaram à
 *     sessão, extraídas do(s) `attachment` de SessionStart (D3, D8) — nunca
 *     das candidatas que o banco tinha, só do que passou pelo corte de
 *     orçamento.
 *   - `texto`: os prompts do usuário mais as entradas (`input`) de cada
 *     `tool_use` do assistente. A prosa do assistente e todo `attachment`
 *     ficam de fora (D4) — a prosa ecoa a injeção e marcaria como "usada"
 *     toda observação só parafraseada.
 *
 * Função pura sobre o conteúdo do arquivo: não escreve nada, não abre banco.
 *
 * As duas formas de mensagem (`user` e `assistant`) passam pelo MESMO laço de
 * blocos — é o que faz a exclusão da prosa do assistente (linha abaixo) ser
 * um filtro de verdade: sem ela, um bloco `text` de um `assistant` cairia no
 * mesmo `if` que inclui texto de `user`, e entraria no texto da sessão.
 *
 * @param {string} caminhoTranscrito
 * @returns {{servidas: string[], texto: string}}
 */
function extrairSessao(caminhoTranscrito) {
  const conteudo = fs.readFileSync(caminhoTranscrito, 'utf8');
  const linhasArquivo = conteudo.split('\n');

  const servidas = [];
  const partesTexto = [];

  for (const linhaArquivo of linhasArquivo) {
    if (!linhaArquivo.trim()) continue;

    let entrada;
    try {
      entrada = JSON.parse(linhaArquivo);
    } catch (e) {
      continue; // linha corrompida/parcial — ignora, não trava a extração
    }

    // Servidas: só o attachment de SessionStart, só o bloco de memória (D3).
    if (entrada.type === 'attachment' && entrada.attachment && entrada.attachment.hookEvent === 'SessionStart') {
      const stdout = entrada.attachment.stdout;
      let parsed = null;
      try {
        parsed = JSON.parse(stdout);
      } catch (e) {
        parsed = null;
      }
      const ctx = parsed && parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext;
      if (ctx) {
        for (const linha of extrairLinhasServidas(ctx)) servidas.push(linha);
      }
      continue; // attachment nunca entra no texto (D4)
    }

    // Texto: prompts do usuário e entradas de tool_use do assistente.
    if ((entrada.type === 'user' || entrada.type === 'assistant') && entrada.message) {
      const conteudoMsg = entrada.message.content;

      if (typeof conteudoMsg === 'string') {
        // Prompt do usuário digitado direto, sem blocos estruturados.
        partesTexto.push(conteudoMsg);
        continue;
      }

      if (Array.isArray(conteudoMsg)) {
        for (const bloco of conteudoMsg) {
          if (!bloco) continue;
          if (bloco.type === 'tool_result') continue; // nunca é prompt do usuário
          if (entrada.type === 'assistant' && bloco.type === 'text') continue;
          if (bloco.type === 'text' && typeof bloco.text === 'string') {
            partesTexto.push(bloco.text);
          } else if (bloco.type === 'tool_use' && bloco.input !== undefined) {
            try {
              partesTexto.push(JSON.stringify(bloco.input));
            } catch (e) {
              // input não serializável (raro/circular) — ignora esse bloco.
            }
          }
        }
      }
    }
  }

  return { servidas, texto: partesTexto.join('\n') };
}

module.exports = {
  extrairLinhasServidas,
  extrairSessao,
};
