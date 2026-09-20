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
  de: `if (normalizarEol(conteudoCommit) !== normalizarEol(conteudoArquivo)) {`
  para: `if (conteudoCommit !== conteudoArquivo) {`
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
