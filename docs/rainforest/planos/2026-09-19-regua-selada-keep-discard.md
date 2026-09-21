# Plano — régua selada por construção e keep/discard por comparação interna

**Slug:** `2026-09-19-regua-selada-keep-discard` · **Design:** `docs/rainforest/design/2026-09-19-regua-selada-keep-discard.md`
**Base:** `origin/main` @ `4f714ef6` · **Branch:** `fluxo/regua-selada-keep-discard`

Cinco tarefas, dezoito decisões. **Fan-out em duas ondas**, separadas por arquivo
compartilhado:

- **Onda 1** (arquivos disjuntos entre si): T1 (`scripts/conferir-regua.cjs` e sua
  bateria), T3 (`skills/regua/SKILL.md`), T5 (`vigias/livro-de-repos.md`).
- **Onda 2**: T2 volta ao script depois da T1, T4 volta à skill depois da T3.

**Restrição que vale para todas:** o repo é público — nenhum caminho desta máquina
em código, teste ou fixture. Toda asserção de bateria tem os dois ramos (`if/else`).
Bloco `mutacao` com `de:`/`para:` **literais**. O critério das duas tarefas `docs`
mora em `docs/rainforest/criterios/fluxo-13-regua-fase0.md` e
`docs/rainforest/criterios/fluxo-13-regua-loop.md`, escritos neste estágio e
**não** por quem executa — critério redigido pelo mesmo agente que ele deveria
travar não trava nada. Os dois são julgados por `scripts/segunda-opiniao.cjs`, na
mesma forma que fechou o fluxo 12 (`docs/rainforest/estado/fluxo-12-regua.json`).
**Atenção para o `verificar`:** `segunda-opiniao.cjs` não é peça marcada `sensor`
por `conferir-categoria.cjs`, então o fechamento das tarefas 3 e 4 precisa
declarar `sensor_externo` no `--json`, senão `estado.cjs` recusa com exit 2.

**Prescrição de nomes para T1/T2.** O bloco `mutacao` depende de linha literal, e
a linha ainda não existe. O script expõe, obrigatoriamente: a constante
`const EXIT_RECUSA = 1;`, a função `ancoraDe(slug)` (só resolve a âncora) e a
função `exigirAncoraEFormato(slug)` (resolve a âncora, valida o formato, aborta
com `EXIT_RECUSA`). Nome diferente reprova a tarefa pelo bloco `mutacao`.

**Emenda de 2026-09-20 (creep do `revisar`).** Três arquivos entraram no diff
sem tarefa que os cobrisse, e o `conferir-fluxo.cjs creep` os pegou:

- `scripts/testa-conferir-categoria.sh` entra em `arquivos:` da T1. Não foi
  escolha: a bateria fixa a distribuição real de categorias do repo, e um sensor
  novo obriga a atualizá-la. Era consequência da T1 que o plano não previu.
- `docs/rainforest/criterios/fluxo-13-regua-fase0.md` entra na T3 e
  `...-loop.md` na T4. Os dois foram escritos **neste estágio**, de propósito —
  critério redigido por quem executa não trava nada —, mas são artefatos do diff
  e precisam de dono declarado.

## O que não pode quebrar
- Todas as baterias `scripts/testa-*.sh` e `hooks/testa-*.sh` continuam verdes (CI roda todas).
- `docs/rainforest/reguas/2026-09-14-conferidor-de-cli.md` não é tocado e nada o passa pelo conferidor novo: foi medição de uma vez só, já encerrada, e reabri-lo para ganhar seção "Freios" seria rejulgar peça antiga sob régua nova.
- O builder continua sem ver o manifesto de mecanismos (critério 1 de `docs/rainforest/criterios/fluxo-12-regua.md`).
- As seis afirmações de `docs/rainforest/criterios/fluxo-12-regua.md` continuam verdadeiras sobre o texto da skill depois das T3 e T4.
- `scripts/conferir-categoria.cjs` continua verde: o script novo declara `// @categoria: sensor`.

## Tarefas

### 1. `conferir-regua.cjs` confere âncora e formato do manifesto [tipo: implementar]
atende: D1, D4, D5, D6, D7
arquivos: `scripts/conferir-regua.cjs`, `scripts/testa-conferir-regua.sh`, `scripts/testa-conferir-categoria.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-regua.cjs`
  de: `const EXIT_RECUSA = 1;`
  para: `const EXIT_RECUSA = 0;`
  bateria: `bash scripts/testa-conferir-regua.sh`
  fixture: `testa-conferir-regua.sh, caso "manifesto editado na arvore de trabalho recusa"`
pronto quando: num repositório git real com `docs/rainforest/reguas/<slug>.md` commitado e depois editado na árvore de trabalho, `node scripts/conferir-regua.cjs conferir --slug <slug>` sai 1 nomeando o arquivo; com o manifesto intacto mas sem a seção `## Freios`, sai 1; com quatro `### M<n>`, sai 1; com manifesto intacto, `## Freios` presente e 5 a 7 `### M<n>` sequenciais, sai 0; com slug inexistente, sai 2 — provado por `bash scripts/testa-conferir-regua.sh` devolvendo `resultado: N ok, 0 falha(s)` e exit 0, com zero casos pulados.

### 2. Modo `mostrar`: a checagem e a leitura são o mesmo caminho [tipo: implementar]
atende: D2, D3
arquivos: `scripts/conferir-regua.cjs`, `scripts/testa-conferir-regua.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/conferir-regua.cjs`
  de: `const ancora = exigirAncoraEFormato(slug);`
  para: `const ancora = ancoraDe(slug);`
  bateria: `bash scripts/testa-conferir-regua.sh`
  fixture: `testa-conferir-regua.sh, caso "mostrar com manifesto editado nao imprime nada"`
pronto quando: num repositório git real, com o manifesto alterado na árvore de trabalho, `node scripts/conferir-regua.cjs mostrar --slug <slug>` escreve **zero byte** em stdout e sai 1; com o manifesto intacto, o stdout é byte a byte idêntico a `MSYS_NO_PATHCONV=1 git show "$(git log --diff-filter=A --format=%H -- docs/rainforest/reguas/<slug>.md | tail -1)":docs/rainforest/reguas/<slug>.md` — provado por `bash scripts/testa-conferir-regua.sh` devolvendo `resultado: N ok, 0 falha(s)` e exit 0.

### 3. Skill `regua`: Fase 0 passa a produzir manifesto selado [tipo: docs]
atende: D2, D18
arquivos: `skills/regua/SKILL.md`, `docs/rainforest/criterios/fluxo-13-regua-fase0.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa de texto prescritivo; não há linha de comportamento a inverter. A falsificação é o crítico cego do `pronto quando`, que julga coerência com o design e não presença de string.
pronto quando: com o diff real da branch contra `origin/main`, um modelo de outra família julgando as quatro afirmações da Fase 0 responde `concordo` na última linha — provado por `node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-13-regua-fase0.md --modelo codex` devolvendo exit 0; e as seis afirmações do fluxo 12 continuam verdadeiras sobre o mesmo arquivo — provado por `node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-12-regua.md --modelo codex` devolvendo `concordo` e exit 0.

### 4. Skill `regua`: Fase 2, keep/discard e as quatro paradas [tipo: docs]
atende: D8, D9, D10, D11, D12, D13, D14, D15, D16
arquivos: `skills/regua/SKILL.md`, `docs/rainforest/criterios/fluxo-13-regua-loop.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: mesma natureza da tarefa 3 — texto prescritivo, sem comportamento executável a inverter.
pronto quando: com o diff real da branch contra `origin/main`, um modelo de outra família julgando as sete afirmações do loop responde `concordo` na última linha — provado por `node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-13-regua-loop.md --modelo codex` devolvendo exit 0.

### 5. `karpathy/autoresearch` entra no livro de repos [tipo: docs]
atende: D17
arquivos: `vigias/livro-de-repos.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: uma linha de tabela; o comportamento que a protege já existe e é a catraca `conferir-livro-de-repos.cjs`, cuja bateria não muda nesta entrega.
pronto quando: com a linha de `karpathy/autoresearch` datada de `2026-09-19` na tabela "Avaliados", `node scripts/conferir-livro-de-repos.cjs` sai 0 — e, trocando o veredito dessa linha para `Enxertar: vale a pena`, sai 2 com `VEREDITO FORA DO VOCABULÁRIO` citando a linha, provando que a linha nova está de fato dentro do alcance da catraca e não antes do corte.

### 6. Fecha os achados do `revisar` no conferidor [tipo: implementar]
atende: D1, D3, D5, D7
arquivos: `scripts/conferir-regua.cjs`, `scripts/testa-conferir-regua.sh`, `skills/regua/SKILL.md`
depende de: 2
paralela: nao
mutacao:
  arquivo: `scripts/conferir-regua.cjs`
  de: `if (!normalizarEolBytes(bytesCommit).equals(normalizarEolBytes(bytesArquivo))) {`
  para: `if (!bytesCommit.equals(bytesArquivo)) {`
  bateria: `bash scripts/testa-conferir-regua.sh`
  fixture: `testa-conferir-regua.sh, caso "manifesto recheckado com autocrlf continua intacto"`
pronto quando: num repositório git real com `core.autocrlf=true` e sem `.gitattributes` forçando `eol=lf`, com o manifesto commitado em LF e depois recheckado na árvore de trabalho (portanto com CRLF em disco e nenhuma alteração de conteúdo), `node scripts/conferir-regua.cjs conferir --slug <slug>` sai **0** e `mostrar --slug <slug>` imprime o manifesto — provado por `bash scripts/testa-conferir-regua.sh` devolvendo `resultado: N ok, 0 falha(s)`, exit 0 e zero pulados; e `node scripts/conferir-regua.cjs mostrar --slug <slug>` num repositório sem `git` no PATH sai **2**, não 1.

**Rodada 2 (achados do `revisar`, 2026-09-20).** A revisão reprovou com quatro
achados. Três são desta tarefa; o quarto (`A4`) é o `titulo` do arquivo de estado,
que nomeava "custo fixo" — o mecanismo que o design descartou — e foi corrigido
direto, porque `docs/rainforest/estado/<slug>.json` é rastro do fluxo, não
artefato com tarefa.

- **A1, bloqueante** — a comparação de integridade não normaliza fim de linha. A
  etapa de formato já removia `\r`, mas ela roda **depois** do gate, que aborta
  antes. Com `core.autocrlf=true` (padrão do Git no Windows) num repo hospedeiro
  sem `.gitattributes`, qualquer checkout que reconstrua o arquivo o devolve em
  CRLF, e o conferidor passa a acusar de adulterado um manifesto que ninguém
  tocou — `conferir` sai 1 e `mostrar` recusa imprimir, travando o loop inteiro.
  É o incidente de 2026-08-13 que o `.gitattributes:1-11` deste repo documenta,
  só que a proteção de lá é do repo do plugin e não acompanha a skill.
- **A2** — o cabeçalho promete exit 2 para "git falhou" e o código sai 1. Falha
  de ambiente passa a ser lida como adulteração. Âncora vazia (manifesto nunca
  commitado) continua 1, que é veredito legítimo; o que vira 2 é o git não
  executar.
- **A3** — o formato exigido (`### M<n>` com separador depois do número, `## Freios`
  comparado por igualdade exata) só existe nas fixtures da bateria. Quem escreve
  a régua na Fase 0 não tem onde ler isso, e a mensagem de erro agrava: diz
  `quantidade invalida de mecanismos: 0` quando o autor escreveu sete com outra
  pontuação.

**Rodada 3 (2026-09-20).** Um contraexemplo novo de estado de git por rodada
(repo sem commit, `packed-refs` ilegível). A sonda em camadas de `ancoraDe`
cobriu os conhecidos e o cabeçalho passou a **declarar o limite**: estado exótico
de git pode cair no lado errado da fronteira 1/2. Decisão do usuário, não
autoaprovação — prometer perfeição numa classificação que três rodadas
independentes furaram é o que estava errado.

**Rodada 4 (2026-09-20), achado `D1`.** `--slug` entra sem validação nos três
pontos que montam `docs/rainforest/reguas/${slug}.md`, e
`--slug '../../../skills/regua/SKILL'` faz o conferidor **ler e dar veredito**
sobre arquivo de fora da pasta de réguas — `fs.existsSync` e `fs.readFileSync`
normalizam o `..`. O que ele não chega a fazer é **imprimir**: `git show
<sha>:<caminho com ..>` não normaliza e falha, então sem a validação o script já
saía 2 ali, por acidente e com a mensagem errada (`erro ao ler conteudo do
commit`). Isso importa para a medição: assertiva de exit code sozinha não
distingue os dois mundos, e a bateria por pouco mediu o acidente em vez da
recusa — quem separa é a mensagem e a ausência de `..` na saída. Não é o limite
declarado na rodada 3 — aquele fala só da fronteira exit 1 vs 2 sob git estranho —
e contradiz o design `D3`, que afirma **um** ponto onde burlar o selo. O conserto
não inventa mecanismo: reusa `validarSlug` de `scripts/recibo.cjs`, que já recusa
barra, contrabarra, dois-pontos e `..` com exit 2, já é exportado e já tem
bateria própria.

pronto quando (rodada 4): com `--slug '../fora'` apontando para um manifesto
válido e commitado fora da pasta de réguas, tanto `conferir` quanto `mostrar`
saem **2** com `RECUSADO: slug invalido` em stderr, nenhum byte em stdout, e
**nenhum caminho contendo `..` na saída** — é esta última que distingue a recusa
do acidente do `git show`. Um slug legítimo ao lado do alvo continua saindo 0.
Provado por
`bash scripts/testa-conferir-regua.sh` devolvendo `resultado: N ok, 0 falha(s)`,
exit 0 e zero pulados.

Alvo de mutação da rodada 4 — vai em cerca de propósito: o bloco `mutacao:`
que o `conferir-fluxo.cjs cobertura` lê é o da tarefa 6 (a inversão de EOL), e
um segundo bloco fora de cerca seria lido em silêncio ou ignorado em silêncio,
que é pior. Este é o que a **integração** re-rodou:

```
arquivo: scripts/conferir-regua.cjs
de: if (slug) validarSlug(slug);
para: if (false) validarSlug(slug);
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 17 "--slug com ../ nao escapa de docs/rainforest/reguas/"
```

**Rodada 5 (2026-09-20), seis achados — um deles atinge a D1.** A revisão
reprovou, e o bloqueante não era de implementação: **em clone raso o selo não
tem no que ancorar**. `git log --diff-filter=A` devolve o commit de adição
*visível*; num clone raso o único commit visível é a fronteira, cujo conteúdo é,
por construção, o do checkout — a comparação de integridade compara o arquivo
consigo mesmo. Reproduzido lado a lado no mesmo repositório: completo sai 1,
raso sai 0 e o `mostrar` entrega a régua afrouxada ao crítico cego. E
`--depth 1` é o default do `actions/checkout`.

A decisão subiu ao usuário, como o teto manda, porque a pergunta era de design:
a D1 diz "git é o selo". **Decidido: manter a D1 e recusar clone raso** — o
conferidor detecta `--is-shallow-repository` e sai 2 (ambiente), em vez de
julgar errado. É a D5 aplicada: âncora que não resolve aborta. O preço é
declarado na skill: em CI, `fetch-depth: 0`. A alternativa (hash próprio como
âncora de reserva) segue em "avaliado e descartado" no design — este achado é o
contraexemplo que faltava a ela, e reabri-la custaria o fluxo desde o primeiro
estágio.

Os outros cinco são conserto da mesma rodada:

- **A2** — a leitura era decodificada como UTF-8 dos dois lados. Byte inválido
  vira U+FFFD, então bytes diferentes passavam por iguais, e o `mostrar`
  entregava manifesto CP-1252 com todo acento trocado — quebrando o
  `pronto quando` da T2, que exige stdout byte a byte igual ao `git show`.
  Agora compara e escreve `Buffer`, com EOL normalizado sobre bytes.
- **A3** — cabeçalho `### M<n>` malformado era ignorado em silêncio quando
  havia outros bem formados, e o teto de 5-7 ficava burlável. Reproduzido: 5
  válidos + `### M6:`/`### M7:` saía 0 com 7 cabeçalhos no arquivo. Agora
  qualquer `### M` fora do formato reprova.
- **A4** — duas asserções do caso 17 passavam por coincidência: slug
  inexistente também sai 2. Ganharam asserção de mensagem.
- **A5** — `stdout_bytes` e a comparação do caso 7 passavam por `$(...)`, que
  come newline final: "zero byte" e "byte a byte" mediam outra coisa. Agora vão
  para arquivo e são julgados por `wc -c` e `cmp`.
- **A6** — o sub-bloco `Uso:` de `conferir` não listava "git falhou" entre os
  motivos de exit 2.

pronto quando (rodada 5): no mesmo repositório, com a régua commitada e depois
adulterada e commitada, `conferir` sai **1** no checkout completo e **2** no
`git clone --depth 1` dele, com `mostrar` imprimindo **zero bytes** no raso; e
um manifesto com cinco `### M<n>` bem formados mais `### M6:` sai **1**
nomeando o cabeçalho ofensor — provado por `bash scripts/testa-conferir-regua.sh`
devolvendo `resultado: N ok, 0 falha(s)`, exit 0 e zero pulados.

Alvos de mutação da rodada 5, em cerca pelo mesmo motivo da rodada 4 (o bloco
`mutacao:` que o `cobertura` lê é o da tarefa 6). Estes são os que a integração
re-rodou:

```
arquivo: scripts/conferir-regua.cjs
de: if (!raso.error && raso.status === 0 && raso.stdout.trim() === "true") {
para: if (false) {
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 18 "clone raso nao ancora"

arquivo: scripts/conferir-regua.cjs
de: if (primeiraLinhaOffensora) {
para: if (false) {
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 19 "### M<n> malformado REPROVA mesmo com 5 bem formados"
```

**Rodada 6 (2026-09-20), onze achados — o bloqueante era meu.** Na rodada 5 a
comparação de integridade passou de texto para `Buffer`, e o bloco `mutacao:`
desta tarefa continuou apontando para a linha antiga. O `de:` casava **zero**
vezes no fonte: `conferir-mutacao.cjs` sairia 3 (`MUTACAO NAO APLICADA`), e o
carimbo `catraca_mutacao` afirmava uma falsificação que não aconteceu. O
`conferir-fluxo.cjs cobertura` não pega isso — ele confere que os campos
existem, não que o `de:` existe no arquivo. O bloco acima agora aponta para o
par vivo (`normalizarEolBytes` contra comparação de bytes crus), e a
integração o re-rodou.

Os outros dez: `normalizarEol` virou código morto e saiu; a `SKILL.md` escopava
"a partir da rodada 2" nas três peças, e o qualificador é só do crítico
interno; a skill não mandava commitar o manifesto **antes** do primeiro
`mostrar`; o contrato de exit 1 omitia "nunca commitado"; o
`formato-manifesto.md` não enunciava sequência nem faixa 5-7; o caso 13 ainda
passava por `$(...)`; manifesto selado e apagado saía 2 em vez de 1; a cláusula
"sem `git` no PATH" deste `pronto quando` não era medida; a Fase 1 redeclarava
o teto em vez de apontar para o `## Freios`; e o parágrafo do topo procedural,
que eu tinha movido para `references/` ao abrir espaço na rodada 5, é exigido
**dentro** da `SKILL.md` pela afirmação 3 do `fluxo-13-regua-fase0` — o
crítico cego do Codex discordou por isso.

pronto quando (rodada 6): `node scripts/conferir-fluxo.cjs mutacoes --slug
2026-09-19-regua-selada-keep-discard` executa o bloco desta tarefa **sem** exit
3; manifesto selado e depois apagado da árvore sai **1** com "removido da
arvore"; e com o `PATH` vazio (git inalcançável pelo spawn) `conferir` sai
**2** — provado por `bash scripts/testa-conferir-regua.sh` devolvendo
`resultado: N ok, 0 falha(s)`, exit 0 e zero pulados.

Alvo de mutação novo desta rodada, em cerca pelo motivo das rodadas 4 e 5:

```
arquivo: scripts/conferir-regua.cjs
de: if (!existeNaArvore) {
para: if (false) {
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 20 "manifesto selado e apagado da arvore e VEREDITO (1)"
```

**Rodada 7 (2026-09-21), cinco achados — o selo tinha uma segunda porta.**
Reproduzido: régua estrita selada na `main`; uma branch nascida antes dela
também adiciona o arquivo, frouxo; o merge conflita (add/add) e é resolvido com
o lado da branch. O `git log` **simplifica o histórico**: num merge TREESAME a um
dos pais, segue só aquele pai, nunca visita a adição selada e devolve só a da
branch. `conferir` saía 0 e `mostrar` entregava `### M1 frouxo` ao crítico
cego. Não exige má-fé elaborada — é um fluxo normal de branch.

Duas decisões subiram ao usuário, como o teto manda:

- **Q1, decidido: recusar mais de uma adição.** `git log --full-history`, e
  mais de um commit de adição sai 1 ("selo ambíguo"). Escolher uma delas não
  resolveria: pela data, a data de commit é de quem commita; pela topologia, é
  a mesma porta. Régua apagada e recriada no mesmo slug também cai aqui, e é
  coerente — régua recriada é régua trocada. Junto, `GIT_NO_REPLACE_OBJECTS`
  em toda leitura de histórico e conteúdo, que fecha a variante do `git replace`
  (o commit selado continua lá, com o mesmo SHA, e o que se lê dele é outro
  blob). O "rebase do commit de adição" segue declarado como limite.
- **Q2, decidido: subcomando `validar`.** Manifesto selado com erro de formato
  ficava sem conserto: a âncora é a primeira adição, a quebrada; corrigir e
  commitar não troca a âncora; validar antes de selar era impossível (sem
  commit, "nunca commitado"). E o orquestrador travado ali tinha o incentivo
  exato para ler o arquivo direto — o furo da D3. `validar` aplica os quatro
  contratos ao arquivo na árvore, sem âncora, e **não imprime** o manifesto: o
  `mostrar` segue sendo o único que imprime. É a mesma função `validarFormato`
  que o `conferir` aplica ao conteúdo selado, para as duas nunca divergirem.
  Cresce o escopo desta tarefa — os arquivos já são dela.

Os outros três: a rodada 1 não inicializava o melhor guardado no TSV (entra
como `keep`, e cada linha depois do commit que fecha a rodada); a `SKILL.md`
ainda dizia "teto da Fase 1" em dois pontos; e dívida — a sanidade do caso 4
imprimia `FALHA` sem contar, e o `mostrar` saía 2 mudo na releitura.

A mesma rodada teve uma discordância do crítico cego do Codex sobre a
afirmação 1 do `fluxo-13-regua-loop` ("dois críticos a cada rodada"): a skill
diz que o crítico interno só existe a partir da rodada 2. A janela rejeitou o
parecer e registrou a divergência com motivo — a D8 define a comparação interna
como nosso-novo contra nosso-melhor-guardado, e na rodada 1 não há melhor
guardado. Comparar a rodada 1 contra o estado pré-loop, quando existir, é
decisão de design nova, não conserto.

pronto quando (rodada 7): com a régua selada na `main` e um merge resolvido com
uma branch que também adicionou o manifesto, `conferir` sai **1** com "selo
ambiguo" e `mostrar` imprime **zero bytes**; com `git replace` trocando o blob
selado, `conferir` sai **1**; e `validar` sai **0** num manifesto bom nunca
commitado, **1** num fora do formato, **2** num slug inexistente, sem imprimir
byte em stdout — provado por `bash scripts/testa-conferir-regua.sh` devolvendo
`resultado: N ok, 0 falha(s)`, exit 0 e zero pulados.

Alvos de mutação da rodada 7, em cerca pelo motivo das anteriores:

```
arquivo: scripts/conferir-regua.cjs
de: '--full-history',
para: '--topo-order',
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 22 "merge TREESAME nao troca a ancora"

arquivo: scripts/conferir-regua.cjs
de: if (linhas.length > 1) {
para: if (false) {
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 22, assercao "e nomeia o selo ambiguo"

arquivo: scripts/conferir-regua.cjs
de: GIT_NO_REPLACE_OBJECTS: '1',
para: GIT_NO_REPLACE_OBJECTS_DESLIGADO: '1',
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 23 "git replace nao troca o conteudo que o selo le"

arquivo: scripts/conferir-regua.cjs
de: if (subcomando === 'validar') {
para: if (subcomando === 'validar-desligado') {
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 24 "validar confere o formato ANTES de selar"
```

**Rodada 8 (2026-09-21), seis achados.** O bloqueante é da mesma classe que a
rodada 5 já tratou como bloqueante — mecanismo que o validador nunca viu — por
um caminho que ela não fechou: a detecção era `/^### M/`, e `###  M8` (dois
espaços), ` ### M8` (recuado) e `#### M8` **renderizam** como cabeçalho sem casar
nada. Reproduzido: 7 válidos + 2 invisíveis, `validar` saía 0 com 9 mecanismos na
tela do crítico cego. A detecção passou a ser o que o markdown renderiza — até
três espaços de recuo, um a seis `#`, espaço, `M` e dígito — e tudo que casa ali
sem casar o formato estrito é recusa. Cercas de código (três crases ou três tis)
deixaram de contar, o que furava o teto e reprovava manifesto bom ao mesmo
tempo.

Também reproduzido: `.git/info/grafts` corta o histórico por um mecanismo que o
`GIT_NO_REPLACE_OBJECTS` não cobre — com o HEAD enxertado como raiz, a adição
selada sumia e `conferir` saía 0. `GIT_GRAFT_FILE` apontando para arquivo
inexistente desliga os grafts sem recusar o repositório. E: diretório no lugar
do manifesto caía no exit 1 com stack trace (agora é ausência, 2); o `Uso:` de
`conferir` e `mostrar` omitia "adicionado mais de uma vez"; a D4 do design ainda
descrevia `tail -1` — ganhou nota datada, sem reescrever a decisão aprovada.

Três decisões subiram ao usuário, como o teto manda:

- **Q1, decidido: consertar tudo acima.**
- **Q2, decidido: emendar a afirmação 1 do `fluxo-13-regua-loop`** para "a cada
  rodada a partir da 2ª", com nota no próprio critério dizendo que a emenda é
  decisão do usuário. A redação anterior contradizia a D8, e o crítico cego do
  Codex discordou por isso em duas rodadas seguidas. A `SKILL.md` foi alinhada
  no mesmo ponto: o crítico interno é `Agent` novo toda rodada **a partir da 2ª**.
- **Q3, decidido: depois de um discard, a lacuna vem da rodada do melhor
  guardado** — a coluna `lacuna` da linha dele no TSV. Antes o builder partia do
  artefato guardado com a lacuna do descartado, que aponta para um artefato de
  que ele não parte. Continua vindo do crítico da régua (D11), só que da rodada
  certa.

pronto quando (rodada 8): 7 mecanismos válidos mais `###  M8`, ` ### M8` ou
`#### M8` saem **1** em `validar`, e 7 válidos mais `    ### M8` (quatro espaços,
bloco de código) saem **0**; 7 válidos mais um `### M8` dentro de cerca saem
**0**, e `## Freios` só dentro de cerca sai **1**; com `.git/info/grafts`
cortando a adição selada de uma régua adulterada e commitada, `conferir` sai
**1** e `mostrar` imprime **zero bytes**; e diretório no caminho do manifesto sai
**2** sem stack trace — provado por `bash scripts/testa-conferir-regua.sh`
devolvendo `resultado: N ok, 0 falha(s)`, exit 0 e zero pulados.

Alvos de mutação da rodada 8, em cerca pelo motivo das anteriores. Nenhum `de:`
leva contrabarra: o quoting do shell que a integração usa come contrabarra, e um
`de:` que chega adulterado dá exit 3 sem culpa do fonte.

```
arquivo: scripts/conferir-regua.cjs
de: const regexMQualquer = /^ {0,3}#{1,6}
para: const regexMQualquer = /^###
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 25, assercoes do recuado e do nivel quatro

arquivo: scripts/conferir-regua.cjs
de: if (abre) { cerca = abre[1][0]; continue; }
para: if (false) { cerca = abre[1][0]; continue; }
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 26 "cerca de codigo nao e manifesto"

arquivo: scripts/conferir-regua.cjs
de: GIT_GRAFT_FILE: path.join(
para: GIT_GRAFT_FILE_DESLIGADO: path.join(
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 27 ".git/info/grafts nao corta o historico"

arquivo: scripts/conferir-regua.cjs
de: try { return fs.statSync(caminho).isFile(); } catch { return false; }
para: return fs.existsSync(caminho);
bateria: bash scripts/testa-conferir-regua.sh
fixture: testa-conferir-regua.sh, caso 28 "diretorio no lugar do manifesto"
```
