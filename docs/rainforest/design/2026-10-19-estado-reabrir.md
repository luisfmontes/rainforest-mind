# Reabrir revisar e verificar quando o código muda depois do ok (#567, #529)

## Objetivo
Commit de código depois do `verificar ok` (CI vermelho, conserto pequeno) passa a exigir
nova revisão e novo `verificar` por mecanismo, não pela memória da sessão; e achado não
bloqueante de uma revisão aprovada ganha caminho formal de volta ao `executar`.

## Decisões fechadas
- **D1 — `verificar ok` grava o HEAD em que rodou, e `exigir --estagio fechar` recusa com
  commit de código depois dele** — porquê: mede o fato em vez de confiar em a sessão lembrar.
  O `marcar verificar ok` grava `verificar.head` (`git rev-parse HEAD` da árvore em que a
  catraca roda, a mesma do `--raiz` quando vier). O `exigir fechar` lista os arquivos de
  `git diff --name-only <verificar.head> HEAD` e tira os isentos (D2); sobrando algum,
  recusa com exit 2, nomeia os arquivos e manda `reabrir` (D3). Sem `verificar.head`
  (estado anterior a este fluxo), avisa e não trava.
- **D2 — "Código" é todo arquivo fora das isenções que o `creep` já usa** — porquê: a lista
  (`globsIsentos` em `scripts/conferir-fluxo.cjs`: estado, design, plano, portões, varredura
  do slug, `relatorios/`, réguas) já define o rastro do fluxo que não é entrega. Reaproveitar
  evita uma segunda lista que diverge. Commit só de estado (o próprio `marcar`) não reabre nada.
- **D3 — Verbo novo `estado.cjs reabrir --slug <s> --estagio executar --motivo "<texto>"`** —
  porquê: hoje a saída é o `leve`, que pula a revisão nova (#529), ou `marcar verificar
  reprovado`, que diz que o verificar reprovou quando quem reabriu foi a sessão (#567). Aceito
  com `revisar` ou `verificar` em `ok`/`aprovado` (e com `fechar` em `ok`, para o CI vermelho
  depois do fechar). Efeito: `executar` volta a `parcial`; `revisar`, `verificar` e `fechar`
  vão a `pendente`; o motivo entra numa lista `reaberturas` do estado (data, estágio de onde
  voltou, motivo). Motivo vazio recusa. Só `--estagio executar` é aceito nesta versão.
- **D4 — `marcar executar ok` recusa quando o `de:` de alguma `mutacao:` não casa no fonte** —
  porquê: hoje a divergência só aparece no `verificar`, depois da revisão, e a sessão emenda o
  plano à mão sem que nada a lembre antes (P2 da #529; nesta sessão, três emendas na tarefa 1
  do lote). No `executar ok` o código já nasceu, então "não casa" deixa de ser "código a nascer"
  e vira recusa, nomeando a tarefa e o arquivo. `mutacao: n/a` e arquivo ausente seguem sem
  recusa, como hoje.
- **D5 — Modelo de ameaça: a trava protege contra a sessão que esquece de refazer revisão e
  verificar** — porquê: é o modelo das outras travas do `estado.cjs`. Fica fora quem edita o
  JSON de estado à mão ou reescreve o histórico para mover o `verificar.head`; isso é critério
  de parada da revisão, não buraco.
- **D6 — Bateria própria e barata, `scripts/testa-estado-reabrir.sh`** — porquê: a #567 pede o
  caso em `testa-estado.sh`, que passa de 10 min e pesa no shard mais lento do CI (#541). A
  bateria nova segue o molde de `testa-estado-decididos.sh` (caixa em `mktemp -d`, `estado.cjs`
  real, confere o JSON em disco).
- **D7 — Skills e CHANGELOG descrevem o verbo, versão MINOR** — porquê: verbo novo e trava nova
  mudam contrato (tabela do `CONTRIBUTING.md`). `skills/revisar/SKILL.md` ("Veredito binário")
  e `skills/fechar/SKILL.md` dizem quando usar `reabrir`.

## Avaliado e descartado
- `marcar revisar reprovado --nao-bloqueante` (P1 alternativa da #529): mistura "o revisor
  reprovou" (D9 do contrato de veredito exige veredito `reprovado` gravado) com "a sessão
  reabriu".
- Lista própria de "arquivos que não são código" para D1: duplicaria `globsIsentos`.

## Fora de escopo
- Reabrir para estágio diferente de `executar` (`--estagio revisar`): sem caso real ainda.
- Reconciliar o plano automaticamente quando o `de:` muda: D4 só recusa e nomeia; emendar
  continua sendo ato da sessão.

## Varredura
docs/rainforest/varredura/2026-10-19-estado-reabrir.txt — achou a #441 (CI vermelho depois do
`fechar ok`, resolvido fazendo `verificar reprovado` reabrir `fechar`) e a #238 (trava de
`executar parcial` com `revisar` em voo), que D3 preserva: `reabrir` é verbo à parte, e
`marcar executar parcial` continua recusado com posterior aberto.

## Em aberto
- (vazio)
