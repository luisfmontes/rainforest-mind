# Partir a elaboração da regra 12, preservando o critério de 3k tokens por consulta

Declarado em 2026-08-26. Origem: apuração das 108 observações abertas da regra 13,
agrupadas por cacho. O cacho da regra 12 rendeu 5 edições cobrindo 10 observações,
e só uma cabia.

## O aperto, medido

`references/regra-12.md` tem 8884 B. A catraca `REFERENCE_MAX_BYTES` é 10500 B, e
ela **não é número solto**: o comentário dela ancora o critério D9 da issue #73 —
*"menos de 3k tokens, medido"* para o custo de **consultar** a elaboração de uma
regra. 10500 B ≈ 3,0k tokens.

As 5 edições do cacho levariam o arquivo a **15603 B** (~4,6k tokens). O teste
`hooks/testa-contexto-sessao.sh` acusa, com a mensagem que já oferece as duas
saídas: *"encurte regra-12.md, ou suba REFERENCE_MAX_BYTES de proposito, com a
conta escrita"*.

Subir o teto foi recusado: revogaria o próprio critério que ele existe para
defender.

## A medição que decidiu o desenho

Quanto de cada elaboração é **incidente** (bloco `>`) em vez de **regra**:

| arquivo | total | citação | % |
|---|---|---|---|
| `regra-12.md` | 8884 B | **3437 B** | 39% |
| `regra-11.md` | 6399 B | 1892 B | 30% |
| `regra-16.md` | 4728 B | 1530 B | 32% |
| as 17 juntas | 53788 B | 11752 B | 22% |

Dois quintos da regra 12 são *por que ela existe*, não *o que fazer*. Tirando os
incidentes sobram 5447 B de regra — e as 5 edições cabem, com o acervo em ~6,8 KB.
As duas metades passam sob a catraca **sem tocá-la**.

## Decisões

**D1. O que faz o segundo arquivo ser opcional: a regra fica, os incidentes saem.**
Não é divisão por tema. `regra-12.md` guarda o que fazer; o acervo guarda o que
aconteceu. É a única divisão em que abrir **um** arquivo já basta para agir — e
sem isso o split esconderia o custo em vez de cortá-lo, porque D9 mede a consulta
de *uma* regra, não de *um arquivo*.

**D2. Isto é convenção, aplicada sob demanda.** O critério fica escrito, e cada
regra parte quando encostar na catraca. A 11 (30%) e a 16 (32%) são as próximas
candidatas; nenhuma parte hoje.

**D3. Critério de corte: bloco `>` cuja primeira linha abre com data.** Os 10
blocos `>` da `regra-12.md` abrem todos com `> AAAA-MM-DD:` — o corte é detectável
por máquina, não por julgamento, e por isso pode virar checagem depois.

**D4. Nome `regra-12-acervo.md`, e a varredura alarga junto.** A checagem de
H1/número em `testa-contexto-sessao.sh` hoje varre só `^regra-\d+\.md$`; o
`medir-skill.cjs` conta **qualquer** `.md` da pasta para o teto de bytes. Ou seja:
um arquivo fora do padrão pesa no teto e escapa da validação de título. A varredura
passa a `^regra-\d+(-acervo)?\.md$`, e o acervo nasce validado (H1
`# Regra 12 — acervo`, número conferido contra o nome). Fechar esse buraco é
metade do valor da entrega.

**D5. O leitor chega ao acervo por um ponteiro no fim de `regra-12.md`.** Um salto.
A fórmula `references/regra-<n>.md` está chumbada na injeção de abertura, no
`ponte.cjs` e no `conferir-ponte.cjs` — com o ponteiro dentro do arquivo, nenhuma
das três muda. A linha `Elaboração:` do `SKILL.md` **não** lista os dois: passaria
a mensagem errada, de que são duas leituras necessárias.

**D6. Cada parágrafo que perdeu incidente ganha uma linha de datas.** Formato
`(acervo: 2026-08-17, 2026-08-20, 2026-08-25)`. Custa ~300 B e preserva o que faz
esta regra colar: ela não se lê como opinião, se lê como algo que já custou caro.

## O que muda

1. `skills/rainforest-mind/references/regra-12.md` — os 10 blocos de incidente
   saem; entram as 5 edições do cacho (a da mutação já está na branch); cada
   parágrafo afetado ganha a linha `(acervo: …)`; o arquivo termina com o ponteiro.
2. `skills/rainforest-mind/references/regra-12-acervo.md` — **novo**. H1
   `# Regra 12 — acervo`, os 10 incidentes movidos mais os das 5 edições novas, em
   ordem cronológica.
3. `hooks/testa-contexto-sessao.sh` — a varredura de H1/número passa a
   `^regra-\d+(-acervo)?\.md$`.
4. `skills/rainforest-mind/SKILL.md` — o parágrafo que descreve a convenção
   `<!-- detalhe -->` / `references/` ganha a frase do acervo. **Abaixo** do
   `<!-- detalhe -->`: não custa injeção.

## Critério de pronto

- `node scripts/medir-skill.cjs` mostra os dois arquivos da regra 12 **cada um**
  sob 10500 B, e `maior-reference` não é nenhum deles acima do teto.
- `bash hooks/testa-contexto-sessao.sh` com as **mesmas 5 falhas** pré-existentes
  da issue #120 e **nenhuma nova** — ou verde, se a #120 já tiver entrado.
- A checagem de H1/número **enxerga** `regra-12-acervo.md`: provado por mutação —
  trocar o número do H1 dele para outro faz o caso `NUMERO` falhar.
- Nenhum incidente perdido: a contagem de blocos `>` iniciados por data em
  `regra-12.md` + `regra-12-acervo.md` é ≥ 10 (os originais) e todo texto movido
  aparece igual no destino.

## Fora de escopo

- As outras 16 regras — a convenção vale sob demanda (D2), não em mutirão.
- O núcleo do `SKILL.md`: folga medida de 11 B, decisão já tomada de não tocar.
- Subir `REFERENCE_MAX_BYTES` ou `SKILL_MAX_BYTES`.
- A issue #120 (5 falhas na `main`), que corre em paralelo.
