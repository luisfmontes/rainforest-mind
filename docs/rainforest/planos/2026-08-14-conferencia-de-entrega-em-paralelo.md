# Plano: Conferencia de entrega e teste de saude sobrevivem a despacho paralelo

Design: docs/rainforest/design/2026-08-14-conferencia-de-entrega-em-paralelo.md

## O que não pode quebrar

Medido no repositorio antes de escrever este plano, em 2026-08-14 — os tres
sao a linha de base contra a qual "verde" significa alguma coisa:

- `bash scripts/testa-conferir-entrega.sh` sai **0** hoje (16 casos). Nenhum
  caso existente pode ser reescrito para acomodar a mudanca: eles sao a prova
  de que o comportamento sem `--paralelo` nao mudou.
- `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`
  sai **0** hoje (Python 3.13.5 no PATH). A paridade dos gemeos e o motivo de a
  variavel `CONFERIR` existir.
- `bash scripts/testa-saude.sh` sai **0** hoje. Ele passa por acidente: o
  historico atual e linear o bastante. Verde depois da mudanca nao prova nada
  sozinho — so prova junto com o cenario de merge da tarefa 2.
- **Sem `--paralelo`, `conferir-entrega` se comporta exatamente como hoje.** A
  flag e a unica porta do comportamento novo.
- Os codigos de saida continuam sendo 0 aprovado, 1 reprovado, 2 erro de uso.
- Aviso nao derruba exit 0; falha derruba para 1.

## Tarefas

### 1. Ancestralidade, cruzamento e avisos no conferir-entrega.cjs [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `scripts/conferir-entrega.cjs`
depende de: nenhuma
paralela: sim
pronto quando: `bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0` com os 16 casos existentes intactos (nenhuma linha de caso reescrita — o diff nao toca `scripts/testa-conferir-entrega.sh`), E `node scripts/conferir-entrega.cjs --worktree . --paralelo 2>&1 | head -1` NAO contem `opcao desconhecida`.

### 2. Fixture da situacao A do testa-saude.sh sem historico real [tipo: teste]
atende: D5
arquivos: `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
pronto quando: `grep -c 'HEAD~3' scripts/testa-saude.sh` devolve `0` E `bash scripts/testa-saude.sh; echo EXIT=$?` devolve `EXIT=0`.

**A prova do merge nao e do agente, e do `verificar`** — ela exige criar um merge commit e desfaze-lo, e git destrutivo e proibido para agente (regra 11). A janela principal roda, em CLONE DESCARTAVEL fora do repo: clonar o worktree, criar uma branch lateral a partir de `HEAD~2`, commitar nela, voltar e `git merge --no-ff`, e entao `bash scripts/testa-saude.sh; echo EXIT=$?` dentro do clone tem de devolver `EXIT=0`. Sem essa segunda medicao a tarefa 2 esta **nao verificada**, porque o primeiro `EXIT=0` e exatamente o que ja passava hoje.

### 3. O caminho paralelo do executar passa a flag [tipo: docs]
atende: D7
arquivos: `skills/executar/SKILL.md`
depende de: nenhuma
paralela: sim
pronto quando: `grep -n -- '--paralelo' skills/executar/SKILL.md` devolve pelo menos uma linha, e essa linha esta dentro do bloco de invocacao que hoje comeca em `skills/executar/SKILL.md:74`; o texto ao redor diz em uma frase que a flag vale **so** no despacho paralelo e o que ela afrouxa. `agents/executor.md` NAO aparece no diff.

### 4. Porte das mesmas mudancas para o gemeo em Python [tipo: implementar]
atende: D6
arquivos: `scripts/conferir-entrega.py`
depende de: 1
paralela: nao
pronto quando: `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0`, E `python scripts/conferir-entrega.py --worktree . --paralelo 2>&1 | head -1` NAO contem `opcao desconhecida`. A logica sai da tarefa 1, nao de reimplementacao independente: mesmas mensagens, mesmos vereditos.

### 5. Casos novos que exercitam a rodada paralela [tipo: teste]
atende: D1, D2, D3, D4, D6
arquivos: `scripts/testa-conferir-entrega.sh`
depende de: 1, 4
paralela: nao
pronto quando: `bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0` E `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh; echo EXIT=$?` devolve `EXIT=0`, com pelo menos estes quatro casos novos, cada um nomeando `paralelo`: (a) HEAD do principal avancou para frente + `--paralelo` -> exit 0 com aviso contendo `avancou`; (b) HEAD do principal moveu para tras (`checkout HEAD~1`) + `--paralelo` -> exit **1**, porque recuo nunca e avanco; (c) sujeira no principal em arquivo que o agente NAO tocou + `--paralelo` -> exit 0 com aviso contendo `nenhuma nos arquivos do agente`; (d) sujeira no principal em arquivo que o agente TOCOU (`feito.txt`) + `--paralelo` -> exit **1**. O caso (b) e o que separa D1 de "desligar a checagem 5".

## Cobertura

- D1 -> tarefas 1, 5
- D2 -> tarefas 1, 5
- D3 -> tarefas 1, 5
- D4 -> tarefas 1, 5
- D5 -> tarefa 2
- D6 -> tarefas 4, 5
- D7 -> tarefa 3
