# Régua selada por construção e keep/discard por comparação interna

## Objetivo

Enxertar na skill `regua` dois mecanismos observados em `karpathy/autoresearch`:
a régua deixa de ser imutável por prosa e passa a ser imutável por construção, e
o loop passa a decidir sozinho, a cada rodada, se guarda ou descarta o trabalho.

Hoje a skill escreve que o arquivo de mecanismos é "commitado na rodada 1 e não
muda depois" (`skills/regua/SKILL.md:74`) e o critério de aceite confere essa
frase lendo o texto (`docs/rainforest/criterios/fluxo-12-regua.md:14`). É prosa
auditada por prosa — exatamente o buraco do autoresearch, que protege o juiz
(`evaluate_bpb`) com uma linha de markdown e nada mais.

## Decisões fechadas

- **D1 — O selo é o git, não hash próprio** — porquê: a régua já é arquivo
  versionado commitado na rodada 1; o commit de adição *é* o selo, e um script
  com `createHash` seria mecanismo novo sobre problema já resolvido.
- **D2 — O manifesto é um arquivo só, com régua, mecanismos e freios** — porquê:
  teto de rodadas trocado no meio do loop é a mesma fraude que mecanismo trocado
  no meio; um arquivo é uma âncora e um `git show`.
- **D3 — O juiz lê do commit, nunca da árvore de trabalho** — porquê: conferir é
  uma checagem que se pode pular; `git show "$ANCORA":<regua>` é imutável por
  construção, porque o crítico não tem como enxergar outra coisa. Exige
  `MSYS_NO_PATHCONV=1` no Windows, senão o `ref:caminho` vira caminho de
  arquivo e falha em silêncio.
- **D4 — A âncora é recomputada, nunca SHA fixo em arquivo versionado** — porquê:
  `git log --diff-filter=A --format=%H -- <regua> | tail -1` sobrevive a rebase;
  âncora hardcoded já quebrou duas vezes neste repo
  (`scripts/testa-conferir-encoding.sh:9-17`).
- **D5 — Âncora que não resolve aborta o loop** — porquê: exit 1 antes de
  despachar qualquer crítico. Degradar para "usa a árvore de trabalho mesmo"
  devolve o problema sem ninguém notar; falha fechada é o enxerto inteiro.
- **D6 — O teto de rodadas passa a viver no manifesto, em seção "Freios"** —
  porquê: hoje ele só existe na conversa, e o que não está em disco não chega ao
  agente novo de cada rodada.
- **D7 — `scripts/conferir-regua.cjs` confere âncora e formato, com bateria** —
  porquê: com o teto dentro do selo, manifesto sem teto sela um buraco. O script
  valida a âncora, a presença da seção "Freios" e 5 a 7 `### M<n>` sequenciais,
  no contrato de exit code do repo (0 ok, 1 veredito negativo, 2 uso errado), com
  `scripts/testa-conferir-regua.sh`. A alternativa — o próprio agente contar — é
  o modo de falha que este trabalho conserta.
- **D8 — Keep/discard nasce de uma segunda comparação cega** — porquê: o veredito
  contra a régua é binário e não ranqueia as nossas rodadas entre si. Nosso-novo
  contra nosso-melhor-guardado é o que dá o descarte automático e faz o builder
  N+1 partir do melhor em vez do último.
- **D9 — Dois despachos de crítico por rodada, ambos agentes novos e cegos** —
  porquê: um crítico só, vendo régua, nosso-novo e nosso-melhor, identifica pelo
  parentesco quais dois são nossos e o anonimato cai.
- **D10 — Os dois críticos recebem o mesmo manifesto, do mesmo commit** — porquê:
  crítico interno sem critério devolve "o B está mais polido", que é a falha
  nomeada na calibragem da Fase 1.
- **D11 — A lacuna única para o builder N+1 sai da comparação contra a régua** —
  porquê: é a régua que define o alvo. Lacuna vinda da comparação interna faria o
  loop se perseguir, que é o "medir a si mesmo" que a skill proíbe.
- **D12 — O melhor guardado é um SHA, registrado no TSV e materializado por
  `git show`** — porquê: o commit por rodada já existe na skill, e o log
  versionado é o ponteiro natural. Limite declarado: quando o artefato é render
  (print, filmstrip), o render precisa estar commitado junto, senão a comparação
  interna fica cega.
- **D13 — Discard não apaga o commit; o que não avança é o ponteiro** — porquê: o
  commit por rodada foi comprado justamente para poder voltar à rodada 3, e a
  regra 11 proíbe git destrutivo em agente. O autoresearch faz `git reset` e
  perde a tentativa; aqui ela fica no histórico.
- **D14 — Quarta condição de parada: estagnação, K=3 rodadas sem keep** — porquê:
  estagnar não é a mesma coisa que acabar o orçamento, e o caso de uso declarado
  é largar rodando no `/loop`. Com dois críticos por rodada, três rodadas paradas
  é o desperdício que o enxerto existe para cortar.
- **D15 — Log das rodadas versionado, colunas fixas** — porquê:
  `docs/rainforest/reguas/<slug>-rodadas.tsv` com
  `rodada  commit  venceu_regua  venceu_interno  status  lacuna`, `status` em
  `keep|discard|abortado`. O autoresearch joga o `results.tsv` no `.gitignore` e
  perde o histórico do raciocínio junto com a máquina.
- **D16 — A seção "O que falsificaria esta skill" ganha um teste para o enxerto**
  — porquê: se em três usos toda rodada der `keep`, a comparação interna não
  discrimina e o mecanismo custa dois críticos por rodada para nunca reprovar
  nada. O remédio seria cortar o crítico interno, não apertá-lo.

## Avaliado e descartado

- **Reusar `scripts/recibo.cjs` para selar a régua.** Ele já faz sha256 dos
  entregáveis e compara depois (`recibo.cjs:114-120`, `:298-336`), mas exige
  `docs/rainforest/estado/<slug>.json` com `plano.entregaveis` — e a `regua` não
  é estágio do fluxo e não aparece no `estado.cjs` (`skills/regua/SKILL.md:178`).
  Grava em `.rainforest/colheita/`, que é gitignorado, então o selo não
  acompanha o repo.
- **Script próprio calculando hash do manifesto.** Degrau 6 sobre um problema que
  o git resolve em duas linhas, e re-inlinar `createHash` é defeito testável
  neste repo (`scripts/testa-ponte.sh:179-183`). O `conferir-regua.cjs` da D7
  sobreviveu porque mudou de trabalho: valida formato e âncora, não recalcula
  hash de conteúdo.
- **Conferir por `git diff --quiet` em vez de ler do commit.** Detecta a
  alteração, mas continua sendo uma checagem que alguém pode deixar de rodar —
  não é "por construção", que é a diferença inteira entre isto e o markdown do
  autoresearch.
- **A âncora como portão do `portoes.cjs`.** No Windows o `CHECK:` roda em
  `cmd.exe /d /s /c` (`portoes.cjs:389-394`) e `$(git log ...)` não expande; a
  âncora viraria SHA fixo em arquivo versionado, que é o anti-padrão da D4.
- **Custo fixo por tentativa (o orçamento de 5 minutos do autoresearch).** Lá ele
  existe para tornar `val_bpb` comparável entre arquiteturas diferentes; aqui a
  comparabilidade vem do crítico cego vendo os dois artefatos lado a lado. O
  papel anti-força-bruta já é do teto de rodadas, e o `Agent` não tem botão de
  orçamento para impor o limite.

## Fora de escopo

- A `regua` virar estágio do fluxo ou entrar no `estado.cjs`. Ela continua
  invocável sozinha, como `divergir`, `semear` e `arqueologia`.
- Mudar o que o builder enxerga. Ele continua recebendo a régua e a lacuna única,
  e continua sem ver o manifesto de mecanismos — critério 1 de
  `docs/rainforest/criterios/fluxo-12-regua.md`.
- Resolver a comparação interna para artefato que só existe renderizado. A D12
  declara o limite e manda commitar o render; automatizar o render está fora.

## Em aberto

- (vazio)
