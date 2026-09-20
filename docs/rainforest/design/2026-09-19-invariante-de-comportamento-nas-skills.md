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

- **D2 — O mecanismo é o `conferir-invariantes.cjs` estendido, não um script novo** — porquê: ele já lê `skills/rainforest-mind/invariantes.json`, já confere 5 frases das regras 10, 11, 12, 13 e 15, já tem bateria própria com mutantes em `scripts/testa-conferir-invariantes.sh` — **eram cinco blocos, não dois, e nenhum deles media nada**, corrigido em 2026-09-20 por achado da revisão: a caixa compartilhada nunca copiava `references/`, então a árvore já saía `exit 2` antes da primeira mutação e os cinco ficariam vermelhos com a mutação sendo no-op; hoje cada bloco monta a **sua** caixa, com `references/` dentro, e tem a **sua** asserção de linha de base imediatamente antes da mutação (ver a nota de 2026-09-20 abaixo) — e essa bateria já é descoberta pelo glob `scripts/testa-*.sh` do `varrer-baterias.sh`, que o CI roda em Node 22 e 24. Estender herda CI de graça; script novo teria de reconquistar tudo isso e criaria um segundo lugar onde a mesma regra mora.

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

- **D7 — As 5 invariantes da `rainforest-mind` migram para o formato novo** — porquê: dois formatos convivendo fazem o segundo nascer como exceção, que é como este repo já descreveu dívida antes. O risco é real e foi pesado: aquele arquivo está verde, tem mutantes (cinco blocos, não dois — ver a correção na D2) e roda no CI em dois Node. A D4 é o que torna a migração barata — o formato novo é superconjunto do atual, então a migração é acrescentar campo, nunca reescrever os cinco registros.

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
mesmo achado da sessão: `git add -A` é **proibido` no `fechar` e `Git destrutivo
proibido` no `executar` já têm gate de `PreToolUse` por trás. Proteger a prosa
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

## Fora de escopo

- Escrever invariante para as outras treze skills.
- Mudar o mecanismo de corte `<!-- detalhe -->` ou o tamanho da injeção.
- Mexer na âncora de bytes de `scripts/testa-plugin-codex.cjs`, que vive na entrega multihost e responde outra pergunta — se o corpo mudou. As duas convivem.
- Implementar `nao_deve` para qualquer frase além de `CONFIRMO fechar issue` nesta rodada.

## Em aberto

- Se a cobertura passar de seis skills, reabrir a D3 (arquivo por skill contra arquivo central).
- Nenhuma outra: a fronteira esvaziou em duas rodadas.
