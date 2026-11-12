# Aviso de contexto alto não para o fluxo

## Objetivo

O aviso de contexto alto do `estado.cjs exigir` (D6 de `2026-11-09-aviso-contexto-alto`) diz "registre o estado e considere /compact ou uma sessão nova". Em 2026-11-12 o Luís viu várias sessões pararem o fluxo por causa dele, oferecendo "faço o plano numa sessão nova" em vez de seguir. O pedido dele: o aviso não trava o fluxo. Na primeira versão desta D1 o aviso pedia ao usuário um `/compact`; ele recusou ("não quero que peça pra eu rodar um compact, vc pode rodar o autocompact, se não, não vai resolver o meu problema que para o fluxo"). A sessão não tem como disparar a compactação (nenhuma ferramenta faz isso); quem compacta é o autocompact do Claude Code, sozinho, quando o contexto enche.

## Decisões fechadas

- **D1 — O texto manda seguir o estágio e deixa a compactação com o autocompact.** Revoga a forma da D6 de `2026-11-09-aviso-contexto-alto`. A linha passa a ser `aviso: contexto em 320 mil tokens (limiar 310 mil). Siga com 'plano' normalmente: o autocompact compacta a sessão sozinho quando precisar, e o estado do fluxo está gravado e sobrevive à compactação. Não pare o fluxo, não peça /compact ao usuário nem proponha sessão nova por causa deste aviso.` O limiar, a medição e o lugar do aviso (stderr, exit inalterado) não mudam. — porquê: a sessão lia "ou uma sessão nova" como permissão para parar, e pedir `/compact` ao usuário também para o fluxo à espera dele; o autocompact já compacta sem ninguém pedir, e o estado em disco cobre a retomada.

## Avaliado e descartado

- Desligar o aviso: o Luís quer o aviso, só que sem parar o fluxo.
- Pedir ao usuário um `/compact` (primeira versão desta D1): para o fluxo à espera dele, que é o problema a resolver.
- A sessão disparar a compactação: não existe ferramenta para isso; o autocompact é o único mecanismo.
- Seguir sem citar o estado: sem a frase, a sessão tende a reescrever um handover antes de seguir.

## Varredura

`node scripts/varrer.cjs --slug aviso-contexto-compactar "considere /compact" "avisoDeContexto"`, saída em `docs/rainforest/varredura/aviso-contexto-compactar.txt` (nenhuma Issue ou ideia sobre o tema): o texto mora só em `scripts/lib/uso-contexto.cjs:81` (`avisoDeContexto`), e é afirmado em `scripts/testa-uso-contexto.sh:71` (texto inteiro) e `:136` (`Antes de abrir 'verificar'`, que passa a procurar `Siga com 'verificar'`). A D6 de `2026-11-09-aviso-contexto-alto` fica como registro histórico, revogada por esta D1.

## Em aberto

- Nada. A versão sobe de PATCH (2.13.1); se o PR do `gate-segmentador` entrar antes, acerta no rebase.

## Fora de escopo

- O limiar (310 mil) e quando o aviso dispara.

## Pronto quando

Com o transcript de uma sessão acima do limiar, `node scripts/estado.cjs exigir --estagio <e>` imprime a linha nova no stderr e sai com o mesmo exit de antes.
