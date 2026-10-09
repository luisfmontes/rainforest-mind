# Plano: Régua D7 da memória por assunto sem as distorções (#436)

Design: docs/rainforest/design/2026-10-09-assunto-regua.md
Base: bb300b30 (branch `fluxo/assunto-regua`, worktree limpo). Versão alvo: 1.54.0 (MINOR: entra o subcomando `utilidade --repontuar`). Os dois `plugin.json` estão em 1.53.1 no HEAD. Não fiz `git fetch`, então a tarefa 11 confere a versão em `origin/main` antes de subir o número, como o plano do projeto-canônico fez.

Rótulos: CONFIRMADO = li o arquivo ou rodei o comando. INFERIDO = dedução minha, dita como tal. LACUNA = não sei, e digo o que falta.

## Achados que mudam o desenho

- **A1. Propagar o `SQLITE_BUSY` do `ALTER` (D6) não basta.** `cmdManutencao` (`scripts/memoria.cjs:2254-2262`) chama `garantirEsquema()` num `try/catch`, registra `esquema: falhou` e **segue** para a etapa `utilidade:`.
  - Se o `ALTER` lançar BUSY, a etapa seguinte roda contra um banco sem a coluna `canal`.
  - O `INSERT` falha com `table uso_memoria has no column named canal`. Isso é `ERR_SQLITE_ERROR` mas não casa `ehBancoOcupado` (`utilidade.cjs:669-671`, que exige "database is (locked|busy)"). A sessão vai para `marcarSessao` e sai da fila para sempre (`utilidade.cjs:731-736`), que é o defeito que o D6 quer evitar.
  - CONFIRMADO por experimento em pasta temporária: com `uso_memoria` legado (sem `canal`) e outra conexão segurando `BEGIN IMMEDIATE`, `criarSchema` da base **retorna sem lançar**, a coluna não nasce, e o `INSERT` seguinte falha com a mensagem acima.
  - Decisão técnica assumida: o D6 vira duas tarefas.
    - A tarefa 4 faz o `criarSchema` engolir só "duplicate column".
    - A tarefa 8 faz `pontuarSessoesPendentes` conferir o esquema na entrada. Se faltar a coluna `canal` ou uma das 3 colunas de buscas, devolve tudo como `adiadas` e não marca nenhuma sessão.
  - Chamadores de `criarSchema` que passam a ver o throw:
    - `hooks/memoria-marca.cjs:166` e `:250`, já em `try` com `process.exit(0)`.
    - `scripts/importar-claude-mem.cjs:203`.
    - `scripts/memoria.cjs:863` (`garantirEsquema`) e `:1269` (`cmdReindexar`), sem `catch` próprio; a CLI sai 1.
  - O `ALTER` só roda quando a coluna falta (`memoria.cjs:421` e `:433`, atrás de `PRAGMA table_info`). No banco real a coluna `canal` já existe (CONFIRMADO: a consulta por `canal` numa cópia funcionou). O throw novo só aparece em banco ainda não migrado, uma vez.
  - Fora do D6, **não mexer**: a migração 1 (`memoria.cjs:446-458`, `offset_processado`) e a migração 4 (`:478-488`) têm o mesmo `catch` vazio. O design limita o D6 às linhas 419-438. O executor registra isso no relato para virar Issue.

- **A2. D2 no canal `subagente`: o briefing que chega ao filho já contém o bloco injetado.**
  - `toolUseResult.prompt` do pai e a primeira linha `user` do filho (`filho.briefing`) vêm com `## Memória do assunto` e as linhas de memória anexadas ao fim. O hook faz `[original.prompt, ...blocos].join('\n\n')`, com o glossário antes da memória (`hooks/memoria-assunto-agente.cjs:66`).
  - Descontar o briefing inteiro tiraria da conta todo termo raro de toda servida do subagente. O canal ficaria 100% nulo (D3) por culpa do instrumento.
  - Decisão técnica: o texto a descontar é o briefing **cortado no primeiro cabeçalho `## Glossário do repo` ou `## Memória do assunto`**. Uma função única serve aos dois caminhos (pai e filho).
  - Limite aceito (INFERIDO): se o pedido original citar esses cabeçalhos no meio do texto, o corte vem cedo demais e o desconto fica menor. Isso erra para o lado de medir mais, não de menos.
  - No canal `pedido` não há esse problema. O attachment da injeção é uma entrada separada (`hook_additional_context`), então `partesTexto[indiceInjecao]` é só a linha do usuário.

- **A3. D3 vaza para o SQL de `gerarRelatorio` e quebra casos existentes.**
  - A nota nula entraria no denominador em três lugares:
    - `temServida` (`utilidade.cjs:787-789`, `servida = 1` sem filtro de nota);
    - `COUNT(DISTINCT sessao) y` por canal (`:862-868`);
    - `MIN(pontuada_em)` da janela (`:893-895`).
  - `MAX(nota)` e `nota >= ?` já ignoram NULL.
  - Decisão técnica: o início da janela (`MIN(pontuada_em)`) **continua contando servida nula**. O canal estava vivo desde aquela sessão, e se a janela andasse com o instrumento, a repontuagem mudaria o denominador.
  - Em `scripts/testa-utilidade-canais.sh` o caso "nota do canal pedido sobe com pedido posterior que contem os termos raros" **quebra por leitura (INFERIDO)**. Sob D2, os `zzraropedido*` estão no pedido e saem. Sobra o termo `pedido` (df 1), que o `prompt2` não contém, então a nota é 0, não > 0.
    - A tarefa 5 reescreve esse caso e lista no relato qualquer outro que a bateria acusar. Não prometo "22 ok sem mexer".
  - `calcularNota` tem chamadores de 3 argumentos que não podem mudar: `scripts/calibrar-limiar-assunto.cjs:159,163` e `scripts/testa-utilidade.sh:261`. O 4º argumento é opcional.

- **A4. D1 medido nos transcritos reais** (varredura somente-leitura das duas contas, só contagens).
  - 45 comandos Bash únicos contêm o texto `memoria.cjs buscar`. 24 são chamada pela regra do D1. 21 não são: 12 só dentro de heredoc, o resto são `grep`, `gh pr`, `node -e` e `echo`.
  - 0 chamadas via PowerShell e 0 here-strings do PowerShell. A regra cobre heredoc de Bash. PowerShell segue sem tratamento de here-string, e não há caso medido que justifique mais.
  - O design diz "3 de 32". Os corpora diferem (o meu inclui as duas contas) e a direção é a mesma. A janela que a régua lê vai mudar: o número de "buscas ativas" cai.

- **A5. D4 exige que `memoria-session-start.cjs` passe a LER o stdin, e hoje não lê.**
  - CONFIRMADO: `grep` só acha `process.argv` (`hooks/memoria-session-start.cjs:342`). O `session_id` vem no payload do `SessionStart`.
  - Havendo chamadores sem stdin fechado, como o runner do mod (`hooks/testa-mod-abertura.cjs:169,279`), ler fd 0 de forma síncrona pode travar a abertura. Decisão técnica:
    - O hook **imprime a saída exatamente como hoje, primeiro**.
    - Depois lê o stdin de forma assíncrona, com teto de 1 s (timer com `unref`) e pulando se for TTY.
    - Grava o arquivo só se houver `session_id` válido (`/^[A-Za-z0-9_-]+$/`, a mesma validação do hook do pedido).
    - Nada disso altera o stdout nem o exit code.
  - `montarMemoria` devolve só a string (`memoria-sessao.cjs:300-357`), então o hook não sabe o que entrou. Decisão: nova função `montarMemoriaComIds(o)` devolve `{ texto, ids }`; `montarMemoria` vira `montarMemoriaComIds(o).texto`. Os `ids` saem do **texto final** (conta as linhas `[AAAA-MM-DD ...]` do bloco e pega esse prefixo de `observacoes`), então valem para os três regimes (inteiro, escada 200/160/120, corte por observação) sem mexer em `travarOrcamentoMemoria`. Só id inteiro de observação vai ao arquivo; resumos têm id `resumo_<n>`, e `lerIds` (`memoria-assunto-prompt.cjs:26-30`) já filtra `Number.isInteger`.
  - **Restrição:** `scripts/testa-memoria-somente-leitura.sh` (seção 4) muta uma cópia do hook apagando o bloco literal `// Se o banco não existe, array vazio é o resultado esperado. ... return []; }` de `hooks/memoria-session-start.cjs`. A tarefa 2 não pode alterar esse texto.
  - LACUNA: não sei se o runner do `--destino mod` entrega stdin com `session_id`. Sem ele o plano degrada para "não grava", igual a hoje.

- **A6. D5: `montarBlocoAssunto` devolve só a string** (`hooks/lib/memoria-assunto.cjs:73-84`). Mesma solução: nova `montarBlocoAssuntoComIds(linhas)` devolve `{ bloco, ids }`, e `montarBlocoAssunto` fica como wrapper.
  - A bateria `hooks/testa-memoria-assunto.cjs` (14 casos) continua intacta.
  - Em `hooks/testa-memoria-assunto-prompt.cjs`, nenhum caso afirma conteúdo de arquivo que dependa do corte. Os 3 alvos têm linhas curtas e cabem em 1.500 B. Os casos devem seguir verdes.

- **A7. D8 tem uma armadilha que o design não nomeia: `pontuada_em`.**
  - `pontuarSessao` grava `pontuada_em = agora` (`utilidade.cjs:584`). Se a repontuagem regravar com a hora de hoje, a janela da régua D7 (`pontuada_em >= MIN(pontuada_em)` do canal novo, `:893-900`) colapsa para o instante da repontuagem. As sessões repontuadas antes da primeira com servida de pedido ou subagente saem da janela, e as sem transcrito (que mantêm a data velha) também. O denominador passa a depender da ordem do laço.
  - Decisão técnica: `--repontuar` **preserva o `pontuada_em` original de cada sessão** (o de `uso_memoria_sessoes`).
  - `TETO_PONTUAR = 30` (`:647`) e a lista `pendentes` com sessões duplicadas pelo `marca_dagua` (CONFIRMADO: 9 sessões têm mais de uma linha) tornam `pontuarSessoesPendentes` inadequado. O `--repontuar` tem laço próprio: parte de `uso_memoria_sessoes` (uma linha por sessão), acha o transcrito em `marca_dagua` (primeiro `arquivo` que existe) e refaz cada sessão numa transação só. O `DELETE` das linhas velhas entra **dentro da mesma transação** da regravação, então erro no meio mantém a nota antiga.
  - Medido numa cópia do banco real em 2026-10-09 (só contagens): 591 sessões pontuadas, **56** desde 2026-10-08, **46** com transcrito e **10** sem. Em `uso_memoria`, 0 linhas com `nota` nula hoje.

- **A8. Mutação em dois blocos iguais é recusada.** O conserto do D6 aparece em duas migrações (0 e 0b). Com a mesma linha duas vezes, a `cobertura` recusa ("`de:` casa mais de uma vez"). Decisão: um helper único `engolirSoColunaDuplicada(e)` com a linha de `throw`, usado nos dois `catch`. O mesmo vale para o filtro SQL do relatório (constante única, tarefa 7).

- **A9. Passos fora do repositório pertencem à janela principal.**
  - O `ao_colher` da ideia mora em `~/.rainforest/ideias.jsonl` (dado do usuário, não versionado). Vira a tarefa 12, só depois do merge e da atualização do plugin.
  - O comentário na Issue #436 com a nota do D7, e o fechamento dela, são do `fechar`. Subagente não escreve no GitHub (hook `gate-subagente-sem-gh.cjs`).

- **A10. Leitura literal do D3 para memória sem nenhum termo raro (INFERIDO).** "Memória sem termo raro fora do pedido sai da conta" inclui a memória que não tem termo raro algum. Hoje ela pontua 0 (`calcularNota`, `utilidade.cjs:436`).
  - No canal `pedido` ou `subagente` ela passa a ter nota nula. Na abertura continua 0, porque a abertura não muda.
  - É a leitura mais fiel do texto e do porquê do D3 (não há como medir uso). Mas muda o número de uma classe de servidas. O relato do executor traz a contagem dessa classe separada, e o ponto está em "Decisões do usuário".

## Decisões do usuário

As quatro decisões de produto do design (Q1 a Q4) estão fechadas. Os dois pontos abaixo são lacunas de leitura. O plano segue a opção recomendada, que é reversível numa linha, e para ali.

- **U1. Sessão da janela sem transcrito (10 de 56 na cópia de hoje).** O design diz que "fica de fora e aparece contada".
  - Opção A (recomendada, é o texto do design): fica **sem tocar**, com a nota antiga, e a saída do `--repontuar` conta quantas são.
  - Opção B: marcar essas sessões para saírem do relatório. Tiraria do denominador com base num critério que nada mediu (a falta do arquivo).
  - Decidido A pelo usuário em 2026-10-09. Essas sessões podem carregar as distorções, e a saída diz isso.
- **U2. Memória sem nenhum termo raro (A10).** A (recomendada): nota nula nos canais `pedido`/`subagente`. B: manter 0. Decidido A pelo usuário em 2026-10-09; conta essa classe à parte no relato.

## Fatos apurados

- HEAD bb300b30. `.claude-plugin/plugin.json` em 1.53.1 (CONFIRMADO). Badge do README: `README.md:7`, URL `vers%C3%A3o-1.53.1`, alt `versão 1.53.1`.
- `scripts/lib/utilidade.cjs`:
  - `contarBuscasArquivo` `:511-534`. A linha defeituosa é `:530`, `b.input.command.includes(PADRAO_BUSCA)`.
  - `extrairSessao` `:141-278`. O canal `pedido` usa `textoPosterior = partesTexto.slice(indiceInjecao + 1)` (`:249`). O canal `subagente` usa `filho.textoTools` (`:259`, `:273`).
  - `calcularNota` `:416-438`. `pontuarSessao` `:583-638`. `gravarUso` `:550-557`. `ehBancoOcupado` `:669`.
  - `pontuarSessoesPendentes` `:691-741`. `gerarRelatorio` `:778-925`.
- `uso_memoria.nota` é `REAL` sem `NOT NULL` (`scripts/esquema-memoria.sql:101-109`), então a nota nula não exige migração. Também não há outro leitor de `uso_memoria.nota` além de `utilidade.cjs` e `calibrar-limiar-assunto.cjs`.
- `hooks/memoria-assunto-prompt.cjs`: `lerServidasDoInicio` `:56-79`. `memoriaDoPedido` `:102-136`. A gravação em D5 é a linha `:130` (`for (const a of achadas) servidos.add(a.id);`). Com o arquivo já existente, o hook usa `lerIds` e não toca o transcrito (`:111-113`).
- `hooks/lib/memoria-assunto.cjs:60-64` é o desempate do peso do projeto atual (insumo do D7).
- `scripts/memoria.cjs`:
  - `criarSchema` `:349`; Migração 0 `:417-426`; Migração 0b `:428-438`.
  - `fazerBackupDoBanco` `:1078` (VACUUM, checkpoint TRUNCATE, rotação). `cmdUtilidade` `:2147-2186`. `cmdManutencao` `:2224-2305`. `module.exports` `:2360`.
- Fixtures reais do harness já no repo (reusar, não inventar formato): `scripts/fixtures/memoria-assunto/prompt-submit.jsonl` (attachment `hook_additional_context`, `hookEvent: UserPromptSubmit`), `agente-pai.jsonl` (linha 0 = `assistant` com `message.content[]` de `tool_use`; linha 2 = `user` com `toolUseResult.prompt` e `agentId`), `agente-filho.jsonl`, e `scripts/fixtures/utilidade/transcrito-sessao.jsonl` (attachment `SessionStart` com `stdout` JSON).
- Payload de `SessionStart` usado pela bateria existente: `{"hook_event_name":"SessionStart","source":"startup","session_id":"<uuid>","cwd":"...","transcript_path":"..."}` (`hooks/testa-memoria-session-start.sh`, seção 20.a).
- Placares na base bb300b30 (rodados por mim, todos `0 falha(s)`):
  - `scripts/testa-utilidade-canais.sh` 22
  - `scripts/testa-utilidade.sh` 19
  - `hooks/testa-memoria-session-start.sh` **85**
  - `hooks/testa-memoria-assunto-prompt.cjs` 14
  - `hooks/testa-memoria-assunto.cjs` 14
  - `hooks/testa-memoria-escada.cjs` 22
  - `scripts/testa-versao.sh` `ok: 5 falhou: 0`
  - `scripts/testa-memoria.sh` 41
  - `hooks/testa-memoria-recuperacao.sh` 14
  - `scripts/testa-memoria-somente-leitura.sh` 29
  - `scripts/testa-migrar-projeto-canonico.cjs` 16
  - `scripts/testa-migrar-emenda.cjs` 7
  - `scripts/testa-utilidade-canonico.cjs` 4
  - `hooks/testa-mod-abertura.cjs` 29, 0 skipped
  - `node scripts/conferir-categoria.cjs`: "CONFERIDO", 57 peças.
- Repositório público: nada de nome de projeto, cliente ou pessoa reais em fixture, relato ou documento. Usar `alfa`, `beta`, `omega`; no ensaio, só contagens.

## O que não pode quebrar

- **A abertura não muda de conteúdo.** Para a mesma caixa, o `additionalContext` impresso por `hooks/memoria-session-start.cjs` é byte a byte o de antes. Com stdin vazio, `{}` ou `session_id` inválido, o hook não grava arquivo nenhum. Falha ao gravar nunca altera stdout nem exit code (sempre 0).
- **O texto da guarda de `hooks/memoria-session-start.cjs` fica intacto** (A5). `bash scripts/testa-memoria-somente-leitura.sh` segue em 29.
- **Os hooks do assunto continuam calados em falha** (stdout vazio, exit 0), com `session_id` validado antes de virar nome de arquivo.
- **`hooks/memoria-marca.cjs` continua saindo 0 e calado** quando `criarSchema` lança BUSY, sem `spawn`/`exec`.
- **Nenhuma linha de `uso_memoria` ou `uso_memoria_sessoes` fora da janela do `--repontuar` muda.** Sessão que falha ou é adiada no meio mantém as linhas antigas (o `DELETE` está na mesma transação).
- **`--repontuar` é idempotente.** Duas execuções seguidas sobre o mesmo banco deixam `uso_memoria` e `uso_memoria_sessoes` iguais, com o `pontuada_em` original.
- **A régua não muda**: limiares 40% e 1/3 e base 27% / 171 de 255 (`REGUA_D7`, `BASE_D7`, `NOTA_UTIL`) ficam como estão.
- **`calcularNota` de 3 argumentos devolve o mesmo número de antes** (chamadores: `calibrar-limiar-assunto.cjs`, `testa-utilidade.sh:261`).
- **O banco real nunca é tocado.** Toda bateria usa `mkdtemp` e `RFM_ROOT` explícito. O ensaio usa **cópia**. Tamanho e mtime de `~/.rainforest/rainforest.db` são iguais antes e depois.
- **Baterias sem regressão de placar**, salvo as que a tarefa 5 reescreve de propósito: as da lista em "Fatos".
- **`node scripts/conferir-categoria.cjs`** segue "CONFERIDO". Arquivo novo em `hooks/` ou em `scripts/` (não `testa-*`) leva `@categoria` válido.

## Tarefas

### 1. Busca ativa é instrução, não texto [tipo: implementar]
atende: D1
arquivos: `scripts/lib/busca-ativa.cjs`, `scripts/lib/utilidade.cjs`, `scripts/testa-busca-ativa.cjs`
depende de: nenhuma
paralela: sim
prova: `node scripts/testa-busca-ativa.cjs`
mutacao:
  arquivo: `scripts/lib/busca-ativa.cjs`
  de: `return instrucoesDe(comando).some((i) => CHAMADA_BUSCA.test(i));`
  para: `return String(comando).includes('memoria.cjs buscar');`
  bateria: `node scripts/testa-busca-ativa.cjs`
  fixture: `testa-busca-ativa.cjs, caso "git commit com heredoc que cita o comando nao conta como busca"`
pronto quando: com transcritos montados a partir da linha `assistant` REAL de `scripts/fixtures/memoria-assunto/agente-pai.jsonl` (linha 0, `message.content[]` com `tool_use`), trocando só `name` e `input.command`, `contarBuscas` devolve a contagem por instrução, e o que a sessão grava acompanha — provado por `node scripts/testa-busca-ativa.cjs` imprimindo `ok` por caso e `0 falha(s)`.
  - O transcrito principal `<caixa>/s1.jsonl` leva 12 `tool_use` (11 Bash e 1 PowerShell).
  - **Contam (6):**
    1. `node scripts/memoria.cjs buscar --texto alfa`
    2. `cd /c/repo && node scripts/memoria.cjs buscar --projeto alfa --json`
    3. `RFM_ROOT=/tmp/caixa FOO=1 node ../scripts/memoria.cjs buscar --texto beta`
    4. `git status; node scripts/memoria.cjs buscar --texto gama | head -5`
    5. duas linhas: `ls` e, na seguinte, `node scripts/memoria.cjs buscar --texto delta`
    6. (PowerShell) `Set-Location C:\repo; node scripts\memoria.cjs buscar --texto eps`
  - **Não contam (6):**
    1. `git commit -F - <<'EOF'` + corpo com a linha `node scripts/memoria.cjs buscar --texto zeta` + `EOF` (o defeito real)
    2. `grep -rn "memoria.cjs buscar" docs/`
    3. `echo "rode node scripts/memoria.cjs buscar"`
    4. `node scripts/memoria.cjs backup`
    5. `cat <<EOF > /tmp/x.md` com a linha da chamada no corpo (delimitador sem aspas)
    6. `cat <<-'FIM'` com a chamada no corpo e `FIM` indentado por tab
  - Um subagente `<caixa>/s1/subagents/agent-a1.jsonl` leva 2 chamadas e 1 heredoc. Uma entrada `user` que cita o texto não conta.
  - **Efeito:** `contarBuscas('<caixa>/s1.jsonl')` devolve `{ buscasPrincipal: 6, buscasSubagente: 2, subagentes: 1 }`. Na base devolve `{ buscasPrincipal: 11, buscasSubagente: 3, subagentes: 1 }`.
  - **Efeito gravado:** um segundo transcrito `s2.jsonl` com só o heredoc, passando por `pontuarSessao` real, grava `uso_memoria_sessoes.buscas_principal = 0` (na base, 1).
  - **Sem regressão:** `bash scripts/testa-utilidade-canais.sh` continua em `22 ok, 0 falha(s)`. Seus casos de buscas (`cd x && node ... buscar`, Agent/Write/Edit citando, PowerShell executando) já são compatíveis.
  - Forma do alvo de mutação (código a nascer): `busca-ativa.cjs` exporta `ehBuscaAtiva(comando)`, função pura sem I/O, cuja última linha é um único `return` na forma do `de:`.
    - Primeiro `instrucoesDe` tira o corpo dos heredocs (`<<`, `<<-`, delimitador com ou sem aspas, `-` indentado) e separa por `&&`, `||`, `;`, `|` e quebra de linha.
    - Depois `CHAMADA_BUSCA` casa o início da instrução, com atribuições de ambiente opcionais: `node <caminho sem espaço>memoria.cjs buscar`.
    - `contarBuscasArquivo` passa a chamar `ehBuscaAtiva(b.input.command)` onde hoje há o `includes`.
  - Nenhum caso de teste lê o texto do fonte.
  - Fora desta regra, e dito como limite: caminho com aspas (`node "x/memoria.cjs" buscar`), prefixos `time`/`timeout`, e here-string do PowerShell (0 ocorrências medidas).

### 2. A abertura grava os ids que serviu [tipo: implementar]
atende: D4
arquivos: `hooks/lib/memoria-sessao.cjs`, `hooks/memoria-session-start.cjs`, `hooks/testa-abertura-grava-servidas.cjs`, `hooks/testa-memoria-session-start.sh`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-abertura-grava-servidas.cjs`
mutacao:
  arquivo: `hooks/lib/memoria-sessao.cjs`
  de: `return observacoes.slice(0, linhasNoBloco(texto)).map((o) => o.id).filter(Number.isInteger);`
  para: `return observacoes.map((o) => o.id).filter(Number.isInteger);`
  bateria: `node hooks/testa-abertura-grava-servidas.cjs`
  fixture: `testa-abertura-grava-servidas.cjs, caso "so os ids das linhas que couberam no bloco entram no arquivo"`
pronto quando: com o payload real de `SessionStart` no stdin do hook como processo (`{"hook_event_name":"SessionStart","source":"startup","session_id":"<uuid>","cwd":"<projeto>","transcript_path":"<caixa>/t.jsonl"}`, `RFM_ROOT=<caixa>`, `CLAUDE_PROJECT_DIR=<projeto>`), o arquivo de dedupe do canal do pedido já nasce com o que a abertura serviu — provado por `node hooks/testa-abertura-grava-servidas.cjs` com `0 falha(s)`.
  - **Caixa:** criada pelo `criarSchema` real, com 30 observações do projeto atual e 1 resumo. Cada observação tem um marcador único no título (`marcador-<id>`). Subtítulos de ~250 caracteres acentuados, para que a escada desça ao degrau de 120 **e** ainda corte linhas inteiras. A bateria confere isso pelo próprio bloco impresso: contém "textos encurtados a 120 caracteres" e "não couberam no teto".
  - **Arquivo de ids:** `<caixa>/memoria-assunto/<uuid>.json` existe e é um array de inteiros. O conjunto de ids é exatamente o dos marcadores presentes no `additionalContext` impresso. É menor que 30, não contém `resumo_*`, e não contém os ids das linhas cortadas pelo teto.
  - **Ponta a ponta com o outro hook:** o `additionalContext` real da abertura é colado num transcrito como o attachment `SessionStart` (formato de `transcrito-sessao.jsonl`). Em seguida o hook REAL `hooks/memoria-assunto-prompt.cjs` recebe o payload de `UserPromptSubmit` com o mesmo `session_id` e um pedido que casa forte com a memória mais recente (a que a escada encurtou, e que o `acharAlvo` não reconhece). O bloco devolvido **não repete** essa memória. Na base ela é re-injetada, porque a semeadura pelo transcrito não a acha.
  - **Retomada:** com o arquivo já contendo um id extra (`999999`, como se viesse do canal do pedido), uma segunda execução da abertura com o mesmo `session_id` e `"source":"resume"` **soma** os ids: o extra continua lá, sem duplicata.
  - **Falhas e portas fechadas (cada uma com stdout idêntico ao da execução sem `session_id` e exit 0):**
    - `<raiz>/memoria-assunto` existe como **arquivo** (a gravação falha).
    - stdin vazio.
    - `{}`.
    - `session_id: "../fuga"`.
    - Nos três últimos não aparece arquivo novo na caixa.
  - **Regimes de `montarMemoriaComIds`:** nos três (bloco inteiro, escada, corte por observação), `.texto` é idêntico ao de `montarMemoria` (formas de `hooks/testa-memoria-escada.cjs`), e `ids` bate com as linhas do texto.
  - **Sem regressão:**
    - `bash hooks/testa-memoria-session-start.sh` em `85 ok, 0 falha(s)`; os casos que rodam o hook com `session_id` e `RFM_ROOT` passam a criar `<raiz>/memoria-assunto/`, e o executor ajusta o que afirmar a raiz inteira.
    - `node hooks/testa-memoria-escada.cjs` em 22.
    - `bash scripts/testa-memoria-somente-leitura.sh` em 29.
    - `bash hooks/testa-abertura-mod-memoria.sh` e `node hooks/testa-mod-abertura.cjs` (29, 0 skipped).
  - Forma do alvo de mutação (código a nascer): `idsQueEntraram(observacoes, texto)` termina na linha do `de:`. `linhasNoBloco(texto)` conta as linhas que começam por `[` entre o cabeçalho `## Memória (corpus residentes)` e `mais:`. A lib não importa `utilidade.cjs` (evita o circular). No hook, a leitura do stdin é um bloco assíncrono depois do `console.log`, com timeout de 1 s. Nenhum caso lê o texto do fonte.

### 3. Só vai para os já servidos o que entrou no bloco [tipo: implementar]
atende: D5
arquivos: `hooks/lib/memoria-assunto.cjs`, `hooks/memoria-assunto-prompt.cjs`, `hooks/testa-prompt-so-o-que-entrou.cjs`, `hooks/testa-memoria-assunto-prompt.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-prompt-so-o-que-entrou.cjs`
mutacao:
  arquivo: `hooks/memoria-assunto-prompt.cjs`
  de: `for (const id of ids) servidos.add(id);`
  para: `for (const a of achadas) servidos.add(a.id);`
  bateria: `node hooks/testa-prompt-so-o-que-entrou.cjs`
  fixture: `testa-prompt-so-o-que-entrou.cjs, caso "memoria cortada pelo teto de 1500 B volta no pedido seguinte da sessao"`
pronto quando: com o payload real de `UserPromptSubmit` no stdin do hook como processo (`prompt`, `session_id`, `cwd`, `transcript_path`, `hook_event_name`, como em `hooks/testa-memoria-assunto-prompt.cjs`), a memória que o teto de 1.500 B cortou não é marcada como servida — provado por `node hooks/testa-prompt-so-o-que-entrou.cjs` com `0 falha(s)`.
  - **Caixa:** `criarSchema` real, com 3 observações do assunto cujas linhas formatadas (300 caracteres acentuados, 2 B cada) estouram o teto na terceira, mais enchimento para o limiar do bm25 (modelo: o corpus de `testa-memoria-assunto-prompt.cjs`).
  - **Primeiro pedido:** devolve o bloco com 2 linhas, e `<raiz>/memoria-assunto/<sid>.json` contém exatamente os 2 ids que entraram. Na base contém os 3.
  - **Segundo pedido** com o mesmo `session_id` e o mesmo assunto: o bloco traz a 3ª memória. Na base o stdout é vazio, porque ela já constava como servida.
  - **Terceiro pedido:** sai vazio com exit 0, porque agora as 3 foram servidas.
  - **Sem regressão:**
    - `node hooks/testa-memoria-assunto.cjs` em `14 ok, 0 falha(s)` (`montarBlocoAssunto` segue exportada com o mesmo contrato).
    - `node hooks/testa-memoria-assunto-prompt.cjs` em 14.
    - `node hooks/testa-memoria-assunto-agente.cjs` sem regressão.
  - Forma do alvo de mutação (código a nascer): em `memoriaDoPedido`, depois de `const { bloco, ids } = montarBlocoAssuntoComIds(achadas);` e do `if (!bloco) return '';`, a gravação dos servidos é a linha do `de:`. `montarBlocoAssuntoComIds` devolve `ids` na ordem em que as linhas entraram, parando no primeiro estouro. Nenhum caso lê o texto do fonte.

### 4. `criarSchema` só engole "coluna duplicada" [tipo: implementar]
atende: D6
arquivos: `scripts/memoria.cjs`, `scripts/testa-esquema-ocupado.cjs`
depende de: nenhuma
paralela: sim
prova: `node scripts/testa-esquema-ocupado.cjs`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: `if (!String(e.message).includes('duplicate column')) throw e;`
  para: `if (false) throw e;`
  bateria: `node scripts/testa-esquema-ocupado.cjs`
  fixture: `testa-esquema-ocupado.cjs, caso "uso_memoria legado com banco ocupado: criarSchema lanca em vez de engolir"`
pronto quando: com um banco de caixa legado — criado pelo `criarSchema` real e depois com `uso_memoria` recriada **sem** a coluna `canal` (e o índice `idx_uso_memoria_sessao` recriado) e `uso_memoria_sessoes` recriada sem `buscas_principal`, `buscas_subagente` e `subagentes`, com 1 sessão e 2 linhas de uso — e outra conexão segurando `BEGIN IMMEDIATE` — `criarSchema` deixa de engolir o BUSY — provado por `node scripts/testa-esquema-ocupado.cjs` com `0 falha(s)`.
  - **Com a trava ligada:** `criarSchema` LANÇA um erro que satisfaz `ehBancoOcupado` (`code === 'ERR_SQLITE_ERROR'` e "database is locked"). As colunas continuam ausentes e as 3 linhas antigas seguem intactas. **Na base não lança** (CONFIRMADO por experimento).
  - **Depois do `ROLLBACK`:** `criarSchema` cria as 4 colunas (as linhas antigas leem `canal = 'abertura'`). Uma terceira chamada não lança, porque "duplicate column" continua sendo engolido.
  - **Hook real:** com a trava ligada sobre o banco legado, `hooks/memoria-marca.cjs` como processo, com o payload de `Stop` (`{session_id, transcript_path, cwd, hook_event_name:'Stop'}` como em `scripts/testa-observar-canonico.cjs`), sai 0 com stdout vazio.
  - **Sem regressão:**
    - `node scripts/testa-migrar-projeto-canonico.cjs` em 16 e `node scripts/testa-migrar-emenda.cjs` em 7 (o caso "outra conexão segurando `BEGIN IMMEDIATE`" parte de banco com esquema completo e não chega ao `ALTER`).
    - `bash scripts/testa-memoria-migracao-atomica.sh`, `bash hooks/testa-memoria-recuperacao.sh` (14), `bash scripts/testa-memoria.sh` (41), `bash scripts/testa-utilidade-canais.sh` (22; o caso "migracao de banco antigo sem a coluna preserva linhas" segue verde).
  - Forma do alvo de mutação (código a nascer): `engolirSoColunaDuplicada(e)` é uma função de uma linha, a do `de:`, chamada nos `catch` das Migrações 0 e 0b — e só nesses dois. O texto não aparece em outro lugar do arquivo. Nenhum caso lê o texto do fonte.

### 5. A nota do canal do assunto desconta os termos do pedido [tipo: implementar]
atende: D2
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-nota-do-pedido.cjs`, `scripts/testa-utilidade-canais.sh`
depende de: 1
paralela: nao
prova: `node scripts/testa-nota-do-pedido.cjs`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const rarosFora = raros.filter((t) => !tokensPedido.has(t));`
  para: `const rarosFora = raros;`
  bateria: `node scripts/testa-nota-do-pedido.cjs`
  fixture: `testa-nota-do-pedido.cjs, caso "Read do arquivo que o pedido citou nao pontua a memoria"`
pronto quando: com transcritos montados das fixtures reais (`prompt-submit.jsonl` para o attachment `hook_additional_context`, `agente-pai.jsonl`/`agente-filho.jsonl` para o subagente, `transcrito-sessao.jsonl` para a abertura) e `pontuarSessao` real sobre uma caixa de `criarSchema` real, a nota do canal do assunto mede só o que **não** estava no texto que disparou a injeção — provado por `node scripts/testa-nota-do-pedido.cjs` com `0 falha(s)`.
  - **Memória** `M1` com termos raros `zzfeixe` e `zzmanga` (o resto é filler de df > 3).
  - **Canal pedido:**
    - Pedido do usuário "revise o zzfeixe agora" + attachment com a linha de `M1` + um `tool_use` `Read` com `input.file_path` `C:/repo/src/zzfeixe.cjs`. A nota gravada é **0** (na base **0,5**, a tautologia).
    - Com um segundo pedido do usuário que cita `zzmanga`, a nota é **1**.
  - **Canal subagente:**
    - `M2` com raros `zzcarro` e `zzroda`. O briefing original (entrada `user` do filho, e `toolUseResult.prompt` do pai, ambos com o bloco anexado) cita `zzcarro`. Se o `tool_use` do filho cita só `zzcarro`, a nota é **0** (base 0,5). Se cita só `zzroda`, é **1** (base 0,5).
    - O desconto usa o briefing **cortado no primeiro `## Glossário do repo` ou `## Memória do assunto`**.
  - **Abertura:** `M3` com termo raro no pedido do usuário e em um `tool_use` posterior mantém a nota de antes (desconto não se aplica à abertura).
  - **Compatibilidade:** `calcularNota(conexao, conteudo, texto)` de 3 argumentos devolve o mesmo valor de antes.
  - **Bateria existente:** em `scripts/testa-utilidade-canais.sh`, o caso "nota do canal pedido sobe com pedido posterior que contem os termos raros" é reescrito: o pedido 1 cita só parte dos termos e o `prompt2` cita o resto. Qualquer outro caso que a bateria acuse é reescrito com a razão no relato. `bash scripts/testa-utilidade-canais.sh` termina com `0 falha(s)`; o número de casos pode mudar e o relato diz de quanto para quanto. `bash scripts/testa-utilidade.sh` segue em 19.
  - Forma do alvo de mutação (código a nascer): `calcularNota(conexao, conteudo, texto, textoDoPedido)` ganha o 4º argumento opcional. Com ele definido, `tokensPedido` é o conjunto de tokens dele e `rarosFora` é a linha do `de:`. Sem ele, o caminho é o de antes. Se `rarosFora` ficar vazio, devolve 0 (a tarefa 6 troca isso). `extrairSessao` passa a devolver, para cada servida de `pedido` e `subagente`, o texto a descontar (`partesTexto[indiceInjecao] || ''` e o briefing cortado), e `pontuarSessao` o repassa. Nenhum caso lê o texto do fonte.

### 6. Memória toda dentro do pedido sai da conta: nota nula [tipo: implementar]
atende: D3
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-nota-nula.cjs`
depende de: 5
paralela: nao
prova: `node scripts/testa-nota-nula.cjs`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (rarosFora.length === 0) return null;`
  para: `if (rarosFora.length === 0) return 0;`
  bateria: `node scripts/testa-nota-nula.cjs`
  fixture: `testa-nota-nula.cjs, caso "memoria cujos raros estavam todos no pedido grava a linha com nota nula"`
pronto quando: com as mesmas fixtures reais da tarefa 5 e `pontuarSessao` real, a servida cujos termos raros estavam todos no pedido fica gravada com a marca de "não medida" — provado por `node scripts/testa-nota-nula.cjs` com `0 falha(s)`.
  - **Canal pedido:** pedido "trate de zzfeixe zzmanga" + attachment com a linha de `M1`. Resultado: 1 linha em `uso_memoria` com `servida = 1`, `canal = 'pedido'` e `nota IS NULL`. Na base a nota é 0, e o relatório a conta como inútil.
  - **Canal subagente:** os dois raros no briefing original dão nota nula.
  - **Termos só no bloco injetado** (a tarefa 5 já corta o bloco): memória cujos raros aparecem apenas na própria linha dentro do bloco do briefing. Tanto pelo caminho do pai (`toolUseResult.prompt`) quanto pelo caminho do filho sem pai (`agent-<id>.jsonl` na pasta `subagents/`) a nota é **numérica** (0), **não nula**.
  - **Sem termo raro nenhum** (leitura literal do D3, Achado A10, decisão do usuário U2): memória só com termos comuns no canal `pedido` grava nota nula; a mesma memória na **abertura** grava 0.
  - **Parcial:** memória com um raro no pedido e outro fora grava um número.
  - **Retrocompatibilidade:** `gravarUso` aceita `nota: null` sem mudar o esquema (a coluna é `REAL` nula).
  - **Total:** `SELECT count(*) FROM uso_memoria WHERE servida = 1 AND nota IS NULL` devolve o número esperado de casos nulos da bateria.
  - Forma do alvo de mutação: a linha do `de:` fica logo depois do cálculo de `rarosFora`, na mesma função da tarefa 5. Nenhum caso lê o texto do fonte.

### 7. O relatório não conta o que não foi medido e diz quantas saíram [tipo: implementar]
atende: D3
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-relatorio-fora-da-conta.cjs`
depende de: 6
paralela: nao
prova: `node scripts/testa-relatorio-fora-da-conta.cjs`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `const SQL_MEDIDA = 'servida = 1 AND nota IS NOT NULL';`
  para: `const SQL_MEDIDA = 'servida = 1';`
  bateria: `node scripts/testa-relatorio-fora-da-conta.cjs`
  fixture: `testa-relatorio-fora-da-conta.cjs, caso "sessao so com servida nula sai do denominador e a linha fora da conta diz quantas"`
pronto quando: com uma caixa de `criarSchema` real e `uso_memoria`/`uso_memoria_sessoes` povoadas como na bateria `bancoRegua` de `testa-utilidade-canais.sh` (mesmo dia `2026-10-09`, `pontuada_em` crescente, a primeira servida no canal pedido), o relatório pelo comando real `RFM_ROOT=<caixa> node scripts/memoria.cjs utilidade --relatorio` tira a servida nula da conta e a mostra à parte — provado por `node scripts/testa-relatorio-fora-da-conta.cjs` com `0 falha(s)`.
  - **Sessões** (10): `s0..s2` servidas medidas de nota 0,8 nos canais pedido/abertura/subagente; `s3..s5` medidas de nota 0,1 nos mesmos canais; `s6` e `s7` só com uma servida nula no pedido; `s8` com uma nula no subagente e uma medida de 0,8 na abertura; `s9` com uma nula no pedido e uma medida de 0,1 na abertura.
  - **Linhas esperadas na saída:**
    - `sessões pontuadas: 10`
    - `2 sessão(ões) sem servida fora da conta`
    - `servidas fora da conta (toda a memória estava no pedido): 4 em 4 sessão(ões)`
    - `canal pedido: sessões com servida útil 1 de 2 (50%)`
    - `canal abertura: sessões com servida útil 2 de 4 (50%)`
    - `canal subagente: sessões com servida útil 1 de 2 (50%)`
    - `sessões com servida útil em qualquer canal: 4 de 8 (50%)`
    - `janela da régua D7: 8 sessão(ões) com servida desde 2026-10-09T...` — o início da janela continua contando a servida nula (A3).
  - Na base, `canal pedido` sai "1 de 5 (20%)" e o total "4 de 10 (40%)".
  - **Superfície humana:** quem lê o relatório para decidir a régua precisa ver quanto ficou de fora. O critério falha se a linha `servidas fora da conta` some, ou se o número dela diverge do `SELECT` direto na caixa. Quando não há nenhuma servida nula, a linha **não aparece**.
  - **Sem regressão:** `bash scripts/testa-utilidade-canais.sh` com `0 falha(s)` (os 5 casos de régua e o de linhas por canal seguem verdes); `bash scripts/testa-utilidade.sh` em 19.
  - Forma do alvo de mutação (código a nascer): `SQL_MEDIDA` é uma constante de módulo definida uma vez e interpolada nas três consultas de `gerarRelatorio` (`temServida`, a contagem por canal e a busca de servidas). A consulta `MIN(pontuada_em)` da janela **não** a usa. Nenhum caso lê o texto do fonte.

### 8. A pontuação não marca sessão quando o esquema está incompleto [tipo: implementar]
atende: D6
arquivos: `scripts/lib/utilidade.cjs`, `scripts/testa-pontuacao-esquema-incompleto.cjs`
depende de: 4, 7
paralela: nao
prova: `node scripts/testa-pontuacao-esquema-incompleto.cjs`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (!esquemaDeUsoCompleto(conexao)) return adiarTudo(pendentes);`
  para: `if (false) return adiarTudo(pendentes);`
  bateria: `node scripts/testa-pontuacao-esquema-incompleto.cjs`
  fixture: `testa-pontuacao-esquema-incompleto.cjs, caso "uso_memoria sem canal: a fila inteira fica para a proxima passada"`
pronto quando: com um banco de caixa legado (como na tarefa 4: `uso_memoria` sem `canal`), 3 linhas de `marca_dagua` apontando para transcritos reais (a fixture `transcrito-sessao.jsonl` copiada 3 vezes, `sessao` distinta e `cwd` coerente) e nenhuma delas em `uso_memoria_sessoes`, a passada não perde a fila — provado por `node scripts/testa-pontuacao-esquema-incompleto.cjs` com `0 falha(s)`.
  - `pontuarSessoesPendentes(conexao)` devolve `pontuadas: 0, falharam: 0, adiadas: 3, total: 3`. `uso_memoria_sessoes` continua **sem** linhas. Na base devolve `falharam: 3` e as 3 sessões ficam marcadas.
  - Depois de `criarSchema(conexao)` (sem trava), uma nova chamada devolve `pontuadas: 3, falharam: 0, adiadas: 0` e grava as 3 linhas em `uso_memoria_sessoes`.
  - **Caso vizinho legítimo:** com o esquema completo e uma segunda conexão com `BEGIN IMMEDIATE`, o comportamento de banco ocupado de hoje continua (`adiadas: 1`, sem marcar). É o caso de `testa-utilidade.sh` perto de `:950-1000`.
  - **Sem regressão:** `bash scripts/testa-utilidade.sh` em 19; `bash scripts/testa-utilidade-canais.sh` com `0 falha(s)`; `bash scripts/testa-memoria.sh` em 41.
  - Forma do alvo de mutação (código a nascer): `pontuarSessoesPendentes` abre com a guarda do `de:` logo depois da consulta de `pendentes` e antes de qualquer `INSERT`. `esquemaDeUsoCompleto` lê `PRAGMA table_info` de `uso_memoria` (coluna `canal`) e de `uso_memoria_sessoes` (as 3 de buscas). `adiarTudo(pendentes)` devolve o objeto de sempre com `adiadas` igual ao número de pendentes. Nenhum caso lê o texto do fonte. A linha do log de `cmdManutencao` não muda.

### 9. `utilidade --repontuar --desde` [tipo: implementar]
atende: D8
arquivos: `scripts/lib/utilidade.cjs`, `scripts/memoria.cjs`, `scripts/testa-repontuar.cjs`
depende de: 1, 4, 5, 6, 7, 8
paralela: nao
prova: `node scripts/testa-repontuar.cjs`
mutacao:
  arquivo: `scripts/lib/utilidade.cjs`
  de: `if (opcoes.refazer) conexao.prepare('DELETE FROM uso_memoria WHERE sessao = ?').run(sessao);`
  para: `if (false) conexao.prepare('DELETE FROM uso_memoria WHERE sessao = ?').run(sessao);`
  bateria: `node scripts/testa-repontuar.cjs`
  fixture: `testa-repontuar.cjs, caso "linha velha que as regras novas nao produzem some da sessao refeita"`
pronto quando: com uma caixa de `RFM_ROOT` temporária (banco de `criarSchema` real, transcritos reais montados das fixtures) e o comando real `RFM_ROOT=<caixa> node scripts/memoria.cjs utilidade --repontuar --desde 2026-10-08`, a janela é pontuada de novo pelas regras de D1 a D3, o resto não é tocado, e a saída diz o que foi feito — provado por `node scripts/testa-repontuar.cjs` com `0 falha(s)`.
  - **Banco semeado com quatro sessões:**
    - `s-antes`: `pontuada_em` `2026-10-02T...`, fora da janela.
    - `s-taut`: `2026-10-09T08:00:00.000Z`, com a servida do pedido de nota 0,5 pela tautologia (`Read` do arquivo citado), uma linha órfã `servida = 1` de `ref_id` que nenhuma regra nova produz, e `buscas_principal = 1` por um heredoc.
    - `s-nula`: tem transcrito com todos os raros no pedido.
    - `s-sem`: `marca_dagua.arquivo` aponta para arquivo inexistente.
  - **Saída esperada** (linhas literais, nesta ordem, exit 0):
    - `repontuar desde 2026-10-08`
    - `backup: <caminho em .rainforest-backups>`
    - `sessões na janela: 3`
    - `refeitas: 2`
    - `sem transcrito (mantidas com a nota antiga): 1`
    - `falharam (mantidas com a nota antiga): 0`
    - `adiadas (banco ocupado): 0`
    - `servidas fora da conta pela regra nova nas refeitas: 1`
  - **Estado depois:**
    - `s-taut`: nota do pedido 0 (era 0,5), a linha órfã sumiu, `buscas_principal = 0`.
    - `s-nula`: `nota IS NULL`.
    - `pontuada_em` de `s-taut` e `s-nula` iguais ao original (em `uso_memoria` e em `uso_memoria_sessoes`).
    - `s-antes` e `s-sem`: linhas **idênticas byte a byte**.
    - O backup abre e tem as contagens de antes.
  - **Idempotência:** a segunda execução devolve o mesmo (exceto o caminho do backup), e `uso_memoria` e `uso_memoria_sessoes` ficam iguais ao instantâneo da primeira.
  - **Banco ocupado:** com outra conexão segurando `BEGIN IMMEDIATE`, sai com **exit 2** e `adiadas (banco ocupado): 2` (as duas sessões com transcrito). `s-sem` continua contada como sem transcrito, e o instantâneo do banco é igual ao de antes.
  - **Uso inválido:** sem `--desde`, ou com `--desde` fora de `AAAA-MM-DD` (por exemplo `2026-13-45` e `ontem`), sai 1 com uma linha de uso no stderr. `node scripts/memoria.cjs utilidade` sem argumentos lista `--repontuar` no uso.
  - **Rodar a pontuação completa:** o laço não tem o teto de 30 sessões (`TETO_PONTUAR`) e a bateria inclui uma janela de 35 sessões para provar isso, refeitas = 35. A contagem de "refeitas" é só o conjunto da janela, não pendentes alheias.
  - **Relatório depois:** `RFM_ROOT=<caixa> node scripts/memoria.cjs utilidade --relatorio` sai 0 e traz as linhas das tarefas 7.
  - Forma do alvo de mutação (código a nascer): `pontuarSessao(conexao, sessao, caminho, opcoes = {})` ganha `{ refazer, pontuadaEm }`. Com `refazer`, a linha do `de:` roda **dentro** do `BEGIN IMMEDIATE`, antes de gravar. Com `pontuadaEm`, esse valor substitui `agora` nas duas tabelas. A função da janela (`repontuarJanela`) parte de `uso_memoria_sessoes`, acha o transcrito em `marca_dagua` e processa por `pontuada_em` crescente. BUSY (`ehBancoOcupado`) interrompe e conta adiadas; outro erro conta `falharam`. O comando garante o esquema (`garantirEsquema`) e faz o backup (`fazerBackupDoBanco`) antes. A bateria de pelo menos 35 sessões usa transcritos mínimos. Nenhum caso lê o texto do fonte.
  - Para o executor: atualizar também o comentário de uso no cabeçalho de `scripts/memoria.cjs` (`:24-25`) e a mensagem de uso de `cmdUtilidade` (`:2185`).

### 10. Ensaio do `--repontuar` numa cópia do banco real [tipo: pesquisar]
atende: D1, D2, D3, D8
arquivos: nenhum arquivo do repositório (cópia no scratchpad; só números entram no relato)
depende de: 9
paralela: nao
mutacao: n/a
  motivo: ensaio de medição em dado real. Não há comportamento do repositório a inverter, e a falsificação é a identidade das contagens e do hash colados no relato.
pronto quando: com uma CÓPIA de `~/.rainforest/rainforest.db` e dos arquivos `-wal` e `-shm` que existirem naquele instante, feita com `cp` para uma pasta fora do repositório, e `RFM_ROOT` apontando para essa pasta, o comando roda sobre os transcritos reais e os números fecham — provado pela colagem das saídas abaixo no relato.
  - **Antes:** `ls -la ~/.rainforest/rainforest.db*` (tamanho e mtime) e `PRAGMA integrity_check` da cópia devolvendo `ok`.
  - **Cópia do estado atual:** `RFM_ROOT=<cópia> node scripts/memoria.cjs utilidade --relatorio`, com as linhas colar-e-guardar (`buscas ativas`, `canal ...`, `janela`, `régua D7`).
  - **Rodar:** `RFM_ROOT=<cópia> node scripts/memoria.cjs utilidade --repontuar --desde 2026-10-08`.
  - **Invariantes colados:**
    - `refeitas + sem transcrito + falharam + adiadas = sessões na janela`.
    - Com os números de 2026-10-09 como referência (56 na janela, 46 com transcrito, 10 sem), `refeitas` e `sem transcrito` ficam próximos disso. Qualquer diferença tem de ser explicada por sessões pontuadas depois da medição de hoje.
    - `count(*)` de `uso_memoria_sessoes` igual antes e depois.
    - O hash de `(sessao, pontuada_em)` de todas as linhas de `uso_memoria_sessoes` é igual antes e depois (prova que `pontuada_em` foi preservado).
    - O hash das linhas de `uso_memoria` das sessões **anteriores** a `2026-10-08` é igual antes e depois.
  - **Segunda execução** devolve as mesmas contagens e deixa o hash de `uso_memoria` igual ao da primeira. `PRAGMA integrity_check` da cópia continua `ok`.
  - **Relatório depois:** `RFM_ROOT=<cópia> node scripts/memoria.cjs utilidade --relatorio` sai 0 com as linhas `régua D7`, `servidas fora da conta ...` e `buscas ativas`. O relato cola o antes e o depois dos números (`canal ...`, útil, perdas, buscas ativas) e diz em uma frase para que lado a régua mudou.
  - **Banco real intocado:** `ls -la ~/.rainforest/rainforest.db*` depois, com tamanho e mtime **iguais** aos de antes, e `ls ~/.rainforest` com a mesma listagem. As duas leituras coladas.
  - Se a cópia mostrar `-wal` ou `-shm`, ela deve incluí-los e o relato diz isso. O banco pode ter sido gravado por outra sessão durante a cópia, então conferir a integridade antes de seguir.
  - **Repositório público:** o relato cola só contagens, nunca nome de projeto, de cliente ou de pessoa. O `cp` e a pasta da cópia ficam no scratchpad; ao fim a cópia é apagada.

### 11. Documentação, CHANGELOG e versão 1.54.0 [tipo: docs]
atende: D1, D2, D3, D4, D5, D6, D7, D8
arquivos: `README.md`, `docs/runtime-e-orcamento.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
paralela: nao
mutacao: n/a
  motivo: documentação e número de versão. A falsificação é a coerência do texto com as decisões do design e dos quatro lugares da versão entre si, não um comportamento a inverter.
pronto quando: com o design e o código entregues, os textos dizem o que as decisões dizem, e a versão vale nos quatro lugares — provado pelos comandos abaixo e pela conferência à mão, colada no relato como uma frase por decisão, lado a lado com a frase do design.
  - **Antes de subir o número:** `git fetch origin` e `git show origin/main:.claude-plugin/plugin.json`. Se `origin/main` já passou de 1.53.1, renumerar para o próximo MINOR livre e dizer isso no relato (foi o que aconteceu em 2026-10-08).
  - **README, seção "Memória", parágrafo da régua D7:**
    - Corrige a frase "Os hooks só leem o banco: o que gravam é a lista de ids já servidos da sessão" para incluir a abertura (D4).
    - D1: a busca ativa conta só a chamada `node ...memoria.cjs buscar` como instrução, não o texto citado.
    - D2 e D3: a nota do canal do assunto mede só os termos raros que o pedido ou o briefing não tinham; a memória que não tem termo raro fora do pedido sai da conta e o relatório diz quantas saíram.
    - D5: o bloco só marca como servido o que de fato entrou.
    - D6: banco ocupado não faz a sessão sair da fila.
    - D7: o peso do projeto atual continua sendo só desempate no bm25 igual, e a parte das duas grafias foi resolvida pelo nome canônico (#435).
    - D8: `node scripts/memoria.cjs utilidade --repontuar --desde 2026-10-08` refaz as sessões da janela com as regras novas, antes do `--relatorio`, com backup, sem tocar as sessões sem transcrito (que aparecem contadas), e é idempotente.
    - A régua em si (limiares 40% e 1/3, base 27% e 171 de 255) **não muda**.
  - **`docs/runtime-e-orcamento.md`, bloco da memória por assunto:**
    - Atualiza "o primeiro uso da sessão semeia a lista com o que a abertura já serviu": agora é a abertura que grava os ids; a leitura do transcrito só atende a sessão aberta antes da atualização.
    - Atualiza a linha "Régua D7: ... Leitura: `node scripts/memoria.cjs utilidade --relatorio`" para citar o passo de `--repontuar`.
  - **CHANGELOG:** `## 1.54.0 — <data>`, linguagem de quem usa o plugin:
    - O que muda na régua e nos hooks, as 8 decisões em frases curtas.
    - Efeito prático: o número do `--relatorio` muda, "buscas ativas" cai, e algumas servidas saem da conta.
    - Como atualizar o que já foi pontuado: rodar o `--repontuar` antes do `--relatorio`, e a colheita de 2026-10-23 não muda de data.
    - Vale a partir da sessão seguinte à atualização. A sessão aberta antes dela segue pela leitura do transcrito.
  - **Versão:** `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` vão a `1.54.0`; o badge do README (`README.md:7`, URL `vers%C3%A3o-1.54.0` e alt `versão 1.54.0`) lê o mesmo. Os três no mesmo commit.
  - **Comandos:**
    - `bash scripts/testa-versao.sh` devolvendo `ok: 5   falhou: 0`.
    - `node scripts/conferir-versao.cjs` com exit 0.
    - `node -p "require('./.claude-plugin/plugin.json').version+' '+require('./.codex-plugin/plugin.json').version"` imprimindo `1.54.0 1.54.0`.
    - `node scripts/memoria.cjs utilidade` sem argumentos saindo 1 com a linha de uso listando `--repontuar`.
  - **Coerência mínima conferida à mão:** o texto do README e do CHANGELOG não cita nenhum número de base, limiar ou data que difira do design (27%, 171 de 255, 40%, 1/3, 2026-10-23, 2026-10-08).

### 12. `ao_colher` da ideia da colheita ganha o passo `--repontuar` [tipo: configurar]
atende: D8
arquivos: nenhum arquivo do repositório (escreve em `~/.rainforest/ideias.jsonl`, dado do usuário)
depende de: 11
paralela: nao
mutacao: n/a
  motivo: edição de dado do usuário fora do repositório. Não há comportamento a inverter, e a falsificação é a leitura da linha da ideia depois da edição.
pronto quando: com a ideia `regua-d7-memoria-por-assunto` em `status: plantada` e o PR da 1.54.0 já mergeado e instalado, o `ao_colher` manda repontuar antes de ler o relatório, e o gancho continua o mesmo — provado por `node -e "const l=require('fs').readFileSync(process.env.USERPROFILE+'/.rainforest/ideias.jsonl','utf8').split('\n').filter(Boolean).map(JSON.parse).find(o=>o.id==='regua-d7-memoria-por-assunto');const a=l.ao_colher;console.log(l.status,l.gancho.slice(0,10),a.indexOf('--repontuar --desde 2026-10-08')>=0&&a.indexOf('--repontuar')<a.indexOf('--relatorio'))"` imprimindo `plantada 2026-10-23 true`.
  - **Quem executa:** a janela principal, no `fechar`, com a palavra do usuário. **O `executar` não despacha esta tarefa a agente.** Só vale depois do merge e da atualização do plugin, senão o `ao_colher` manda rodar um comando que ainda não existe na versão instalada.
  - **Como:** ler o `ao_colher` atual, inserir antes de "Rodar node scripts/memoria.cjs utilidade --relatorio" o passo "Rodar `node scripts/memoria.cjs utilidade --repontuar --desde 2026-10-08` (refaz as sessões da janela com as regras novas) e só depois o relatório", manter o resto do texto literal e enviar só `ao_colher` por `echo '{"ao_colher":"..."}' | node scripts/ideias.cjs editar --id regua-d7-memoria-por-assunto`. Esta linha não reproduz o texto atual porque ele cita uma pessoa; o plano é público.

## Notas de integração

- **Ondas:** a 1ª leva as tarefas **1, 2, 3 e 4 em paralelo** (arquivos disjuntos: `busca-ativa.cjs`+`utilidade.cjs`, `memoria-sessao.cjs`+`memoria-session-start.cjs`, `memoria-assunto*.cjs`, `memoria.cjs`). Depois seguem em série **5, 6, 7, 8 e 9** (todas editam `utilidade.cjs`; a 9 e a 4 editam `memoria.cjs`). Depois **10, 11 e 12**. A 12 só roda com o PR mergeado.
- **Integração (janela principal):**
  - `bash scripts/varrer-baterias.sh` completo (o agente não roda a varredura sem `--so`).
  - `node scripts/conferir-categoria.cjs`, `node scripts/conferir-fluxo.cjs cobertura --slug 2026-10-09-assunto-regua` e a conferência dos placares da base listados em "Fatos".
  - Toda bateria nova usa `mkdtemp`, `RFM_ROOT` explícito e (quando precisa de repositório ou worktree) `git worktree add` com `-c user.name/-c user.email` (a CI é windows-latest).
- **Comandos com `timeout`:** quem executa roda cada bateria longa com `timeout` explícito na chamada do Bash (até 600000). Nada fica rodando depois da resposta.
- **Alvos de mutação em código a nascer** (tarefas 1, 2, 3, 4, 5, 6, 7, 8, 9): se o executor escrever a linha diferente da prescrita, atualiza o bloco `mutacao:` do plano **antes** de rodar `conferir-mutacao.cjs`. A `cobertura` só avisa em zero ocorrências, mas a catraca sai com "MUTACAO NAO APLICADA". Nenhum teste pode ler o texto do fonte para satisfazer isso.
- **`fechar` (janela principal):**
  - PR direto (destino padrão de branch).
  - Comentário na Issue #436 com a nota do D7 (o menor (a) se fecha ali: o desempate só no bm25 igual é a D4 do design `2026-10-08-memoria-por-assunto`, e a parte das duas grafias saiu com a #435), e fechamento da Issue como resultado natural da entrega.
  - Tarefa 12.
  - Issue nova, a critério do usuário, para o `catch` vazio das migrações 1 e 4 de `criarSchema` (Achado A1).
- **Janela de colheita:** publicar cedo mantém a colheita de 2026-10-23 limpa. A data não se move, e o `--repontuar` é o passo que o `ao_colher` passa a mandar.

## Premissas aceitas sem conferir

1. O payload real de `SessionStart` traz `session_id`. Conferi só a forma usada pela bateria existente (`hooks/testa-memoria-session-start.sh`, seção 20.a), não uma captura do harness. LACUNA: o payload de `source: resume`.
2. Na retomada (`source: resume`) o `session_id` é o mesmo da sessão original. É a premissa do D4 ("na sessão retomada, ele soma"), e não achei captura que mostre isso.
3. O runner do `--destino mod` entrega (ou não) stdin com `session_id`. Não li o runner, e o plano degrada para "não grava" se faltar.
4. O hook de abertura no `hooks.json` (`:11-14`) não mostrou `timeout` no trecho que li. Assumi que 1 s de espera pelo stdin no caso patológico cabe no teto.
5. O formato da pasta de transcritos e a forma do heredoc/briefing do harness real vêm das fixtures do repo (`scripts/fixtures/memoria-assunto/*.jsonl`); não observei o harness em execução.
6. `uso_memoria_sessoes.pontuada_em` está em UTC ISO (`new Date().toISOString()`), então `--desde AAAA-MM-DD` compara com data UTC. Não confirmei em linhas reais além de ler o código.
7. A contagem de buscas (45 comandos, 24 que contam, 21 que não) vem de uma varredura minha, com regex aproximada, nas duas contas. O design fala em "3 de 32"; os corpora diferem e não reconciliei os dois números.
8. O número de sessões da janela (56, 46 com transcrito, 10 sem) é de uma cópia de hoje. Cresce até o ensaio, e a tarefa 10 explica a diferença.
9. A quebra do caso "sobe com pedido posterior" e a sobrevivência dos demais de `testa-utilidade-canais.sh` sob D2/D3 são por leitura do código, não por execução.
10. Não li `testa-memoria-assunto-agente.cjs` nem `testa-glossario-prompt.cjs` por inteiro. Assumi que não dependem do conteúdo do arquivo de ids nem da forma de `montarBlocoAssunto`.
11. Não confirmei a versão de `origin/main` (sem `git fetch`). Assumi que 1.54.0 está livre, e a tarefa 11 confere.
12. Não verifiquei se o hook `PreToolUse` do subagente concatena o glossário antes da memória em todos os casos (li o código e a fixture). Se a ordem mudar, o corte no primeiro cabeçalho continua correto.
13. Os arquivos que o plano nomeia como "pode precisar de ajuste" (`hooks/testa-memoria-session-start.sh`, `hooks/testa-memoria-assunto-prompt.cjs`, `scripts/testa-utilidade-canais.sh`) são onde espero mudança. Pode haver outra bateria com expectativa que a `varrer-baterias.sh` acuse só na integração.
