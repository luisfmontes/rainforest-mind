# Aviso de contexto alto manda compactar, não parar

## Objetivo

O aviso de contexto alto do `estado.cjs exigir` (D6 de `2026-11-09-aviso-contexto-alto`) diz "registre o estado e considere /compact ou uma sessão nova". Em 2026-11-12 o Luís viu várias sessões pararem o fluxo por causa dele, oferecendo "faço o plano numa sessão nova" em vez de seguir. O pedido dele: o aviso dá a ideia de compactar antes de começar o estágio, e não trava o fluxo.

## Decisões fechadas

- **D1 — O texto pede o /compact e diz que o fluxo segue depois.** Revoga a forma da D6 de `2026-11-09-aviso-contexto-alto`. A linha passa a ser `aviso: contexto em 320 mil tokens (limiar 310 mil). Antes de abrir 'plano', peça ao usuário um /compact e siga o fluxo depois dele: o estado está gravado e sobrevive à compactação. Não pare o fluxo nem proponha sessão nova por causa deste aviso.` O limiar, a medição e o lugar do aviso (stderr, exit inalterado) não mudam. — porquê: a sessão lia "ou uma sessão nova" como permissão para parar, e o Luís perdia o fluxo; compactar mantém a sessão e o estado em disco já cobre a retomada.

## Avaliado e descartado

- Desligar o aviso: o Luís quer o aviso, só que apontando para a compactação.
- Pedir a compactação sem citar o estado: sem a frase, a sessão tende a reescrever um handover antes de compactar.

## Varredura

`node scripts/varrer.cjs --slug aviso-contexto-compactar "considere /compact" "avisoDeContexto"`, saída em `docs/rainforest/varredura/aviso-contexto-compactar.txt` (nenhuma Issue ou ideia sobre o tema): o texto mora só em `scripts/lib/uso-contexto.cjs:81` (`avisoDeContexto`), e é afirmado em `scripts/testa-uso-contexto.sh:71` (texto inteiro) e `:136` (`Antes de abrir 'verificar'`, que continua valendo). A D6 de `2026-11-09-aviso-contexto-alto` fica como registro histórico, revogada por esta D1.

## Em aberto

- Nada. A versão sobe de PATCH (2.13.1); se o PR do `gate-segmentador` entrar antes, acerta no rebase.

## Fora de escopo

- O limiar (310 mil) e quando o aviso dispara.

## Pronto quando

Com o transcript de uma sessão acima do limiar, `node scripts/estado.cjs exigir --estagio <e>` imprime a linha nova no stderr e sai com o mesmo exit de antes.
