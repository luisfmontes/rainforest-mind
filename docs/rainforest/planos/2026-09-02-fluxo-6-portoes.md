# Plano: Fluxo 6 — Portões (`portoes.cjs`)

Design: `docs/rainforest/design/fluxo-6-design-portoes.md` (seção final "Perguntas abertas — resolvidas em 2026-09-02" fecha layout e escopo — decisão fechada, não reaberta aqui).

## Achados que mudam o plano (leia antes das tarefas)

**1. O slug real (`2026-09-02-fluxo-6-portoes`) carrega prefixo de data, ao contrário dos irmãos `fluxo-9-portaria` e `fluxo-11-conselho` — CONFIRMADO.** `scripts/conferir-fluxo.cjs:475` deriva o caminho do plano estritamente de `--slug` (`docs/rainforest/planos/${slug}.md`) e recusa com exit 2 ("plano não existe") se não bater — isso dispara de verdade no fechamento de `revisar` (checagem de creep). Por isso este arquivo se chama `docs/rainforest/planos/2026-09-02-fluxo-6-portoes.md`.

**2. O design não usa o formato `## Decisões fechadas` / `- **D<n> — texto**` que `conferir-fluxo.cjs cobertura` exige — CONFIRMADO.** `docDe('design', slug)` (`scripts/estado.cjs:651`) procura `docs/rainforest/design/2026-09-02-fluxo-6-portoes.md`, que não existe — o arquivo real é `fluxo-6-design-portoes.md`. Como a checagem `cobertura` só dispara quando **os dois** caminhos derivados do slug existem (`scripts/estado.cjs:662-671`), ela nunca roda para este fluxo. Por isso as tarefas abaixo usam `atende:` citando **seções do design por nome**, não `D<n>`.

> **Nota da janela principal (2026-09-02), conferida no fonte:** este achado é maior do que "não se aplica aqui". `fluxo-9-portaria.json` grava `design.arquivo: "docs/rainforest/design/fluxo-9-design-portaria.md"` — o estado **sabe** onde o design mora — e `conferirFechamento` nunca lê esse campo, só `docDe(tipo, slug)`. Consequência: a `cobertura` (a trava que prova que toda decisão do design virou tarefa e que toda tarefa cita decisão real) **não rodou no fluxo 9** e não rodaria neste. **Tarefa 6 proposta, pendente de decisão do usuário** (2026-09-02).

**3. Versão: base já está em 0.80.0, consumida pelo fluxo 9.** O bump para **0.81.0** (comando novo) acontece no estágio `fechar`, fora das tarefas numeradas. Nenhuma tarefa abaixo mexe em `plugin.json`.

**4. Guarda de progresso no hook de Stop confirmada fora de escopo** (resolvida 2026-09-02, P2 do design). Nenhuma tarefa toca `hooks/`.

## O que não pode quebrar

- As três checagens existentes de `conferirFechamento` (`scripts/estado.cjs:656-693`) — `design`, `cobertura`, `creep` — continuam rodando sem alteração de comportamento para fluxo que não tem `portoes.md`.
- Fluxo sem `docs/rainforest/portoes/<slug>.md` fecha `plano` e `verificar` exatamente como hoje — os dois ganchos novos só agem quando o arquivo existe (mesma invariante já comentada em `scripts/estado.cjs:645-648`).
- `conferirFechamento` deixa de ser uma cadeia `if/else if` (que escolhe UMA checagem por estágio) e passa a rodar checagens **independentes em sequência** — necessário porque `plano` agora pode disparar `cobertura` **e** lint de portões no mesmo fechamento.
- Nenhum exemplo de `CHECK:` nos fixtures usa `grep`/`tail`/`tr`/`sed` — o próprio lint que este fluxo constrói reprovaria isso.

## Tarefas

### 1. Parser + `status` (nunca executa) [tipo: implementar]
atende: Formato do arquivo, Comandos (`status`)
arquivos: `scripts/portoes.cjs`, `scripts/testa-portoes-parser.sh`, `test/fixtures/portoes/**`
depende de: nenhuma
paralela: sim

Escopo: `scripts/portoes.cjs` nasce aqui, com cabeçalho de atribuição obrigatória ("reescrito a partir de unlazy (MIT), Leonxlnx"). Parser lê o arquivo (normaliza BOM e `\r\n`, igual a `lerMarkdown` de `conferir-fluxo.cjs`), reconhece por portão: id único (`P<n>:`), par `CHECK:`/`ESPERA:` (um sem o outro é erro de parse), `EVIDENCIA:` (`pendente` ou JSON inline `{"shell":...,"cwd":...,"exit":...,"match":...,"fingerprint":...}`), e `ABANDONA: P<n> <razão>` com razão não-vazia. Id duplicado, arquivo sem portão nenhum, `CHECK` sem `ESPERA` (ou vice-versa) e `ABANDONA` com razão vazia são erro de parse — exit 2 em qualquer modo, citando o motivo.

`status <arquivo>`: imprime por portão `P<n>: cumprido|pendente|abandonado|inconsistente` — `inconsistente` quando o checkbox (`[x]`) e o `EVIDENCIA:` discordam, tratado como não-cumprido. **Nunca invoca o `CHECK:` de portão nenhum.** Exit 0 em arquivo bem formado, exit 2 em malformado.

mutacao:
  arquivo: `scripts/portoes.cjs`
  de: `status` nunca invoca `child_process` para o `CHECK:` de nenhum portão
  para: `status` executa o `CHECK:` de cada portão antes de reportar
  bateria: `bash scripts/testa-portoes-parser.sh`
  fixture: `test/fixtures/portoes/portoes-sentinela.md` — um portão cujo `CHECK:` roda `node test/fixtures/portoes/scripts/sentinela.cjs <caminho>`, que só existe se o script rodar. A bateria apaga a sentinela antes e afirma que ela **não existe** depois. É a asserção mais importante do fluxo (P1 do esboço do design).

pronto quando: `bash scripts/testa-portoes-parser.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: (a) `portoes-ok.md` parseia e `status` sai 0; (b) `portoes-crlf.md` parseia igual a `portoes-ok.md`; (c) os três `portoes-malformado-*.md` saem exit 2, cada um citando o defeito certo; (d) `portoes-abandona.md` reporta `abandonado`, exit 0; (e) o caso da sentinela.

### 2. `lint` (a peça de maior valor) [tipo: implementar]
atende: Formato do arquivo (seção "O lint")
arquivos: `scripts/portoes.cjs`, `scripts/testa-portoes-lint.sh`, `test/fixtures/portoes/**`
depende de: 1
paralela: sim

Escopo: `lint <arquivo> [--strict]`. Nunca executa `CHECK:` nenhum. Regras de **erro** (reprovam sempre): `CHECK:` é comando de saída fixa isolado (`echo`, `printf`, `true`, `exit 0` como comando inteiro); `ESPERA:` vazio ou trivial (`ok`, `done`, `0`, case-insensitive); título do portão começa com verbo de atividade (`rodar`, `executar`, `testar`, `criar`, `gerar`, `validar`) em vez de resultado.

**Avisos** (viram erro só com `--strict`): `ESPERA:` contém termo de mensagem de erro (`erro`, `error`, `fail`, `exception`, `traceback`); `ESPERA:` é só um número isolado (`^\d+$`); `CHECK:` referencia `grep`, `tail` ou `tr` como token isolado.

Exit: 0 limpo, 1 achou erro (ou aviso com `--strict`), 2 malformado.

mutacao:
  arquivo: `scripts/portoes.cjs`
  de: comando de saída fixa isolado é ERRO de lint
  para: essa checagem é removida
  bateria: `bash scripts/testa-portoes-lint.sh`
  fixture: `test/fixtures/portoes/portoes-echo.md` — `CHECK: echo ok` / `ESPERA: ok`. Controle positivo do detector (P2 do esboço do design): com a mutação, este fixture passaria a dar lint limpo, que é o furo que o lint existe para fechar.

pronto quando: `bash scripts/testa-portoes-lint.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: `portoes-ok.md` limpo; `portoes-echo.md`, `portoes-titulo-atividade.md`, `portoes-espera-trivial.md` reprovando (exit 1) com o motivo certo; `portoes-espera-substring-erro.md`, `portoes-espera-numero-cru.md`, `portoes-grep.md` passando sem `--strict` (exit 0 com aviso) e reprovando com `--strict`; `portoes-sentinela.md` sob `lint` não cria a sentinela.

### 3. `rodar` (execução, evidência, abandono) [tipo: implementar]
atende: Comandos (`rodar`, `rodar --reverificar`), Portabilidade
arquivos: `scripts/portoes.cjs`, `scripts/testa-portoes-rodar.sh`, `test/fixtures/portoes/**`
depende de: 1
paralela: sim

Escopo: `rodar <arquivo> [--reverificar]`. Sem a flag, pula portão já `cumprido` (por `EVIDENCIA:` real, não pelo checkbox sozinho); com ela, re-executa todos. Por portão pendente e executável, roda o `CHECK:` via `spawn` — `cmd.exe /d /s /c` no Windows, `sh -c` no resto —, com timeout (default 120000 ms, overridável só para teste pela env `PORTOES_TIMEOUT_MS`, nunca por flag de produção). Cumprido = exit 0 **e** o `ESPERA:` aparece no stdout+stderr combinados, com `\r\n` normalizado antes da busca. Timeout mata o processo e conta como não-cumprido.

Ao cumprir, grava atomicamente (temp+rename) checkbox `[x]` e `EVIDENCIA:` com `shell`, `cwd`, `exit`, `match: true` e fingerprint sha256 truncado (12 hex) do output combinado — **nunca o output bruto**. Portão com `ABANDONA:` válido nunca é executado; a presença de qualquer `ABANDONA:` torna o veredito final **sempre** exit 1 com `DEVOLUCAO OBRIGATORIA`, mesmo que todo o resto esteja cumprido. Sem `ABANDONA`, exit 0 só quando todos terminam cumpridos; qualquer falha ou timeout é exit 1. Malformado continua exit 2.

mutacao:
  arquivo: `scripts/portoes.cjs`
  de: cumprido exige exit 0 **e** match do `ESPERA:` (os dois)
  para: cumprido exige só exit 0, ignora `ESPERA:`
  bateria: `bash scripts/testa-portoes-rodar.sh`
  fixture: um portão cujo `CHECK:` sai 0 mas nunca imprime o marcador declarado — com a mutação vira `[x]` cumprido; sem ela fica pendente e `rodar` sai 1.

pronto quando: `bash scripts/testa-portoes-rodar.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: `portoes-ok.md` fecha exit 0 com `EVIDENCIA:` de fingerprint (nunca output bruto); `portoes-falha.md` não marca `[x]`, exit 1; `portoes-abandona.md` não executa o `CHECK` abandonado e sai 1 com `DEVOLUCAO OBRIGATORIA` mesmo com os outros cumpridos; `portoes-crlf-saida.md` fecha exit 0; `portoes-timeout.md` com `PORTOES_TIMEOUT_MS` baixo mata `devagar.cjs` sem travar a bateria; `--reverificar` re-executa e regrava `EVIDENCIA:`; **e** `portoes-sentinela.md` sob `rodar` **cria** a sentinela — prova cruzada de que o não-executar das Tarefas 1 e 2 não é script quebrado.

### 4. Encaixe no pipeline — dois ganchos em `estado.cjs` [tipo: implementar]
atende: Encaixe no pipeline
arquivos: `scripts/estado.cjs`, `scripts/testa-portoes-gate.sh`
depende de: 2, 3
paralela: nao

Escopo: `conferirFechamento` (`scripts/estado.cjs:656-693`) deixa de ser `if/else if` e passa a rodar checagens independentes em sequência. Dois blocos novos, cada um só age se `docs/rainforest/portoes/<slug>.md` existir (caminho derivado do `--slug` já recebido, sem campo novo no estado — decisão P1 fechada do design):
- `estagio === 'plano'`: roda `portoes.cjs lint <portoesPath>`, recusa se exit ≠ 0. Roda **além** de `cobertura`, não em vez dela.
- `estagio === 'verificar'`: roda `portoes.cjs rodar <portoesPath>`, recusa se exit ≠ 0. Gancho novo — hoje `verificar` não tem checagem nenhuma em `conferirFechamento`.

mutacao:
  arquivo: `scripts/estado.cjs`
  de: gate do `verificar` roda `portoes.cjs rodar` e recusa se exit ≠ 0, quando `portoes.md` existe
  para: gate do `verificar` não roda nada quando `portoes.md` existe
  bateria: `bash scripts/testa-portoes-gate.sh`
  fixture: sandbox `RFM_ESTADO_ROOT` (padrão de `scripts/testa-conferir-fluxo.sh`) com `portoes.md` de `CHECK` proposital-falho; `marcar --estagio verificar --status ok` deve recusar (exit 2) — com a mutação, fecharia `ok` sem o `CHECK` nunca ter passado.

pronto quando: `bash scripts/testa-portoes-gate.sh` devolve `== resultado: N ok, 0 falha(s) ==` e exit 0, cobrindo: (a) fluxo sem `portoes.md` fecha `plano ok` e `verificar ok` igual a hoje; (b) lint-erro → `marcar plano ok` recusa (exit 2) citando a saída do lint; (c) lint-limpo → fecha; (d) `CHECK` falho → `marcar verificar ok` recusa; (e) todos os `CHECK`s passando → fecha; (f) o caso da mutação.

### 5. Documentação [tipo: docs]
atende: Atribuição obrigatória, Créditos
arquivos: `README.md`
depende de: 4
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação — sem comportamento de código para mutar.

Conteúdo: a tabela "Travas mecânicas" ganha uma linha para `scripts/portoes.cjs` (mesma forma da linha de `conferir-fluxo.cjs`, `README.md:343`: o que audita, quando dispara, exit codes), e "Créditos" (`README.md:721-729`) ganha o bullet de atribuição a unlazy/Leonxlnx (MIT), no formato dos bullets existentes.

pronto quando: o trecho novo responde por leitura semântica o que `portoes.cjs` audita (oráculo executável, não prosa colada), os dois pontos de disparo (`plano`/lint, `verificar`/rodar) e que é opt-in por fluxo; e o bullet de Créditos nomeia unlazy e Leonxlnx com a licença MIT.

## Divergências do design

- **Caminho do plano** (achado 1): `docs/rainforest/planos/2026-09-02-fluxo-6-portoes.md` — exigência mecânica de `conferir-fluxo.cjs creep`, não estilo.
- **`atende:` não usa `D<n>`** (achado 2): o design deste fluxo não tem seção `## Decisões fechadas` numerada. A Tarefa 6 proposta mudaria isso; **pendente de decisão do usuário**.
- **Sem tarefa de bump de versão** (achado 3): o bump para 0.81.0 é passo do `fechar`.
