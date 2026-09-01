# Design — Segunda opinião cross-model no `revisar`

Escrito em 2026-09-01, contra `origin/main` `cc1db6a` (0.79.0, já com o PR #137).
Origem: ideia `segunda-opiniao-cross-model-no-revisor`, plantada em 2026-08-09,
destravada em 2026-08-31 quando o Codex CLI e o Gemini CLI passaram a existir
nesta máquina.

## Objetivo

Dar ao `revisar` um segundo auditor de **família de modelo diferente**, e parar
de manter os fatos operacionais de CLI externo copiados dentro do
`scripts/conselho.cjs`.

Hoje quem audita é da mesma família de quem produziu: o `revisar` despacha
`rainforest-mind:revisor` (Claude, sonnet) contra entrega de agente Claude. A
troca de contexto já está resolvida — contexto zerado, nunca `fork` — mas a
troca de família não: o mesmo modelo erra do mesmo jeito duas vezes, e nenhuma
anonimização descorrelaciona treinamento.

## O que já existe (medido, não suposto)

| Fato | Onde |
|---|---|
| `adaptadorCodex`, 65 linhas | `scripts/conselho.cjs:1175-1239` |
| `adaptadorGemini`, 70 linhas | `scripts/conselho.cjs:1249-1318` |
| ~85% do corpo **literalmente igual** após normalizar o nome | diff dos dois: 3 hunks (nome, guard de `GEMINI_API_KEY`, linha do `cmd`, linha do `env`) |
| O padrão `isWindows ? cmd.exe /d /s /c : sh -c` aparece **4 vezes** | `:404-415`, `:800-812`, `:1201-1211`, `:1279-1290` |
| `parseJsonDeMembro` existe e os adaptadores **não o usam** | definido `:45-50`; eles reimplementam a mesma regex dupla em `:1227` e `:1306` |
| `hooks/lib/` não tem helper de CLI externo | único spawn de lá é `poda-estagio.cjs:28-37`, e só roda `git` |
| Os adaptadores **não são exercitados por teste nenhum** | as 8 fixtures de `scripts/fixtures/conselho/` substituem o CLI; `testa-conselho.sh` (29 casos, ~81 asserções) testa o orquestrador |
| O `revisar` **não tem script** | `skills/revisar/SKILL.md` (145 linhas) + `agents/revisor.md`; a mecânica vive em `scripts/estado.cjs` |
| O veredito hoje é JSON no estado, não linha grepável | `SKILL.md:113-123` → `estado.cjs marcar --status ok/reprovado --json` |

Os três fatos operacionais que custam uma sessão cada, e que já estão pagos
dentro dos adaptadores: o conteúdo do prompt vai por **stdin** (por argumento
quebrava com aspas e quebras de linha no cmd.exe, e mandava o path como
pergunta — achado da T9); `windowsVerbatimArguments` no Windows; e teto de tempo
por chamada (`TIMEOUT_MEMBRO_MS`, `conselho.cjs:41`).

## Decisões fechadas

- **D1 — O transporte de CLI externo sai do `conselho.cjs` e vira
  `hooks/lib/cli-externo.cjs`.** Exporta `rodarCli({ cmd, entrada, timeoutMs,
  env })` → `{ status, stdout, stderr }` (shell por plataforma, conteúdo por
  stdin, `windowsVerbatimArguments` no Windows, timeout obrigatório) e
  `extrairJson(stdout)` → objeto ou `null` (a regex dupla, uma vez só no repo).
  Porque: com o `revisar` virando segundo consumidor, os fatos do `codex exec`
  passariam a viver em dois lugares e apodreceriam separados.
- **D2 — Os dois adaptadores e as duas cópias do orquestrador consomem o helper
  na mesma entrega.** Adaptador vira wrapper fino: só o comando e, no Gemini, o
  guard de `GEMINI_API_KEY`. Porque: extrair e deixar as cópias vivas é criar
  uma quinta cópia, não remover quatro.
- **D3 — A bateria do helper nasce ANTES da extração, e a extração se prova por
  mutação.** `scripts/testa-cli-externo.sh` contra fixture; três mutações
  declaradas (quebrar o stdin, quebrar o timeout, quebrar a regex) têm de deixar
  um teste vermelho nomeado. Porque: os adaptadores não têm rede hoje —
  refatorar sem teste é refatorar no escuro.
- **D4 — O `revisar` chama o segundo modelo por caminho próprio, consumindo o
  transporte compartilhado.** Porque: o `conselho` é multi-membro, com
  anonimização, quórum e ranking cruzado — maquinário sem sentido quando um
  auditor olha um diff: não há quem anonimizar, o quórum de N>=3 barraria a
  dupla, e não há ranking a cruzar. O que os dois compartilham é só o spawn.
- **D5 — Contrato da segunda opinião.** Entra `git diff <base>...<head>` (três
  pontos, o escopo que o `revisar` já fixa em `SKILL.md:34-44`), o critério de
  sucesso falsificável do briefing e o commit-base. Sai veredito de **uma
  linha**, vocabulário fechado (precedente: `conferir-livro-de-repos.cjs:33`).
  Arbitra a janela, sempre — o externo aconselha, não manda. Divergência
  rejeitada vai para o log **com motivo**: não decide sozinha, mas também não
  evapora.
- **D6 — Indisponibilidade do modelo externo é falha fechada.** Ligado e
  indisponível reprova; nunca segue sem ele. Porque: é a mesma regra que o
  fluxo 11 já provou ao vivo em 2026-08-31, quando o free tier do Gemini deu 503
  e o `revisar` do conselho recusou em vez de prosseguir com 4/5.
- **D7 — Fixture nas baterias; Codex e Gemini reais só na validação manual
  final.** Porque: bateria que depende de rede e de cota de terceiro não é
  bateria — e o free tier do Gemini já devolveu 503/429 sob demanda.

## Avaliado e descartado

- **Segunda opinião como conselho de 2 membros.** Mais barato de construir — zero
  caminho novo — mas herda anonimização, quórum N>=3 e ranking cruzado, que são
  semântica errada para um auditor olhando um diff. Descartado na D4.
- **Deixar o `revisar` duplicar o spawn e adiar a extração.** Era a alternativa
  honesta enquanto o PR #137 estava aberto; deixou de ser quando ele entrou na
  main em 2026-09-01.
- **Copiar do `chaseai-yt/claudex-loop`.** O repo reprovou no teste de
  acoplamento em 2026-08-26 (framework de método sobre o fluxo de sete
  estágios). O que se aproveita é o contrato, já destilado na D5, não código.

## Fora de escopo

- **Trocar** o revisor Claude pelo externo. O externo é segundo auditor, nunca
  substituto: perder o revisor com método embutido seria trocar sinal por ruído.
- O **veredito grepável do próprio revisor Claude** — ideia
  `contrato-de-veredito-de-uma-linha-no-revisar`, que não depende de modelo
  externo nenhum.
- **Rotear execução para modelo externo.** O roteamento de trabalho continua nos
  subagentes Claude; o externo só audita.
- **Autoavaliação do método** (`autoavaliacao-do-metodo-contra-o-rastro`): aplica
  troca de auditor ao MÉTODO, não à entrega. Ideia vizinha, trabalho separado.

## Em aberto

- Onde exatamente o `revisar` invoca a segunda opinião: passo da `SKILL.md` em
  prosa, ou subcomando novo. Depende de a Fase A revelar de quanto o helper
  precisa saber do estado — decisão do estágio `plano`, não deste design.
- Qual modelo externo é o padrão quando os dois estão ligados. Sem uso real não
  há base para escolher; a primeira rodada de verdade responde.
