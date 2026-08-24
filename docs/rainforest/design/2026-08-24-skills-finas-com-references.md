# Skills finas com references: consultar uma regra deve custar menos de 3k tokens

## Objetivo

Fazer o contrato da abertura ser cumprível. O núcleo injetado marca regras com `↳` e
manda carregar a skill antes de aplicá-las; carregar custa ~16,8k tokens, e paga-se as
17 para ler uma. Contrato caro é contrato que se descumpre — o incentivo empurra para
aplicar a regra de memória, que é exatamente o modo de falha que a injeção dimensionada
existia para corrigir.

Duas medições feitas em 2026-08-24 delimitam o trabalho. A primeira: das 16 skills, uma
é 58.540 B e a segunda maior é 14.158 B — o defeito está concentrado, não espalhado. A
segunda: a linha de corte já existe no arquivo e já é usada. São 17 marcadores
`<!-- detalhe -->`, e `extrairNucleo` (`hooks/lib/contexto-sessao.cjs:174-185`) já
descarta tudo depois deles. O que falta é o texto do outro lado da marca sair de dentro
do arquivo.

## Decisões fechadas

- **D1 — Quebra-se só a skill `rainforest-mind`; as outras 15 ficam como estão.** — porquê:
  o critério da issue fala em consultar a elaboração de **uma** regra, e isso só existe
  nessa skill — nas outras 15, carregar o arquivo inteiro é o uso pretendido, não há
  "uma parte" a consultar. Medido: `rainforest-mind` 58.540 B contra `analisar` 14.158 B,
  `executar` 13.354 B e as outras 13 abaixo de 10.903 B.

- **D2 — Um `references/regra-<n>.md` por regra, não agrupamento por tema.** — porquê: o
  ponteiro injetado já é por regra — o núcleo marca a regra individual com `↳`. Agrupar
  faria consultar uma regra pagar pelas vizinhas: o bloco temático "agentes" (regras 10,
  11 e 12) soma 20.428 B sozinho, pior em proporção do que o problema atual.

- **D3 — O núcleo fica no `SKILL.md`; depois de cada `<!-- detalhe -->` entra uma única
  linha de ponteiro, e a elaboração sai para o arquivo da regra.** — porquê: é o único dos
  três desenhos avaliados que passa no critério sem tocar no parser. O marcador já existe
  e já é respeitado, então a estrutura que o hook lê continua idêntica byte a byte nos
  núcleos.

- **D4 — Consultar uma regra deixa de passar por carregar a skill: lê-se o arquivo da
  regra direto.** — porquê: o núcleo já chegou pela injeção da abertura, então carregar o
  `SKILL.md` para chegar na elaboração é pagar duas vezes pela mesma informação. O texto
  do contrato muda junto — em `hooks/lib/contexto-sessao.cjs` e em `scripts/ponte.cjs:195`,
  onde hoje se lê "carregue `Skill(rainforest-mind)`", passa a se ler o caminho do arquivo
  da regra. Custo medido do desenho: **645 tokens na mediana e 2,5k no pior caso**, contra
  16,8k hoje.

- **D5 — Os literais estruturais do `SKILL.md` são preservados: `## As regras`, o formato
  `**N.` no começo de linha, e a linha `Última revisão:`.** — porquê: não é estética, é
  load-bearing, e foi verificado por mutação. Trocar `## As regras` por outro texto e rodar
  o parser devolve **0 bytes** de núcleo, o que faz a sessão subir com o alarme "FALHA AO
  CARREGAR AS REGRAS" (`REGRAS_MIN_CHARS`, `contexto-sessao.cjs:118`). O formato `**N.` é o
  lookahead de `INICIO_REGRA` (`:139`) e é contado pelos testes. A linha `Última revisão`
  é lida por `hooks/foco-session-start.cjs:167` num `if` sem `else` — movê-la desliga o
  aviso bimestral em silêncio.

- **D6 — A seta dupla da regra 15 entra nesta entrega.** — porquê: o núcleo dela termina
  com um `↳` literal no arquivo e `extrairNucleo` acrescenta outro, então ela chega em toda
  sessão como `↳ ↳` — confirmado na saída do parser (`setas duplas = 1`) e visível na
  abertura desta própria sessão. É um caractere, no arquivo que já está sendo
  reestruturado.

- **D7 — A folga de 7 bytes no teto de núcleo sai desta entrega e vira a issue #79.** —
  porquê: são dois defeitos que moram no mesmo arquivo e não se resolvem juntos. Medido:
  núcleos em 5.593 B contra `NUCLEOS_MAX_BYTES` de 5.600 (`contexto-sessao.cjs:82`). Quem
  enche esse teto são os núcleos, e eles ficam onde estão — esta entrega não devolve nem
  um byte de folga. Misturar faria a entrega carregar uma decisão que não é dela.

- **D8 — O gate de orçamento agregado não conta `references/`.** — porquê: `references/`
  não é contexto residente, só entra quando alguém lê um arquivo específico, e é essa a
  razão de existir do desenho. `scripts/orcamento.cjs:104` mede `skills/<dir>/SKILL.md`
  contra um teto agregado de 14.000 B (`:164`); passar a somar os 17 arquivos reprovaria a
  quebra no dia seguinte à entrega, punindo exatamente o que a issue pede.

- **D9 — O custo de consulta ganha teste, com teto de 10.500 B e margem declarada no
  comentário.** — porquê: o critério é "menos de 3k tokens, **medido**", e sem teste ele
  vale no dia da entrega e apodrece depois — foi assim que os "~16,8k tokens" do
  `description` viraram um número que não é derivado de nada nem verificado por nada. O
  teto de 10.500 B equivale a ~3,0k tokens e o maior arquivo hoje é a regra 12 com
  8.826 B, o que dá **16% de margem**. A margem nasce escrita no comentário, e não
  implícita: a #79 é o que acontece quando uma constante load-bearing encosta no teto sem
  ninguém ver.

## Avaliado e descartado

- **Desenho (a) — núcleo fica no `SKILL.md` e a elaboração sai, sem linha de ponteiro.**
  Consultar continuaria passando por carregar a skill: ~2,7k tokens do `SKILL.md` mais até
  2,5k do arquivo da regra, **5,2k tokens**. Reprova no critério de 3k.
- **Desenho (b) — `SKILL.md` vira índice puro, núcleo e elaboração vão juntos para os 17
  arquivos e o hook passa a ler os 17.** Passa no critério, mas a varredura de acoplamento
  mapeou **9 pontos de quebra** entre `contexto-sessao.cjs`, `testa-contexto-sessao.sh`,
  `testa-ponte.sh`, `foco-session-start.cjs`, `ponte.cjs` e `orcamento.cjs`. O desenho (c)
  chega no mesmo lugar deixando 2.
- **Agrupar as regras por tema em 4 ou 5 arquivos.** O bloco "agentes" (10, 11, 12) daria
  20.428 B, e consultar a regra 10 pagaria pela 11 e pela 12.
- **Quebrar as 16 skills.** As outras 15 já estão em ou abaixo de ~4k tokens e não têm "uma
  parte" a consultar. Custo de trabalho e indireção sem ganho medido.
- **Contar `references/` no gate agregado.** Ver D8.

## Fora de escopo

- **A folga de 7 bytes no teto de núcleo, e o rebalanceamento de `NUCLEOS_MAX_BYTES`
  contra `ORCAMENTO_BYTES`.** Ver D7 — issue #79, aberta em 2026-08-24 com a medição
  colada.
- **As outras 15 skills.** Ver D1.
- **A citação de página de acervo dentro da elaboração de cada regra.** É a segunda metade
  da D4 do design de 2026-08-24 da camada Obsidian, e depende de o `references/` existir —
  ou seja, vem **depois** desta entrega, não dentro dela.

## Em aberto

- **Se a regra 12 deve ser subdividida.** Com 8.826 B ela é a maior elaboração por larga
  margem, e é a primeira que encostaria no teto de 10.500 B da D9 se crescer. É a maior
  justamente por ser a que mais acumulou incidente datado, então encurtá-la tem custo real.
  Não se decide aqui: decide-se no dia em que o teste da D9 acusar.
