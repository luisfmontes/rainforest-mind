# Zerar as Issues abertas, rodada 10 — stdbuf longo (#346), --body-file MSYS (#344), R5 intermitente (#342), bateria em dobro (#341), transcrito absoluto (#340), três contrabarras (#339)

## Objetivo
Fechar seis defeitos abertos em uma entrega: dois buracos de gate, um falso
positivo de gate, uma intermitência de CI, um custo dobrado no varredor e um
vazamento de caminho pessoal no estado versionado. A #337 e a #302 continuam
abertas, fora desta rodada.

## Decisões fechadas
- **D1 — #346: `stdbuf` entra em `WRAPPERS_QUE_REPASSAM` e `FLAGS_COM_VALOR` de `hooks/lib/tokens-comando.cjs`, com as formas curtas e longas (`-i/-o/-e`, `--input/--output/--error`), e o `gate-bateria-sem-timeout` troca o laço ad hoc por `pularFlagsDoWrapper`** — porquê: o laço só conhecia a forma curta com valor separado; a lib comum já resolve flag + valor para os outros wrappers. Critério: `stdbuf --output L bash hooks/testa-x.sh` em subagente sem `timeout` → 2; as formas que já passavam (`--output=L`, `-oL`, `-o L`, `-i0 -o0 -e0`) continuam → 2; com `timeout` na frente → 0; caso novo em `hooks/testa-gate-bateria-sem-timeout.cjs`, mais mutação (tirar `--output` de `FLAGS_COM_VALOR` deixa o caso vermelho).
- **D2 — #344: `gate-fechar-issue` aplica `normalizarMsys` ao caminho de `--body-file` antes de `path.isAbsolute`/`resolve`** — porquê: `/c/...` é absoluto no win32 e vira `C:\c\...`; o `cd` já normaliza, o `--body-file` não. Critério: caso em `hooks/testa-gate-fechar-issue.sh` com `--body-file /c/...` apontando para arquivo real (com `closes` e evidência) → mesmo veredito que o caminho `C:/...`; mutação (sem a normalização) deixa o caso vermelho.
- **D3 — #342: o R5 de `scripts/testa-saude.sh` separa falha de fixture de falha do `saude.cjs`: sem o arquivo `pronto` depois da espera, reprova com mensagem própria ("fixture: servidor não subiu"); porta ocupada é sorteada de novo pelo próprio servidor (ou porta 0 com a porta real gravada no `pronto`); pronto quando 5 reexecuções seguidas do job no CI do PR ficam verdes** — porquê: hoje "servidor não subiu" e "saude não enxergou" saem com a mesma cara, e o laço de espera segue em frente calado. As 5 reexecuções custam só tempo de CI e são a única prova de que a intermitência acabou.
- **D4 — #341: sai o bloco de não-regressão de `hooks/testa-gate-publicacao-destino.sh` que chama `testa-gate-staging-total.sh` e `testa-conferir-publicacao.sh`; o teste (n) de `scripts/testa-varrer-baterias.sh` passa a pegar qualquer `testa-*.sh` que execute outra `testa-*` (`.sh` ou `.cjs`), com contraprova em sandbox; junto, o cosmético da #339 no teste (m) (`chmod +x` no arquivo que existe)** — porquê: o varredor já roda as duas; rodar em dobro dobra o custo e atribui a falha à bateria errada. Critério: (n) na árvore real → verde; sandbox com uma `.sh` chamando outra `.sh` → (n) vermelho; teste (m) sem erro no stderr.
- **D5 — #340: `estado.cjs veredito` grava `transcrito` com `~` no lugar da pasta pessoal (`~/.claude*/projects/...`); a conferência D12/D14 continua sobre o caminho real no momento do `veredito`; as ocorrências na main são reescritas nos arquivos atuais (histórico do git fica como está)** — porquê: nada lê o campo de volta, ele existe para deixar visível qual transcrito foi usado; `~` preserva qual das contas (`.claude` / `.claude-personal`) gerou, o que caminho relativo ou só o nome perderiam. Critério: `veredito` real grava valor começando por `~/`; `git grep` por caminho de pasta pessoal em `docs/rainforest/estado/` → vazio; caso na bateria do `estado.cjs`, com mutação (voltar para `path.resolve`) deixando vermelho.
- **D6 — #339: no ramo de aspas duplas de `desempacota` (`hooks/lib/tokens-comando.cjs`), uma única passada da esquerda para a direita trata `\\`, `\"`, `\$`, `` \` `` e `\<quebra>` (este some, os demais viram o caractere); `colapsaContinuacaoDeLinha` continua valendo para o que não vem de aspas duplas** — porquê: é o que o bash faz; duas passadas divergem com três contrabarras. Critério: com 1, 2, 3 e 4 contrabarras antes da quebra, entre aspas duplas, o exit do gate bate com o bash real (gh falso no PATH registra a chamada; a bateria compara lado a lado); casos (#313a)-(#313e) continuam verdes; mutação (voltar às duas passadas) deixa vermelho o caso de três.
- **D7 — Entrega: um PR com as seis, tarefas independentes em paralelo, bump de minor sobre `origin/main` no `fechar`, issues fechadas pelo `fechar-issue.cjs` depois do merge** — porquê: formato das rodadas 1-9; D1 e D6 mexem na mesma lib (`tokens-comando.cjs`) e vão em série.

## Avaliado e descartado
- #340 caminho relativo a `projects/` ou só o nome do arquivo: perdem qual das contas gerou o transcrito.
- #342 só o fixture, sem reexecuções no CI: a intermitência já passou em rerun antes; sem as 5 seguidas não há prova de que acabou.

## Fora de escopo
- #337 (`bash $VAR` sem aspas): quatro revisões da rodada 9 acharam bypass na resolução estática por regex; precisa de outro modelo (allowlist de formas ou execução em shell de sandbox), rodada própria.
- #302 (eval de gatilho): trava de desenho (grader de disparo fora do score sob `--ablation with-without`) e custo (~US$ 13/rodada).

## Em aberto
(nenhum)
