# Memória da abertura encurta antes de cortar

## Objetivo
O bloco de memória da abertura (`hooks/lib/memoria-sessao.cjs`, teto de 3.000 B) corta observações inteiras, começando pelas mais antigas, até caber. Medido nas duas contas em 2026-09-26: das 148 aberturas com bloco de memória nos 14 dias anteriores, 79 cortaram observações, em geral de 4 a 7 das 14. O bloco passa a encurtar o texto das linhas antes de cortar qualquer observação.

## Decisões fechadas
- **D1 — Escada de encaixe: (1) completo, como hoje; (2) o texto de todas as linhas (título — subtítulo, depois do rótulo `[data (projeto)]`) com no máximo 200 caracteres; (3) no máximo 160; (4) no máximo 120; (5) só então corta observação inteira, a mais antiga primeiro, com os textos em 120. Cada degrau só roda se o anterior não coube** — porquê: medido no banco real em 2026-09-26 (só leitura), simulando 12 aberturas com as 60 observações mais recentes, cabem em média 6,3 de 14 hoje, 10 com o texto até 200 caracteres, 12 com até 160 e 14 com até 120 — nas 12 janelas, a escada parou no degrau de 120. A escada preserva o texto inteiro quando há espaço. Mecanismo enxertado da escada de encaixe do `tamaratran/fast-jev-compaction` (`src/state.ts`, MIT): cada degrau só roda se o anterior não bastou, e a função devolve em que degrau parou. Decidido pelo usuário em 2026-09-26.
- **D2 — O que encurta é o texto da linha inteiro (título e subtítulo juntos, cortando pelo fim), não só o título nem só o subtítulo** — porquê: medido no banco real em 2026-09-26 (só leitura), o título é a frase-resumo longa (mediana de 254 caracteres, máximo de 435), mas o subtítulo também é longo: mediana de 188 B. Encurtar só o título a 120, com o subtítulo inteiro, cabia 8,7 de 14; encurtar o texto todo a 120 cabe as 14. Cortar pelo fim mantém o começo do título, que é o que identifica a observação. A primeira versão deste D2 dizia "o subtítulo tem 22 B em média" — a simulação tinha descartado o subtítulo; corrigido antes da implementação fechar.
- **D3 — O corte do texto cai na última palavra inteira antes do limite e termina em `…`. O limite é contado em caracteres, não em bytes** — porquê: palavra cortada no meio fica ilegível, e caractere é a unidade de leitura (lição do `LEGENDA_LINHA_MAX_CHARS`, no mesmo arquivo). O teto do bloco continua em bytes, e é ele que decide quando descer um degrau.
- **D4 — O aviso no topo do bloco diz em que degrau parou: "textos encurtados a N caracteres" quando só encurtou, e isso mais as observações cortadas quando chegou ao degrau 5. O aviso entra dentro do teto de 3.000 B** — porquê: corte silencioso já apagou regras inteiras em 2026-08-10, e quem lê a memória precisa saber que a linha está incompleta e que `memoria.cjs buscar` traz o resto.

## Avaliado e descartado
- Texto sempre com no máximo 120 caracteres, sem escada: corta mesmo quando caberia inteiro (D1).
- Encurtar só o subtítulo, como a ideia propunha, ou só o título: nenhum dos dois cabe as 14 (D2).

## Fora de escopo
- Superação entre observações: "a superada sai primeiro", a segunda parte da ideia `memoria-encurta-antes-de-cortar-e-superada-sai-primeiro`, continua plantada. Só a escada já cabe as 14 no banco real, e o critério de "mesmo assunto" é o ponto arriscado: um falso positivo apaga contexto certo, sem medição que mostre ganho. Decidido pelo usuário em 2026-09-26.
- O teto de 3.000 B e a seleção das 14 (FTS do foco, resumos): não mudam.
- O foco que não coube no payload da abertura ("609 B livres, piso 700 B") é outro orçamento, o do `contexto-sessao.cjs`.

## Em aberto
