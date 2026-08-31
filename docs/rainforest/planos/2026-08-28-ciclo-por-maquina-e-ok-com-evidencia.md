# Plano: o ciclo reprovado→executar vira máquina, e `ok` sem evidência não fecha

> **Fluxo 1** na fila do `LEIA-PRIMEIRO-CONSOLIDADO-v2`. Recuperado da conversa
> de origem em 2026-08-30, verbatim.
> Destino: `docs/rainforest/planos/2026-08-28-ciclo-por-maquina-e-ok-com-evidencia.md`
> Ressalva registrada na origem: os alvos de mutação foram escritos contra
> código lido por amostragem; o `executar` deve tratá-los como intenção e
> deixar o `conferir-mutacao.cjs` recusar o que não morder.

Design: docs/rainforest/design/2026-08-28-ciclo-por-maquina-e-ok-com-evidencia.md

## O que não pode quebrar

- **`--json` continua aceitando metadado arbitrário.** A validação do D1 exige
  a presença de `comando` e `saida` em dois estágios; não rejeita nem apaga
  chave desconhecida — invariante fixado no plano
  `decisao-que-evapora-na-esteira`.
- **Estado antigo continua legível.** Todo `estado/*.json` já commitado (sem
  `tentativas`, sem `reaberto_por`) passa por `exigir`, `proximo` e `marcar`
  sem erro: campo ausente vale zero/ausente, nunca exceção.
- **`arqueologia` e `limpar` seguem nunca bloqueando** — a trava de tentativas
  vive só nos estágios de execução.
- **Fluxo sem reprovação não muda em nada.** Um slug que fecha
  design→plano→executar→revisar→verificar→fechar sem `reprovado` produz o
  mesmo JSON de hoje, mais nenhum campo.
- **Nenhuma env nova.** O teto é constante nomeada no fonte (Q3).

## Tarefas

### 1. `ok` sem evidência não fecha `executar` nem `verificar` [tipo: implementar]
atende: D1, Q1
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: a lista de estágios que exigem evidência, `['executar', 'verificar']`
  para: `['executar']`
  bateria: `bash scripts/testa-estado.sh`
  fixture: o caso "ok de verificar sem saida colada e recusado" de `scripts/testa-estado.sh`
pronto quando: `marcar --estagio verificar --status ok --json '{}'` sai ≠ 0 com
mensagem nomeando `comando` e `saida`; o mesmo com os dois campos não vazios
(string com conteúdo, não `""` nem espaço) fecha; `revisar` e `fechar` seguem
fechando sem os campos; e a bateria cobre os quatro casos com a saída colada

### 2. `reprovado` rebaixa o upstream imediato para `parcial`, com rastro [tipo: implementar]
atende: D2, Q2
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: a atribuição que rebaixa o upstream, `status: 'parcial'`
  para: `status: 'ok'`
  bateria: `bash scripts/testa-estado.sh`
  fixture: o caso "reprovado em verificar reabre executar" de `scripts/testa-estado.sh`
pronto quando: com `executar` fechado `ok`, rodar `marcar --estagio verificar
--status reprovado` deixa `executar` com `status: parcial` e `reaberto_por:
{estagio: verificar, data: <ISO>}` no JSON; o `exigir --estagio verificar`
seguinte recusa com exit 2 nomeando `executar`; o upstream vem do inverso de
`PRE_REQUISITOS`, sem tabela nova; e reprovar `revisar` reabre `executar` pelo
mesmo mecanismo, provado na bateria com o JSON colado

### 3. Três reprovações travam o `exigir` do estágio reaberto; destrave é comando [tipo: implementar]
atende: D3, Q3
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: a comparação do teto, `tentativas >= TETO_TENTATIVAS`
  para: `tentativas > TETO_TENTATIVAS`
  bateria: `bash scripts/testa-estado.sh`
  fixture: o caso "a terceira reprovacao trava, a segunda nao" de `scripts/testa-estado.sh`
pronto quando: `tentativas` incrementa a cada `reprovado` do estágio e zera no
fechamento `ok`; na terceira reprovação consecutiva, `exigir` do estágio
reaberto sai com exit 2 mandando subir a decisão ao usuário — na segunda,
passa; `estado.cjs liberar --slug <s> --estagio <e>` destrava gravando
`liberado_em` no bloco e o `exigir` seguinte passa; estado antigo sem
`tentativas` conta do zero sem erro; tudo provado na bateria com saída colada,
inclusive a fronteira 2/3

### 4. `proximo` cola o bloco do último `reprovado` [tipo: implementar]
atende: D4
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: a chamada que imprime o bloco do reprovado no `proximo`
  para: a mesma linha removida (ou atrás de `if (false)`)
  bateria: `bash scripts/testa-estado.sh`
  fixture: o caso "proximo imprime criterio, comando, saida e faltou do reprovado" de `scripts/testa-estado.sh`
pronto quando: com um `reprovado` como último veredito, `estado.cjs proximo
--slug <s>` imprime `criterio`, `comando`, `saida` e `faltou` do `--json` da
reprovação junto do próximo passo; sem reprovação pendente, a saída de hoje não
muda byte; provado na bateria comparando as duas saídas coladas
