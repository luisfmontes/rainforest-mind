# Enxertos: poda idempotente (strands) e impressao digital de falha (reef)

## Objetivo

Fazer a falha de vigia que se repete aparecer como **persistente**, e não como novidade
a cada dia. O mecanismo é enxertado da impressão digital de falha do reef
(`reef/train/cordis_backend/manifest.py:41-63`, lido no código em 2026-09-29, relatório
`relatorios/2026-09-29-batedor-strands-reef-flowsint.md`).

O caso que motivou: "backup externo falhou" apareceu **6 vezes em 18 dias** no
`vigias/ERROS.md` (11, 21, 22, 23, 25 e 29/09). "não achei o FOCO.md" apareceu 5 vezes
(27/08 a 31/08). Nas duas, cada ocorrência chegou como novidade, porque o `ERROS.md` só é
lido numa janela de 24h (`erros_24h` em `vigias/dados-batedor-repos.js` e no
`scripts/saude.cjs`).

A poda de saída grande, a segunda metade do pedido, foi medida e descartada (ver
"Avaliado e descartado").

## Decisões fechadas

- **D1 — A poda condicionada a medição, com limiar de 10% dos caracteres de entrada** —
  porquê: a condição de colheita da própria ideia
  `poda-de-resultado-com-invariante-de-convergencia` manda não construir sem causa
  nomeada, e a contaminação 2,5x de 24/08 não foi atribuída a saída grande. A única
  medição daquele dia que se achou (issue #81) apontava estado pessoal na injeção.
- **D2 — A poda agiria só sobre Bash e Grep, e por isso fica descartada** — porquê: podar
  Read corta o meio de um arquivo lido de propósito, e o Edit precisa do texto exato que
  foi visto. Sem o Read, a faixa 8k-30k soma 3,1%, abaixo do limiar da D1.
- **D3 — Classificar na leitura, não na escrita** — porquê: uma lib Node lê o `ERROS.md` e
  deriva a classificação. O arquivo continua só recebendo linhas no fim. O `erros.ps1`
  (PowerShell só em ASCII, com histórico de quebra por encoding) não é tocado.
- **D4 — Impressão = sha256(vigia, causa normalizada)** — porquê: é o `fingerprint` do
  reef sem o "estágio", que aqui não existe. A normalização segue `normalize_cause`, na
  mesma ordem: caminho absoluto vira `<path>`, sequência opaca longa vira `<id>`, dígitos
  viram `<n>`, espaço colapsa e o texto é truncado em tamanho fixo. A causa é o texto
  depois de `[vigia]:`. A data e a hora do prefixo ficam de fora da chave.
- **D5 — Dois rótulos, janela de 30 dias, mínimo de 2 ocorrências** — porquê: ronda
  limpa não prova conserto quando a falha é intermitente. Rodando a regra anterior à mão
  sobre os dados reais, o backup virava "corrigido" em 14/09, 24/09 e 28/09, porque só
  falha com sessão aberta segurando o banco. Resultado: hoje nada apareceria. O critério
  de 2 ocorrências vem do reef (reaparecer no passo seguinte). Contam as ocorrências da
  impressão nos últimos 30 dias, posteriores ao último `RESOLVIDO` da vigia (D6):
  - **persistente ×S desde DD/MM**: a última ronda da vigia no log ainda tem a
    ocorrência, e as S ocorrências em rondas seguidas até ela somam S ≥ 2. `desde` é a
    primeira dessa sequência.
  - **intermitente ×N em 30 dias, última DD/MM**: N ≥ 2, e houve ronda limpa depois de
    alguma ocorrência.
  - Com N < 2 a impressão não é mostrada.

  Sobre os dados reais de 30/09, o resultado esperado é uma linha só:
  `backup externo falhou … RemoteException` como **intermitente ×5 em 30 dias, última
  25/09**. A falha de 29/09 (`ZipArchiveHelper`) tem outra causa normalizada e fica
  com ×1.
- **D6 — Corrigida só por linha `RESOLVIDO`; ronda limpa não corrige, silêncio não
  corrige** — porquê: silêncio de N dias engana com vigia semanal, e ronda limpa engana
  com falha intermitente (D5). Uma linha `[<vigia>]: RESOLVIDO…` zera a contagem das
  impressões daquela vigia anteriores a ela. Linha sem vigia nomeada
  (`[conferido na janela principal]`) não zera nada.

  O log da vigia (`vigias/log-<vigia>.txt`, cabeçalho de ronda `=== AAAA-MM-DD HH:MM ===`,
  `vigias/run-vigia.ps1:153`) serve só para separar persistente de intermitente. A
  ocorrência pertence à ronda de cabeçalho mais recente com hora ≤ a dela. Sem log (CI,
  máquina nova), não há prova de ronda limpa, e a impressão com N ≥ 2 sai como
  **persistente ×N desde** a primeira. A regra é nunca inferir melhora sem evidência.
- **D7 — Os dois rótulos aparecem no resumo de erros das vigias (`erros_24h`, em
  `vigias/dados-batedor-repos.js`) e no `/saude`** — porquê: é onde o erro já é lido.
  WhatsApp fica fora, porque o aviso viraria ruído no celular.

## Avaliado e descartado

- **Poda cabeça+marcador+cauda sobre a saída de ferramenta (strands `buildPreview`).**
  Medido em 2026-09-29, sobre 14 dias de transcripts: 1.094 sessões, 30,6 M caracteres.
  - Saída de ferramenta = 49,0% do total.
  - Faixa 8k-30k = 13,6%, sendo Read 10,4%, Bash 2,6% e Grep 0,5%.
  - Acima de 30k já existe o corte do próprio Claude Code.
  - Sem o Read (D2), sobram 3,1%, abaixo do limiar de 10% (D1).

  O ponto de aplicação existe e foi medido: um `PostToolUse` com `updatedToolOutput`
  **troca** a saída do Bash nativo, desde que o valor tenha o formato de objeto
  (`{stdout, stderr, interrupted, isImage, noOutputExpected}`); string é recusada com
  `schema_invalid`. O que falta é o problema a resolver.

  Se voltar: o `buildPreview` do strands não é idempotente (2072 → 2064 caracteres na
  segunda passada), e o enxerto exigiria pular o texto quando o marcador já está
  presente.
- **Classificar na escrita (`erros.ps1`).** Descartado na D3.
- **Corrigida por silêncio de N dias.** Descartado na D6.
- **Corrigida por ronda limpa no log** (a primeira versão desta D6, aprovada e reaberta
  no plano). Simulada sobre o log real do sentinela, marcou o backup como corrigido três
  vezes em 18 dias, e hoje não sobraria nada para mostrar (D5).
- **A impressão digital sobre as observações da regra 13.** As observações são prosa que
  o modelo redige, e duas descrições do mesmo erro não colidem no hash. O mecanismo
  pressupõe texto de erro de máquina, que é o que o `ERROS.md` tem.

## Fora de escopo

- A medição em pares do reef (candidato contra atual). Exige um executor de episódios que
  o rainforest não tem.
- Transformar falha em caso de regressão permanente (`promote_failures` do reef). É outra
  peça, e fica como pergunta de revisita do reef no livro.
- Aviso por WhatsApp (D7).

## Em aberto

- (vazio)
