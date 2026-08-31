# Design — o ciclo reprovado→executar vira máquina, e `ok` sem evidência não fecha

> **Fluxo 1** na fila do `LEIA-PRIMEIRO-CONSOLIDADO-v2`. Recuperado da conversa
> de origem em 2026-08-30. Duas costuras marcadas com ⚠ foram remontadas a
> partir do contexto (o teor é fiel; a redação exata pode diferir do original).
> Destino: `docs/rainforest/design/2026-08-28-ciclo-por-maquina-e-ok-com-evidencia.md`

Origem: revisão externa do plugin (2026-08-28), lida contra a tese do próprio
repo — "comando com exit code, não instrução". Três garantias centrais do fluxo
ainda vivem só no texto das skills; este design as move para o `estado.cjs`.

Data: 2026-08-28. Status: aprovado em 2026-08-28 — Q1–Q3 fechadas na recomendada.

## Objetivo

Fechar três buracos entre o que as skills prometem e o que a máquina cobra:

1. `marcar --status ok` aceita `--json` vazio de evidência — o "✅ sem comando e
   saída colados = não feito" (regra 12) é instrução, não trava.
2. `reprovado` "devolve o trabalho ao executar" no texto de
   `skills/verificar/SKILL.md`, mas nenhuma linha do `estado.cjs` reabre o
   estágio upstream — a back-edge do grafo é conselho.
3. ⚠ Não existe critério de parada no ciclo executar↔verificar: sem contador de
   tentativas, um critério que reprova indefinidamente gira infinito gastando
   token sem escalar a decisão ao usuário.

## Decisões fechadas

- **D1 — `marcar --status ok` nos estágios de execução recusa fechamento sem
  `comando` e `saida` preenchidos no `--json`.** ⚠ (título remontado)
  Porque: a regra 12 diz que pronto se prova com comando e saída colados, e a
  única forma de a trava não virar teatro é a máquina recusar o fechamento sem
  eles. Presença, não conteúdo: quem julga se a saída prova o critério é o
  estágio `verificar` (e o usuário lendo o relatório) — o `estado.cjs` só
  garante que há o que ler. Validar conteúdo aqui duplicaria a régua do plano
  dentro de um script que não a conhece. (Q1 decide se `revisar`/`fechar`
  entram agora ou depois.)

- **D2 — `reprovado` em um estágio rebaixa o upstream imediato para `parcial`,
  gravando `reaberto_por` com estágio e data.**
  Porque: a back-edge precisa existir onde o `exigir` olha, senão ela não
  existe. `parcial` já é vocabulário do fluxo e já bloqueia `exigir` — reusar
  custa zero conceito novo. O campo `reaberto_por` preserva o rastro: quem abrir
  o JSON sabe que `executar` não está `parcial` por entrega pela metade, e sim
  por devolução do `verificar` de tal data. O mapeamento da devolução é o
  inverso de `PRE_REQUISITOS` (o upstream imediato), não uma tabela nova.

- **D3 — contador `tentativas` por estágio: incrementa a cada `reprovado`,
  zera no fechamento `ok`; na terceira reprovação, `exigir` do estágio
  reaberto recusa com exit 2 e manda subir a decisão.**
  Porque: três reprovações do mesmo estágio é o sinal de que o giro
  executar↔verificar não vai convergir sozinho — ou o critério está errado
  (problema do `plano`), ou a decisão está errada (problema do `design`), e as
  duas hipóteses são decisão do usuário, não do loop (regra 16). A trava é no
  `exigir` do estágio reaberto, não no `marcar` da reprovação: reprovar é
  sempre legítimo; o que precisa de autorização é insistir. O destrave é
  comando explícito (`estado.cjs liberar --slug <s> --estagio <e>` ou
  equivalente), que grava quem liberou e quando — decisão que evapora na
  esteira já tem plano próprio dizendo por que rastro importa.

- **D4 — `estado.cjs proximo` imprime o bloco do último `reprovado` quando ele
  é o motivo do próximo passo.**
  Porque: o retry só se corrige com o sinal bruto da falha, e hoje esse sinal
  fica num JSON que o modelo pode não reler — especialmente numa sessão nova ou
  pós-compactação, que é exatamente quando `proximo` roda. O comando que já é o
  ponto de retomada vira também o canal do feedback: critério, comando, saída e
  `faltou`, colados, sem depender de memória.

## Avaliado e descartado

- **`marcar` re-executar o comando do critério e comparar a saída.** Seria a
  trava perfeita — e uma superfície de execução arbitrária dentro do script de
  estado: comando vindo de JSON, rodando no cwd errado, possivelmente caro ou
  com efeito colateral duplicado. O ganho sobre validar presença não paga esse
  risco. Quem executa critério é `verificar`, com contexto.

- **Validar o conteúdo da saída no `marcar` (regex, saída esperada).** Duplica
  a régua do plano num lugar que não conhece o plano, e régua duplicada
  diverge. Descartado pelo mesmo motivo que a validação é de presença (D1).

- **Status novo `reaberto` em vez de rebaixar para `parcial`.** Mais preciso na
  leitura do JSON cru, mas cresce o vocabulário (`STATUS_EXECUCAO`,
  `estaFechado`, toda bateria que enumera status) para distinguir algo que o
  campo `reaberto_por` já distingue. Vocabulário cresce quando um campo não
  basta.

- **Contador por critério, não por estágio.** Mais fino — três reprovações de
  critérios diferentes não significam loop travado. Mas exigiria o `estado.cjs`
  entender a estrutura do plano (parsear tarefas e critérios), acoplando o
  script de estado ao formato de um arquivo que hoje ele não lê. Por estágio
  primeiro; se o teto errar pra menos na prática, o refinamento tem para onde ir.

- **Teto configurável por env ou config.** Chave para afrouxar trava é como
  trava morre. O 3 é constante nomeada no fonte; mudar exige commit.

## Fora de escopo

- **Hook `Stop` que barra fim de turno com estágio em voo.** Mesma família
  (mecanizar o "não chama de pronto"), superfície diferente (hooks, não
  `estado.cjs`) e custo próprio de falso positivo — design separado.
- **`conferir-entrega.cjs`.** Nada aqui muda a conferência de worktree.
- **A régua dos critérios em si.** Este design garante que evidência existe e
  circula; se ela prova o que diz provar continua sendo juízo do `verificar`.

## Decisões das Qs (fechadas em 2026-08-28, na recomendada)

- **Q1 — evidência obrigatória só em `executar` e `verificar`.** `revisar` e
  `fechar` ficam de fora desta entrega; `fechar` tem evidência de formato
  próprio (hash de commit) e merece campo próprio quando entrar.
- **Q2 — devolução mecânica é sempre para o upstream imediato.** A devolução
  longa (`verificar` → `plano`) fica manual, tomada pelo usuário quando o teto
  do D3 o aciona — a máquina não distingue código errado de critério errado.
- **Q3 — teto de tentativas = 3**, constante nomeada no fonte, sem env.

## Em aberto

- **O 3 do teto é chute calibrado por custo** (três giros completos de despacho
  + conferência), não medição. Revisitar com os dados que os `estado/*.json`
  acumularem depois desta entrega.
