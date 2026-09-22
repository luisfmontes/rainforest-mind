# Invariante de comportamento nas skills de ação, com assertiva negativa

Enxerto de `openai/openai-developers-for-claude`, trilha declarada pelo Luís em
2026-09-19. Ancorado na ideia `gate-do-p1-e-hook-nao-texto`.

## Objetivo

Impedir que uma instrução de comportamento suma de um `SKILL.md` sem ninguém
perceber.

O problema tem dono e data. Na sessão de 2026-09-19, na entrega multihost, a
âncora de bytes de `scripts/testa-plugin-codex.cjs` ficou vermelha porque a
`main` reescreveu `skills/fechar/SKILL.md` de quatro para seis passos. O conserto
foi recalcular o `sha256` para os bytes novos. Se aquela reescrita tivesse
**apagado** a frase "pare e mostre o `git status` ao usuário em vez de commitar
por cima", a âncora teria ficado vermelha exatamente igual, e o conserto teria
sido exatamente o mesmo. Âncora de bytes não distingue reescrita legítima de
instrução removida — e é o único teste que existe hoje sobre corpo de skill.

A ideia âncora, `gate-do-p1-e-hook-nao-texto`, resolve o comportamento que **pode**
virar hook, com a ressalva mecânica de que no Claude Code só o `PreToolUse`
bloqueia. Este trabalho cobre o resto: instrução de skill, que não tem como virar
hook e hoje não tem teste nenhum.

## Decisões fechadas

- **D1 — O escopo são as seis skills de ação destrutiva ou irreversível** — porquê: `fechar`, `limpar`, `executar`, `revisar`, `verificar` e `plano` são onde uma frase perdida muda o que o agente **faz**, não o que ele explica. Cobrir as 19 de uma vez transformaria a escolha de frase em trabalho de horas, e lista longa vira manutenção que ninguém faz; cobrir só `fechar`, que é o caso com evidência real, entregaria mecanismo sem cobertura quando o mecanismo já quase existe.

- **D2 — O mecanismo é o `conferir-invariantes.cjs` estendido, não um script novo** — porquê: ele já lê `skills/rainforest-mind/invariantes.json`, já confere 5 frases das regras 10, 11, 12, 13 e 15, já tem bateria própria com mutantes em `scripts/testa-conferir-invariantes.sh` — **eram cinco blocos, não dois, e nenhum deles media nada**, corrigido em 2026-09-20 por achado da revisão: a caixa compartilhada nunca copiava `references/`, então a árvore já saía `exit 2` antes da primeira mutação e os cinco ficariam vermelhos com a mutação sendo no-op; hoje cada bloco monta a **sua** caixa, com `references/` dentro, e tem a **sua** asserção de linha de base imediatamente antes da mutação (ver a nota de 2026-09-20 abaixo) — e "cada bloco" só virou verdade sem exceção na quinta revisão, também de 2026-09-20, quando o sexto deles, o meta-teste sem caixa e sem linha de base que repetia a mutação do bloco (4), foi apagado; os blocos hoje são **seis**, os cinco numerados mais o do degrau desconhecido ao lado de um válido — e essa bateria já é descoberta pelo glob `scripts/testa-*.sh` do `varrer-baterias.sh`, que o CI roda em Node 22 e 24. Estender herda CI de graça; script novo teria de reconquistar tudo isso e criaria um segundo lugar onde a mesma regra mora.

> **Nota de 2026-09-20, achado da TERCEIRA revisão, sobre a D2.** A forma
> anterior desta decisão dizia "hoje o setup copia `references/` e a bateria
> assere a linha de base antes de mutar", como se o vácuo estivesse fechado. Ele
> estava fechado **só para o primeiro bloco**: a `$CAIXA` era criada uma vez e
> nunca restaurada, então os blocos (2) a (5) rodavam sobre a árvore estragada
> pelo anterior — o (5) restaurava o `SKILL.md` e deixava dentro a mutação que o
> (4) fez em `references/regra-15.md` —, e a asserção de linha de base existia
> uma vez só, entre o setup e o bloco (1). Medido sem aplicar as mutações (2) a
> (5): as quatro continuavam imprimindo `ok VERMELHO` sobre uma árvore que já
> saía `exit 2`. Cada bloco passou a montar a sua caixa e a asserir a linha de
> base dela antes de mutar. Duas outras formas de verde vazio foram fechadas na
> mesma passagem: chave desconhecida na invariante era descartada em silêncio
> (grafar `onde` como `ondes` nas cinco entradas da `rainforest-mind` deixava a
> mutação canônica passar com exit 0), e nada fixava **quais** skills estavam
> protegidas — apagar os seis arquivos das skills de ação deixava o CI verde
> conferindo cinco invariantes. Agora há asserção de roster e de contagem contra
> o repositório real.

- **D3 — Um `invariantes.json` por skill, ao lado do `SKILL.md`** — porquê: é a convenção que já existe, e o caminho `skills/<nome>/invariantes.json` é derivável do nome da skill sem tabela de tradução. O contra-argumento pesado foi considerado e perdeu por pouco: um arquivo central responderia "o que está protegido hoje?" mais barato. Fica registrado porque, se a cobertura passar de seis skills, é a primeira coisa a reabrir.

- **D4 — O campo `onde` passa a ser opcional e o padrão é presença no corpo** — porquê: hoje ele vale `["skill","nucleo"]` e essa distinção só existe para `skills/rainforest-mind/SKILL.md`, a **única** que tem a marca de corte `<!-- detalhe -->`. Para as outras dezoito não há núcleo extraído, então exigir o campo obrigaria a inventar um valor sem significado. Ausente, o teste é "a frase está no corpo"; presente, vale a semântica atual, sem regressão para a `rainforest-mind`.

- **D5 — Ganha o caso `nao_deve`, que trava a AUSÊNCIA de uma frase** — porquê: é a peça genuinamente nova do enxerto, lida em `tests/skill-contracts.test.mjs` do repo da OpenAI, onde `assert.doesNotMatch(skill, /secure encrypted provisioning/i)` impede que uma formulação já rejeitada volte. Aqui ela tem usuário concreto: `CONFIRMO fechar issue` é o prefixo do token `CONFIRMO fechar issue #<n>` que `scripts/fechar-issue.cjs` exigia antes de `be8c49eb` (16/09, D1 do `zerar-issues-5`, "o fechamento de Issue é o resultado natural do fluxo"). **É guarda prospectiva, não detector daquela regressão** — corrigido em 2026-09-20, por achado da revisão: a frase nunca esteve no corpo do `fechar` (`be8c49eb^:skills/fechar/SKILL.md` tem 0 ocorrências de "confirmo"), e o checador só lê corpo de skill, então reintroduzir `--confirmo` em script deixa este invariante verde. O que ela trava é o corpo do `fechar` voltar a mandar digitar frase. **A comparação do `nao_deve` ignora caixa, como o `/i` do enxerto, e a do `deve` continua exata** — acrescentado em 2026-09-20, por achado da revisão: a implementação tinha nascido sensível a caixa, e `Confirmo fechar issue #12` passava verde, quando uma versão futura escreveria essa forma com a mesma probabilidade da maiúscula; no `deve` a insensibilidade mudaria o que as dez frases aprovadas significam, então ela fica só do lado negativo.

- **D6 — Frase proibida só vale se for vocabulário que o texto correto nunca usa** — porquê: `--confirmo` sozinho seria um `doesNotMatch` desastroso. Ele é **proibido** no `fechar` (linha 33, "Sem `--confirmo`") e **obrigatório** no `limpar` (linhas 48 a 122, apagar worktree sujo e branch), e aparece dentro da própria frase que o proíbe. Um `nao_deve` que dispara no texto certo é pior que nenhum, porque ensina a ignorar o vermelho. A regra é o que faz o caso `CONFIRMO fechar issue` ser seguro e o caso `--confirmo` ser recusado.

- **D7 — As 5 invariantes da `rainforest-mind` migram para o formato novo** — porquê: dois formatos convivendo fazem o segundo nascer como exceção, que é como este repo já descreveu dívida antes. O risco é real e foi pesado: aquele arquivo está verde, tem mutantes (seis blocos, não dois — ver a correção na D2) e roda no CI em dois Node. A D4 é o que torna a migração barata — o formato novo é superconjunto do atual, então a migração é acrescentar campo, nunca reescrever os cinco registros.

- **D8 — Um vermelho do invariante é falha de bateria, não aviso** — porquê: o `conferir-invariantes.cjs` já sai diferente de zero e já está dentro da varredura; manter o comportamento é o que faz o teste valer alguma coisa. Aviso que não quebra o CI é a "trava verde que só testava escrita" que este repo já documentou em `relatorios/2026-09-01-trava-verde-que-so-testava-escrita.md`.

- **D9 — A linha do livro de repos entra neste fluxo** — porquê: ela é a procedência do enxerto, e fluxo que enxerta sem registrar de onde veio perde o rastro. É uma linha de tabela validada por `scripts/conferir-livro-de-repos.cjs`, então o custo de carregar junto é menor que o de lembrar depois. Caminho da cascata: `Enxertar: enxerta`.

- **D10 — As frases propostas entram no design para o Luís cortar, não no plano** — porquê: escolher frase é critério, não fato, e a regra 16 manda subir decisão. A pergunta por skill é "qual instrução, se sumisse numa reescrita, mudaria o que o agente faz sem ninguém perceber?". Invariante que ele não leu não protege o que ele quis proteger.

- **D11 — Cada frase proposta foi conferida como substring exata e única antes de entrar aqui** — porquê: frase que aparece duas vezes não distingue remoção de uma ocorrência, e frase que já não bate nasce vermelha. As dez foram medidas por script: as nove de `deve` ocorrem exatamente uma vez, e a de `nao_deve` ocorre zero vezes.

## Frases propostas

Nove `deve` e uma `nao_deve`. O corte é do Luís.

| Skill | Tipo | Frase | Se sumisse |
|---|---|---|---|
| `fechar` | deve | `O destino da branch é sempre PR` | o agente volta a oferecer menu de merge/PR/manter |
| `fechar` | deve | `Árvore suja de algo que não é deste trabalho é condição de parada` | volta a commitar por cima de trabalho alheio |
| `fechar` | **nao_deve** | `CONFIRMO fechar issue` | vocabulário prospectivo: uma versão futura do corpo do `fechar` volta a exigir frase digitada e ninguém nota. Não é a reversão de 16/09 — aquela vivia em `scripts/fechar-issue.cjs` (10 **linhas** com "confirmo" em qualquer caixa em `be8c49eb^`, por `grep -ci` — não 10 ocorrências, corrigido em 2026-09-20 por achado da revisão; as ocorrências da substring são 13; o hook tinha 0), fora do alcance do checador, que só lê o corpo da skill |
| `limpar` | deve | `Nunca entra na remoção` | branch `viva` entra na remoção — perda irreversível |
| `executar` | deve | `O hash da base é executado \`git rev-parse\`, nunca digitado` | volta o hash copiado de prosa, que a regra 12 proíbe |
| `executar` | deve | `nunca é nomeado` | agente que edita ganha nome e escapa do worktree |
| `revisar` | deve | `nunca reduz a severidade de um achado` | o revisor passa a negociar a própria nota |
| `revisar` | deve | `Justificar em prosa não destrava` | creep volta a ser destravado por narrativa |
| `verificar` | deve | `Antes de "verde" virar achado` | mutação neutra volta a virar achado de cobertura |
| `plano` | deve | `"\`bash <bateria>\` sai 0" não é critério de pronto` | o critério volta a medir o instrumento, não o sistema |

Duas que foram consideradas e **não** entraram, com o motivo, porque o motivo é o
mesmo achado da sessão: o `git add -A` **proibido** no `fechar` e o `Git
destrutivo proibido` no `executar` já têm gate de `PreToolUse` por trás. Proteger a prosa
deles duplicaria defesa onde ela já existe, e a sessão de 2026-09-19 mostrou o
custo disso: um mutante que tirava `-A` de `CAMINHO_TOTAL` sobreviveu porque
`temCurta(opcoes, "A")` pegava o mesmo caso sozinho. Defesa redundante não morre
com um tiro só, e invariante redundante não prova nada.

## Avaliado e descartado

- Copiar o formato de teste da OpenAI (`node:test` com `assert.match` no próprio arquivo de teste): descartado porque enterra a frase protegida dentro de código, onde o Luís não a lê ao editar a skill. O `invariantes.json` ao lado do `SKILL.md` mantém a lista legível para quem edita.
- Um `doesNotMatch` genérico sobre `--confirmo`: descartado pela D6 — o token é correto no `limpar` e aparece na frase que o proíbe no `fechar`.
- Cobrir as 19 skills nesta rodada: descartado pela D1.
- Arquivo central único de invariantes: descartado pela D3, com o contra-argumento registrado para reabrir se a cobertura crescer.
- Enxertar também a proibição de fato embutido do `openai-docs` ("Never use bundled or remembered model facts as a fallback"): descartado porque não se aplica. Medido: os quatro `claude-haiku-4-5-20251001` do repo são **pino deliberado** em invocação de CLI, para custo e determinismo, não fato lembrado apresentado como corrente. Este plugin não responde perguntas sobre modelo.
- Fazer o invariante avisar em vez de quebrar: descartado pela D8.
- **Consolidar os literais `CONFIRMO fechar issue` das caixas de areia de `scripts/testa-conferir-invariantes.sh` na declaração `INVARIANTES_ESPERADAS`**: descartado em 2026-09-20, junto com a entrada da segunda fonte. São oito literais digitados — achados por `grep -n "CONFIRMO fechar issue" scripts/testa-conferir-invariantes.sh` menos as quatro linhas de comentário e a da declaração; não os fixamos por número de linha porque editar o cabeçalho daquele arquivo já os deslocou uma vez, em 2026-09-20 —, e eles **ficam digitados**. Três motivos, na ordem do peso. Primeiro: cada caixa grava o mesmo literal no `invariantes.json` **e** no `SKILL.md` que ela mesma monta, dentro do mesmo bloco — ela é autoconsistente por construção, e um typo ali não esconde nada, porque o que ela afere é que a frase plantada e a frase declarada na caixa casam, quaisquer que sejam. Segundo: elas testam o **mecanismo** do checador (proibida presente, proibida ausente, insensibilidade a caixa, chave errada, `onde` em `nao_deve`), não o dado de produção; lê-las da produção faria uma mudança legítima da frase real alterar em silêncio o que essas cinco caixas medem, e uma frase de produção vazia ou malformada as faria **abortar** em vez de medir o mecanismo. Terceiro: se alguém "consertar" um CI vermelho editando a **declaração** em vez da produção, essas caixas passariam a seguir a declaração em silêncio. **Reescrito em 2026-09-20, por achado da SÉTIMA revisão**, que mediu a redação anterior e a achou superdimensionada: ela dizia que acoplá-las à produção "recriaria exatamente a fonte única que esta rodada existe para desfazer", e isso não procede — consolidar os literais das caixas na declaração não tocaria a comparação declaração × produção, que continuaria com os dois lados escritos por mãos diferentes. O risco é este aqui, e é menor: os motivos 1 e 2 se sustentam sozinhos, e este é coadjuvante. **E a conta também estava errada**: a receita dizia "menos as três linhas de comentário", e elas são quatro — medido, `grep -c "CONFIRMO fechar issue" scripts/testa-conferir-invariantes.sh` dá 13, e `13 − 3 − 1` dá 9, não 8. O número OITO sempre esteve certo; quem errava era a receita.

## Fora de escopo

- Escrever invariante para as outras treze skills.
- Mudar o mecanismo de corte `<!-- detalhe -->` ou o tamanho da injeção.
- Mexer na âncora de bytes de `scripts/testa-plugin-codex.cjs`, que vive na entrega multihost e responde outra pergunta — se o corpo mudou. As duas convivem.
- Implementar `nao_deve` para qualquer frase além de `CONFIRMO fechar issue` nesta rodada.

## Em aberto

- Se a cobertura passar de seis skills, reabrir a D3 (arquivo por skill contra arquivo central).
- ~~**Segunda fonte da frase de um invariante**~~ — **FECHADO para a `nao_deve` em
  2026-09-20** (sexta revisão) e **FECHADO para as catorze `deve` no mesmo dia**
  (sétima revisão). As duas metades são o mesmo defeito em eixos diferentes:
  nada, fora do próprio `invariantes.json`, fixava **qual** frase cada invariante
  protege.

  **Metade `nao_deve`:** um `nao_deve` bem-formado com a frase grafada errado
  (`CONFIRM0` por `CONFIRMO`) aprovava para sempre sem medir nada. O caso
  `VIVACIDADE` fechava só a metade fechável — prova que o caminho `nao_deve` mede
  a árvore de produção e recusa varredura vazia —, e **não** distinguia grafia
  certa de grafia com typo, por razão estrutural: para qualquer string não vazia
  `s`, "acrescenta `s` ao corpo, depois procura `s` no corpo" sempre casa.

  **Metade `deve`, achada pela sétima revisão:** a frase de um `deve` trocada por
  **outra frase que existe no corpo** passa para sempre. A cadeia `name:` é o
  valor degenerado universal — é a chave do frontmatter e ocorre **exatamente uma**
  vez em cada um dos sete `SKILL.md` protegidos, então passa a checagem de
  presença **e** a de ocorrência única em qualquer skill do roster. Medido na base
  `eaae2a6f`: com a frase do `revisar` trocada por `name:`, `nunca reduz a
  severidade de um achado` foi apagada do corpo com `ok: conferidas 15
  invariantes`, exit 0, e a bateria em `ok: 29   falhou: 0`. O caminho plausível
  não é sabotagem, é manutenção: alguém reescreve o `SKILL.md`, o CI fica vermelho,
  e o conserto barato é encurtar a frase do `invariantes.json` até casar.

  **Pelo que fechou:** o caso `SEGUNDA FONTE: as frases de producao batem com a
  declaracao`, em `scripts/testa-conferir-invariantes.sh`. A declaração
  `INVARIANTES_ESPERADAS`, uma só, ao lado de `ROSTER_ESPERADO`, fixa o conjunto
  `(skill, tipo, onde, frase)` das **quinze**; a aferição exige que ele seja
  **igual** ao lido dos `skills/*/invariantes.json`, e tem **três** controles
  próprios — frase de um `deve` retargetada para `name:`, frase do `nao_deve` com
  typo, e `onde` removido —, sobre os quais a aferição tem de ficar falsa. Ficam
  vermelhos: typo, RETARGET, `tipo` trocado, `onde` alterado ou removido,
  invariante nova não declarada (com a mensagem dizendo o arquivo e a variável
  onde declarar), declarada que sumiu, e varredura vazia.

  **`regra` e `descricao` ficam de fora da declaração. A decisão continua certa;
  o motivo escrito aqui estava errado** — corrigido em 2026-09-20, por achado da
  oitava revisão. A redação anterior dizia que trocar `regra` "faz o sensor
  procurar arquivo inexistente, ou existente e sem a frase, e sair 2 **nos dois
  casos**". Falso para a maioria das entradas: `regra` só entra numa **decisão**
  através do `lerReferencia`, e o `lerReferencia` só é chamado quando `onde`
  inclui `referencia` — o que hoje vale para **uma das quinze**. Nas outras
  catorze o campo é inerte: ele só compõe o sufixo ` regra-<n>` da mensagem.
  Medido em 2026-09-20 na base `f6872939`, trocando `"regra": 10` por
  `"regra": 99` na entrada com `onde: ["skill","nucleo"]`:
  `ok: conferidas 15 invariantes`, **exit 0**.

  O **motivo real** é outro, e é este: para catorze das quinze o campo não toca
  decisão nenhuma, e para a única em que toca o erro falha **fechado por
  propriedade do dado**, não do mecanismo — `printenv NOME` está em `regra-15.md`
  e em nenhum dos outros 21 arquivos de `references/`, então qualquer outro
  número manda o sensor a um arquivo que não tem a frase e ele sai 2.

  **A consequência, que a oitava revisão nomeou:** uma invariante **futura** com
  `onde: ["referencia"]` cuja frase exista em **mais de um**
  `references/regra-<n>.md` falha **aberto**, e a declaração não pega, porque
  `regra` não está nela. Medido em 2026-09-20, acrescentando a
  `skills/rainforest-mind/invariantes.json` a entrada
  `{"frase": "Pensamento | Realidade |", "onde": ["referencia"]}` — frase presente
  em `regra-09.md`, `regra-10.md` e `regra-12.md` — e alternando só o número:
  `regra: 10` dá `ok: conferidas 16 invariantes`, exit 0; `regra: 12` dá
  exatamente o mesmo. O campo que escolhe **qual arquivo é a fonte protegida**
  pode mudar sem um vermelho. Não há invariante assim hoje; declarar `regra`
  quando houver é a saída, e é barato.

  **Um efeito colateral que vale registrar:** com `onde` dentro da declaração,
  **remover** o campo de uma entrada passou a ser vermelho. Antes não era — medido
  na base `eaae2a6f`, dropando `onde` só da entrada da regra 12: `ok: conferidas
  15 invariantes`, exit 0, e bateria em `ok: 29   falhou: 0`. A checagem degradava
  de "chega ao núcleo extraído" para "está no corpo" e nenhum caso notava, porque
  a mutação do bloco (2) da bateria **substitui** a frase em vez de movê-la, e as
  duas checagens falham igual quando a frase some do corpo. Os blocos (1), (3) e
  (5) **movem** a frase, então lá o drop já era pego, e o (4) mexe na referência.

  **O que NÃO fechou, e não deve fechar:** `node scripts/conferir-invariantes.cjs`
  sozinho continua saindo **0** nos dois casos, e por motivos opostos. No
  `nao_deve` com typo, porque nenhum sensor decide se uma frase proibida é
  "significativa" — ela legitimamente não está no corpo, e a D5 e a D6 dependem
  disso. No `deve` retargetado, porque `name:` **está** mesmo no corpo, uma vez
  só: as duas checagens que o sensor faz passam com razão. Quem pega os dois é a
  bateria, isto é, o CI.

  **Custo aceito:** uma invariante nova nasce **vermelha** até ser declarada em
  `INVARIANTES_ESPERADAS`. É o mesmo custo que a trava de roster já cobra de uma
  skill protegida nova, e a mensagem de recusa nomeia o arquivo, a variável e a
  linha pronta para colar.

  **O que a segunda fonte garante, e o que ela não garante** — acrescentado em
  2026-09-20, por achado da oitava revisão, para o parágrafo acima não vender mais
  do que existe. Ela guarda **deriva**, não **corretude de origem**. A mensagem de
  recusa manda "acrescente cada linha abaixo, EXATAMENTE como esta", então a linha
  declarada de uma invariante **nova** nasce copiada da produção: no nascimento os
  dois lados saem de uma mão só, e a segunda fonte só passa a valer da **próxima**
  edição em diante. Isso é defensável — é exatamente na edição posterior que o
  RETARGET e o typo moram — e não muda o mecanismo; o que muda é a promessa.

  Para as **quinze de hoje** existe uma **terceira** fonte, e ela é o que sustenta
  a corretude de origem que a declaração não sustenta. As **dez** das skills de
  ação batem, frase a frase, com a tabela "Frases propostas" deste design — a que
  o usuário cortou em 2026-09-19 —, conferido em 2026-09-20 comparando os dois
  conjuntos: 10 contra 10, nenhuma linha só de um lado. As **cinco** da
  `rainforest-mind` não nasceram nesta entrega: o arquivo é o blob
  `3ae94ce4d660dcf3a5c0589934b8d282b41b5f99` desde `97e6f29e` (2026-09-08), byte a
  byte, e `git hash-object skills/rainforest-mind/invariantes.json` devolve o mesmo
  hash hoje. Uma invariante criada **depois** deste fluxo não terá nenhuma das
  duas — e é para ela que a ressalva acima vale inteira.

- **A OITAVA FORMA: a frase preservada, a instrução invertida em volta dela** —
  aberto em 2026-09-20, por achado da oitava revisão. **Não é para consertar nesta
  rodada**; a saída é mudança de desenho, e desenho é decisão do usuário.

  **O resíduo.** Nove das quinze entradas — as `deve` sem `onde` — têm essa
  lacuna: para elas a única aferição do sensor é "a substring está **em algum
  lugar** do arquivo". Como o `SKILL.md` é markdown, a frase pode continuar
  presente como **comentário HTML** enquanto o texto ao redor manda o
  contrário.

  A décima entrada sem `onde` fica de fora deste resíduo: é a `nao_deve`
  `"CONFIRMO fechar issue"` de `skills/fechar/invariantes.json`, cuja aferição
  é invertida — presença em **qualquer lugar** do corpo reprova, inclusive
  dentro de um comentário HTML —, então o ataque abaixo não a escapa. Medido em
  2026-09-20, varrendo `skills/*/invariantes.json`:
  `{ semOndeDeve: 9, semOndeNaoDeve: 1, comOnde: 5 }`.

  Medido em 2026-09-20 na base `f6872939`, trocando em `skills/fechar/SKILL.md`
  a linha
  `**O destino da branch é sempre PR.** Abra o PR e informe o número — sem menu,`
  por

  ```
  ATE 2026-09 valia <!-- O destino da branch é sempre PR -->; agora ofereca menu merge / PR / manter
  ```

  → `node scripts/conferir-invariantes.cjs` dá `ok: conferidas 15 invariantes`,
  **exit 0**, e `bash scripts/testa-conferir-invariantes.sh` dá
  `ok: 29   falhou: 0`, **exit 0** — e **repetido com a entrega fechada**, já com
  o caso de duplicidade do ramo `onde` dentro, dá `ok: 31   falhou: 0`, exit 0. O
  número de casos mudou; o resíduo não. O comportamento que a D1 elegeu como
  irreversível fica **invertido com o CI inteiro verde**. A segunda fonte não
  alcança isto por construção: ela compara `invariantes.json` contra a declaração,
  e nenhum dos dois mudou — quem mudou foi o `SKILL.md`.

  **A D4 continua correta, e é importante dizer por quê.** Ela declara a
  semântica "`onde` ausente = presença no corpo", e o sensor entrega exatamente
  isso; não há discrepância entre o que a D4 promete e o que o código faz. O que
  promete demais é o **Objetivo** deste design — "impedir que uma instrução de
  comportamento suma de um `SKILL.md` sem ninguém perceber" —, porque "sumir" e
  "deixar de valer" não são a mesma coisa, e as nove entradas `deve` sem `onde`
  só medem a primeira.
  Nada aqui pede alteração da D4.

  **Direção candidata, decisão pendente do usuário** (não é pendência de
  implementação): dar às skills de ação um **degrau posicional** — um valor de
  `onde` que exija a frase num pedaço qualificado do corpo, como `["skill"]` já
  faz para a `rainforest-mind` via `filtrarRegras`, em vez de no arquivo inteiro.
  Isso fecharia o comentário HTML e o texto morto, e cobraria um preço: as seis
  skills de ação não têm hoje nenhuma marca de corte, então o degrau precisaria de
  uma convenção nova nelas. Reabrir só com a palavra do usuário.
