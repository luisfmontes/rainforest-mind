# Zerar as Issues abertas, rodada 9 — gates (#337, #313, #322), CI das baterias .cjs (#335), veredito em worktree (#329), duplicação gitignorada (#323), carimbo de emenda (#312)

## Objetivo
Fechar sete defeitos abertos em uma entrega: três falsos positivos/buracos de
gate, um buraco de CI, dois de estado do fluxo e um de medição do `/saude`. A
#302 (eval de gatilho) continua aberta, fora desta rodada.

## Decisões fechadas
- **D1 — #337: `bash $VAR` / `sh $VAR` (variável sem aspas, com ou sem argumentos depois) é execução de arquivo, não comando encapsulado; `bash -c "$x"` e `eval "$x"` continuam ilegíveis (exit 2)** — porquê: reproduzido em 2026-09-26 na base 5d59d36e (`for t in a b; do bash $t; done` → 2, `bash "$t"` → 0); é o mesmo defeito da #309 no ramo sem aspas. Critério: os dois comandos da tabela da issue → 0, `bash -c "$x"` → 2, caso novo na bateria do gate.
  - *Emenda de 2026-09-26 (Q1 da execução, (a)):* o caso (cj) do lote 4 exige `bash $CMD` → 2 (variável não resolvida é o que o gate não lê), e contradiz o D1 literal. Decidido: `bash $V`/`sh $V` sem aspas só é arquivo quando o valor de `V` está **escrito no próprio comando** — `for V in <palavras literais ou globs>` ou `V=<literal>` antes do uso — e cada valor possível é literal, não começa com `-` e não tem espaço; `# Zerar as Issues abertas, rodada 9 — gates (#337, #313, #322), CI das baterias .cjs (#335), veredito em worktree (#329), duplicação gitignorada (#323), carimbo de emenda (#312)

## Objetivo
Fechar sete defeitos abertos em uma entrega: três falsos positivos/buracos de
gate, um buraco de CI, dois de estado do fluxo e um de medição do `/saude`. A
#302 (eval de gatilho) continua aberta, fora desta rodada.

## Decisões fechadas
- **D1 — #337: `bash $VAR` / `sh $VAR` (variável sem aspas, com ou sem argumentos depois) é execução de arquivo, não comando encapsulado; `bash -c "$x"` e `eval "$x"` continuam ilegíveis (exit 2)** — porquê: reproduzido em 2026-09-26 na base 5d59d36e (`for t in a b; do bash $t; done` → 2, `bash "$t"` → 0); é o mesmo defeito da #309 no ramo sem aspas. Critério: os dois comandos da tabela da issue → 0, `bash -c "$x"` → 2, caso novo na bateria do gate.
, crase, `$(`, ou `IFS=` no comando → ilegível. `bash $CMD` sem atribuição visível continua 2 e o (cj) fica de pé. Descartada a primeira entrega (separava pelo tamanho do nome da variável). Rejeitado (b), D1 ao pé da letra: reabria o `bash -c` escondido por `IFS`.
- **D2 — #313: ao desempacotar o interno de aspas DUPLAS de um wrapper, aplicar a redução de escape de aspas duplas (`\\`→`\`, `\"`→`"`) antes de `colapsaContinuacaoDeLinha`; aspas simples não sofrem a redução** — porquê: é o que o bash faz em duas passadas. Bateria dos três gates de texto ganha `bash -c "gh issue \\<quebra>close 12"` → 2 e `bash -c 'gh issue \\<quebra>close 12'` → comportamento de comandos separados, mais mutação no alvo da redução.
- **D3 — #322: (a) no hook, para `Edit`/`MultiEdit`, só barra achado de `new_string` que não aparece em `old_string`; (b) `conferir-publicacao` aceita o endereço noreply da Anthropic somente na forma `Co-Authored-By: … <noreply@anthropic.com>`** — porquê: (a) mede o que a edição introduz; (b) cobre `Write` e a checagem de publicação, que (a) não alcança. Critério: `conferir-publicacao` no arquivo com o trailer → 0; Edit que preserva e-mail de terceiro → 0; Edit que introduz e-mail novo → 2; e-mail noreply fora da forma do trailer continua recusado; mutação de cada uma.
  - *Emenda de 2026-09-26 (plano):* (b) já está na `main` desde `f947e85e` ("publicacao: noreply@ nao e e-mail de ninguem"), mais larga que o decidido — isenta todo `noreply@`, não só o trailer. Medido: a linha do trailer de `agents/*.md` → exit 0. Esta rodada não mexe em (b); só acrescenta o caso do trailer à bateria do gate como regressão. Estreitar a isenção fica fora (um `noreply@` genérico não é dado de terceiro).
- **D4 — #335: `scripts/varrer-baterias.sh` descobre também `scripts/testa-*.cjs` e `hooks/testa-*.cjs` e os roda com `node`; as 3 cascas `.sh` que só chamam um `.cjs` saem** — porquê: fecha a classe (bateria `.cjs` nova não esquece de entrar) e evita rodar duas vezes. Critério: placar do varredor lista todas as `.cjs`; uma quebrada de propósito deixa o varredor com exit ≠ 0.
- **D5 — #329: quando o slug não existe na raiz de `payload.cwd`, `veredito-revisor` procura em `git worktree list`; grava no único worktree que tiver `docs/rainforest/estado/<slug>.json`; em 0 ou 2+, avisa em stderr e não grava** — porquê: só avisar mantém o contorno manual; gravar em ambíguo arrisca o estado errado.
- **D6 — #323: `conferir-duplicacao` enumera candidatos pelo git (`ls-files --cached --others --exclude-standard`), e a seção K de `testa-saude.sh` copia a árvore pela mesma lista, não por `tar` do diretório** — porquê: duplicata é medida contra o plugin versionável; sem o K, o `testa-saude` segue vermelho no checkout principal. Critério da issue: `duplicados` vazio com `.claude/marketplaces/` presente; `testa-saude.sh` 0 falhas no checkout principal; caso gitignorado não conta / não-gitignorado conta, com mutação.
- **D7 — #312: o teto do carimbo em `estado.cjs` lê o número de tarefas do arquivo do plano (itens `### <n>. `), como a validação de `mutacao`; `plano.tarefas` fica de fallback quando o arquivo não existe** — porquê: duas fontes para a mesma pergunta, e só uma acompanha emenda.
- **D8 — Entrega: um PR com as sete, tarefas independentes em paralelo, bump de minor sobre `origin/main` no `fechar`, issues fechadas pelo `fechar-issue.cjs` depois do merge** — porquê: formato das rodadas 1-8; D1 e D2 mexem nos mesmos gates/bateria e vão em série.

## Avaliado e descartado
- #335 (b), casca `.sh` por `.cjs`: não fecha a classe.
- #329 só avisar em stderr: deixa o contorno manual com `estado.cjs veredito`.
- #322 só (a): `Write` de arquivo novo com o trailer e o `conferir-publicacao` seguiriam recusando.
- #323 sem mexer no K: o DUP2 ficaria verde e o K vermelho no mesmo checkout.

## Fora de escopo
- #302 (eval de gatilho): trava é de desenho (grader de disparo fora do score sob `--ablation with-without`) e custo (~US$ 13/rodada); redesenho com `--ablation none` é rodada própria.

## Em aberto
(nenhum)
