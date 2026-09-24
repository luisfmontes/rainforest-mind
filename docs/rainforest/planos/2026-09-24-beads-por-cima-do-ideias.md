# Plano: Dependência entre ideias, por cima do ideias.jsonl

Design: docs/rainforest/design/2026-09-24-beads-por-cima-do-ideias.md

## O que não pode quebrar
- Escrita atômica, trava entre sessões, backup e conferência byte a byte do `ideias.cjs` (`comTrava`, `gravar`): todo caminho novo que grava passa por eles.
- Ideia sem `depende_de` se comporta exatamente como hoje em todos os subcomandos; `bash scripts/testa-ideias.sh` não muda de resultado.
- Nenhuma bateria escreve no `~/.rainforest` real (`RFM_ROOT` em caixa temporária, como `testa-ideias.sh`).
- O `ideias.jsonl` real não é escrito por nenhuma tarefa: os `depende_de` aprovados (tarefa 6) se gravam depois do merge, pelo `ideias.cjs editar`.

## Tarefas

### 1. Biblioteca do grafo: quem bloqueia, e ciclo [tipo: implementar]
atende: D1, D2, D5
arquivos: `scripts/lib/dependencias-ideias.cjs`, `scripts/testa-ideias-dependencias.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/lib/dependencias-ideias.cjs`
  de: `const LIBERAM = new Set(["colhida", "descartada"]);`
  para: `const LIBERAM = new Set([]);`
  bateria: `bash scripts/testa-ideias-dependencias.sh`
  fixture: `testa-ideias-dependencias.sh, caso "bloqueadora colhida libera a dependente"`
pronto quando: com um conjunto de linhas no formato real do `ideias.jsonl` (campos `id`, `status`, `unificada_em_id`, e o novo `depende_de` como lista de ids), `bloqueadoresDe(ideia, todas)` devolve os ids que ainda bloqueiam — a bloqueadora aberta bloqueia; colhida ou descartada não; unificada é trocada pela sobrevivente (`unificada_em_id`, seguindo a cadeia) e bloqueia se a sobrevivente estiver aberta; e `acharCiclo(todas)` devolve o caminho do ciclo ou `null` — provado por `bash scripts/testa-ideias-dependencias.sh` imprimindo os casos "bloqueadora aberta bloqueia", "bloqueadora colhida libera a dependente", "bloqueadora descartada libera", "unificada segue para a sobrevivente" e "ciclo de tres e detectado com o caminho".

### 2. `plantar`/`editar` recusam id inexistente e ciclo [tipo: implementar]
atende: D2, D6
arquivos: `scripts/ideias.cjs`, `scripts/testa-ideias-dependencias.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/ideias.cjs`
  de: `if (ciclo) throw new Erro(`
  para: `if (false) throw new Erro(`
  bateria: `bash scripts/testa-ideias-dependencias.sh`
  fixture: `testa-ideias-dependencias.sh, caso "editar que fecha ciclo e recusado e nada e gravado"`
pronto quando: numa caixa com `RFM_ROOT`, `ideias.cjs plantar` com `depende_de` apontando id inexistente sai com erro que nomeia o id e o arquivo fica byte-idêntico; `editar --id A` com `{"depende_de":["B"]}` quando B já depende de A sai com erro que mostra o caminho do ciclo e nada é gravado; `depende_de` que não é lista de strings é recusado; e um `depende_de` válido grava — provado por `bash scripts/testa-ideias-dependencias.sh` nesses casos (sha256 do arquivo antes/depois nas recusas).

### 3. `listar` marca bloqueadas e filtra `--prontas` [tipo: implementar]
atende: D4
arquivos: `scripts/ideias.cjs`, `scripts/testa-ideias-dependencias.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/ideias.cjs`
  de: `if (args.prontas) itens = itens.filter((o) => bloqueadoresDe(o, objs).length === 0);`
  para: `if (false) itens = itens.filter((o) => bloqueadoresDe(o, objs).length === 0);`
  bateria: `bash scripts/testa-ideias-dependencias.sh`
  fixture: `testa-ideias-dependencias.sh, caso "listar --prontas esconde a bloqueada"`
pronto quando: numa caixa com uma ideia A plantada e B plantada com `depende_de: ["A"]`, `ideias.cjs listar` mostra B com a marca de bloqueada nomeando A (a pessoa que lê vê QUEM bloqueia, não só que está bloqueada), `listar --prontas` mostra A e não B, e depois de `colher --id A` o `listar --prontas` passa a mostrar B — provado por `bash scripts/testa-ideias-dependencias.sh`.

### 4. `iniciar`/`colher` de ideia bloqueada avisam sem recusar [tipo: implementar]
atende: D4
arquivos: `scripts/ideias.cjs`, `scripts/testa-ideias-dependencias.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/ideias.cjs`
  de: `avisarSeBloqueada(alvo, objs);`
  para: `void 0;`
  bateria: `bash scripts/testa-ideias-dependencias.sh`
  fixture: `testa-ideias-dependencias.sh, caso "iniciar de ideia bloqueada avisa nomeando a bloqueadora e segue"`
pronto quando: numa caixa com B dependendo de A aberta, `ideias.cjs iniciar --id B` sai 0, grava o `em-colheita` e escreve em stderr um aviso que nomeia A e o título dela; o mesmo para `colher --id B`; sem dependência, nenhum aviso — provado por `bash scripts/testa-ideias-dependencias.sh` (exit, status gravado e texto do stderr).

### 5. `conferir` acusa dependência inconsistente e avisa a de descartada [tipo: implementar]
atende: D5, D6
arquivos: `scripts/ideias.cjs`, `scripts/testa-ideias-dependencias.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/ideias.cjs`
  de: `problemasDeDependencia(objs)`
  para: `[]`
  bateria: `bash scripts/testa-ideias-dependencias.sh`
  fixture: `testa-ideias-dependencias.sh, caso "conferir acusa ciclo gravado a mao"`
pronto quando: numa caixa em que o `ideias.jsonl` foi escrito à mão com um ciclo e com um `depende_de` para id inexistente, `ideias.cjs conferir` nomeia os dois como problema (exit != 0, como os outros problemas que bloqueiam); com uma dependente aberta de ideia descartada, `conferir` imprime o aviso nomeando as duas sem mudar o exit — provado por `bash scripts/testa-ideias-dependencias.sh`; e `node scripts/ideias.cjs conferir` contra o arquivo real (só leitura) não passa a acusar nada novo, porque nenhuma ideia real tem `depende_de` ainda.

### 6. Classificar as abertas que citam outra ideia [tipo: pesquisar]
atende: D3
arquivos: `docs/rainforest/pesquisas/2026-09-24-dependencias-propostas.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: pesquisa; o artefato é a proposta para o usuário aprovar, não código.
pronto quando: lendo o `~/.rainforest/ideias.jsonl` real (só leitura), o documento lista TODAS as ideias abertas (`plantada` e `em-colheita`) cujo texto cita o id de outra ideia — a contagem bate com a medição reproduzível colada no próprio doc (comando + saída) —, e para cada uma dá: o trecho que cita, a classificação `depende_de` / `irma` / `outro` com o porquê em uma linha, e, nas `depende_de`, o id proposto. No topo, a lista final de `depende_de` propostos em formato pronto para aplicar (id → [ids]) e a checagem de que ela não fecha ciclo nem aponta id inexistente (rodada com a biblioteca da tarefa 1). O usuário aprova ou corta itens; a gravação no `~/.rainforest/ideias.jsonl` real, por `ideias.cjs editar`, acontece depois do merge (o `ideias.cjs` instalado precisa aceitar o campo), fora do fluxo, com a frase de aprovação dele registrada no doc.

### 7. Documentar `depende_de` para quem planta [tipo: docs]
atende: D2, D4
arquivos: `commands/ideia.md`, `skills/rainforest-mind/references/regra-06.md`
depende de: 3, 4
paralela: nao
mutacao: n/a
  motivo: doc; a falsificação é a coerência com D2 e D4 e com o comportamento real das tarefas 2-4.
pronto quando: `commands/ideia.md` diz quando usar `depende_de` (só bloqueio; parentesco fica em `[[id]]` na prosa, D2), o formato (lista de ids) e o que acontece (listar marca, `--prontas` esconde, `iniciar`/`colher` avisam sem recusar, D4); a regra 6 (que manda plantar com gancho) cita o campo em uma linha — conferido lendo cada frase contra `scripts/ideias.cjs` das tarefas 2-4, e por `bash scripts/testa-teto-skills.sh` sem skill acima do teto.

### 8. Versão [tipo: configurar]
atende: fechar
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 7
paralela: nao
mutacao: n/a
  motivo: bump de versão, sem comportamento a inverter.
pronto quando: `.claude-plugin/plugin.json` e o selo da linha 7 do `README.md` dizem a versão seguinte à da `origin/main` no momento do bump (hoje `1.23.10` → `1.23.11`) — conferido por `MSYS_NO_PATHCONV=1 git show origin/main:.claude-plugin/plugin.json`. Feita como última tarefa do `executar` de código, para o `revisar` cobrir o diff inteiro.
