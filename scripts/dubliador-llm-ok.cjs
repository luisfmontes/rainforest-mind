#!/usr/bin/env node
async function chamarLLM(texto) {
  // Eco do texto recebido (simula sucesso honesto).
  // Se o texto é vazio, retorna null para indicar que não há nada a observar.
  if (!texto || !texto.trim()) {
    return null;
  }
  // Devolver um resumo que depende do conteúdo recebido
  return `[Resumo do dublê] ${texto.substring(0, 100)}${texto.length > 100 ? '...' : ''}`;
}
module.exports = { chamarLLM };
