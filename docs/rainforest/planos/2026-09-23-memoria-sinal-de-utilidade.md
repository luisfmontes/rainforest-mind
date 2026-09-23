# Plano: Sinal de utilidade no ranking da memória

Design: docs/rainforest/design/2026-09-23-memoria-sinal-de-utilidade.md

Fato que molda o plano (levantado em 2026-09-23, antes de escrever): a abertura é
**somente-leitura** por decisão antiga (D16 do design de memória de 2026-08-17,
provada por `scripts/testa-memoria-somente-leitura.sh`, que compara o hash do banco
antes e depois de uma abertura). Então a abertura **não grava** o que serviu. O
bloco injetado fica inteiro no transcrito, como `attachment` com
`hookSpecificOutput.additionalContext` contendo `## Memória (corpus residentes)` —
a pontuação extrai as servidas de lá, que é o que de fato chegou à sessão (D8).
Hoje, na sessão conferida, chegaram 5 de 14.

## O que não pode quebrar
- A abertura continua somente-leitura: `bash scripts/testa-memoria-somente-leitura.sh` verde, e `git diff origin/main -- hooks/memoria-session-start.cjs hooks/lib/memoria-sessao.cjs` vazio (D2: a seleção não muda).
- Falha na pontuação não derruba reconciliar nem consolidar dentro do `manutencao`: registra no `manutencao.log` e segue.
- Nenhum texto de sessão entra no banco (D10): as tabelas novas só têm id, sessão, flag de servida, nota e data.
- `buscar` e a eviction não mudam (D3).

## Tarefas

### 1. Extrator do transcrito: servidas e texto da sessão [tipo: implementar]
atende: D3, D4, D8
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade.sh`, `scripts/memoria.cjs`
depende de: nenhuma
paralela: sim
Função pura `extrairSessao(caminhoTranscrito)` em `scripts/lib/utilidade.cjs`, devolvendo `{ servidas: [linha, ...], texto: string }`:
- `servidas`: as linhas `[AAAA-MM-DD (projeto)] ...` do bloco entre `## Memória (corpus residentes)` e a linha `mais:`, lidas do `attachment` de SessionStart (só o bloco de memória — D3).
- `texto`: os prompts do usuário (entradas `type: "user"` com conteúdo de texto, excluindo `tool_result`) mais as entradas (`input`) de cada `tool_use`; **a prosa do assistente e todo `attachment` ficam de fora** (D4). A linha que exclui a prosa do assistente é exatamente `if (entrada.type === 'assistant' && bloco.type === 'text') continue;`.
- Subcomando de inspeção `node scripts/memoria.cjs utilidade --extrair <transcrito>` imprime `{"servidas":N,"bytesTexto":M}`.
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (entrada.type === 'assistant' && bloco.type === 'text') continue;`
  para: `if (false) continue;`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "prosa do assistente que ecoa a injecao nao entra no texto"`
pronto quando: com um transcrito **real** desta máquina copiado para a caixa de teste (o mais recente de `~/.claude-personal/projects/C--Projetos-rainforest-mind/` que contenha `corpus residentes`), `utilidade --extrair` devolve `servidas` igual ao número de linhas `[` entre `## Memória (corpus residentes)` e `mais:` do attachment desse mesmo arquivo, contado de forma independente por `grep`/`node` na bateria — provado por `bash scripts/testa-utilidade.sh` imprimindo a linha `ok   servidas do transcrito real = <N> (contagem independente = <N>)`.

### 2. Pontuação: nota crua das servidas e do contrafactual [tipo: implementar]
atende: D1, D5, D6, D10
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/esquema-memoria.sql`, `scripts/testa-utilidade.sh`
depende de: 1
paralela: nao
- Tabelas novas no `criarSchema` de `scripts/memoria.cjs`: `uso_memoria(origem TEXT, ref_id INTEGER, sessao TEXT, servida INTEGER, nota REAL, pontuada_em TEXT, UNIQUE(origem, ref_id, sessao))` — `origem` é `observacao` ou `resumo` — e `uso_memoria_sessoes(sessao TEXT PRIMARY KEY, pontuada_em TEXT)`. Nenhuma coluna de texto além de ids e datas (D10).
- Cada linha servida é mapeada ao id por igualdade com a formatação que a abertura usa (`formatarObservacao` de `hooks/lib/memoria-sessao.cjs`), sobre observações e resumos do mesmo projeto e dia; linha sem par vai para um contador `servidas_sem_id` no log, nunca inventa id.
- Nota = fração dos termos **raros** da observação presentes no `texto` da sessão; termo raro = frequência de documento no `observacoes_fts` menor ou igual a `LIMIAR_DF`. A linha que filtra é exatamente `const raro = df <= LIMIAR_DF;`.
- Contrafactual (D6): as 14 que o FTS devolve com os termos do `texto` da sessão (bm25), excluídas as servidas, gravadas com `servida = 0`.
- `pontuarSessao(conexao, sessao, caminhoTranscrito)` é idempotente (`INSERT OR REPLACE`).
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const raro = df <= LIMIAR_DF;`
  para: `const raro = true;`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "termo comum a todo o corpus nao pontua"`
pronto quando: com uma **cópia** do `rainforest.db` real e o transcrito real da tarefa 1, `pontuarSessao` grava em `uso_memoria` exatamente as servidas extraídas (`servida = 1`) mais até 14 do contrafactual (`servida = 0`), com `nota` entre 0 e 1, e rodar duas vezes não muda a contagem — provado por `bash scripts/testa-utilidade.sh` imprimindo `ok   pontuacao real: <S> servidas + <C> contrafactual, idempotente` e `ok   nenhuma coluna de texto em uso_memoria` (lida por `PRAGMA table_info`).

### 3. Pontuação dentro da manutenção, sessões pendentes [tipo: implementar]
atende: D7
arquivos: `scripts/memoria.cjs`, `scripts/testa-utilidade.sh`
depende de: 2
paralela: nao
- `pontuarSessoesPendentes(conexao)`: toda sessão da `marca_dagua` sem linha em `uso_memoria_sessoes`, com transcrito ainda existente, é pontuada e marcada; transcrito ausente marca a sessão com nota nenhuma e segue. Chamada no `cmdManutencao` **depois** de consolidar, numa linha exatamente `pontuarSessoesPendentes(conexao);`, dentro de `try` próprio que registra `utilidade: falhou <motivo>` no `manutencao.log` sem abortar o resto.
- A manutenção roda uma vez por dia (trava diária do `memoria-manutencao-session-start.cjs`): o laço cobre todas as sessões acumuladas desde a última, não só a anterior.
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `pontuarSessoesPendentes(conexao);`
  para: `// pontuarSessoesPendentes(conexao);`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "manutencao pontua as sessoes pendentes da marca_dagua"`
pronto quando: com a cópia do banco real e duas sessões na `marca_dagua` apontando para transcritos reais copiados, `node scripts/memoria.cjs manutencao` deixa as duas em `uso_memoria_sessoes` e grava `utilidade: 2 sessao(oes) pontuada(s)` no `manutencao.log`; com o transcrito de uma delas apagado, a manutenção sai 0, reconciliar e consolidar continuam registrados no log — provado por `bash scripts/testa-utilidade.sh` imprimindo as duas linhas `ok` correspondentes.

### 4. Relatório com a régua D9 [tipo: implementar]
atende: D2, D9, D11
arquivos: `scripts/memoria.cjs`, `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade.sh`
depende de: 2
paralela: nao
- `node scripts/memoria.cjs utilidade --relatorio` lê só `uso_memoria` e `uso_memoria_sessoes` e imprime, para quem decide: número de sessões pontuadas e o período; em quantas uma não-servida pontuou acima da melhor servida; a fração contra 1/3; e uma linha final `régua D9: LIGA o ranking (X de Y sessões)` ou `régua D9: NÃO liga — recência basta (X de Y sessões)`. Lista as 5 não-servidas de maior nota com idade em dias, para mostrar **o que** a recência perdeu.
- A comparação é exatamente `const liga = sessoesComPerda * 3 >= total;` — "pelo menos 1/3" inclui o empate.
- Não altera seleção nenhuma (D2): o relatório só lê.
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const liga = sessoesComPerda * 3 >= total;`
  para: `const liga = sessoesComPerda * 3 > total;`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "exatamente 1/3 das sessoes liga a regua"`
pronto quando: com um banco de caixa de teste contendo 3 sessões, das quais exatamente 1 tem não-servida com nota acima da melhor servida, `utilidade --relatorio` termina com `régua D9: LIGA o ranking (1 de 3 sessões)`; com 1 de 4, termina com `régua D9: NÃO liga — recência basta (1 de 4 sessões)`; e a pessoa que lê vê, antes da linha da régua, as não-servidas que motivaram a decisão com a idade em dias — provado por `bash scripts/testa-utilidade.sh` imprimindo as três linhas `ok` (liga, não liga, lista presente e some quando não há perda).

### 5. Gancho de retorno em 2026-10-07 [tipo: configurar]
atende: D11
arquivos: `~/.rainforest/ideias.jsonl` (via `scripts/ideias.cjs plantar`, nunca à mão)
depende de: 3, 4
paralela: nao
mutacao: n/a
  motivo: não há comportamento de código a inverter — é um registro de dado do usuário escrito pela ferramenta que já tem trava e backup; a falsificação é o registro existir com a data e o comando certos.
pronto quando: com o plugin mergeado, `node scripts/ideias.cjs listar` mostra a ideia `rodar-relatorio-de-utilidade-da-memoria` com `gancho` contendo `2026-10-07` e `ao_colher` contendo `node scripts/memoria.cjs utilidade --relatorio` e a régua D9 por extenso — provado por `grep '"id":"rodar-relatorio-de-utilidade-da-memoria"' ~/.rainforest/ideias.jsonl` devolvendo uma linha com os três trechos, conferidos contra o texto de D9 do design.

**Emenda de 2026-09-23 — achados do `revisar` (reprovado, 3 achados + 1 da integração):** as tarefas 6-8 abaixo.

### 6. Servida substituída pela reconciliação ainda casa com o id [tipo: implementar]
atende: D8
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade.sh`
depende de: 4
paralela: nao
A reconciliação roda **antes** da pontuação na mesma passada e marca `substituida_por` em observação que pode ter sido servida numa sessão ainda pendente; D8 mede o que chegou à sessão, não o que sobreviveu. A busca de observações do dia em `acharAlvo` deixa de filtrar `substituida_por`, numa constante de uma linha exatamente `const SQL_OBS_DO_DIA = 'SELECT id, projeto, conteudo, criada_em FROM observacoes WHERE criada_em LIKE ?';`.
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const SQL_OBS_DO_DIA = 'SELECT id, projeto, conteudo, criada_em FROM observacoes WHERE criada_em LIKE ?';`
  para: `const SQL_OBS_DO_DIA = 'SELECT id, projeto, conteudo, criada_em FROM observacoes WHERE criada_em LIKE ? AND substituida_por IS NULL';`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "servida substituida pela reconciliacao ainda casa com o id"`
pronto quando: com a cópia do banco real e o transcrito real, marcando `substituida_por` numa das observações servidas antes de pontuar, `pontuarSessao` ainda grava essa observação com `servida = 1` e `servidasSemId` fica igual ao da pontuação sem a marca — provado por `bash scripts/testa-utilidade.sh` imprimindo `ok   servida substituida pela reconciliacao ainda casa com o id`.

### 7. Teto por passada e `servidas_sem_id` no log [tipo: implementar]
atende: D7, D8
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/testa-utilidade.sh`
depende de: 6
paralela: nao
- `pontuarSessoesPendentes` processa no máximo `TETO_PONTUAR = 30` sessões **com transcrito** por passada, as mais antigas primeiro (ordem por `processada_em`), seguindo o padrão do `TETO_RECONCILIAR`; o resto fica para a passada seguinte. Sessões sem transcrito continuam marcadas sem custo e não contam no teto. A linha que corta é exatamente `const lote = comTranscrito.slice(0, TETO_PONTUAR);`.
- Devolve a soma de `servidasSemId` das sessões pontuadas, e o `cmdManutencao` registra `utilidade: <N> sessao(oes) pontuada(s), <M> servida(s) sem id, <R> pendente(s) para a proxima` no `manutencao.log`.
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const lote = comTranscrito.slice(0, TETO_PONTUAR);`
  para: `const lote = comTranscrito;`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "passada respeita TETO_PONTUAR e deixa o resto pendente"`
pronto quando: com a cópia do banco real e `TETO_PONTUAR + 2` sessões com transcrito real copiado na `marca_dagua`, uma `manutencao` (com dublê de LLM) pontua exatamente `TETO_PONTUAR`, grava no `manutencao.log` a linha com `2 pendente(s) para a proxima` e um número de `servida(s) sem id`, e a segunda passada pontua as 2 restantes — provado por `bash scripts/testa-utilidade.sh` imprimindo `ok   passada respeita TETO_PONTUAR e deixa o resto pendente` e `ok   manutencao.log registra servidas sem id`.

### 8. Denominador da régua só conta sessão com servida [tipo: implementar]
atende: D9
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade.sh`
depende de: 7
paralela: nao
Sessão sem transcrito ou sem nenhuma servida não tem como "perder" nada para a recência; contá-la no total empurra a régua para "não liga" sem dado. O relatório passa a contar só sessões com ao menos uma linha `servida = 1` em `uso_memoria`, e mostra à parte quantas ficaram de fora e por quê. A linha é exatamente `const total = sessoesComServida.length;`.
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const total = sessoesComServida.length;`
  para: `const total = sessoes.length;`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "sessao sem servida nao entra no denominador da regua"`
pronto quando: com um banco de caixa de teste com 3 sessões com servida (1 com perda) e 3 sessões marcadas sem transcrito, `utilidade --relatorio` termina com `régua D9: LIGA o ranking (1 de 3 sessões)` e mostra antes a linha `3 sessão(ões) sem servida fora da conta` — provado por `bash scripts/testa-utilidade.sh` imprimindo `ok   sessao sem servida nao entra no denominador da regua`.

**Emenda 2 de 2026-09-23 — achados da segunda revisão (reprovado, 2 achados):** as tarefas 9-10 abaixo.

### 9. Servida sem id nunca vira não-servida no contrafactual [tipo: implementar]
atende: D6, D8
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/testa-utilidade.sh`
depende de: 8
paralela: nao
- `lerProjetoDoTranscrito` resolve o projeto como a abertura resolve: sobe do `cwd` do transcrito até o `.git` mais próximo (a mesma `encontrarGit` de `scripts/memoria.cjs`, exportada se ainda não for); se o diretório não existe mais (worktree removido), cai no `cwd` cru, como hoje.
- Defesa independente do rótulo: o contrafactual descarta todo candidato cujo texto formatado, **sem o prefixo `[AAAA-MM-DD (projeto)] `**, é igual ao de alguma linha servida da sessão — casada por id ou não. A comparação é exatamente `if (textosServidos.has(semPrefixo(linhaCandidato))) continue;`.
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (textosServidos.has(semPrefixo(linhaCandidato))) continue;`
  para: `if (false) continue;`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "servida sem id nao reaparece como nao-servida"`
pronto quando: com a cópia do banco real e o transcrito real com o `cwd` de todas as entradas trocado por uma subpasta do repositório (`<raiz>/scripts`), `pontuarSessao` casa as mesmas servidas por id que com o `cwd` original; e, forçando um rótulo de projeto que não casa, nenhuma das linhas servidas aparece em `uso_memoria` com `servida = 0` — provado por `bash scripts/testa-utilidade.sh` imprimindo `ok   cwd em subpasta casa as mesmas servidas` e `ok   servida sem id nao reaparece como nao-servida`.

### 10. Sessão que falha é marcada e não trava a fila [tipo: implementar]
atende: D7
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/testa-utilidade.sh`
depende de: 9
paralela: nao
Transcrito que faz `pontuarSessao` lançar não fica mais legível na passada seguinte; deixar sem marca, com a fila ordenada da mais antiga, garante que ele volta ao lote para sempre e, acumulado, trava a fila. No `catch`, a sessão é marcada em `uso_memoria_sessoes` e contada; o `manutencao.log` ganha `<F> falharam` na linha `utilidade:`. A marcação no `catch` é exatamente `marcarSessao(conexao, sessao, agora); falharam++;`.
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `marcarSessao(conexao, sessao, agora); falharam++;`
  para: `falharam++;`
  bateria: `bash scripts/testa-utilidade.sh`
  fixture: `testa-utilidade.sh, secao "sessao que falha e marcada e a fila anda"`
pronto quando: com a cópia do banco real e `TETO_PONTUAR` sessões mais antigas apontando para transcritos que fazem `pontuarSessao` lançar (JSON truncado no meio de uma linha de attachment de SessionStart) mais 2 sessões válidas mais novas, duas `manutencao` seguidas (com dublê de LLM) deixam as 2 válidas em `uso_memoria_sessoes` e o log registra `30 falharam` na primeira — provado por `bash scripts/testa-utilidade.sh` imprimindo `ok   sessao que falha e marcada e a fila anda`.
