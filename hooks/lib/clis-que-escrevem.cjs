// CLIs externas que leem repositórios e escrevem código: não podem rodar fora
// de worktree linkado porque escreveriam no principal.
//
// Só a lista fechada de nomes conhecidos. Para adicionar uma CLI nova:
// 1. Abra Issue pedindo autorização
// 2. Documente por que ela escreve (link da Doc oficial)
// 3. Passe por review — qualquer rejeição volta à lista
// 4. Commit único, uma CLI por commit, mensagem começando por "CLI:"
//
// Exemplo: `git commit -m "CLI: adiciona 'aider' — escreve código por IA"`
module.exports = [
  "codex",
  "gemini",
  "claude",
  "aider",
  "cursor",
  "copilot",
];
