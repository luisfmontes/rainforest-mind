# Absorver de um plugin de terceiro: 16 ideias e commit por partes

Data: 2026-09-12. Origem: análise do marketplace de plugins de um terceiro
(plugin de dados; o autor autorizou a leitura e não é nomeado aqui). O que entra aqui é a **ideia** por trás
de cada ponto forte e fraco, não o código: o plugin é macOS-only, preso à
empresa e a um autor; o método viaja.

## Objetivo

Fechar, num fluxo só, as lições que a análise deixou: regra que só vive em
texto se viola (25 `Co-Authored-By` num repo que os bania), então cada lição
vira trava ou vira frase declarada como "vale por disciplina". Nada plantado.

## Decisões fechadas

- **D1 — Um fluxo, em ondas por arquivo compartilhado.** Um design, um plano,
  um PR, uma revisão. Fatiar em "código" e "texto" deixaria metade no limbo,
  que é o que este trabalho existe para não fazer. Precedente: `zerar-issues`,
  19 tarefas em 3 ondas — porquê: uma revisão cobre tudo, e nada espera a
  próxima rodada.
- **D2 — Gate de mensagem de commit.** Hook `PreToolUse` sobre `git commit`
  (janela principal e subagente): assunto imperativo com até 72 colunas, sem
  ponto final; **corpo obrigatório** (linha em branco + texto que diz o
  porquê) quando o diff em stage toca **mais de 3 arquivos ou mais de 150
  linhas** (`git diff --cached --numstat`). Recusa com exit 2 e imprime a
  forma esperada. "Por partes" já é um commit por tarefa do plano, e o
  `gate-staging-total` já obriga `git add` por caminho — a mensagem era a
  metade que ninguém conferia — porquê: o plugin de terceiro prova por regex o
  formato e vive "um commit lógico" por hábito (285 de 441 commits tocam até
  3 arquivos, 310 têm corpo); a trava dele é o que faz o hábito sobreviver.
- **D3 — Frase de confirmação com o alvo dentro.** Três ações irreversíveis
  passam a exigir uma frase que nomeia ação e alvo, comparada pelo script
  com o alvo que **ele mesmo** derivou; divergência recusa e imprime a frase
  esperada: `limpar-branches --remover --forcar` (`-D` apaga commit que não
  está em lugar nenhum), `limpar-worktrees --remover` sobre worktree **sujo**
  (hoje nunca remove; passa a remover só com a frase), e `gate-fechar-issue`
  para o caminho que fecha Issue (`scripts/fechar-issue.cjs`). A frase é
  digitada pelo usuário e repassada verbatim; o script não a inventa.
  `marcar aprovado` fica de fora — é reversível — porquê: "sim" confirma a
  pergunta; "CONFIRMO apagar branch fluxo/x" confirma o alvo, e obriga a ler o
  que vai ser destruído.
- **D4 — Tabela de racionalizações nas regras 9, 10 e 12.** Seção
  "Racionalizações" em `regra-09.md`, `regra-10.md` e `regra-12.md`, 3 a 6
  linhas cada, forma `| Pensamento | Realidade |`, alimentada por incidente
  real do acervo (ex.: "a suíte passou" → regra 12; "despachar custa mais que
  fazer" para task de 5k tokens → regra 10; "só mais uma rodada" → regra 9).
  Se a catraca de 3k tokens encostar, a regra parte em acervo pelo mecanismo
  que já existe — porquê: o `clickhouse-query` pré-registra a desculpa que
  faz o modelo pular a regra; regra sem a desculpa catalogada é pulada pela
  desculpa não escrita.
- **D5 — Exit 69 = "não pude verificar".** `conferir-entrega`,
  `conferir-mutacao`, `conferir-fluxo` e `conferir-ponte` saem com **69**
  (`EX_UNAVAILABLE`) e primeira linha de stderr `nao-verificavel: <motivo>`
  quando o que falta é ambiente (git indisponível, worktree sumiu, CLI
  ausente, rede), separando de 0 (passou) e de 1/2 (reprovou). O `executar`
  e o `revisar` tratam 69 como bloqueio de ambiente (regra 14): nem
  aprovação, nem reprovação, nem `flaky`. 64 descartado (é `EX_USAGE`), 75 já
  é "Codex sem cota" — porquê: o `run_gates.sh` do plugin de terceiro separa "gate
  falhou" de "harness quebrou" com exit 64 + sentinela, e o orquestrador não
  conta o segundo como falha do gerador; a regra 12 hoje só diz "exit ≠ 0 não
  é sucesso", e um `conferir` que não conseguiu rodar vira reprovação falsa.
- **D6 — Mapa regra → trava, com bateria.** `docs/travas-mecanicas.md` ganha
  uma tabela com as 17 regras: coluna "trava" (hook, script ou `exigir` que a
  garante) e coluna **"vale por disciplina"** para as que não têm nenhuma.
  Bateria nova falha se uma regra do `SKILL.md` não tem linha na tabela —
  porquê: o CLAUDE.md do plugin de terceiro bania trailer e heredoc e o histórico
  tem 25 trailers e 2 heredocs; regra sem trava é aspiração, e a lista
  explícita das desprotegidas impede acreditar que estão protegidas.
- **D7 — Teto de tamanho para toda skill.** `SKILL.md` de qualquer skill do
  plugin: **500 linhas e 16 KB**, medido em bateria, exit ≠ 0 ao passar. Hoje
  só `rainforest-mind` tem teto (`SKILL_MAX_BYTES`); a maior das outras,
  `executar`, tem 15 KB — o teto pega o próximo crescimento — porquê: o
  plugin de terceiro impõe 500 linhas no `skill-author` e quatro skills furam (815,
  665, 548, 504), porque o limite era texto; `commit/` soma 187 KB de prosa
  para um commit.
- **D8 — Veredito por tarefa carimbado.** Cada `marcar` de tarefa no
  `executar` grava `{tarefa, hash_base, iteracao, sessao}` no estado; na
  retomada (`proximo`/`ler`) o `estado.cjs` **avisa** quando `hash_base` não é
  ancestral do HEAD atual. Invalidação automática fica para quando a
  retomada falhar por isso uma vez — porquê: o `plan_state.mjs` valida
  veredito por sessão/task/iteração/schema, e o `resume` re-marca o que não
  bate; o nosso `revisar` já trava base/HEAD, mas tarefa aceita não sabe em
  que base foi aceita.
- **D9 — Duplicação e allowlist.** Novo `conferir-duplicacao.cjs`: arquivo
  com hash idêntico a outro dentro do plugin (fora de fixture declarada)
  **falha** o `conferir-publicacao`; função homônima exportada entre
  `scripts/*.cjs` e padrão largo na allowlist do usuário (`Bash(bash -c *)`,
  `Bash(sh -c *)`, `Bash(*)`, `Bash(eval *)`) viram **aviso** no `/saude`
  — porquê: `ch_mcp.py` idêntico em duas skills e 20 funções homônimas
  nasceram de copiar a skill que funcionava; e `Bash(bash -c *)` na allowlist
  do autor fazia o hook destrutivo e a permissão se anularem em silêncio. A
  nossa allowlist está limpa hoje; o aviso é prevenção.
- **D10 — `conferir-publicacao` lê o commit.** Além do disco, varre
  `git show HEAD:<path>` de cada arquivo rastreado tocado no range a
  publicar; divergência entre disco e commit é achado. Os outros seis
  `conferir-*` que leem só disco (encoding, invariantes, mutação, ponte,
  divergência, livro) são sobre o worktree por natureza e ficam — porquê: o
  passo 7.9 do plugin de terceiro lê versão de `git show <sha>:<path>`, nunca do
  worktree, porque edição não commitada anunciaria release que não existe.
- **D11 — Modelo de ameaça e plataforma declarados.** Cada `hooks/gate-*.cjs`
  e `hooks/portaria.cjs` ganha no docblock duas linhas fixas: `Protege
  contra:` e `Não protege contra:`; o README declara a plataforma em que a
  bateria roda (Windows + Git Bash; Linux/macOS não medidos). Sem trava, por
  decisão: é texto que descreve trava — porquê: o `check_destructive` diz "not
  a boundary against a local adversary" e isso muda "tem bypass" para "fora
  do escopo declarado"; e o plugin de terceiro é macOS-only sem uma linha dizendo
  (99 testes Node e 10 Python caem no Windows só por caminho e `uid`).
- **D12 — Afirmação medida leva data e comando de re-verificação.** Convenção
  em `skills/rainforest-mind/SKILL.md` (seção "Como este arquivo é lido") e
  no `docs/rainforest/README.md`: bloco `>` de incidente ou medição traz a
  data **e** a linha `re-verificar: <comando>`. Sem trava — porquê: o
  `engine-rules.md` data "verificado em julho de 2026" e dá o `SELECT` que
  mostra se o setting virou; nossas memórias têm data e não têm o comando.
- **D13 — Paridade ao portar.** `modo-dev`, seção "Despachar": briefing de
  porte (bash→cjs, py→cjs) tem como critério "saída byte a byte igual sobre
  os fixtures do original", não "testes verdes" — porquê: o porte
  Python→Node do plugin de terceiro carrega `pyJsonDumps`/`pySort`/`pySplitLines`
  para os fixtures antigos seguirem valendo; sem isso porte é reescrita
  disfarçada.
- **D14 — Legibilidade por terceiro e escalonamento em frase.** `fechar`
  ganha o item "outra pessoa faz o release lendo só o README?" no passo do
  bump de versão; `executar` ganha uma frase fixando a ordem gate mecânico →
  tester → revisor, sequencial, sem trava nova (a catraca de mutação antes do
  `revisar` já existe) — porquê: 89% dos commits do plugin de terceiro são de uma
  pessoa e o release mora em 187 KB de prosa; e o avaliador caro do pipeline
  deles só roda quando o gate barato falhou.

## Avaliado e descartado

- **Dois fluxos (travas vs. texto)**: metade ficaria para "depois", e "depois"
  é onde as ideias plantadas morreram — o motivo declarado deste trabalho.
- **Exit 64 para "não verificável"**: é `EX_USAGE` (erro de linha de comando)
  em `sysexits`; colidiria de sentido com erro de flag.
- **Invalidar tarefa automaticamente em D8**: nunca vimos retomada quebrar
  por base velha; trava sem incidente é trava que se contorna por hábito.
- **Arquivo único de racionalizações**: a desculpa é lida junto da regra que
  ela pula, ou não é lida.
- **Frase de confirmação em `marcar aprovado`**: reversível; frase em ação
  reversível ensina a digitar sem ler.
- **Portar o pipeline plan/execute inteiro**: já temos o equivalente (fluxo
  de 7 estágios, portaria, catraca de mutação, ponte Codex); o que faltava
  está em D5 e D8.

## Fora de escopo

- Rede no SessionStart: nenhum hook de abertura nosso faz rede (medido em
  2026-09-12); não há o que corrigir.
- Caminhos de máquina no repo: `conferir-publicacao` já pega
  `C:\Users\<nome>` e `/Users/<nome>`.
- Tratamento de `bash -c`/`eval` no `gate-git-verificacao`: já feito (rodada 2,
  2026-09-04).
- Hook destrutivo genérico (`rm`, `DROP`, `kubectl delete`): o escopo do
  rainforest-mind é fluxo e git; guardrail de serviço mora no plugin de cada
  serviço.
- Conteúdo de domínio do plugin de terceiro (ClickHouse, Kafka, Airflow): é do
  terceiro, não do método.

## Em aberto

- (vazio)
