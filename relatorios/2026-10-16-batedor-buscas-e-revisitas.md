# Batedor de repos — 2026-10-16: buscas ancoradas e revisitas

## Âncora
- 191 ideias abertas; 3 problemas escolhidos (os mais antigos, 64–66 dias): **gramática tree-sitter de ADVPL/TLPP**, **memória local para o rainforest** e **scanner de descrição de MCP/skill de terceiro**. 188 ficaram de fora.
- Fila de repos (`vigias/fila-de-repos.jsonl`): vazia. 0 utilizáveis, 0 recusados pelo script.

## Busca ancorada
- **Tree-sitter ADVPL/TLPP** — sem achado. Busca web sem gramática para ADVPL/TLPP; `gh search repos` por "advpl tree-sitter" e "tlpp grammar" voltou vazio. Voltou de mãos vazias: resultado válido.
- **Memória local para Claude Code (SQLite/FTS5)** — candidatos achados, nenhum com trilha na fila, portanto **não avaliados**: `ij5a/subrosa`, `tznthou/ccRecall`, `sdsrss/claude-mem-lite`, `ErebusEnigma/context-memory`. `thedotmack/claude-mem` já consta como adotado no livro.
- **Scanner de descrição de MCP/skill** — candidatos achados, sem trilha na fila, **não avaliados**: `invariantlabs-ai/mcp-scan` (Snyk Agent Scan), `mcpscan-cli` (PyPI), `cisco mcp-scanner`, `mcpsentry`. Relevante para a ideia já aberta `auditar-descricao-de-ferramenta-de-terceiro-como-superficie-de-ataque`.

## Avaliação
- Nenhum candidato novo avaliado: a fila não traz trilha para nenhum deles, e o procedimento não permite escolher trilha depois de ver o candidato.

## Revisitas (gatilho duplo: 60+ dias desde a avaliação e push posterior ao registrado)
Teto de 3. Elegíveis e não elegíveis, pelos números da API consultada hoje:

| Repo | Situação | Saída |
|---|---|---|
| `upstash/context7` | avaliado 08-09, push registrado 08-07, push atual 10-16 | (a) segue reprovado: sem doc de ERP legado (busca de `advpl` vazia) |
| `bmad-code-org/BMAD-METHOD` | avaliado 08-09, push registrado 08-09, push atual 10-16 | (a) segue reprovado: framework de método segue concorrendo com o SKILL.md |
| `Mansuro/claude-projects` | avaliado 08-09, push registrado 07-30, `pushed_at` 09-25 | (a) segue reprovado: último commit 01-10, sem mudança de conteúdo |
| `headroomlabs-ai/headroom` | avaliado 08-09; push 10-16; release v0.41.0 (10-14) | **não revisitado nesta ronda**: já marcado em 10-09 para reavaliação a fundo, e sem trilha na fila para virar candidato |
| `Graphify-Labs/graphify`, `tirth8205/code-review-graph` | revisitados em 10-09 | fora do gatilho (7 dias desde a última avaliação) |
| `SuperClaude-Org/SuperClaude_Framework` | elegível por data | **não revisitado**: a consulta à API falhou (TLS timeout) |
| `affaan-m/ECC`, `debpalash/VoiceStudio`, `book-to-skill`, `claude-mem`, `whatsapp-mcp` | avaliados 08-08 | **não revisitados**: o livro não tem push registrado (`—`), então o gatilho não pode ser verificado |
| `snarktank/ralph` | push atual = push registrado (02-02) | fora do gatilho |
| `gsd-build/get-shit-done` | arquivado | fora do gatilho |
| `maslennikov-ig/claude-code-orchestrator-kit` | push atual (03-05) anterior ao registrado (08-04) | fora do gatilho |
| `getagentseal/codeburn` | categoria `testar`, fora da tabela de revisita | fora do gatilho |

Excedentes do teto, com nome: `headroomlabs-ai/headroom`, `SuperClaude-Org/SuperClaude_Framework`, e os demais da tabela marcados como elegíveis por data.

## Registro
- Três linhas acrescentadas à tabela "Avaliados" do `vigias/livro-de-repos.md` (revisitas de context7, BMAD e Mansuro).

## Para decidir
Nada novo para `/ideia`. Os scanners de MCP acima alimentam a ideia já aberta sobre auditoria de descrição de ferramenta de terceiro; não é ideia nova.
