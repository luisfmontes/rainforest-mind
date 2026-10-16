# Painel Deixado oferece virar pendência do fluxo (#470)

## Objetivo
O painel "Deixado para depois" do mod (`hooks/mod.tsx`) e as `pendentes` do estado do fluxo (#449) são duas fontes que não se falam. O item do painel passa a poder virar pendência do fluxo aberto, sempre com a confirmação da pessoa, para que a trava da #449 (pendência só sai com destino) valha também para ele.

## Decisões fechadas
- **D1 — Sem medição de ruído, caminho (b) da issue** — porquê: os itens do painel vivem só na memória da sessão (o mod não escreve em disco, contrato do `2026-10-07-desk-no-mod`), então não há histórico para medir. A medição só era necessária para o caminho (a), em que o item trava o `ok` sozinho; no (b) quem decide é a pessoa, e um falso positivo custa um "não" (Luís, Q1 da rodada anterior: recomendado).
- **D2 — Subcomando `node scripts/estado.cjs pendencia --slug <slug> --texto "<texto>"`** — porquê: hoje a pendência só entra por `marcar ... --json '{"pendentes":[...]}'`, que exige repetir o status do estágio; um subcomando deixa o caminho mecânico, sem depender de a janela lembrar a forma. Acrescenta o texto às `pendentes` do estágio aberto (D3) sem mudar o `status` nem outro campo do bloco; texto vazio recusa com exit 1; texto já presente nas `pendentes` desse estágio sai 0 sem duplicar; fluxo completo (sem estágio aberto) recusa com exit 2 (Luís, Q1: recomendado).
- **D3 — A pendência entra no estágio aberto** — porquê: é o estágio que o painel "Fluxos em curso" mostra e o que `estado.cjs proximo` devolve; a pendência cobra destino no próximo `marcar ... ok` desse estágio, não só no fim (Luís, Q2: recomendado).
- **D4 — Botão "Vira pendência de <fluxo>" por item aberto do painel, um por fluxo aberto** — porquê: mesmo padrão do "Faz agora": o botão só preenche o prompt (`$.prompt.fill`, modo `append`) com o comando do D2 para aquele fluxo e item, e quem envia é a pessoa (a confirmação). O mod continua sem escrever em disco. Prompt preenchido marca o item como `enviado`, como o "Faz agora"; prompt que recusa deixa o item aberto. Sem fluxo aberto (ou leitura dos fluxos indisponível), o botão não aparece. O texto do item vai para o comando com as aspas e a contrabarra escapadas, para o comando colado rodar com o texto literal (Luís, Q3: recomendado).

## Avaliado e descartado
- Medir o ruído reconstruindo pelos transcripts: só a parte das regras de texto (`deferimentos()`) se reconstrói; a do segundo modelo não.
- Instrumentar o mod para gravar os itens: quebra o contrato de o mod não escrever em disco e adia a issue.
- O painel gravar direto em `pendentes` (caminho a): falso positivo travaria o fluxo sem a pessoa decidir.
- Botão que preenche um pedido em prosa: o caminho volta a depender de a janela lembrar como gravar.
- Pendência sempre no `fechar`: só cobraria no fim.

## Fora de escopo
- Mudar como o painel acha os itens (regras de texto e segundo modelo).
- O botão "Faz agora" e o "Limpar tudo" ficam como estão.

## Varredura
docs/rainforest/varredura/2026-10-15-deixado-vira-pendencia.txt — só a própria #470 está aberta com esses termos.

## Em aberto
nada
