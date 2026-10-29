# gate-pergunta-memoria sem o canal do banco

## Objetivo
O `gate-pergunta-memoria` (2.1.0) barra a `Q<n>` que a memória já responde, por dois canais: os arquivos de memória do projeto e o banco de observações do `memoria.cjs`. Em uso real, o canal do banco só produziu falso positivo, e o usuário viu o erro "em várias sessões". Este trabalho tira o canal do banco e mantém o dos arquivos.

Conduzido pela sessão a partir do relato do usuário em 2026-10-29 (print do bloqueio com `F080KCO` numa pergunta sobre classe de valor), sob a autorização permanente de seguir o fluxo com a recomendada. As decisões ficam marcadas no PR para veto.

## Decisões fechadas
- **D1 — Alvo** — serve ao usuário em todas as sessões das duas contas, onde o gate está ligado por padrão. O canal dos arquivos de memória continua igual. — porquê: o defeito está todo no canal do banco. O dos arquivos casa por nome e descrição, que são escritos à mão para dizer do que a memória trata.
- **D2 — O canal do banco sai do gate** — `hooks/gate-pergunta-memoria.cjs` deixa de abrir o banco (`conectarBancoLeitura`, `achadoNoBanco`, o orçamento `RFM_PERGUNTA_MEMORIA_ORCAMENTO_MS` e a chamada no laço das perguntas). Pergunta que só o banco "responderia" passa (exit 0). — porquê: medido em 2026-10-29 nos transcritos das duas contas desde a 2.1.0, foram 23 sessões com bloqueio. As 11 perguntas distintas barradas pelo banco eram todas falso positivo: a observação citada não respondia a pergunta e só compartilhava um termo raro (o código de uma rotina, o nome de um cliente). O canal casa por bm25 abaixo de -10, com até 30 termos raros em `OR`, e basta um termo raro em comum.
- **D3 — `soProjeto` sai de `buscarPorAssunto`** — a opção que a 2.1.1 criou só para o gate fica sem chamador e é removida da biblioteca e da bateria dela. — porquê: a varredura de chamadores (`rg "soProjeto"`) só acha o gate e o teste. Opção sem chamador é código morto, e a 2.1.1 a criou só para esse uso.
- **D4 — A remoção ganha caso de regressão** — o caso do banco na bateria do gate passa a afirmar o contrário: banco com observação do projeto atual que casa a pergunta, e sem `memory/` que responda, sai com exit 0. — porquê: sem esse caso, alguém pode religar o canal sem nenhuma bateria ficar vermelha. A mutação que religa a consulta tem de ser pega.
- **D5 — Contra quem protege, e o que fica fora** — continua protegendo contra a janela principal subir `Q<n>` que um arquivo de memória do projeto responde. Ficam fora: a observação do banco que de fato responderia (perda aceita: em 11 de 11 casos medidos o banco errou); falso positivo do canal dos arquivos (não medido como problema; os bloqueios vistos por esse canal vieram de arquivos com nome e descrição do assunto); e o hook de prompt (`memoria-assunto-prompt.cjs`), que injeta observações como contexto e não barra nada. — porquê: modelo de ameaça escrito, para a revisão parar nele.

## Avaliado e descartado
- **Aplicar ao banco a regra dos arquivos (3 termos em comum, sem o vocabulário do projeto)** — medido sobre as 11 perguntas: sobram 4, e as 4 continuam falsas. Os termos em comum são o vocabulário de domínio do próprio projeto (nome do produto, do módulo, das rotas), porque as observações são resumos de sessão do mesmo projeto. Apertar o limiar só troca quais falsos aparecem.
- **Desligar o gate inteiro por padrão** — perde o canal dos arquivos, que não tem defeito medido.

## Fora de escopo
- Melhorar a busca por assunto do banco (`construirQueryAssunto`) para o hook de prompt: o hook só injeta contexto, e o ruído dele não bloqueia o turno.

## Varredura
docs/rainforest/varredura/2026-10-29-gate-memoria-sem-banco.txt — nenhuma Issue aberta sobre o gate. Os precedentes são o design `2026-10-28-colheita-observacoes` (D6 criou o canal do banco, com a #509 como risco de prazo) e o `2026-10-29-colheita-pos-2-1-0` (D3 criou o `soProjeto`). Isso confirma que a opção nasceu só para o gate, e por isso o D3 a remove.

## Em aberto
