# observar.cjs respeita o orçamento do SessionEnd (#701)

## Objetivo

O `scripts/observar.cjs` roda no `SessionEnd` (e no `SessionStart`) com `timeout: 30`. O Claude Code dá a todos os hooks de `SessionEnd`, de todos os plugins, um sinal único de `max(1500, min(maior timeout declarado, 60000))` ms. Quando o `observar` passa desse tempo, os hooks irmãos ainda em voo saem com `Hook cancelled`.

Em 2026-11-12 o `Hook cancelled` de outro plugin coincidiu com o arquivo de estado dele ficando com 0 bytes: o hook foi morto no meio de uma gravação não atômica. A #198 (PR #212) já pôs um orçamento de 25 s. Medido no código em `origin/main` (`969e24b1`), esse orçamento deixa três furos:

1. **Orçamento por marca, não por execução.** `inicioDaPassada` nasce dentro de `processarMarca` (`scripts/observar.cjs:559`). Sem `--sessao`, que é como o hook chama, `processarSessao` varre todas as marcas pendentes em sequência (`:706-709`). Cada marca ganha 25 s novos: três pendentes dão até 75 s.
2. **A chamada à LLM não respeita o que sobra.** O orçamento só é conferido entre fatias (`:567`), e cada chamada tem timeout próprio de 60 s (`:334`). Uma fatia que começa aos 24 s pode ir até 84 s.
3. **O processo filho sobrevive ao timeout.** O `setTimeout` resolve `null` aos 60 s, mas o `spawn` só mata o `claude` aos 65 s (`timeout + 5000`). Esses 5 s mantêm o node vivo.

## Decisões fechadas

- **D1 — Um orçamento por execução.** O relógio começa uma vez, no início da passada (`processarSessao`), e vale para todas as marcas e fatias. Esgotado, a varredura para e as marcas seguintes ficam para a próxima sessão, com a mensagem `orcamento de <N>ms atingido; <k> marca(s) ficam para a proxima sessao`. — porquê: o hook é um processo só e o Claude Code mede o processo; o furo 1 é o maior dos três.
- **D2 — Cada chamada à LLM recebe como teto o que sobra do orçamento.** `chamarLLM(texto, tetoMs)` usa `Math.min(60000, tetoMs)` como timeout e mata o processo filho quando ele estoura, sem os 5 s a mais. Quem chama corta também o dublê de teste com o mesmo teto (`Promise.race`). Com menos de `min(7000, orçamento/3)` ms sobrando, a fatia não chama o modelo (a chamada sairia paga e seria cortada antes de responder). Fatia cortada pelo orçamento não é falha da LLM. A passada para com `orcamento de <N>ms atingido durante a fatia <i> (decorrido <d>ms)`, e a marca d'água fica na última fatia gravada. — porquê: os furos 2 e 3; a marca já avança por fatia (D6 da #198), então cortar no meio não perde trabalho.
- **D3 — O padrão continua 25 s.** `ORCAMENTO_MS` e o `timeout: 30` do `hooks/hooks.json` não mudam. — porquê: os 5 s de folga cobrem abrir o banco e ler o transcrito antes da primeira fatia, número que a #198 já mediu.

## Avaliado e descartado

- **Tirar o `observar` do `SessionEnd`:** é ali que o resto da sessão é capturado, e a #198 decidiu manter.
- **Baixar o `timeout` declarado para encurtar o sinal de todos:** o sinal é o maior timeout entre todos os plugins. Baixar o nosso só tira tempo do `observar`, sem proteger os irmãos.
- **`process.exit` no fim do `main`:** com o filho morto pelo D2, nada fica pendente em produção, e sair à força arrisca cortar a escrita de log.

## Varredura

`node scripts/varrer.cjs --slug observar-orcamento "ORCAMENTO_MS" "Hook cancelled"`, com a saída em `docs/rainforest/varredura/observar-orcamento.txt`.
- Achou a #198 fechada pelo PR #212 (orçamento de 25 s por marca, base deste trabalho) e a #701 aberta, que é esta.
- As outras Issues que casam com "Hook cancelled" são de timeout do CI, sem relação.
- `ORCAMENTO_MS` mora só em `scripts/observar.cjs:558`.
- A bateria `scripts/testa-observar.sh` mede o orçamento no caso 8.c e o padrão de 25 s nos casos 18 a 20.

## Em aberto

- Nada. A versão sobe de PATCH.

## Fora de escopo

- A gravação não atômica do arquivo de estado do outro plugin, que é de outro repositório.

## Pronto quando

Os casos rodam `node scripts/observar.cjs` sem `--sessao`, com `TESTADOR_ORCAMENTO_MS=2500`:
- Com duas marcas pendentes de várias fatias cada e um dublê de LLM de 1500 ms, a passada para com a mensagem do D1, e a segunda marca fica intocada.
- Com um dublê que demora 5 s, a passada para durante a primeira fatia com `decorrido` abaixo de 3500 ms, e a marca d'água não sai do lugar.
- Com um processo de verdade no lugar do `claude`, que trava 40 s, o observar sai em menos de 6000 ms: o filho morreu no corte.
