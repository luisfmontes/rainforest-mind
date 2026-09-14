# Portaria de subagente vale em todo repo, como a regra 10 promete

## Objetivo

Fechar a decisão D10 da Issue #241, tomada pelo usuário em 2026-09-13: *"o certo
é funcionar para todos os repos como a regra 10 diz"*.

Hoje a portaria roda **só neste repositório**. Está registrada no
`.claude/settings.json` daqui, apontando para `$CLAUDE_PROJECT_DIR/hooks/portaria.cjs`,
e o `hooks/hooks.json` do plugin não a registra em `PreToolUse` nenhum. A regra 10
— injetada em toda sessão — diz "rodar exige manifesto + estágio ativo" como se
valesse em qualquer lugar. É a opção (2) na prática e a (1) no texto.

O texto não encolhe para caber na realidade. A realidade sobe para caber no texto.

## Decisões fechadas

- **D1 — A portaria é registrada no `hooks/hooks.json`, com matcher `Task|Agent`,
  e sai do `.claude/settings.json` deste repo** — porquê: é o único lugar que
  alcança toda sessão em que o plugin está habilitado, que é o que a regra 10
  promete. A saída do `settings.json` não é limpeza: sem ela a portaria roda
  **duas vezes** neste repositório, e um gate que decide duas vezes sobre o mesmo
  despacho tem duas chances de divergir.

- **D2 — Existe um manifesto padrão versionado no plugin, achado por
  `path.resolve(__dirname, '..', '.rainforest', 'agentes.padrao.json')`** —
  porquê: registrar a portaria sem isso nega tudo em todo lugar. Medido: com
  manifesto ausente o código cai em `hooks/portaria.cjs:499` e nega com
  `manifesto ausente`; num repo qualquer, todo despacho de subagente passaria a
  ser recusado. O padrão é pré-requisito da D1, não acessório dela.

  **Por `__dirname` e não por `CLAUDE_PLUGIN_ROOT`**: o harness expande essa
  variável **na string do comando** do `hooks.json`. Contar com ela no `env` do
  processo é suposição não medida, e o custo de estar errado é o gate morrer em
  toda sessão. `__dirname` é fato do processo. O `hooks/lib/raiz.cjs` já usa
  exatamente esta forma para achar a raiz do plugin (`path.resolve(__dirname,
  '..', '..')`).

- **D3 — O manifesto do repo SUBSTITUI o padrão por inteiro; não soma** —
  porquê: merge apaga a diferença entre *não declarei* e *declarei e tirei*, e é
  justamente essa diferença que o portão decide. Um repo que quer barrar o
  `executor` teria de conseguir barrá-lo; com merge, ele voltaria pelo padrão.
  Substituição também torna o manifesto legível sozinho: o que está no arquivo é
  o que vale, sem precisar simular a fusão de cabeça.

- **D4 — O `.rainforest/agentes.json` deste repositório é APAGADO** — porquê:
  medido, ele não tem nada deste repositório. São os 9 agentes nativos do plugin
  mais `Explore`, `general-purpose` e `claude-code-guide` — já é o manifesto
  padrão vestido de manifesto de repo. Como o plugin é auto-hospedado aqui,
  `__dirname` resolve para esta própria árvore e o padrão **é** o arquivo.
  Manter os dois é manter duas cópias da mesma lista genérica, que divergem.

- **D5 — "manifesto ausente" muda de significado, e o código tem de mudar junto**
  — porquê: com um padrão embarcado, ausência em produção não é "o repo não foi
  configurado", é **o plugin está quebrado**. Repo sem manifesto próprio passa a
  ser o caso **normal**, não o caso negado.

  Quatro baterias hoje afirmam o contrário e precisam ser reescritas junto, não
  depois: `testa-portaria-nucleo.cjs:217`, `testa-portaria-autorizacao.cjs:547`,
  `testa-portaria-diagnostico.cjs:111` e `testa-portaria-gitignore.cjs:12`.

  > **Correção de 2026-09-14, durante o `executar`.** A redação original desta
  > decisão dizia: *"Isso não é negação com motivo: é falha interna, exit 2,
  > pela mesma rede que já converte erro de resolvedor"* — como se negação e
  > exit 2 fossem saídas diferentes. **São a mesma.** `hooks/portaria.cjs:175`:
  > `negar()` termina em `process.exit(2)`, e o contrato de hook do Claude Code
  > é que **exit 2 barra**, exit 0 passa e **qualquer outro código é erro
  > não-bloqueante — a tool call segue**. Isso está escrito no próprio arquivo,
  > em 30 linhas de comentário sobre o defeito da rodada 6 do fluxo anterior,
  > em que sair 1 por exceção deixou despacho passar em silêncio. Eu decidi sem
  > ler essas linhas.
  >
  > O que a decisão queria continua de pé, e é o que foi implementado. A
  > distinção não é de exit code — é de **duas outras coisas**:
  >
  > 1. **o log não registra como política o que é falha de instalação.** Uma
  >    linha `deny` sobre o `revisor` diria que houve decisão sobre aquele
  >    agente; não houve.
  > 2. **a mensagem aponta para o plugin, não para o repo do usuário**, que não
  >    tem nada a consertar.
  >
  > Implementado sem caminho novo: padrão ausente faz `throw`, e a rede que já
  > existe no topo do arquivo converte em exit 2 com "falha interna" e sem linha
  > no log. O mecanismo já estava lá — o erro foi inventar um segundo.

- **D6 — O log de despacho sai do repositório, resolvido por
  `hooks/lib/raiz.cjs`, com o caminho do repo em cada linha** — porquê: hoje
  `gravarDespacho` escreve em `<projeto>/.rainforest/portaria/despachos.jsonl`.
  Aqui isso está no `.gitignore`; num repo de cliente, não — viraria pasta não
  rastreada aparecendo no `git status` de outra pessoa. A regra 15 diz que
  ninguém altera o ambiente do usuário, e sujar repo alheio é a versão pequena
  disso.

  **Usando `resolverRaiz` em vez de um caminho fixo**, porque ele já existe, já
  é testado e já responde certo. Medido desta árvore e de um repo de cliente:
  os dois devolvem `<home>/.rainforest` (nível `global`) — que é o destino que o
  usuário pediu, obtido por mecanismo em vez de por constante. E `RFM_ROOT` é o
  nível 1 da cadeia, então bateria se isola apontando para caixa de areia, sem
  nunca escrever na pasta pessoal de verdade.

  **A divergência, declarada:** um repositório que tenha o próprio `.rainforest/`
  com `FOCO.md` ou `ideias.jsonl` mantém o log lá. Isso não é escape — é um repo
  que **optou** por ter dados próprios do rainforest, e o log acompanha a raiz
  que governa. Medido: o `.rainforest/` deste repo **não** qualifica (não tem
  marcador), então nem aqui o log fica no repositório.

- **D7 — `skills/setup/SKILL.md` passa a citar o manifesto** — porquê: é metade
  do critério de pronto que a própria #241 escreveu. Com o padrão embarcado o
  `/setup` não precisa **instalar** nada; precisa dizer que o portão existe, onde
  está o padrão, e como um repo o substitui. Contar que existe um portão é parte
  de instalar um portão.

- **D8 — Falha ao gravar o log passa a aparecer no stderr** — porquê:
  `gravarDespacho` engole erro de escrita num `catch` vazio. Enquanto o log era
  um arquivo ignorado do próprio repo, uma linha perdida era uma linha perdida.
  Depois da D6 ele é a **única** trilha de auditoria que atravessa repositórios,
  e perder linha em silêncio é pior que não ter trilha — porque parece ter. A
  escrita continua não-fatal (log ilegível não pode barrar trabalho), mas deixa
  de ser calada.

## Avaliado e descartado

- **Um terceiro nível de manifesto, na raiz de dados do usuário, entre o repo e
  o padrão.** A cadeia do `hooks/lib/config.cjs` tem exatamente essa forma
  (projeto, depois usuário), e seria coerente. Descartado porque o usuário
  escolheu entre "o do repo substitui" e "soma" — um nível a mais é decisão que
  ele não tomou, e enfiá-la aqui em silêncio é o erro de método já registrado em
  `obs-2026-09-12-afirmei-alcance-do-plugin-sem-medir`. Fica como pergunta para
  depois, se um repo precisar.

- **`resolverRaiz` nível 4 (raiz do plugin) para achar o padrão.** Não dispara:
  medido, `ehRaiz('.rainforest')` do plugin é `false` porque não há `FOCO.md` nem
  `ideias.jsonl` lá. Usar a cadeia para isso seria depender de um nível que nunca
  responde.

- **Deixar o `.claude/settings.json` como está e só adicionar ao `hooks.json`.**
  Menos diff, e portaria rodando duas vezes aqui. Um gate idempotente sobreviveria;
  este grava log a cada decisão, e duplicaria cada linha da trilha de auditoria
  no único repositório onde ela é mais lida.

- **`merge` de manifesto com o repo podendo remover por `null`.** Resolve a
  objeção da D3 e cria outra: um manifesto de repo passa a só ser legível ao lado
  do padrão da versão instalada do plugin. O arquivo deixaria de dizer o que vale.

## Fora de escopo

- **Issue #249** (o laço das 114 baterias só existe no YAML da CI). Causou o
  retrabalho de hoje, mas é ferramenta de teste, não portaria.
- **Issue #244** (bump de versão manual, sem check de CI).
- **Qualquer mudança no que a regra 10 exige.** Manifesto + estágio ativo
  continua sendo a regra; o que muda é onde ela vale. Repo sem fluxo continua
  sem estágio, e lá o caminho é a autorização explícita do usuário — que entrou
  na `main` no PR #246 e não se altera aqui.

## Em aberto

- **O critério de pronto da #241 aponta para o lugar errado depois da D6.** Ele
  diz que um despacho aparece em `.rainforest/portaria/despachos.jsonl` do repo
  de teste; depois da mudança, não aparece — o log resolve para a raiz de dados.
  O critério é corrigido **aqui, no design**, antes de virar tarefa: o fato a
  conferir é uma linha com `repo: <caminho do repo de teste>` no log resolvido.
  Corrigir isso no `verificar` seria repetir a podridão da tarefa 9 do fluxo
  anterior, que cobrava uma frase em vez de um fato.

- **O que executa na máquina do usuário ainda é o cache 1.11.0.** Nada disto
  vale para ele até `claude plugin marketplace update` e uma janela nova. É ação
  dele, não do fluxo, mas o `fechar` deve dizer isso em voz alta em vez de deixar
  a entrega parecer ativa.
