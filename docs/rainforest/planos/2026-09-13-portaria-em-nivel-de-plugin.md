# Plano: a portaria vale em todo repo, com manifesto padrão embarcado

Design: docs/rainforest/design/2026-09-13-portaria-em-nivel-de-plugin.md

Medições feitas antes de escrever este plano:

```
resolverRaiz desta árvore          <home>/.rainforest   (nível `global`)
resolverRaiz de um repo cliente    <home>/.rainforest   (nível `global`)
ehRaiz('.rainforest') deste repo   false  (sem FOCO.md nem ideias.jsonl)
resolverRaiz com RFM_ROOT          honra RFM_ROOT (nível 1 da cadeia)
quem lê o manifesto hoje           só hooks/portaria.cjs (:496 runtime, :1121 lint)
quem lê despachos.jsonl em código  ninguém — só baterias e documentação
baterias que afirmam "manifesto ausente → nega"   4
portaria registrada hoje           .claude/settings.json:9, matcher Task|Agent
hooks.json PreToolUse hoje         8 hooks, nenhum é a portaria
```

## O que não pode quebrar

- A portaria continua **fail-closed**. Agente não declarado, `escreve: true` sem
  `isolation: "worktree"` e ausência de estágio continuam negando. O que muda é
  onde o manifesto é lido, nunca o que ele decide.
- Toda negação continua com **motivo não vazio**.
- A admissão por autorização explícita do usuário (PR #246) continua valendo
  exatamente como está: dispensa o portão de **estágio** e nada mais.
- Nenhuma bateria fica vermelha ao fim. As quatro da tarefa 5 mudam de
  asserção **no mesmo lote** em que o comportamento muda — nunca depois.
- Nenhum teste escreve na pasta de dados real do usuário. Isolamento por
  `RFM_ROOT`, que é o nível 1 de `resolverRaiz`.
- O plugin continua funcionando quando é o próprio repo aberto (auto-hospedado).

## Tarefas

### 1. Manifesto padrão versionado no plugin [tipo: criar]
atende: D2, D4
arquivos: `.rainforest/agentes.padrao.json`, `.rainforest/agentes.json` (removido), `.gitignore`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `.rainforest/agentes.padrao.json`
  de: `"estagios": ["revisar"]` (do `revisor`)
  para: `"estagios": []`
  bateria: `node hooks/testa-portaria-nucleo.cjs`
  fixture: caso do `revisor` admitido no estágio `revisar`
pronto quando: `.rainforest/agentes.json` não existe mais e `git ls-files .rainforest/agentes.padrao.json` devolve o caminho; `node -e "const m=require('./.rainforest/agentes.padrao.json'); console.log(m.versao, Object.keys(m.agentes).length)"` devolve `1 12`; e `git check-ignore .rainforest/agentes.padrao.json` sai **1** (não ignorado)

### 2. Busca do manifesto em dois níveis, repo substituindo o padrão [tipo: implementar]
atende: D2, D3
arquivos: `hooks/portaria.cjs`
depende de: 1
paralela: não
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `path.resolve(__dirname, "..", ".rainforest", "agentes.padrao.json")`
  para: `path.resolve(__dirname, "..", ".rainforest", "agentes.json")`
  bateria: `node hooks/testa-portaria-manifesto.cjs` (tarefa 6)
  fixture: caso "repo sem manifesto próprio usa o padrão embarcado"
pronto quando: num diretório temporário **sem** `.rainforest/`, um despacho do `revisor` com estágio `revisar` ativo é **admitido** citando o padrão; no mesmo diretório com um `.rainforest/agentes.json` que declara só o `executor`, o mesmo despacho do `revisor` é **negado** com `não consta no manifesto` — provando substituição, não soma

### 3. Registro no hooks.json e saída do settings.json [tipo: configurar]
atende: D1
arquivos: `hooks/hooks.json`, `.claude/settings.json`, `hooks/testa-portaria-portoes.cjs`
depende de: 2
paralela: não
mutacao:
  arquivo: `hooks/hooks.json`
  de: `"matcher": "Task|Agent"`
  para: `"matcher": "Bash"`
  bateria: `bash hooks/testa-portaria.sh`
  fixture: caso do despacho de `Task` passando pela portaria
pronto quando: `node hooks/testa-portaria-portoes.cjs` fecha o portão **P6** (`registro:alcance`); e `grep -c portaria .claude/settings.json` devolve **0**

> **Correção de 2026-09-14, ao exercitar esta mutação:** ela **não matava nada**.
> Trocar o matcher por `"Bash"` deixava `hooks/testa-portaria.sh` inteiro
> **verde**, exit 0 — porque todas as 10 baterias invocam `portaria.cjs` como
> processo, direto, e nenhuma perguntava se o harness chegaria a invocá-lo. A
> decisão que a portaria toma estava coberta em 307 casos; o fato de ela ser
> **chamada** — que é a D1 inteira, e o motivo deste fluxo existir — não estava
> coberto em nenhum. Gate desarmado passa em todo teste que só mede o gate.
>
> O critério original também não servia: era um `node -e` colado aqui, que
> ninguém roda de novo depois do `fechar`. Vira portão **P6** em
> `testa-portaria-portoes.cjs`, com quatro afirmações que o `node -e` não fazia:
> o matcher casa `Task` **e** `Agent`; **não** casa `Bash`/`Read`/`Write` (largo
> demais faria a portaria decidir sobre trabalho que ela não governa); o comando
> resolve por `CLAUDE_PLUGIN_ROOT` e não por `CLAUDE_PROJECT_DIR` (é a diferença
> entre valer em toda sessão e valer só onde o arquivo existir); e o
> `.claude/settings.json` não registra a portaria de novo, o que duplicaria cada
> linha da trilha. Com o P6, a mutação sai exit 1.

### 4. Log de despacho resolvido pela raiz de dados, com o repo em cada linha [tipo: implementar]
atende: D6, D8
arquivos: `hooks/portaria.cjs`
depende de: 2
paralela: não
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: a resolução por `resolverRaiz`
  para: `const base = raiz;` (volta a gravar no projeto)
  bateria: `node hooks/testa-portaria-log-fora-do-repo.cjs` (tarefa 6)
  fixture: caso "log de um repo sem `.rainforest` não cria pasta no repo"
pronto quando: com `RFM_ROOT` apontando para caixa de areia, um despacho num repo temporário grava em `<RFM_ROOT>/portaria/despachos.jsonl` e **não** cria `<repo>/.rainforest/`; a linha gravada tem o campo `repo` com o caminho do repo temporário; e forçar erro de escrita (raiz apontando para caminho não-gravável) imprime a falha no **stderr** sem mudar o exit code da decisão

### 5. As baterias que afirmam "manifesto ausente → nega" [tipo: testar]
atende: D5
arquivos: `hooks/testa-portaria-nucleo.cjs`, `hooks/testa-portaria-autorizacao.cjs`, `hooks/testa-portaria-diagnostico.cjs`, `hooks/testa-portaria-gitignore.cjs`, `hooks/testa-portaria-captura.cjs`, `hooks/testa-portaria-portoes.cjs`, `hooks/testa-portaria-tools-bloco.cjs`, `hooks/portaria.cjs`
depende de: 2, 4
paralela: não
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: o `throw` de padrão embarcado ausente
  para: `gravarDespacho(raiz, "deny", ...)` seguido de `negar(...)`
  bateria: `node hooks/testa-portaria-nucleo.cjs`
  fixture: caso "padrão embarcado ausente não grava linha no log"
pronto quando: as quatro saem exit 0; `node hooks/testa-portaria-nucleo.cjs` tem um caso que apaga o padrão embarcado numa cópia e exige **exit 2 com stderr citando o padrão do plugin e NENHUMA linha nova no log** — não o exit code, que é 2 nos dois casos; e `testa-portaria-gitignore.cjs` passa a afirmar que o log **não aparece** em `git status --porcelain` do repo porque não é escrito lá, não porque está ignorado

> **Correção de 2026-09-14, durante o `executar`:** o critério original cobrava
> "**exit 2** com motivo citando o padrão, não `deny`", e a mutação invertia "o
> `exit 2` de padrão ausente" para `negar(...)`. As duas frases supõem que
> negação e exit 2 sejam saídas diferentes. `hooks/portaria.cjs:175` mostra que
> `negar()` **é** `process.exit(2)` — a mutação original não mudaria o exit
> code, e o critério teria passado com o bug dentro. Critério e mutação passaram
> a cobrar o que de fato distingue os dois caminhos: **linha no log e destino da
> mensagem**. Ver a correção da D5 no design.

> **Segunda correção de 2026-09-14:** a medição do design contou **4** baterias
> que afirmam "manifesto ausente → nega"; rodadas uma a uma depois da tarefa 3,
> **6** ficaram vermelhas. As duas que faltavam:
> `testa-portaria-captura.cjs` (a amostra de payload deixou de ser escrita em
> repo que não é o próprio plugin) e `testa-portaria-portoes.cjs` (procura o log
> em `<repo>/.rainforest/`, que a D6 mudou). Entram em `arquivos:` agora, não
> quando o `marcar` recusar.
>
> Uma sétima entrou por outro caminho, e vale registrar como se achou:
> `testa-portaria-tools-bloco.cjs` ficou **verde o tempo todo** e mesmo assim
> despejava 15 linhas por execução em `<home>/.rainforest/portaria/` — a pasta
> pessoal do usuário. Só apareceu porque a linha "nenhum teste escreve na pasta
> de dados real" de **O que não pode quebrar** foi conferida olhando a pasta, e
> não deduzida do placar. Passar nas asserções e não sujar o ambiente do usuário
> (regra 15) são coisas independentes; as seis vermelhas escondiam a sétima,
> porque quem olha placar só vê quem falha. Total medido antes do conserto: 53
> linhas de teste na pasta pessoal, removidas.
>
> `hooks/portaria.cjs` também entra: a tarefa 2 tornou **inalcançável** o bloco
> `if (!fs.existsSync(manifestoPath))` — os dois ramos de `usandoPadrao` já
> conferem existência antes. Deixá-lo lá é dizer no código que "repo sem
> manifesto nega", que é o que deixou de ser verdade. O diagnóstico que ele
> carregava (`raiz lida`, `branch`, outros worktrees) já existe igual nas
> negações por **sem estágio ativo**; a metade que não existia em lugar nenhum —
> **qual** dos dois manifestos foi lido — passa para a negação por
> `não consta no manifesto`.

### 6. Baterias novas: busca do manifesto e log fora do repo [tipo: testar]
atende: D2, D3, D6
arquivos: `hooks/testa-portaria-manifesto.cjs`, `hooks/testa-portaria-log-fora-do-repo.cjs`
depende de: 2, 4
paralela: não
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: o `negar` de manifesto de repo inválido
  para: cair no padrão embarcado em vez de negar
  bateria: `node hooks/testa-portaria-manifesto.cjs`
  fixture: caso "manifesto de repo inválido nega, não cai no padrão"
pronto quando: as duas saem exit 0 e cada uma cobre, com caso próprio: repo sem manifesto usa o padrão; repo com manifesto substitui; manifesto de repo inválido nega (não cai no padrão); log vai para a raiz resolvida; repo com `.rainforest/FOCO.md` mantém o log local (a divergência declarada na D6)

### 7. Registro do escopo no `/setup` e na regra 10 [tipo: documentar]
atende: D7
arquivos: `skills/setup/SKILL.md`, `skills/rainforest-mind/references/regra-10-portaria.md`, `skills/rainforest-mind/references/regra-10-portaria-escopo.md`, `skills/rainforest-mind/references/regra-10.md`
depende de: 3
paralela: não
mutacao: n/a
  motivo: a entrega é texto de skill e de referência; inverter uma linha de prosa não muda veredito de bateria nenhuma. Quem falsifica este par é a tarefa 8, que mede o comportamento que o texto descreve.
> **Correção de 2026-09-14, no `revisar`:** as adições ao
> `regra-10-portaria.md` estouraram a catraca de `reference` — 10247 B viraram
> 13342, contra teto de 10500. A catraca não é de estilo: ela existe para que
> consultar uma regra custe menos de 3k tokens (D9/issue #73), e foi a varredura
> das 115 baterias que a pegou, não o critério desta tarefa, que só cobrava
> `grep`. A resposta é a da própria casa, registrada no cabeçalho do arquivo:
> **partir**, como o `regra-10-portaria.md` nasceu do `regra-10.md`. O escopo, a
> precedência entre os dois manifestos e o destino do log saem para
> `regra-10-portaria-escopo.md`; o que fica é a regra operativa com ponteiro.
> `regra-10.md` entra junto porque a frase dele — "declarado em
> `.rainforest/agentes.json`" — apodreceu pela mesma mudança.
>
> **Folga de 19 B.** O `regra-10-portaria.md` fica a 10481 B de um teto de
> 10500: a próxima linha que alguém acrescentar ali estoura de novo. É o preço
> de não reescrever conteúdo histórico que este fluxo não veio mexer — e o
> sibling existe agora justamente para receber o que crescer.

> **Segundo achado do `revisar`:** o default do `--lint` ficou incoerente
> consigo mesmo. A tarefa 2 mudou o manifesto default para o caminho absoluto do
> padrão embarcado e deixou `agentesDir` como `"agents"`, relativo — e relativo
> resolve contra `raizDoProjeto()`. Rodado de qualquer outro repositório,
> `--lint` sem argumentos lia o manifesto do plugin e procurava os `.md` no
> `agents/` alheio: medidos **9 erros** de "declarado no manifesto mas sem
> arquivo" e **exit 1**, num manifesto correto. Antes da mudança os dois eram
> relativos, e por isso coerentes; o defeito nasceu de mover um par pela metade.
> Três casos novos em `hooks/testa-portaria-lint.cjs` (28 → 31), incluindo o
> controle de que o veredito de fora é o mesmo de dentro; a mutação de volta
> para `"agents"` mata os três.

pronto quando: `grep -c 'agentes.padrao.json' skills/setup/SKILL.md` devolve ≥1; a seção "O que este setup NÃO faz" diz que ele **não instala** manifesto porque o padrão vem embarcado; e `regra-10-portaria.md` deixa de dizer que a portaria depende de registro no `settings.json` do projeto

### 8. Fechar o critério da #241 com o fato, não com a frase [tipo: verificar]
atende: D1, D6
arquivos: nenhum (medição)
depende de: 3, 4, 5, 6, 7
paralela: não
mutacao: n/a
  motivo: a tarefa NÃO escreve código — ela roda o critério da #241 contra um repo de teste real. O que ela mede já está sob as mutacoes das tarefas 2, 4 e 6; uma mutacao própria aqui mediria o próprio comando de medicao.
pronto quando: num repositório de teste recém-criado fora deste, com `RFM_ROOT` em caixa de areia, um despacho de subagente produz uma linha no log resolvido com `repo` igual ao caminho desse repositório — **e não** um arquivo em `<repo>/.rainforest/portaria/despachos.jsonl`; `gh issue view 241` é comentada com o comando e a saída colados

### 9. Bump de versão [tipo: configurar]
atende: nenhuma decisão — exigência de release
arquivos: `.claude-plugin/plugin.json`, `README.md`, `scripts/conferir-versao.cjs`, `scripts/testa-conferir-versao.sh`
depende de: 8
paralela: não
mutacao: n/a
  motivo: subir dois literais de versao nao tem comportamento a inverter. A catraca que morde aqui ja existe e e outra: `scripts/conferir-versao.cjs` recusa versao que nao supera a da origin/main, e `scripts/testa-versao.sh` recusa numero divergente entre plugin.json e README.
pronto quando: `node scripts/conferir-versao.cjs` sai 0 com versão **MINOR** acima da `origin/main` (entrou capacidade: portão em toda sessão), e `bash scripts/testa-versao.sh` sai 0

> **Correção de 2026-09-14, durante o `executar`:** a catraca recusou este bump
> com *"6 commits desde o bump, e o teto é 5"* tendo a branch **cinco** seus. O
> sexto era `fdc0a28f`, o commit de **merge** do PR #246 — aquele que *entregou*
> o bump 1.13.1 na `main`. O bump nasce numa branch de fluxo e chega por merge,
> então ele é **segundo pai**; `--first-parent` o pula e conta o merge no lugar
> dele. Como todo bump chega assim, o teto efetivo era o declarado **menos um**,
> para todo fluxo, sempre.
>
> É a mesma família do defeito que `8025a18b` consertou ontem — contagem
> inflada por escrituração de merge — e é defeito de ferramenta que apareceu na
> frente do trabalho, então foi consertado na hora em vez de plantado:
> `scripts/conferir-versao.cjs` passa a ancorar a contagem no ponto em que o
> bump **alcançou** a linha de primeiro pai (o próprio bump quando está nela, o
> merge que o trouxe quando não está). Dois casos novos em
> `scripts/testa-conferir-versao.sh`, mais um simétrico que impede a âncora de
> passar a subtrair um de todo mundo; a mutação `const ancora = bump` deixa os
> dois primeiros vermelhos, errando por exatamente 1.
>
> O `>=` do teto foi olhado e **não** é defeito: `teto 7 com 7 commits: recusa`
> é caso testado desde antes. "Teto 5" quer dizer menos de 5, e continua
> querendo.

## Ordem

1 e depois 2 são o caminho crítico: sem manifesto padrão achável, a tarefa 3
transforma toda sessão do usuário numa sessão sem subagente. **A 3 não entra
antes da 2 estar verde** — é a única ordem em que um erro no meio não deixa a
máquina dele pior que antes.

4, 5, 6 e 7 dependem de 2 mas não entre si, exceto 5 e 6, que se encostam nas
mesmas baterias. 8 é o portão do `verificar`. 9 fecha.
