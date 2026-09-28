# Zerar as Issues abertas, rodada 11 — mensagem do `bash $t` (#337) e trava de gatilho sob demanda (#302)

## Objetivo
Fechar a #337 trocando a orientação do bloqueio, e tirar a #302 do impasse de
desenho: a suíte de eval de gatilho do rascunho #311 entra na main com um script
de trava que pontua o disparo, rodado sob demanda e fora do CI. Nenhuma eval
paga roda nesta rodada (decisão do Luís, 2026-09-28): o mecanismo se prova com
um `claude` falso, e o critério 4 da #302 (ver a eval reprovar de verdade) fica
pendente, com a issue aberta.

## Decisões fechadas
- **D1 — #337: `bash $t` sem aspas continua ilegível; a mensagem de bloqueio do `gate-fechar-issue` passa a dizer que rodar um arquivo cujo caminho está numa variável se faz com aspas (`bash "$t"` passa), e a #337 fecha com essa justificativa** — porquê: quatro revisões da rodada 9 acharam bypass na resolução estática de `$VAR`; o custo real da issue era a mensagem mandar "rodar o `gh` diretamente" num comando que não tem `gh`. Critério: `for t in a b; do bash $t; done` e `f=x.sh; bash $f 2>&1 | tail -1` continuam saindo 2, com `bash "$t"` no stderr; `bash "$t"` continua 0; `bash -c "$x"` continua 2; caso novo na bateria, com mutação (tirar a linha) deixando vermelho.
- **D2 — #302: a suíte de 21 casos do #311 entra como está (graders de disparo com `arm: with-only`), e a trava roda com `--ablation none`, onde esses graders contam no score** — porquê: sob `with-without` o disparo sai do score e a eval não reprova regressão (achado 1 do #311); sob `none` o `--help` diz que o score volta a ser o de braço único, e `with-only` continua certo para a rodada de baseline. Premissa ainda não vista em rodada paga: que `with-only` pontua sob `none`; a primeira rodada da trava confirma ou derruba.
- **D3 — #302: `scripts/eval-gatilho.sh` com três modos, todos sob demanda: `trava` (cada caso roda N vezes, padrão 3, uma chamada `claude plugin eval --ablation none --runs 1 --case <nome> --threshold 1.0` por rodada; o caso passa com a maioria das rodadas em exit 0), `mutacao <skill>` (cópia dos arquivos rastreados em diretório temporário, `description` da skill sabotada, trava rodada nos casos positivos dela; sucesso = trava vermelha) e `baseline` (rodada `with-without` única, relatório para o "acrescenta / peso morto")** — porquê: a maioria em 3 foi a escolha do Luís para o disparo instável; decidir pelo exit de `--threshold`, caso a caso, depende só do contrato documentado do CLI, não do formato ainda não visto do JSON de agregado. Exit do CLI 2 (teto de custo) aborta a trava com exit próprio.
- **D4 — #302: o script aceita `CLAUDE_BIN` para trocar o executável, e a bateria `scripts/testa-eval-gatilho.sh` usa um `claude` falso que decide o exit pelos argumentos e pelo diretório do plugin (description sabotada ou não), sem rede, credencial nem custo** — porquê: é o que prova o mecanismo sem gastar; a bateria entra no varredor e no CI como qualquer outra.
- **D5 — #302 emenda o critério 3 da issue: a suíte não roda no CI; roda sob demanda pelo script, com custo medido (~US$ 0,32 por caso por rodada, só com o plugin)** — porquê: ~US$ 20 por trava completa em 3 rodadas não cabe em todo PR; a emenda vai registrada na issue no `fechar`.
- **D6 — Entrega: um PR, T1 e T2 independentes, bump de minor sobre `origin/main`; a #337 fecha pelo `fechar-issue.cjs` depois do merge; a #302 recebe comentário com o que entrou e o que falta (critério 4, pago) e continua aberta; o rascunho #311 fecha como absorvido** — porquê: formato das rodadas anteriores; fechar a #302 sem a rodada paga seria declarar pronto sem prova.

## Avaliado e descartado
- Ler o `aggregate-result.json` para contar disparos por rodada: formato não documentado e nunca visto nesta máquina (os resultados do #311 não foram guardados); o exit de `--threshold` por caso basta.
- Tirar o grader LLM dos casos para a trava medir só disparo: o CLI não filtra grader por flag, e duplicar os 21 casos dobra a manutenção; a maioria em 3 absorve a oscilação do LLM junto com a do disparo.

## Fora de escopo
- Reescrever as 16 `description` sem roteamento negativo (fora de escopo da própria #302).
- Rodar a trava, a mutação e o baseline pagos: pendentes até o Luís liberar gasto.

## Em aberto
(nenhum)
