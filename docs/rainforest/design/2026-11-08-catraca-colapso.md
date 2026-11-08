# Design: a catraca recusa a mutação que quebra a sintaxe do fonte

## Objetivo
Em 2026-11-08, no fluxo `busca-doc`, uma mutação do `conferir-busca.cjs` deixou o fonte com
`SyntaxError`. O `--de` começava com `//`, e o Git Bash tirou uma barra; sobrou uma `/` solta
no lugar do comentário. Os 35 casos de `scripts/testa-conferir-busca.sh` saíram exit 1, e o
`scripts/conferir-mutacao.cjs` respondeu "bateria VERMELHA com o comportamento invertido,
confirmada em duas rodadas. A bateria sabe falhar." É vermelho falso sobre um artefato que nem
carrega, que é o que a catraca existe para não aprovar. A guarda de colapso que existe
(`bateriaColapsou`) não pegou: a bateria imprime `total=N vermelhas:[...]`, que o
`extrairPlacar` não reconhece, e mesmo um placar reconhecido com todos os casos vermelhos tem a
cara de vermelho legítimo (uma bateria de uma asserção só fica 100% vermelha com razão). Modo
autônomo ("oq mais tem para melhorar das ideias, pode ir fazendo", 2026-11-08): as decisões
**[sessão]** foram a recomendada, sem rodada, e ficam para veto no PR. Ideia
`catraca-colapso-por-erro-de-sintaxe`.

## Decisões fechadas
- **D1 — Antes da bateria pós-mutação, a catraca confere a sintaxe do arquivo mutado [sessão]** — porquê: o sinal certo é o artefato, não a saída da bateria. Procurar `SyntaxError` na saída dá falso colapso em bateria que ecoa saída de processo filho ao falhar (a própria `testa-conferir-mutacao.sh` tem fixture que imprime `ReferenceError`). Conferir o arquivo é determinístico e mais barato que rodar a bateria. Para `.js`, `.cjs` e `.mjs`: `node --check <arquivo>` com o `process.execPath` da própria catraca. Para `.sh` e `.bash`: `bash -n <arquivo>`, com o mesmo bash que roda a bateria (`caminhoExecutavel('bash')`). Outras extensões: sem conferência, como hoje.
- **D2 — Só recusa quando o original passa e o mutado não [sessão]** — porquê: um fonte que a conferência já reprova antes da mutação (sintaxe que a versão do node não entende, `.sh` que depende de `source` de outro arquivo) não diz nada sobre a mutação. A conferência roda no original, logo depois do baseline, e no mutado, logo depois de escrever. Original reprovado: segue sem conferência no mutado. Ferramenta ausente ou que não executa (bash não encontrado, erro de spawn): segue sem conferência, como hoje.
- **D3 — A recusa é o exit 6 do colapso, sem rodar a bateria [sessão]** — porquê: é a mesma pergunta do colapso ("a bateria mediu comportamento?"), e o exit 6 já significa "refine a mutação ou a bateria" para quem lê a catraca. A mensagem abre com `RECUSADO: a mutação quebrou a sintaxe de <arquivo>`, cita a primeira linha não vazia do erro da conferência e diz que a bateria não rodou. No modo no lugar, a restauração continua sendo a da saída do processo.
- **D4 — Versão PATCH, com CHANGELOG e a tabela de saídas** — porquê: conserta uma trava que existia (o colapso), sem comando nem campo novo. 2.9.0 → 2.9.1. A linha do exit 6 em `skills/executar/references/catraca-de-mutacao.md` passa a citar a sintaxe quebrada.

## Avaliado e descartado
- Procurar `SyntaxError`/`ReferenceError` na saída pós-mutação e ausente no baseline: falso colapso em bateria que despeja a saída de um processo filho quando um caso falha, e o caso que falhou pode ter falhado com razão.
- Contar a proporção de casos vermelhos: a bateria de uma asserção que mede exatamente o comportamento mutado fica 100% vermelha com razão (comentário de `bateriaColapsou`, 2026-09-11).
- Python (`ast.parse` por `python`): exige achar o interpretador certo no Windows e nenhuma bateria deste repositório muta `.py` pela catraca hoje. Fica para quando houver.
- `ReferenceError` em tempo de execução: a conferência de sintaxe não o vê. O caso de bateria que para de imprimir placar já é colapso (`bateriaColapsou`, placar ausente).

## Fora de escopo
- O Git Bash tirar uma barra de argumento que começa com `//`: já documentado em `catraca-de-mutacao.md` ("Ponha um caractere antes das barras").
- O `extrairPlacar` reconhecer `total=N vermelhas:[...]`: outro assunto.

## Varredura
docs/rainforest/varredura/2026-11-08-catraca-colapso.txt — os termos casam Issues e PRs antigos que só citam "colapso" ou "catraca" de passagem; nenhum trata mutação que quebra a sintaxe. O `deriva --arquivo scripts/conferir-mutacao.cjs` lista 28 decisões com âncora (23 intactas, 5 com âncora perdida); nenhuma é sobre conferir o fonte mutado antes da bateria.

## Em aberto
- Nada bloqueia. D1, D2 e D3 ficam para veto no PR.
