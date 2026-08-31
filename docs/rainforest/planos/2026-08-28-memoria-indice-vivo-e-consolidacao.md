# Plano: a memória ganha índice vivo, leitura por relevância e ciclo de vida

Design: docs/rainforest/design/2026-08-28-memoria-indice-vivo-e-consolidacao.md

## O que não pode quebrar

- **Memória indisponível nunca bloqueia a sessão.** Toda mudança nos hooks
  preserva a degradação graciosa: banco ausente/corrompido → bloco vazio,
  exit 0. A relevância é enriquecimento — FTS quebrado volta para recência.
- **O teto de 3.000 B do bloco injetado não sobe.** Rodapé e casadas por FTS
  cabem dentro dele; a bateria de bytes de `memoria-sessao` continua mandando.
- **`observacoes` é verdade de máquina: nada apaga linha dela.** Consolidar
  marca (`consolidada_em`), nunca deleta. As derivadas continuam rederiváveis.
- **Banco legado abre sem erro.** Migração de schema (FTS de conteúdo externo,
  coluna nova) roda dentro do `criarSchema`, idempotente, e `reindexar`
  reconstrói o índice de qualquer estado.
- **`/saude` continua sem fazer rede** e sem escrever nada.

## Tarefas

### 1. O FTS5 vira conteúdo externo com triggers, e a migração é idempotente [tipo: implementar]
atende: D1
arquivos: `scripts/esquema-memoria.sql`, `scripts/memoria.cjs`, `scripts/testa-memoria.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: a criação do trigger de INSERT em observacoes
  para: a mesma linha removida
  bateria: `bash scripts/testa-memoria.sh`
  fixture: o caso "observacao gravada aparece no buscar sem reindexar" de `scripts/testa-memoria.sh`
pronto quando: gravar uma observação (pelo mesmo caminho do `observar.cjs`) e
rodar `memoria.cjs buscar` com termo dela devolve a linha, **sem** `reindexar`
no meio; um banco criado no schema antigo passa pelo `criarSchema` novo sem
erro e o `buscar` volta a funcionar após o rebuild; UPDATE e DELETE de teste
mantêm o índice casado (count FTS == count observacoes); tudo com saída colada

### 2. O rodapé do bloco injetado ensina o `buscar` [tipo: implementar]
atende: D3
arquivos: `hooks/lib/memoria-sessao.cjs`, `hooks/testa-memoria-session-start.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/memoria-sessao.cjs`
  de: a concatenação do rodapé no fim do bloco
  para: a mesma linha removida
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: o caso "o bloco termina ensinando o comando de busca" de `hooks/testa-memoria-session-start.sh`
pronto quando: com pelo menos uma observação, o bloco termina com a linha
`mais: node scripts/memoria.cjs buscar "<termo>"`; sem observação nenhuma, o
rodapé não aparece (caixa vazia continua vazia); o total continua sob os
3.000 B com o rodapé contado dentro do teto, provado pela bateria de bytes

### 3. A abertura injeta 9 recentes + até 5 casadas com o foco [tipo: implementar]
atende: D2
arquivos: `hooks/memoria-session-start.cjs`, `hooks/lib/memoria-sessao.cjs`, `hooks/testa-memoria-session-start.sh`
depende de: 1
paralela: sim
mutacao:
  arquivo: `hooks/memoria-session-start.cjs`
  de: a exclusão das já-recentes na consulta FTS (o filtro de id)
  para: o filtro removido
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: o caso "casada por FTS nao duplica observacao ja recente" de `hooks/testa-memoria-session-start.sh`
pronto quando: com foco ativo cujos termos casam observação antiga (fora das 9
recentes), ela entra entre as até 5 casadas, sem duplicar nenhuma recente; sem
foco, sem termo casado ou com FTS indisponível, saem 14 recentes byte a byte
como hoje; os termos vêm do título do foco que `foco-session-start` já parseia;
provado na bateria com os dois blocos colados

### 4. `memoria.cjs consolidar` produz `resumos` e marca, nunca apaga [tipo: implementar]
atende: D4
arquivos: `scripts/memoria.cjs`, `scripts/esquema-memoria.sql`, `scripts/testa-memoria.sh`
depende de: 1
paralela: sim
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: a marcação `consolidada_em` nas observações do lote
  para: a mesma linha removida
  bateria: `bash scripts/testa-memoria.sh`
  fixture: o caso "consolidar duas vezes nao gera resumo duplicado" de `scripts/testa-memoria.sh`
pronto quando: num banco de teste com 50+ observações de 60+ dias no mesmo
projeto, `memoria.cjs consolidar` grava resumos em lotes de 10 → 1 (LLM pelo
mesmo dublê `TESTADOR_CHAMAR_LLM` do `observar.cjs`), marca as originais com
`consolidada_em` e **não apaga linha nenhuma** (count antes == count depois);
rodar de novo não reconsolida o já marcado; abaixo dos gatilhos, sai sem
gravar; falha de LLM deixa o lote intacto para a próxima rodada

### 5. `/saude` ganha a seção do banco de memória [tipo: implementar]
atende: D5, Q3
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: 1
paralela: sim
mutacao:
  arquivo: `scripts/saude.cjs`
  de: a comparação de 48 h da pendência, `> QUARENTA_E_OITO_HORAS_MS`
  para: `>= 0`
  bateria: `bash scripts/testa-saude.sh`
  fixture: o caso "pendencia recente nao acusa pipeline parado" de `scripts/testa-saude.sh`
pronto quando: a seção acusa em uma linha cada — banco que não abre ou schema
que não confere (alerta), `count(observacoes) != count(observacoes_fts)`
(aviso, com a ação `memoria.cjs reindexar`), e pendência de marca d'água com
mais de 48 h (aviso, com a ação `observar.cjs`); banco simplesmente ausente é
`ok` com nota (instalação sem memória é estado legítimo); pendência de menos
de 48 h não acusa; no padrão dos `checar*` existentes, sem rede e sem escrita

### 6. O pipeline do observar volta a andar: teto trunca e vazio avança [tipo: implementar]
atende: D5
arquivos: `scripts/observar.cjs`, `scripts/testa-observar.sh`
depende de: 5
paralela: nao
mutacao:
  arquivo: `scripts/observar.cjs`
  de: o bloco de `avancarMarca` + `ultimoOffsetProcessado = offsetFim` dentro do ramo de prompt vazio
  para: só o `continue` (o avanço removido)
  bateria: `bash scripts/testa-observar.sh`
  fixture: o caso "offset_processado avancou (janela vazia = processada)" de `scripts/testa-observar.sh`
pronto quando: com um transcrito real cuja janela pendente tem um único
evento acima de `TETO_ARGUMENTO`, a passada trunca o texto (com marcador
explícito), grava observação e a marca avança — provado pelo caso 17 da
bateria e pela fila real desta máquina drenando de 34 pendências para 0;
e com janela cujo texto formatado é vazio, a marca avança sem gravar nada
— provado pelo caso 13 (contrato novo) e por `observar.cjs --seco`
devolvendo "nenhuma marca com pendencia" no banco real. Emenda registrada
em 2026-08-31: a tarefa nasceu da operação (duas causas de pendência
eterna achadas ao drenar o banco vivo), foi executada pela janela
principal e revisada pelo revisor independente na 3ª rodada (2 avisos
aceitos e documentados).
