# Impasse: bearer-variavel (#494) — teto de 3 reprovações

Data: 2026-10-14

## Onde parou
O objetivo da issue está cumprido desde a volta 1: o header de autorização montado por template JS com `${token}`, ou por concatenação do esquema com uma variável, passa; literal no lugar da variável continua barrado. As três reprovações vieram de apertar o que vem DEPOIS da expressão isenta:

- volta 1: o esquema sem aspa seguido de `+<token>`, e o template fechado seguido de `+ '<hex>'`, passavam (fugas);
- volta 2: a régua era lista de proibição (só `+` cancelava); passavam `.concat('<hex>')`, `/* c */ + '<hex>'`, `${tok||'<hex>'}` e `${tok} <hex>` dentro do template;
- volta 3: a régua virou lista de permissão (depois da aspa de fechamento, só fim de linha ou `, ; ) ] }`) e fechou todas as fugas (varredura de cerca de 45 mil combinações sem literal novo passando). Mas ela foi aplicada também às aspas comuns e passou a barrar linhas legítimas que a `main` (régua da #410) deixa passar: comentário no fim da linha, continuação de shell (`\`), variável de ambiente antes de comando, `.trim()` depois da string, `if token else None` na f-string, e prosa em markdown que cita o header entre crases.

## Não é só defeito de implementação
É tensão do design. O D1 diz "sem literal colado" depois da referência. Para aspas comuns, a `main` sempre aceitou qualquer coisa que não fosse caractere de palavra depois dela. Lista de permissão estrita cumpre o D1 e quebra a #410; a régua da main cumpre a #410 e deixa passar referência entre aspas seguida de espaço e literal (lacuna que a main já tinha).

## Proposta (rodada extra)
Limitar a lista de permissão à superfície NOVA, o template com crase e a concatenação, aceitando depois dela também comentário até o fim da linha (`//` ou `#` precedido de espaço) e a barra de continuação. As aspas comuns (dupla, simples, f-string, `.format`) voltam exatamente à régua da main.

Junto, os achados baixos da volta 3: regex quadrático em espaços (`scripts/conferir-publicacao.cjs:405`), comentários que apontam para `referenciaIsenta` (função que não existe mais) e o CHANGELOG descrevendo a régua real. A lacuna pré-existente das aspas comuns vira ideia plantada, fora do escopo deste PR.
