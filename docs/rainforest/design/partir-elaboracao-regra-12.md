# Partir a elaboração da regra 12, preservando o critério de 3k tokens por consulta

Declarado em 2026-08-26. Origem: apuração das 108 observações abertas da regra 13,
agrupadas por cacho. O cacho da regra 12 rendeu 5 edições cobrindo 10 observações,
e só uma cabia.

## Objetivo

Fazer as 5 edições do cacho da regra 12 caberem sem revogar o critério que a
catraca defende — e fechar, no caminho, o buraco de validação que o arquivo novo
revelaria.

O aperto, medido: `references/regra-12.md` tem 8884 B; a catraca
`REFERENCE_MAX_BYTES` é 10500 B, e ela **não é número solto** — o comentário dela
ancora o critério D9 da issue #73, *"menos de 3k tokens, medido"* para o custo de
**consultar** a elaboração de uma regra (10500 B ≈ 3,0k tokens). As 5 edições
levariam o arquivo a **15603 B** (~4,6k tokens), e o
`hooks/testa-contexto-sessao.sh` acusa com a mensagem que já oferece as duas
saídas: *"encurte regra-12.md, ou suba REFERENCE_MAX_BYTES de proposito, com a
conta escrita"*.

A medição que decidiu o desenho — quanto de cada elaboração é **incidente**
(bloco `>`) em vez de **regra**:

| arquivo | total | citação | % |
|---|---|---|---|
| `regra-12.md` | 8884 B | **3437 B** | 39% |
| `regra-11.md` | 6399 B | 1892 B | 30% |
| `regra-16.md` | 4728 B | 1530 B | 32% |
| as 17 juntas | 53788 B | 11752 B | 22% |

Dois quintos da regra 12 são *por que ela existe*, não *o que fazer*. Tirando os
incidentes sobram 5447 B de regra — as 5 edições cabem, e o acervo fica em
~6,8 KB. As duas metades passam sob a catraca **sem tocá-la**.

## Decisões fechadas

- **D1 — A regra fica, os incidentes saem, e nao e divisao por tema**
  `regra-12.md` guarda o que fazer; o acervo guarda o que aconteceu. É a única
divisão em que abrir **um** arquivo já basta para agir. Sem isso o split
esconderia o custo em vez de cortá-lo, porque D9 mede a consulta de *uma regra*,
não de *um arquivo*.

- **D2 — Isto e convencao, aplicada sob demanda**
   O critério fica escrito, e cada
regra parte quando encostar na catraca. A 11 (30%) e a 16 (32%) são as próximas
candidatas; nenhuma parte hoje.

- **D3 — Criterio de corte: bloco > cuja primeira linha abre com data**
   Os 10
blocos `>` da `regra-12.md` abrem todos com `> AAAA-MM-DD:` — o corte é
detectável por máquina, não por julgamento, e por isso pode virar checagem
depois.

- **D4 — Nome regra-12-acervo.md, e a varredura de H1/numero alarga junto**
   A checagem de
H1/número em `testa-contexto-sessao.sh` hoje varre só `^regra-\d+\.md$`; o
`medir-skill.cjs` conta **qualquer** `.md` da pasta para o teto de bytes. Ou
seja: um arquivo fora do padrão pesa no teto e escapa da validação de título. A
varredura passa a `^regra-\d+(-acervo)?\.md$`, e o acervo nasce validado (H1
`# Regra 12 — acervo`, número conferido contra o nome). Fechar esse buraco é
metade do valor da entrega.

- **D5 — O leitor chega ao acervo por um ponteiro no fim de regra-12.md**
   Um
salto. A fórmula `references/regra-<n>.md` está chumbada na injeção de abertura,
no `ponte.cjs` e no `conferir-ponte.cjs` — com o ponteiro dentro do arquivo,
nenhuma das três muda.

- **D6 — Cada paragrafo que perdeu incidente ganha uma linha de datas**
   Formato
`(acervo: 2026-08-17, 2026-08-20, 2026-08-25)`. Custa ~300 B e preserva o que faz
esta regra colar: ela não se lê como opinião, se lê como algo que já custou caro.

### O que muda

1. `skills/rainforest-mind/references/regra-12.md` — os 10 blocos de incidente
   saem; entram as 5 edições do cacho (a da mutação já está na branch); cada
   parágrafo afetado ganha a linha `(acervo: …)`; o arquivo termina com o
   ponteiro.
2. `skills/rainforest-mind/references/regra-12-acervo.md` — **novo**. H1
   `# Regra 12 — acervo`, os 10 incidentes movidos mais os das 5 edições novas,
   em ordem cronológica.
3. `hooks/testa-contexto-sessao.sh` — a varredura de H1/número passa a
   `^regra-\d+(-acervo)?\.md$`.
4. `skills/rainforest-mind/SKILL.md` — o parágrafo que descreve a convenção
   `<!-- detalhe -->` / `references/` ganha a frase do acervo. **Abaixo** do
   `<!-- detalhe -->`: não custa injeção.

### Critério de pronto

- `node scripts/medir-skill.cjs` mostra os dois arquivos da regra 12 **cada um**
  sob 10500 B.
- `bash hooks/testa-contexto-sessao.sh` **verde**: o veredito é a última linha
  (`ok: N falhou: 0`) e o `exit 0`, nunca um grep por `FALHA` — a seção 17.1 do
  arquivo imprime linhas `FALHA` de propósito, mostrando o vermelho esperado de
  cada sabotagem, dentro de sub-shell que não conta no placar.
- A checagem de H1/número **enxerga** `regra-12-acervo.md`: provado por mutação —
  trocar o número do H1 dele faz o caso `NUMERO` falhar, e desfazer devolve o
  verde.
- Nenhum incidente perdido: a contagem de blocos `>` iniciados por data somando
  os dois arquivos é ≥ 10, e todo texto movido aparece igual no destino.

## Avaliado e descartado

**Subir `REFERENCE_MAX_BYTES` para 16000 B.** Foi a primeira recomendação desta
sessão, e caiu quando o comentário do próprio teto foi lido: 10500 B ancora o
critério D9 da #73. Subir para ~4,6k tokens revogaria exatamente o que o teto
existe para defender. Registrado aqui para a opção não voltar como novidade.

**Partir por tema, em duas metades autônomas** (ex.: "critério e briefing" ×
"validação da entrega"). Cada metade se leria inteira, mas quem não sabe de
antemão qual delas tem a resposta abre as duas — e aí a consulta volta a custar
o dobro, que é o que D9 proíbe.

**Extrair os incidentes das 17 regras de uma vez.** Resolveria 11752 B num
movimento, e é mudança de convenção em 17 arquivos sem nenhuma delas encostando
na catraca hoje. Vira a D2 (sob demanda).

**Listar os dois arquivos na linha `Elaboração:` do `SKILL.md`.** Custaria ~40 B
dos 1465 B de folga do índice e nada de injeção — mas passa a mensagem errada,
de que são duas leituras necessárias.

**Nome `acervo-12.md`.** Mais curto, e quebra a ordenação alfabética que hoje
agrupa cada regra com a sua.

## Fora de escopo

- As outras 16 regras — a convenção vale sob demanda (D2), não em mutirão.
- O núcleo do `SKILL.md`: folga medida de 11 B, decisão já tomada de não tocar.
- Subir `REFERENCE_MAX_BYTES` ou `SKILL_MAX_BYTES`.
- A issue #120: apurada e **inválida** — a suíte está verde (`ok: 273 falhou: 0`,
  `exit 0`). Fechada com a correção.
- Tornar o corte por data uma **checagem** automática — D3 deixa o critério
  detectável, mas não escreve o detector.

## Em aberto

Nada bloqueia o plano. Duas coisas ficam anotadas para depois, sem decisão
pendente aqui:

- Se a 11 (30%) ou a 16 (32%) encostar na catraca, a D2 manda repetir este
  desenho — e é o momento de decidir se o corte por data vira checagem.
- As outras 9 observações do cacho da regra 12 só fecham quando as 4 edições
  restantes entrarem, o que este trabalho destrava mas não executa.
