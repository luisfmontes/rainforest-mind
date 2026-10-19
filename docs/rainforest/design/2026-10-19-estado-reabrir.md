# Reabrir revisar e verificar quando o código muda depois do ok (#567, #529)

## Objetivo
Commit de código depois do `verificar ok` (CI vermelho, conserto pequeno) passa a exigir
nova revisão e novo `verificar` por mecanismo, não pela memória da sessão; e achado não
bloqueante de uma revisão aprovada ganha caminho formal de volta ao `executar`.

## Decisões fechadas
- **D1 — `verificar ok` grava o HEAD em que rodou, e `exigir --estagio fechar` recusa com
  commit de código depois dele** — porquê: mede o fato em vez de confiar em a sessão lembrar.
  O `marcar verificar ok` grava `verificar.head` (`git rev-parse HEAD` da árvore do estado).
  O `exigir fechar` junta duas listas e tira os isentos (D2): os arquivos de
  `git diff --name-only <verificar.head> HEAD` que a branch também muda contra
  `merge-base(HEAD, origin/<padrão>)`, e os rastreados sujos do `git status`. Sobrando algum,
  recusa com exit 2, nomeia os arquivos e manda `reabrir` (D3). Sem `verificar.head`
  (estado anterior a este fluxo, ou `verificar` fechado com `--raiz`), avisa e não trava.
  *Emenda da revisão 1 (decidida pelo usuário, Q1–Q3):* com `--raiz` o HEAD não se grava,
  porque o da outra árvore comparado na árvore do estado recusava para sempre; trazer a
  padrão depois do `verificar` não acusa o que veio dela; edição de código não commitada
  conta, porque entraria no commit do passo 1 do `fechar` sem revisão.
  *Emenda da revisão 2 (decidida pelo usuário, Q1–Q3):* (a) a mesma recusa roda no
  `marcar fechar ok`, porque o conserto de CI vem depois do `exigir fechar` da abertura;
  (b) o `marcar verificar ok` recusa código mudado depois do HEAD do instantâneo do
  `revisar` — refazer só o `verificar` não pula a revisão; (c) a interseção de nomes
  dá lugar à comparação por arquivo da mudança da branch, `merge-base(head)..head` contra
  `merge-base(HEAD)..HEAD`, por `git patch-id --stable` (ignora deslocamento de linha):
  a padrão mexendo no mesmo arquivo não acusa, e apagar ou reverter o que a branch tinha
  acusa. Sem `origin/<padrão>`, vale `head..HEAD`.
  *Emenda da revisão 3 (4ª rodada liberada pelo usuário; impasse em
  `docs/rainforest/portoes/2026-10-19-estado-reabrir-impasse.md`):* o arquivo só conta
  quando o modo ou o blob em HEAD difere do verificado **e** a impressão difere; a
  impressão é `git diff --no-renames -U0 --binary` com `git patch-id --verbatim` (sem
  contexto, com indentação), e erro do git vale como mudança; renomeação conta pelos
  dois nomes. Conteúdo igual ao verificado não acusa (squash na padrão, conflito de
  versão resolvido para o valor da branch); conflito resolvido para outro conteúdo acusa.
  *Emenda da revisão 4 (aprovada, não bloqueantes reabertos pelo `reabrir`):* com o
  merge-base igual antes e depois, o conteúdo diferente basta (a impressão sem contexto
  não vê a mesma linha mudada de lugar); o git roda da raiz do repositório, com pathspec
  `:(top,literal)`, e o prefixo da subpasta sai dos nomes; erro nas listas de candidatos
  mantém a lista de `head..HEAD` inteira.
- **D2 — "Código" é todo arquivo fora das isenções que o `creep` já usa** — porquê: a lista
  (`globsIsentos` em `scripts/conferir-fluxo.cjs`: estado, design, plano, portões, varredura
  do slug, `relatorios/`, réguas) já define o rastro do fluxo que não é entrega. Reaproveitar
  evita uma segunda lista que diverge. Commit só de estado (o próprio `marcar`) não reabre nada.
  *Emenda da revisão 1 (Q4):* nesta trava o estado de **qualquer** slug
  (`docs/rainforest/estado/*.json`) também é isento: o lote leva o `fechar ok` do fluxo
  anterior para a branch seguinte, e isso é rastro, nunca entrega.
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
- Limites aceitos da trava de código (revisão 5): com a `main` movendo o merge-base, a
  mesma linha mudada de lugar passa (a impressão sem contexto não vê posição, e com
  contexto a `main` vizinha acusaria); com o projeto numa subpasta, arquivo fora dela sai
  com o nome relativo à raiz do repositório e pode casar com uma isenção do projeto. Erro
  nas listas de candidatos é defesa sem caso na bateria: as mesmas revisões acabaram de
  responder ao primeiro `diff`.

## Varredura
docs/rainforest/varredura/2026-10-19-estado-reabrir.txt — achou a #441 (CI vermelho depois do
`fechar ok`, resolvido fazendo `verificar reprovado` reabrir `fechar`) e a #238 (trava de
`executar parcial` com `revisar` em voo), que D3 preserva: `reabrir` é verbo à parte, e
`marcar executar parcial` continua recusado com posterior aberto.

## Em aberto
- (vazio)
