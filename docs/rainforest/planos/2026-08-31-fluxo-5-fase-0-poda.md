# Plano: Fluxo 5, fase 0 — `poda.cjs` em modo passthrough + medição

Design: `docs/rainforest/design/fluxo-5-design-poda.md` (+ `docs/rainforest/design/adendo-fluxo-5-deepagents.md`, cuja parte útil a esta fase é só a validação de rumo — o conteúdo dele é todo de fase 1, ver "Fora de escopo" abaixo)

## Achados do repo real que mudam o plano (não vêm do briefing)

1. **Existe um contrato de arquivo que o briefing não citou, e que esta fase precisa satisfazer.** CONFIRMADO em `docs/rainforest/design/fluxo-8-design-handover-regente.md:43`: *"a fase 0 da poda grava `.rainforest/poda/contexto.json` com `usage.input_tokens` real. Regente monitora..."* — e `:66-69` lista `.rainforest/poda/` inteiro como não-commitável (`.gitignore`), citando risco de segurança (CCR guarda tool output bruto — irrelevante à fase 0, mas o diretório é o mesmo). O design da própria fase 0 (`fluxo-5-design-poda.md:49`) só menciona `metricas.jsonl`. Sem o `contexto.json`, a frase da fila "fase 0 destrava o gatilho do fluxo 8" (`LEIA-PRIMEIRO-CONSOLIDADO-v2.md:47-48`) fica falsa — por isso este plano tem uma tarefa própria pra esse arquivo (Tarefa 6), não uma nota de rodapé.

2. **O caminho `.rainforest/poda/...` citado nos dois designs não pode ser relativo ao cwd — o repo já resolve isso por uma cadeia de 4 níveis, e ela não é sempre `<projeto>/.rainforest`.** CONFIRMADO em `hooks/lib/raiz.cjs`: a raiz de dados é `RFM_ROOT` (nível 1) → `<projeto>/.rainforest` **só se já tiver `FOCO.md` ou `ideias.jsonl`** (`MARCADORES`, linha 40) → `~/.rainforest` (nível 3, o caso comum nesta própria máquina) → raiz do plugin (nível 4, auto-hospedado). Hardcodar `.rainforest/poda/` a partir do cwd ignoraria essa cadeia e, nesta máquina, escreveria no lugar errado (ou criaria uma segunda raiz de dados por engano). Este plano usa `resolverRaiz()` (Tarefa 1), nunca um caminho literal.

3. **O design pede um `docs/rainforest/poda.json` para porta/limiares, mas isso não bate com o único mecanismo de config que o repo tem.** CONFIRMADO em `hooks/lib/config.cjs:34-119`: `CHAVES` só guarda **booleanos**, em dois arquivos (`<projeto>/.rainforest/config.json`, `<dados>/config.json`) — nenhum precedente de config numérica. E `docs/rainforest/` é a árvore **versionada** (design/planos/estado — comentário em `scripts/estado.cjs`: "veredito vs. tagarelice"); gravar ali uma porta local de processo é confundir as duas coisas. Como a fase 0 não tem limiar nem retenção de CCR pra configurar (isso é fase 1), a única config real que falta é a porta e o kill switch — resolvidos por env var (`RFM_PODA_PORTA`, no padrão de `RFM_ROOT`/`RFM_ESTADO_ROOT`) e por uma chave nova em `CHAVES` (Tarefa 2). Nenhum `poda.json` é criado nesta fase.

4. **Um único processo em `127.0.0.1:4141` não tem como saber, por requisição, de qual projeto/sessão ela veio — e nenhum dos dois designs resolve isso (as Q1-Q3 do design são sobre auth e formato, não sobre isto).** O `estado.cjs` rastreia estágio por **slug**, resolvido de `CLAUDE_PROJECT_DIR || cwd` (comentário em `scripts/estado.cjs`), e isso é uma propriedade da SESSÃO que fez a chamada — não do corpo HTTP que chega no proxy. Nada na arquitetura (`ANTHROPIC_BASE_URL` aponta pra um host:porta fixo, headers passam intactos) carrega essa informação até o proxy. Este plano assume a simplificação de fase 0, documentada e não escondida: o "estágio ativo" é resolvido **uma vez, na partida do processo**, a partir do cwd/env de quem rodou `poda.cjs iniciar` — reaproveitando a mesma heurística de correspondência branch↔slug já provada em `scripts/saude.cjs:155-166` (`checarFluxo`). Isso é correto no caso comum (uma sessão por vez) e **abertamente errado** se dois projetos compartilharem o mesmo processo — caso em que o campo grava `estagio: null` em vez de adivinhar (mesma filosofia de `limpar-branches.cjs --sem-fetch`: "nunca inventa alvo"). Resolver correlação por requisição fica fora desta fase — não há dado no request pra basear isso, e inventar seria construir sobre suposição.

5. **Não existe, neste repo, um precedente de "processo em background com pidfile" escrito pelo próprio código do plugin** — `worker.pid` do claude-mem (lido em `scripts/saude.cjs:633-676`) é de uma ferramenta de terceiro, só lido, nunca escrito por aqui. `poda.cjs iniciar/parar` é território novo; este plano espelha deliberadamente o mesmo formato já lido em `saude.cjs` (`{pid, port, startedAt}`), pra que uma futura seção `/saude` de `poda` (Tarefa 7) reuse a receita "PID vivo não é prova de porta viva" que o próprio `checarClaudeMem` já demonstrou (linhas 645-663 do mesmo arquivo).

6. **O nome de arquivo pedido pelo briefing (`docs/rainforest/planos/fluxo-5-fase-0-poda.md`) não segue a convenção documentada do próprio diretório.** CONFIRMADO em `docs/rainforest/planos/README.md:3`: *"Um arquivo por trabalho... `AAAA-MM-DD-<tema>.md`."* Não é chamado deste plano decidir nome de arquivo alheio à sua tarefa — só registro, pra quem gravar escolher. (Gravado como `2026-08-31-fluxo-5-fase-0-poda.md`, seguindo a convenção.)

7. **A dependência declarada no cabeçalho do design ("Depende de: fluxo 1 fechado", `fluxo-5-design-poda.md:3`) já está satisfeita**, ainda que sob outro nome histórico. CONFIRMADO em `scripts/estado.cjs:111` (`ESTAGIOS_EXIGEM_EVIDENCIA = ['executar', 'verificar']`), `:140` (`TETO_TENTATIVAS = 3`) e o bloco `PRE_REQUISITOS`/back-edge `reprovado→executar` — exatamente o "endurecer estado.cjs" que o fluxo 1 descreve, entregue em `docs/rainforest/planos/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md` antes de a numeração 1–11 existir. Não é bloqueio.

## Decisão do usuário: valor padrão da chave `poda` (kill switch)

A Tarefa 2 cria uma chave nova em `hooks/lib/config.cjs` que liga/desliga a **escrita em disco** (`metricas.jsonl` + `contexto.json`) — o passthrough em si roda sempre que o processo está de pé, independente da chave.

- **Opção A — nasce `padrao: true` (recomendado).** Ligar o proxy (`poda.cjs iniciar`) e apontar `ANTHROPIC_BASE_URL` já são, sozinhos, as duas ações explícitas que o usuário precisa tomar. Exigir um terceiro passo (`setup.cjs --ligar poda`) só pra começar a medir vai contra o próprio objetivo da fase 0: juntar uma semana de evidência real o quanto antes. O padrão dos outros toggles `false` (`vigias`, `ponte-*`, `integracao-*`) existe porque cada um deles ou grava em repositório de terceiro, ou dispara automação sem o usuário pedir a cada vez — nenhum dos dois se aplica aqui.
- **Opção B — nasce `padrao: false`**, no padrão conservador dos demais. Exige `setup.cjs --ligar poda` antes de qualquer coleta.

Este plano segue a Opção A abaixo (Tarefa 2). Se a escolha for B, é uma linha (`padrao: true` → `false`) sem efeito em nenhuma outra tarefa.

## O que não pode quebrar

- **A resposta do upstream nunca é alterada, byte a byte, em nenhum caminho de código** — nem sucesso, nem erro, nem streaming SSE. Falsificável: hash SHA-256 do corpo recebido pelo cliente de teste é idêntico ao hash do corpo que o fixture upstream enviou.
- **Nenhum header de autenticação (`Authorization`, `x-api-key`) aparece em `metricas.jsonl`, `contexto.json`, stdout ou stderr do processo** — falsificável por `grep` do valor secreto do fixture contra os três destinos, em nenhum deles casando.
- **O proxy só escuta em `127.0.0.1`** — falsificável por `server.address().address === '127.0.0.1'`, nunca `0.0.0.0`.
- **Corpo de requisição em formato inesperado nunca derruba a requisição** (Risco 5 do design) — passthrough puro + aviso no log; falsificável com um fixture que manda um body que não é JSON válido e ainda assim recebe resposta 200 do upstream fixture.
- **Nenhuma tarefa desta fase implementa compressão, stub CCR ou os defaults 85%/10% do adendo** — isso é fase 1. Falsificável por ausência: nenhum arquivo criado nesta fase referencia `TOO_LARGE_TOOL_MSG`, limiar de 85%, ou grava arquivo de CCR.
- **Com a chave `poda` desligada, o processo continua de pé e faz só passthrough — zero escrita em disco por requisição** (R3: nunca custa mais caro que a ausência do proxy). Falsificável: rodando com a chave off, `metricas.jsonl` e `contexto.json` não mudam de tamanho após N requisições.
- **Zero dependência: nenhum `require` de pacote fora de `http`, `https`, `net`, `crypto`, `fs`, `path`, `child_process`** em qualquer arquivo novo — falsificável por grep.
- **Todo caminho de arquivo é montado com `path.join`, nunca concatenação de string** — falsificável por grep (nenhum `+ '/'` ou template literal com `/` de separador nos módulos novos).
- **`docs/rainforest/design/fluxo-5-design-poda.md` e o `adendo` continuam legíveis e não são reescritos** — esta fase só acrescenta um rodapé de status, nunca edita o corpo do design aprovado.

## Fora de escopo desta fase (reafirmado, não é omissão)

- Todo o conteúdo do adendo (defaults 85%/10%, formato do stub CCR, `sessao-<id>.md` append-only) — é fase 1, compressão. Lido, confirma que o rumo do design está certo; nada dele é implementado aqui.
- Fase 2 (poda em fronteira de estágio, leitura de `fechar` aprovado).
- `/custo` com "top ofensores por tipo de bloco" — exige a classificação de tipo de `tool_result` que só a heurística da fase 1 introduz. A fase 0 soma por estágio e por request, sem classificar conteúdo.
- `handover.cjs` / `regente.cjs` (fluxo 8) — só o arquivo-contrato `contexto.json` que eles vão consumir entra aqui; nada que os implemente.
- Correlação de "estágio ativo" por requisição em processo multi-sessão (achado 4) — documentado como limitação conhecida, não resolvido.

## Tarefas

### 1. `hooks/lib/poda-dados.cjs` — resolve a raiz de dados da poda pela cadeia existente, não por caminho relativo [tipo: implementar]
atende: Fase 0 (armazenamento local, `fluxo-5-design-poda.md:49`); Achado 2
arquivos: `hooks/lib/poda-dados.cjs`, `scripts/testa-poda-dados.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/poda-dados.cjs`
  de: a chamada real a `resolverRaiz()` de `hooks/lib/raiz.cjs` dentro de `raizPoda()`
  para: retorna sempre `null` (raiz nunca resolvida)
  bateria: `bash scripts/testa-poda-dados.sh`
  fixture: caso "com `RFM_ROOT` apontando pra pasta com `FOCO.md`, `raizPoda()` resolve para `<fixture>/poda`"
pronto quando: com `RFM_ROOT` fixture (pasta contendo `FOCO.md`), `raizPoda()` devolve `path.join(<fixture>, 'poda')` — comparação de string exata; `caminhoMetricas()`, `caminhoContexto()` e `caminhoPid()` devolvem arquivos dentro dessa pasta; `portaPadrao()` devolve `4141` sem env var e o valor de `RFM_PODA_PORTA` quando declarada (numérica, faixa 1-65535, valor fora da faixa cai no padrão com aviso — não derruba); chamar qualquer uma das funções **não cria a pasta** (mkdir só acontece na escrita real, provado checando ausência de diretório logo após a chamada); `bash scripts/testa-poda-dados.sh` sai `== resultado: N ok, 0 falhas ==`.

### 2. Chave `poda` em `hooks/lib/config.cjs` — kill switch da escrita, sem nova config numérica [tipo: implementar]
atende: R3 (`fluxo-5-design-poda.md:42,82`); Achado 3; Decisão do usuário (Opção A)
arquivos: `hooks/lib/config.cjs`, `hooks/testa-config.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/config.cjs`
  de: a entrada `poda` inteira do objeto `CHAVES`
  para: entrada removida
  bateria: `bash hooks/testa-config.sh`
  fixture: bloco novo "PODA: escrita em disco, nasce ligada" no padrão dos blocos existentes (uma chave, três origens: padrão/projeto/usuário)
pronto quando: `resolverConfig().valores.poda === true` sem nenhum arquivo de config (padrão); `<projeto>/.rainforest/config.json` com `"poda": false` sobrescreve o padrão e a origem reportada é `'projeto'`; a mutação faz `poda` sumir de `CHAVES` sem afetar nenhuma outra chave existente; `bash hooks/testa-config.sh` continua 100% verde.

### 3. `scripts/poda.cjs` — proxy passthrough (request+resposta intactos, SSE sem buffer) e ciclo de vida `iniciar`/`parar`/`status` [tipo: implementar]
atende: Arquitetura e Princípio 1/2 (`fluxo-5-design-poda.md:9-34`); Risco 2, Risco 5
arquivos: `scripts/poda.cjs`, `scripts/testa-poda.sh`
depende de: 1
paralela: sim
mutacao:
  arquivo: `scripts/poda.cjs`
  de: o uso de `res.pipe`/repasse por stream do corpo de resposta upstream sem bufferizar antes de reenviar
  para: bufferiza a resposta inteira antes de reenviar (acumula em memória e só então escreve)
  bateria: `bash scripts/testa-poda.sh`
  fixture: caso "primeiro chunk chega ao cliente antes de o fixture terminar de enviar os últimos" — fixture upstream que escreve 3 chunks com `setTimeout` espaçados, cliente de teste registra timestamp de cada chunk recebido
pronto quando: com um `http.createServer` fixture fazendo o papel do upstream (host/porta configuráveis por env var só para teste, nunca usado em produção sem essa env var), `poda.cjs iniciar --porta <livre>` sobe o processo, grava `poda.pid` em `raizPoda()` no formato `{pid, porta, iniciadoEm}`, e uma requisição HTTP contra o proxy: (a) chega ao fixture com o MESMO corpo, MESMOS headers de autorização (`Authorization`/`x-api-key`) e mesmos bytes — provado por hash SHA-256 dos dois lados; (b) a resposta chega ao cliente com hash idêntico ao que o fixture mandou, inclusive em streaming SSE (o teste de "primeiro chunk antes do último enviado" acima); (c) um corpo de requisição que não é JSON válido ainda assim é encaminhado e recebe resposta 200 do fixture (Risco 5); (d) `poda.cjs status` lê o pidfile e diz se a porta responde; (e) `poda.cjs parar` mata o processo e apaga o pidfile; (f) `server.address().address === '127.0.0.1'` sempre; (g) nenhum valor do header `Authorization`/`x-api-key` do fixture aparece em stdout/stderr do processo (grep negativo); `bash scripts/testa-poda.sh` sai `== resultado: N ok, 0 falhas ==`.

### 4. `hooks/lib/poda-estagio.cjs` — resolve o estágio ativo na partida do processo, nunca por requisição [tipo: implementar]
atende: Fase 0 ("estágio ativo via estado.cjs", `fluxo-5-design-poda.md:50`); Achado 4
arquivos: `hooks/lib/poda-estagio.cjs`, `scripts/testa-poda-estagio.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/poda-estagio.cjs`
  de: a checagem de que existe EXATAMENTE UM trabalho aberto cujo slug (sem a data) bate com a branch atual (reaproveitando a heurística de `scripts/saude.cjs:155-166`)
  para: sempre devolve o primeiro trabalho aberto da listagem, sem checar a branch
  bateria: `bash scripts/testa-poda-estagio.sh`
  fixture: dois trabalhos abertos em `estado.cjs`, um cujo slug bate com a branch atual e outro não
pronto quando: com um único trabalho aberto cujo slug bate com a branch git atual, `estagioAtivo({cwd, env})` devolve `{slug, estagio}` do trabalho certo; com dois trabalhos abertos e branch batendo só um, devolve o que bate (prova de que a mutação — pegar "o primeiro da lista" — muda o resultado); sem nenhum trabalho aberto, sem repo git, ou com a branch não batendo slug nenhum, devolve `null` — nunca adivinha; chamável tanto como função quanto por CLI direta (`node hooks/lib/poda-estagio.cjs`) pra facilitar depuração manual; `bash scripts/testa-poda-estagio.sh` 100% verde.

### 5. Captura de métricas por requisição — `metricas.jsonl` respeitando o kill switch [tipo: implementar]
atende: Fase 0 (campos do JSONL, `fluxo-5-design-poda.md:49-51`)
arquivos: `scripts/poda.cjs`, `scripts/testa-poda-metricas.sh`
depende de: 1, 2, 3, 4
paralela: nao
mutacao:
  arquivo: `scripts/poda.cjs`
  de: a checagem de `resolverConfig().valores.poda` antes de escrever em `metricas.jsonl`
  para: sempre escreve, ignorando a chave
  bateria: `bash scripts/testa-poda-metricas.sh`
  fixture: uma sequência de requisições contra o proxy fixture, uma vez com `poda: true` e uma vez com `poda: false`
pronto quando: com a chave ligada, cada requisição grava uma linha em `metricas.jsonl` com `timestamp`, `estagio` (do módulo da Tarefa 4, ou `null`), `mensagens` (contagem de blocos do body), `bytes_corpo`, `duracao_ms` (tempo do proxy, não do upstream) e — extraídos de uma CÓPIA do stream SSE de resposta, sem alterar o passthrough real — `usage.input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` (parse dos eventos `message_start`/`message_delta`, provado com um fixture SSE que injeta valores conhecidos e o teste compara campo a campo); com a chave desligada, **zero bytes** são acrescentados a `metricas.jsonl` depois de N requisições (arquivo do mesmo tamanho, ou ausente); nenhuma linha contém o valor do header `Authorization`/`x-api-key` do fixture (grep negativo); `bash scripts/testa-poda-metricas.sh` 100% verde.

### 6. `contexto.json` — o contrato que o fluxo 8 espera, atualizado atomicamente [tipo: implementar]
atende: Achado 1 (`fluxo-8-design-handover-regente.md:43`)
arquivos: `scripts/poda.cjs`, `scripts/testa-poda-metricas.sh`
depende de: 1, 5
paralela: nao
mutacao:
  arquivo: `scripts/poda.cjs`
  de: o `fs.renameSync` que promove o `.tmp` a `contexto.json` depois de cada requisição medida
  para: linha comentada (a escrita para no `.tmp`, nunca promovida)
  bateria: `bash scripts/testa-poda-metricas.sh`
  fixture: caso novo "contexto.json nunca fica pela metade, mesmo sob duas requisições em sequência rápida"
pronto quando: depois de cada requisição com a chave `poda` ligada, `contexto.json` existe com `{atualizadoEm, estagio, usage: {input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}, requisicoes}` — `usage.input_tokens` é o real da ÚLTIMA resposta processada (não acumulado), `requisicoes` é o total desde que o processo subiu; a escrita é atômica (`.tmp` + rename, no padrão já usado em `scripts/ponte.cjs` pra `projeto.md`) — provado que nunca existe um `contexto.json` com JSON inválido mesmo interrompendo o processo entre duas requisições consecutivas; com a chave desligada, `contexto.json` não é criado nem atualizado; `bash scripts/testa-poda-metricas.sh` 100% verde.

### 7. Seção `poda` no `/saude` — porta responde? env var desta sessão aponta pra ela? [tipo: implementar]
atende: Integração com o ecossistema (`fluxo-5-design-poda.md:76`)
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: 2, 3
paralela: sim
mutacao:
  arquivo: `scripts/saude.cjs`
  de: o `aviso(...)` de `checarPoda` quando o pidfile existe mas a porta não responde
  para: `alerta(...)` com os mesmos argumentos
  bateria: `bash scripts/testa-saude.sh`
  fixture: pidfile fixture apontando para uma porta que não tem servidor nenhum
pronto quando: com a chave `poda` desligada, `saude.cjs --json` não tem item com `item === 'poda'` (nenhuma linha, no padrão de `integracao-*`); com a chave ligada e sem `poda.pid`, aparece `aviso` "processo não está rodando" citando `node scripts/poda.cjs iniciar`; com `poda.pid` presente mas a porta não respondendo, aparece exatamente uma linha `aviso` (nunca `alerta` — quebrado é aviso, mesmo padrão do `integracao-*`) e o exit de `/saude` continua 0; a mutação faz o mesmo cenário virar `alerta` e exit 1 — prova que o teste mede o NÍVEL, não só a presença; com a porta respondendo mas `ANTHROPIC_BASE_URL` da sessão atual não apontando pra ela, aparece `aviso` "as requisições desta sessão não passam pelo proxy"; com tudo alinhado, `ok` citando quantas requisições `contexto.json` já registrou; `bash scripts/testa-saude.sh` 100% verde.

### 8. `scripts/relatorio-poda.cjs` — o relatório executável que fecha o gate da fase 0 [tipo: implementar]
atende: Gate de saída da fase 0 (`fluxo-5-design-poda.md:53`); Risco 1 (comparação de custo)
arquivos: `scripts/relatorio-poda.cjs`, `scripts/testa-relatorio-poda.sh`
depende de: 1, 5
paralela: nao
mutacao:
  arquivo: `scripts/relatorio-poda.cjs`
  de: a checagem de que `metricas.jsonl` cobre pelo menos 7 dias-calendário DISTINTOS antes de declarar o gate aberto
  para: sempre declara o gate aberto, independente da contagem de dias
  bateria: `bash scripts/testa-relatorio-poda.sh`
  fixture: `metricas.jsonl` sintético com registros em só 3 dias-calendário distintos, e um segundo fixture com 7 dias distintos (múltiplos registros no mesmo dia contam como 1)
pronto quando: com um fixture de **menos** de 7 dias-calendário distintos, `relatorio-poda.cjs` sai com **exit != 0** e mensagem citando quantos dias faltam ("GATE FECHADO: N de 7 dias"); com um fixture de 7 dias distintos (ainda que poucos registros por dia), sai **exit 0** com "GATE ABERTO" e imprime: soma de `input_tokens`/`output_tokens`/`cache_read_input_tokens` por estágio (agrupando por `estagio`, com uma linha `desconhecido` pros `null`), percentual de cache hit agregado (`cache_read_input_tokens / (cache_read_input_tokens + input_tokens)`, com a fórmula e o resultado conferíveis à mão contra números fixos do fixture), contagem de requisições e média de `duracao_ms` (o custo de ter o proxy — nunca compara com "sem proxy" porque não há como medir isso retroativamente, e o relatório diz isso explicitamente em vez de inventar uma comparação); `--json` produz a mesma soma em formato máquina; a mutação prova que a contagem de dias-calendário é o que decide o gate, não a quantidade de linhas; `bash scripts/testa-relatorio-poda.sh` 100% verde.

### 9. Docs — README, status do design, e o rodapé "fase 0 entregue" [tipo: docs]
atende: convenção do repo (README acompanha entrega de script/config novo)
arquivos: `README.md`, `docs/rainforest/design/fluxo-5-design-poda.md`
depende de: 3, 5, 6, 7, 8
paralela: nao
mutacao: n/a
  motivo: documento sem lógica executável própria; a prova de não-divergência é o `grep` dos comandos citados contra os scripts reais, não mutação
pronto quando: a tabela de scripts do `README.md` (a partir da linha ~336) ganha uma linha para `scripts/poda.cjs` e uma para `scripts/relatorio-poda.cjs`, cada uma citando o que o script faz e não faz (proxy passthrough + medição; nada de compressão) — provado por grep dos dois nomes na tabela; a chave `poda` aparece documentada onde as demais `CHAVES` já são citadas no README; `docs/rainforest/design/fluxo-5-design-poda.md` ganha uma linha de rodapé (não reescreve o corpo do design) dizendo que a fase 0 foi entregue, com o caminho deste plano — provado por grep; nenhuma menção nova a fase 1/2, `poda.json` ou defaults do adendo entra em nenhum dos dois arquivos (grep negativo, reforça o limite de escopo).

## Premissas aceitas sem conferir

- Que o dev que rodar `poda.cjs iniciar` faz isso de dentro do diretório do projeto ativo (pra Tarefa 4 resolver `CLAUDE_PROJECT_DIR`/cwd corretamente) — se for rodado de outro lugar, o estágio sai `null`, o que é seguro mas menos útil.
- Que o formato dos eventos SSE da Anthropic (`message_start`, `message_delta` com `usage` incremental) não muda durante o ciclo desta fase — é o formato documentado hoje; mudança de formato cai no mesmo guarda-chuva do Risco 5 (nunca derruba a requisição, só para de extrair métrica).
- Que `git bash`/`mktemp -d` seguem disponíveis nas baterias novas, como em todas as `testa-*.sh` existentes.
- Que o `.github/workflows/baterias.yml` (citado no `README.md:591-594`) já roda `scripts/testa-*.sh` e `hooks/testa-*.sh` por convenção de nome — as baterias novas (`testa-poda*.sh`) entram na esteira de CI sem wiring adicional.

## Emendas da revisão (2026-08-31)

Nota de invariante: a lista de requires permitidos passa a incluir `stream`
(built-in do Node, usado no tap de cópia do SSE) — o espírito "zero dependência
npm" está mantido; a enumeração original só esqueceu o módulo.

### 10. Header Host reescrito para o upstream — o proxy funciona contra a API real [tipo: implementar]
atende: invariante "resposta nunca alterada" no caso REAL (achado 1 da revisão: Host do cliente vaza e a borda Cloudflare devolve 403)
arquivos: `scripts/poda.cjs`, `scripts/testa-poda.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/poda.cjs`
  de: a reescrita do header Host para o host do upstream
  para: headers do cliente repassados intactos (Host inclusive)
  bateria: `bash scripts/testa-poda.sh`
  fixture: caso novo "Host recebido pelo upstream e o do upstream, nao o do cliente"
pronto quando: os headers repassados ao upstream têm `host` = host[:porta] da URL de upstream (default `api.anthropic.com`), com TODOS os demais headers (auth incluso) intactos; caso novo na bateria com fixture que LOGA o Host recebido e o compara ao host do fixture — nunca ao `127.0.0.1:<porta-do-proxy>` que o cliente mandou

### 11. Remove a bateria órfã da T7 [tipo: limpeza]
atende: achado 2 da revisão (creep)
arquivos: `scripts/testa-saude-poda-only.sh`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: remoção de arquivo duplicado; a prova é o arquivo ausente e os casos R1-R4 continuarem verdes em testa-saude.sh
pronto quando: o arquivo não existe mais e `bash scripts/testa-saude.sh` continua 100% verde

### 12. `checarPoda` lê o pidfile que o `poda.cjs` REALMENTE grava [tipo: implementar]
atende: T7/D4 (achado da revisão rodada 2: consumidor lia `port`, produtor grava `porta` — caminho de sucesso inatingível; fixture casava o defeito do consumidor)
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `scripts/saude.cjs`
  de: a leitura da chave `porta` do pidfile
  para: de volta a `port`
  bateria: `bash scripts/testa-saude.sh`
  fixture: caso novo R5 "caminho de sucesso com pidfile no formato REAL e porta viva"
pronto quando: `checarPoda` lê `pidInfo.porta` (a chave que `gravarPidfile` escreve); as variáveis mortas `portaEsperada`/`urlEsperada` saem; o fixture do R3 grava o pidfile no formato REAL (`porta`); e um caso novo R5 sobe um servidor local vivo, grava pidfile real apontando pra ele, seta `ANTHROPIC_BASE_URL` para a porta e afere o item `poda` nível `ok` com a contagem de requisições — o caminho de sucesso roda pela primeira vez
