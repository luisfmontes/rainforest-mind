# Notas de atualização

O que mudou em cada versão publicada, do ponto de vista de quem **usa** o plugin —
não o log de commits. A versão instalada aparece em `/plugin` → Installed Plugins,
e atualizar é `/plugin` → Browse Plugins → Update Marketplace, depois Update no
`rainforest-mind`.

Este arquivo começa na **1.19.0**. As versões anteriores não têm notas escritas: o
que existe delas é o commit de release (`git log --grep="^Versao "`), e reescrever
29 releases de memória produziria nota bonita e errada. Versão nova daqui em diante
entra aqui no mesmo commit que sobe o `version` do `plugin.json`.

## 1.47.2 — 2026-10-08

- **Painel do mod confere de novo o que ainda não tinha resposta.** Escrever um arquivo antes de o plano existir
  e reescrevê-lo depois agora checa o desvio na reescrita; antes o "sem plano" ficava guardado e o arquivo
  fora do plano passava sem aviso. Um arquivo cuja checagem falhou e depois respondeu aparece uma vez só no
  mapa, e uma sessão `claude -p` aberta ao lado não zera mais a memória da sua sessão.

## 1.47.1 — 2026-10-07

- **Pasta com acento não acusa mais creep falso.** Num repo com caminho acentuado (`Transferencia Serviço/`),
  o `marcar revisar` recusava por "arquivo no diff sem tarefa correspondente": o git devolve o nome escapado em
  octal e o plano o traz em UTF-8. As listagens de caminho do fluxo (`conferir-fluxo`, `estado`, `conferir-entrega`,
  `conferir-versao`, `conferir-publicacao`) passam a pedir o nome literal ao git, sem mexer na sua config.

## 1.47.0 — 2026-10-07

- **Erros de ferramenta ficam registrados.** O "Erros N" do mod zerava com a sessão. Agora cada falha (comando que
  falhou, gate que bloqueou, permissão negada) vira uma linha em `~/.rainforest/erros.jsonl` na hora, com pasta,
  ferramenta, comando e o começo da mensagem — inclusive em janela fechada no X. `/painel erros [horas]` lista
  as últimas 24 h agrupadas por tipo, e o `/saude` avisa quantas houve.

## 1.46.2 — 2026-10-07

- **Janela fechada sai do relógio.** O `⏰ … parada há` mostrava janela que já tinha sido fechada no X — inclusive
  a da outra conta, que divide o `sessoes.json` — por até 6 h. O heartbeat agora grava o PID da sessão (lido do
  registro do próprio Claude Code em `<config dir>/sessions/`), e janela com processo morto some na hora.

## 1.46.1 — 2026-10-07

- **"Deixado para depois" fecha o que se resolveu.** O segundo modelo passa a receber os itens abertos e
  diz quais o turno resolveu — por ferramenta, pelo relato ou pela sua resposta — e esses saem da lista e da
  contagem da barra. Roda em todo turno com item aberto, mesmo sem ferramenta.
- **Pergunta de decisão não é pendência.** Turno que termina com `Q1.`, `Q2:`… para você não gera item: a
  linha `Q` sai da varredura de frases e o segundo modelo não anota pendência nova nesse turno.
- **`/painel limpar`** zera a lista, como o botão "Limpar tudo".

## 1.46.0 — 2026-10-07

Fecha as Issues #409 a #414, #417 e #419, e retira o contorno da política de segurança em conta de organização.

- **Pastas de docs do repositório (#412).** Mapa da arqueologia, design e plano passam a seguir a pasta que o
  repositório já usa: `docs/legado/` quando existe `docs/legado/COBERTURA.md` (o mapa entra com uma linha por
  fatia no índice que já existe), `docs/plans/` quando lá há `*-design.md` ou `*.gates.json` (design e plano com
  sufixo `-design.md`/`-plano.md`), ou o que a chave nova `pastas` do `.rainforest/config.json` disser. Sem nada
  disso, `docs/rainforest/` como sempre. `node scripts/pastas-docs.cjs caminho --tipo <t> [--slug <s>]` diz onde.
  Estado, portões, réguas e varredura continuam em `docs/rainforest/`. O estado passa a ler o caminho do design
  que o brainstorm grava (`doc`).
- **Desligar gate: só `RAINFOREST_GATE_OFF` ou a chave do config (#417).** O arquivo `.rainforest-gate-off` deixou
  de ser lido por qualquer gate; se você usava, troque por `node scripts/setup.cjs --desligar <gate> --escopo
  projeto`. O `gate-git-verificacao` não oferece mais a saída a subagente.
- **Config de projeto em worktree (#411).** `.rainforest/config.json` é lido da raiz do checkout principal, também
  de dentro de `.claude/worktrees/*` ou de um subdiretório, e `setup --escopo projeto` grava lá.
- **Repo privado fora do GitHub (#419).** Com `"visibilidade-repo": "privada"` no config **do projeto**, o gate de
  publicação deixa de barrar termos da sua lista privada quando o `gh` não sabe a visibilidade (GitLab, por
  exemplo). Telefone, JID, CPF e credencial continuam barrando, e a declaração não vale com remoto GitHub.
- **Gate de publicação (#409, #410).** Pseudo-versão de módulo Go em `go.mod`/`go.sum` não é mais telefone, e
  `Authorization` com `Bearer`/`Basic`/`Token` seguido de referência de variável (`f"Bearer {KEY}"`, `.format(KEY)`,
  `${KEY}`) não é mais credencial. Literal depois do esquema continua barrado.
- **`gate-fechar-issue` (#414).** `. arquivo`/`source arquivo` lê o arquivo e só barra se ele fecha Issue: carregar
  `.env` com `set -a; . x.env; set +a` passa.
- **`verificar --raiz <dir>` (#413).** Quando o código vive noutro worktree que não o do estado (PR para upstream),
  `estado.cjs marcar --estagio verificar --raiz <worktree>` roda as mutações lá.
- **Conta de organização.** Em conta com o plugin gerenciado `cc-plugin-sec-default`, o mod da abertura não entrega
  mais as regras inteiras como mensagem de usuário: a política da organização barra o system prompt de plugin de
  usuário, e contorná-la saiu. Nessa conta as regras chegam pelo núcleo do SessionStart; para as regras inteiras,
  peça ao admin da organização a liberação do plugin.

## 1.45.0 — 2026-10-07

Uma barra de sessão acima do prompt e um painel que abre sob demanda.

- **A barra entra no lugar da faixa.** Foco, fluxo e Q saem da linha acima do prompt, porque você as
  ignorava; o relógio ⏰ (jornada e janela parada) fica, agora como uma figura da barra, e a nota da
  regra 8 segue como estava. A barra mostra estado (trabalhando ou pronto), tokens, custo, contexto de 0
  a 100, cache (quente ou frio, com a estimativa do reenvio), itens deixados, ferramentas por minuto,
  subagentes, turnos e erros; cada figura entra se couber no que sobra, então o corte não é contíguo, e o ⏰
  é o último a cair.
- **`/painel` abre o pane** com os fluxos em curso, o mapa da sessão, o contexto por fatia, o cache, os
  subagentes e o custo. Subcomandos: `esconder`, `mostrar` (a barra só volta quando você manda),
  `cache 5m|1h` e `checar ligar|desligar`. O mapa lista os arquivos escritos, as skills, os serviços MCP e os
  subagentes; com um fluxo em curso, escrever num arquivo fora dos `arquivos:` do plano acende uma linha
  vermelha e um único toast, o aviso de desvio, que vai só a você, nunca ao modelo. Só `Edit`, `Write` e
  `NotebookEdit` contam: escrita por `Bash` não é detectada, e fora de fluxo o mapa só lista.
- **Deixado para depois, com um checker que vê as ferramentas.** Frases de adiamento em português e inglês,
  marcadores de pendência em arquivo e, em turno com 5 ou mais ferramentas, um segundo modelo (Haiku) que lê o
  pedido, o fim do relato e a lista de ferramentas do turno com as falhas — a regra 12 na tela: "feito" sem
  comando que o sustente aparece como item. "Faz agora" só preenche o prompt; quem envia é você.
- **Crédito.** O painel é adaptado do terminal-desk 0.2.1 (licença MIT, ClariSortAi); o texto da licença está
  em `NOTICE`, e os arquivos adaptados abrem com a remissão a ele.
- **Falha aberta nas duas contas.** Se uma leitura (uso de tokens, segundo modelo, pane, subprocesso) é
  recusada, falha ou demora, some só aquela peça; a barra e o pane nunca derrubam a sessão, e o mod não
  grava nada em disco. Medido no terminal, Claude Code 2.1.292, nas contas pessoal e de trabalho: a barra, o
  `/painel`, as fatias de contexto e o toast funcionam nas duas; o checker Haiku respondeu em 835 ms na
  conta de trabalho, e na pessoal um `Edit` fora do plano gerou a linha vermelha e um único toast, com cerca de 5 s
  de latência.
- **A conta de trabalho barra só duas coisas** (política `cc-plugin-sec-default`): `prompt.compose` e
  `classic.SessionStart`, e o painel não usa nenhuma. `ui.render`, `ui.open`, `session.usage`,
  `model.complete` e `ui.toast` passam.
- **Requisito.** O painel pede o Claude Code 2.1.292 ou mais novo, a versão em que foi medido, no terminal; o
  desktop não foi medido. Sem o mod nada muda.
- **Vale a partir da sessão seguinte à atualização:** o mod é carregado na abertura da sessão.

## 1.44.1 — 2026-10-07

- **O aviso de agente em voo só barra a sessão que despachou.** Antes, qualquer sessão aberta no mesmo
  worktree era bloqueada no fim do turno por um agente que outra janela tinha despachado. Agora o
  `estado.cjs marcar` grava a sessão dona em cada item de `em_voo`, e o aviso só conta os da sessão que
  está parando; registro antigo, sem dono, segue barrando como antes. Vale a partir da sessão seguinte
  à atualização.

## 1.43.0 — 2026-10-06

Fecha as doze Issues abertas pela revisão bimestral (#396 a #405, #407, #408).

- **Hooks novos.** `aviso-fluxo` (PreToolUse em Write/Edit): no primeiro arquivo de código editado numa
  sessão de repositório com fluxo rainforest e nenhum fluxo aberto, lembra de abrir o fluxo ou de dizer por
  que pula (#396; desliga com a chave `aviso-fluxo`). `gate-subagente-sem-instalar` (PreToolUse em
  Bash/PowerShell/Write/Edit/MultiEdit/NotebookEdit): subagente não instala pacote — também atrás de `bash -c`,
  `sudo`, `env`, `FOO=1`, `pwsh -Command`, `&` do PowerShell e flags com valor antes do verbo (`npm --prefix x install`), decidido pelo subcomando (`npm test`, `yarn build`, `--help` passam) — nem cria
  ou altera `.rainforest-gate-off` nem define `RAINFOREST_GATE_OFF` (#402; chave `subagente-sem-instalar`). `idioma-session-start` (SessionStart na
  compactação): com a chave `idioma` no config, a sessão compactada volta a responder no idioma preferido (#401).
- **`gate-fechar-issue`:** `bash scripts/$b.sh` (caminho que mistura literal e variável) deixa de ser
  ilegível (#405), e `--body-file` criado por heredoc no mesmo comando é lido do próprio comando (#407).
- **`conferir-fluxo cobertura`** recusa plano que o `executar` não consome: tarefa paralela com
  dependência, paralelas que tocam o mesmo arquivo, `tipo` inválido, chave desconhecida, caminho com `..` ou
  absoluto, e `de:` de mutação que casa mais de uma vez no fonte (#397).
- **Baterias (#398, #403):** `varrer-baterias.sh` confere a lista de obrigatórias
  (`scripts/baterias-obrigatorias.txt`) antes de repartir em shards; a catraca roda o bash por caminho e sai 69
  com o bash do WSL; mutação concorrente nas fixtures de cobertura sai 69 com a trava ocupada, e a restauração do fonte se confere por sha256 (divergindo, sai ≠ 0 e a trava fica marcada, barrando a próxima rodada); três baterias de memória
  recusam rodar contra a raiz real; o payload das sete baterias de gate da #403 sai de `JSON.stringify` — seis casos eram
  JSON inválido e ficavam verdes sem o gate olhar.
- **`conferir-entrega` (.cjs e .py, #400):** stderr do git vira aviso em vez de sujeira; `status` que falha
  sai 69; `--gravar-sujo-antes` grava o snapshot com a árvore de origem e a conferência recusa snapshot de
  outra árvore; regressão em bateria vizinha passa a ser avisada.
- **`limpar-worktrees` e leitor de estado (#399):** revalidam antes de remover, poupam worktree em uso
  recente (10 min, nome acentuado incluído) e dizem "fluxo concluído na base" quando a branch já entrou na `main`.
- **`/saude`** avisa skill de usuário divergente entre os dois config dirs (#404).
- **Memória:** legenda e bloco mostram a data local da observação, não a UTC (#408); o relatório de
  utilidade continua achando a observação servida quando a data local e a UTC caem em dias diferentes.

## 1.42.0 — 2026-10-06

- **`/transferir claude`: a sessão muda de conta com o contexto inteiro.** Copia o transcript da sessão atual
  (e a pasta dos subagentes e das saídas de ferramenta) da conta em que ela roda para a outra conta do Claude
  Code nesta máquina, e imprime a linha `cd` + `claude --resume <id>` para continuar lá. Não resume nada nem
  gasta token; a origem fica intacta; cópia que já existe no destino só é sobrescrita com `--forcar`. Sem chave
  no `/setup`. `/transferir` sem argumento continua indo para o Codex.
- **Conserto:** o `/transferir` para Codex recusava (exit 2) toda sessão da conta pessoal, porque só aceitava
  transcript em `~/.claude/projects`; agora aceita as duas contas.

## 1.41.0 — 2026-10-05

- **Revisão bimestral das regras.** As 214 observações registradas desde 2026-08-08 foram triadas por conteúdo:
  85 já estavam cobertas pelo texto e foram colhidas; 26 lições viraram texto novo nas regras e nas skills do
  fluxo; o que era defeito de script virou Issue (#396 a #404). Nenhum núcleo mudou; as elaborações das regras 11,
  12, 16 e 17, que a abertura injeta inteiras, cresceram 1,3 KB (38.863 B de 40.960 B) — o resto do texto novo
  mora em arquivos irmãos das `references/`.
- **Regras (references):** citar terceiro pela frase literal e memória do usuário como ambiente (16); `Q` só
  para decisões independentes, sempre com recomendada (16); a prova tem de medir o defeito, verde em quantos
  ambientes, e mutação que alarga o padrão (12, em `regra-12-prova.md`); um worktree por atividade e sem
  `EnterWorktree` com agente em voo (11, em `regra-11-atividade.md`); foco é entrega, não pasta (3); plantio
  é para o que desvia, não para o que ele quer resolver (6); ressalva antes da ordem e comentário lateral não
  vira gate (7); como ler recusa de gate e anunciar quando parar de despachar (14); processo de fundo e `&`
  no Bash (15); balanço da sessão antes de "alguma observação?" (5); origem marcada em mensagem entre sessões (17).
- **Skills do fluxo:** `brainstorm` varre ideias e Issues antes da primeira rodada, pergunta alvo e
  convive-ou-substitui, exige modelo de ameaça quando o design cria trava, e reconhece delegação prévia e
  pedido de conversa; `plano` ganha "Critério de trava" e três cuidados de critério; `modo-dev` manda invocar
  a catraca de mutação, proíbe temporário de nome genérico e põe teto no relatório; `fechar` troca a base da
  PR empilhada antes do merge; `arqueologia` não devolve arquivo sem funções; `regua` confere a cobertura do
  material de origem; `CONTRIBUTING` pede releitura hostil de texto injetado.
- **Vigia `revisao-bimestral`** passa a ser por ciclo: quem fecha a revisão reagenda a próxima.

## 1.40.0 — 2026-10-05

- **Mapa de estágios do território.** Um plugin de domínio (um "território") passa a declarar, num
  `territorio.json`, quais agentes despachar, quais tools de MCP e skills consultar e quais comandos
  rodar em cada estágio do fluxo. Antes, mesmo com os dois plugins habilitados, o modelo não
  despachava nenhum agente do outro plugin: ficava por iniciativa dele.
- **`scripts/territorio.cjs estagio <nome>`.** Descobre o território do repositório (pela detecção do
  manifesto, ou pelo apontamento `.rainforest/territorio`, que vence) e imprime o bloco do estágio.
  Variáveis de comando vêm de `~/.rainforest/territorios/<nome>.json`; variável sem valor sai 3
  nomeando a que falta. Sem território, imprime `sem territorio` e nada muda. O `{arquivo}` sai
  citado para shell (aspas simples quando tem caractere fora do conjunto seguro): o nome vem do
  repositório em que se trabalha e a linha impressa é executada, então `x$$(cmd).prw` não roda `cmd`.
- **O `marcar` recusa item obrigatório sem evidência.** Agente, tool ou comando que o mapa marca
  como obrigatório e não aparece no campo `territorio` do `--json` do `marcar` recusa com exit 2
  nomeando o item. Item opcional só gera aviso. Sem território, o `marcar` se comporta como antes.
- **As quatro skills ligadas.** `brainstorm`, `executar`, `revisar` e `verificar` rodam o
  `territorio.cjs` na abertura e agem sobre o bloco: consultas de MCP no brainstorm, agente do
  território no lugar do executor (`modo: substitui`), revisores em paralelo ao do rainforest
  (`modo: soma`) e comandos do mapa na verificação.
- **Contrato `versao_contrato: 0`, experimental.** Está descrito em
  `docs/rainforest/referencia/contrato-territorio.md`, com o protocolo de aceite em números (agentes
  despachados, qualidade do júri cego, custo até +30%). Vira v1 quando um segundo território o
  implementar. O mapa de um território real mora no plugin dele, não neste repositório.

## 1.39.3 — 2026-10-05

- **`git` e `gh` não são mais procurados na pasta do repositório aberto** (#392). Hooks e scripts chamavam
  os dois pelo nome, com a pasta atual dentro do repositório, e no Windows o `cmd.exe` e o Node procuram o
  executável ali antes do PATH quando `NoDefaultCurrentDirectoryInExePath` não está definida: um `git.exe`
  plantado na raiz de um repositório rodaria a cada hook. Agora o caminho sai do PATH, com as mesmas extensões
  que o Node usa (`.com`, `.exe`), e entrada relativa do PATH (`.`) é ignorada. Sem `git` no PATH, o erro
  continua sendo `ENOENT` — nunca volta a procurar pelo nome. Os `execSync("git ...")` de string viraram
  chamadas sem shell. Os desvios de teste `RAINFOREST_GH` e `RFM_VARRER_GH` continuam valendo, e o `gh`
  instalado como `.cmd` segue alcançado onde já era. Vale também para os dois scripts Python
  (`conferir-entrega.py`, `validar-colhidas.py`), porque o `subprocess` do Windows procura do mesmo jeito.
- **Bateria nova `scripts/testa-git-por-nome.sh`** barra a regressão: acusa `git`/`gh` chamado pelo nome em
  `hooks/` e `scripts/` — inclusive por wrapper, em chamada quebrada em duas linhas e em `.py`, e roda o `conferir-versao` numa pasta com um `git.exe` falso para provar que ele
  não é executado.

## 1.39.2 — 2026-10-05

- **Plano ou design que não existe no disco não fecha mais o estágio.** `marcar --estagio plano --status ok`
  com `arquivo` declarado, ou `--estagio design --status aprovado` com `doc` declarado, recusa (exit 2)
  quando o arquivo não está lá. Antes, uma escrita barrada por um gate deixava o fluxo andar sem o documento.
- **A catraca de mutação mede em pasta com `node_modules` como junction.** É o jeito de dar dependências a
  um worktree no Windows, e antes a cópia morria com `EPERM` e saía 1 sem veredito. Quando a cópia falha por
  outro motivo, sai 69 (`nao-verificavel: copia da raiz falhou — ...`), e os casos que ficaram vermelhos
  saem inteiros numa seção `--- casos vermelhos ---`, mesmo com o resto da saída cortado.
- **Monorepo: `raiz:` no bloco `mutacao:` do plano.** A bateria roda na pasta do app; o `verificar` deixa de
  ser infechável quando cada app tem seus testes. Tarefa pulada sem rótulo de erro passa a mostrar a linha do erro.
- **O `node` não é mais procurado na pasta do repositório aberto.** O mod roda seus scripts com a pasta atual
  na raiz do plugin, e os `.cjs` chamam o Node pelo caminho do processo. No Windows, um `node.exe` plantado
  na raiz de um repositório não confiável podia rodar no lugar do seu.
- **CI em dois jobs.** As baterias se repartem por tempo entre dois jobs de ~17 min, em vez de um de ~31 min
  que encostava no teto de 35.

## 1.39.1 — 2026-10-05

- **A jornada de ontem não acende mais depois da meia-noite.** A leitura da jornada roda a cada
  5 min; nos primeiros minutos do dia novo ela ainda era a de ontem e a linha `⏰ jornada` piscava
  com as horas do dia anterior rotuladas como de hoje (e um "esconder" nesse intervalo valia para o
  dia inteiro). Agora só acende quando a última mensagem medida é do mesmo dia.
- **O relógio sobrevive ao `/clear`.** Antes, `/clear` parava a linha do relógio até a próxima
  sessão; agora ela segue e passa a se reconhecer pelo id novo da conversa.
- **O fim de outra sessão não para o relógio.** Só o fim da sessão que ligou o relógio o desliga.
- **Caracteres invisíveis não deformam mais a faixa.** Marcas de direção (LRM, RLM, ALM),
  separadores de linha e parágrafo, espaços de largura zero e o BOM, vindos de um título de foco, de
  uma Q ou da pasta de uma janela, viram espaço — como já acontecia com ESC e os overrides bidi.
- **`sessoes.json` acima de 256 KB é recusado.** O relógio apaga só a sua linha em vez de ler um
  arquivo enorme a cada minuto.

## 1.39.0 — 2026-10-05

- **Linha do relógio na faixa.** Quando você passa de 9 h efetivas de jornada, ou trabalha entre 19 h
  e 5 h com mensagem sua nos últimos 30 min, aparece `⏰ jornada 9h12 · 20h40`. Uma janela esperando
  você além da ociosidade máxima do `FOCO.md` (45 min se não houver) entra na mesma linha, nomeada
  pela pasta: `⏰ jornada 9h12 · 20h40 | janela-a parada há 32 min`, com ` (+1)` quando há mais
  de uma. Só entram janelas paradas há menos de 6 h. Antes, esses avisos dependiam de o modelo
  lembrar de checar.
- **A faixa tem até 4 linhas:** foco, fluxo, relógio e Q. Com pouco espaço, sobra primeiro a Q, depois
  o relógio, depois o fluxo.
- **"esconder" não volta com os minutos.** Ele tira a faixa inteira até algo mudar, e os minutos não
  contam: da parte do relógio, só o dia novo ou outra janela virando a mais parada (ou uma nova
  cruzando o limite) a trazem de volta. Quando volta, volta a faixa inteira, jornada inclusive.
- **Nota de uma vez por dia para o modelo.** Quando a jornada acende, o prompt seguinte que você
  digita leva ao modelo uma nota que traz a regra 8; você não a vê, e quem decide se avisa ou se
  cala (por exemplo, quando você só está delegando) continua sendo o modelo. No REPL real, o modelo
  citou a nota no primeiro prompt do dia e não a recebeu no segundo.
- **As Q respondidas saem da faixa no envio, agora de verdade no REPL.** A 1.38.1 prometia isso, mas no
  REPL interativo o gancho que usava não rodava, e a linha das Q ficava até o fim do turno. A limpeza
  passou para o evento que o REPL executa.
- **`scripts/jornada.cjs` ficou rápido.** Passou a ler só os transcripts tocados no dia: de 14 a 18 s
  antes para 0,39 s numa medição de manhã e entre 0,75 e 2 s em medições à tarde.
- **Requisito:** Claude Code 2.1.287+. Sem o mod, nada muda. Vale a partir da sessão seguinte à
  atualização do plugin, e o relógio só nasce em sessão interativa.

## 1.38.1 — 2026-10-03

- **Q respondida sai da faixa na hora.** Ao enviar a mensagem, a linha das Q some; o fim do turno
  seguinte traz de volta só as que continuarem abertas. Antes, as Q do turno anterior ficavam na
  tela enquanto o modelo trabalhava na resposta.
- **Todas as Q cabem na linha.** O título é só a pergunta (na forma `**Qn.** texto`, a
  recomendação que vinha depois deixou de entrar), e cada Q ganha uma fatia da largura, cortada com
  `…` dentro dela. Antes, uma Q1 longa empurrava as outras para fora da tela.

## 1.38.0 — 2026-10-03

- **Faixa acima do prompt.** Com Claude Code 2.1.287+, no terminal e no desktop, aparecem até três
  linhas logo acima do prompt: o **foco** ativo, o **fluxo em curso** (etapa, progresso, agentes em
  voo e `+N` se houver outros) e as **Q abertas** da última resposta (`Q1 título | Q2 título`).
  Os fluxos vêm de todos os worktrees do repositório, inclusive quando a janela está no checkout
  principal.
- **Só acende quando ajuda.** Sem fluxo em curso e sem Q aberta, a faixa não aparece; o foco
  sozinho não a acende. Ela continua visível durante o turno do modelo e cede a vaga quando o
  Claude Code mostra uma pesquisa.
- **"esconder"** tira a faixa até algo mudar: Q nova ou resolvida, etapa nova, ou
  mudança nos agentes em voo.
- **Atualiza** ao abrir a sessão, ao fim de cada turno e ao apertar o botão. Uma resposta sem Q
  zera a linha das Q. Falha de leitura apaga só a linha afetada; a sessão nunca quebra.
- **Não repete a statusline** (jornada, prazo, versão).
- **Sem mod, nada muda.** No Codex ou em Claude Code anterior à 2.1.287 não há faixa.
- **Vale a partir da sessão seguinte** à atualização do plugin.

## 1.37.0 — 2026-10-03

- **A abertura chega inteira.** Com Claude Code 2.1.287+, o mod (`hooks/register.ts`) entrega a
  abertura da sessão como seção do system prompt, fora do teto de entrega do hook: o núcleo das
  regras **mais a elaboração inteira das regras 16, 12, 11 e 17**, o `FOCO.md` sem corte e a
  memória sem o corte de 160 caracteres por linha. Medido: a seção de 48.589 caracteres chegou
  inteira ao modelo, e o núcleo deixa de vir duplicado (o mod tira do `SessionStart` as entradas
  que ele mesmo passou a entregar).
- **Lista e orçamentos num lugar só.** `hooks/abertura-mod.json` diz quais regras vêm inteiras e
  os tetos (regras 40.960 B, foco 12.288 B, memória 8.192 B, total 61.440 B).
  `node scripts/sugerir-elaboracoes.cjs` sugere a ordem a partir das observações, sem alterar nada;
  quem muda a lista edita o JSON. `node scripts/orcamento.cjs --agregado --destino mod` mede o total.
- **Sem mod, nada muda.** No Codex, em Claude Code anterior à 2.1.287, ou se o mod falhar, a abertura
  vem pelo hook com o núcleo, byte a byte como antes. O mod não chega ao prompt de subagente.
- **Vale a partir da sessão seguinte** à atualização do plugin. O canário da 1.36.0 saiu.

## 1.36.0 — 2026-10-02

- **Entra o primeiro mod do plugin, e é um canário.** `hooks/hooks.json` ganha a chave
  `modules` apontando para `hooks/register.ts` (Claude Code 2.1.287+, "Claude Mods"); a
  chave `hooks` não mudou. O mod é **inerte**: sem a variável `RFM_CANARIO_MOD` o hook
  `prompt.compose` devolve o prompt como veio. É temporário, do fluxo
  `2026-10-02-mod-regras-inteiras`, e será substituído.
- **Como medir.** Com o plugin instalado do marketplace, rode
  `RFM_CANARIO_MOD=1 claude -p --model haiku "Procure no seu system prompt linhas no formato RF-TETO-CANARIO-<numero>. Responda SO com os numeros, ou NENHUM."`.
  A seção tem ~49.500 caracteres com marcas em 1024, 3072, 16384, 32000, 40000 e 48000; as
  marcas que voltam dizem até onde o texto chega. Três linhas finais (`RF-TETO-TRAITS-`,
  `-TOOLS-`, `-IDS-`) mostram o que o mod enxergou. Sem a variável, a resposta esperada é `NENHUM`.

## 1.35.2 — 2026-10-01

- **A recusa do gate de PR ensina o caminho do PR.** Quando `gh pr create/edit/merge` cita
  `closes #N` e a Issue não tem evidência, a mensagem agora nomeia o marcador literal
  `<!-- rainforest-evidencia -->` e mostra como comentar a evidência **sem fechar** a Issue
  (`gh issue comment`, em comando separado do `gh pr`). Antes ela só apontava o
  `fechar-issue.cjs`, que fecha a Issue antes de o PR existir.

## 1.35.1 — 2026-10-01

Os dois menores da revisão da rodada 14 (#373).

- **Slug com `*` ou `?` é recusado.** O `estado.cjs` recusa curinga de glob no slug, como já recusava
  `/`, `\` e `..`: o `conferir-fluxo creep` monta a isenção com o slug (`portoes/*<slug>.md`,
  `varredura/<slug>.txt`), e um slug `x*` alargava a isenção a arquivos de outro fluxo.
- **A premissa do desempate do `veredito-revisor` está escrita.** A docstring de `raizComEstadoDoSlug`
  dizia "2+ → ambíguo", o que o desempate da 1.35.0 já não fazia. Agora diz que o worktree do revisor
  vence e por quê, inclusive o caso aceito de revisor isolado fora de `agent-*`.

## 1.35.0 — 2026-10-01

Rodada 14: a triagem de inbox do `sentinela-foco` (#367), o creep da varredura (#368) e as três
dívidas da revisão da rodada 13 (#369).

- **A ronda do vigia dá 90 s para o MCP subir** (#367). O `run-vigia.ps1` define `MCP_TIMEOUT=90000`
  só no próprio processo, antes do `claude -p`. Medido em 01/10: o `@artymclabin/gmail-mcp` via
  `npx -y` levou 57,6 s para responder ao `initialize`, acima do teto de 30 s do Claude Code, e a
  triagem sumia do briefing em silêncio. Nenhuma variável do usuário ou do sistema muda.
- **O vigia lê só pelo `gmail-leitura`** (#367). Toda ronda, com ou sem `-Teste`, nega o servidor
  `gmail` inteiro por `--disallowedTools mcp__gmail`; o prompt nomeia `mcp__gmail-leitura__search_emails`.
  Em 01/10 a triagem tinha lido pelo `gmail` de escopo completo (envia, apaga).
- **Inbox não lido vira aviso explícito** (#367). Quando o MCP não sobe nem com o teto maior, o briefing
  traz `inbox: não verificado — MCP do Gmail não subiu`, além do registro no `ERROS.md`.
- **A varredura do próprio fluxo não é mais creep** (#368). O `conferir-fluxo creep` isenta
  `docs/rainforest/varredura/<slug>.txt` do slug em revisão — o `brainstorm` obriga a criar e o
  `marcar --estagio design` exige. Varredura de outro slug continua creep.
- **Dívidas da rodada 13** (#369). Empate de worktrees armados no `veredito-revisor`: vence o do revisor.
  `preparar-worktree --exige` aceita `..foo` dentro do worktree, recusa `.` dizendo que é a raiz e
  confere existência pelo mesmo caminho resolvido (absoluto dentro do worktree passa). Saiu do
  `gate-turno-prometido` a normalização de CRLF que nenhum caso distinguia.

Fora desta versão: o log da ronda sem a saída do modelo entre 03 e 28/09 (#372).

## 1.34.0 — 2026-10-01

Rodada 13: os três resíduos da revisão do semear-travas (#362, #363, #364).

- **`bash $b` sem aspas continua barrado, e agora a mensagem diz por quê** (#362). Sem aspas,
  a variável se divide em palavras e pode injetar `-c`. Medido: `CMD='-c gh${IFS}issue${IFS}close${IFS}12'; bash $CMD`
  fecha a Issue. O gate não ganhou exceção nenhuma; o contorno é pôr aspas (`bash "$b"` passa).
- **O veredito do revisor vai para o worktree do fluxo** (#363). O `veredito-revisor` descarta
  os worktrees de agente do harness (`.claude/worktrees/agent-*`) e, sobrando mais de um candidato,
  prefere o que tem a janela de revisar armada. Antes, com o revisor isolado (regra 11), o veredito
  caía na cópia do estado dentro do worktree descartável do revisor.
- **`gate-turno-prometido` lê aspas e citações direito** (#364). Aspa ou crase solta (`5"`, `6"`,
  ou uma aspa aberta e nunca fechada, com LF ou CRLF) não engole mais a promessa; citação entre
  aspas colada em negrito, itálico ou pontuação (`**"…"**`, `_"…"_`), citação que atravessa uma
  quebra de linha e citação em bloco `>` deixam de contar como promessa.
  O pareamento ficou mais estrito de propósito: aspa com espaço por dentro (`"… "`, `" …"`) ou
  colada em letra (`"…"s`, `x"…"`) não conta como citação e a promessa dentro dela barra o turno —
  afrouxar isso reabre o caso da aspa solta que engole a promessa.
- O `veredito-revisor` ainda grava quando a única cópia do estado está num worktree de agente.
- **Caminho fora do lugar é recusado** (#364). `preparar-worktree --exige` fora do worktree e
  `varrer --slug` com separador ou `..` saem com exit 2 e nomeiam o valor.
- `docs/travas-mecanicas.md` cita `python3` na forma simples do `conferir-prova`, como o código aceita.

## 1.33.1 — 2026-10-01

- Arrumação: os erros do sentinela de 21 a 30/09 entram no `vigias/ERROS.md` versionado, e sai o estado `2026-09-05-inventario-do-acervo`, que nunca passou do design.

## 1.33.0 — 2026-10-01

- **Falha de vigia que volta aparece como recorrente.** O `/saude` ganha o aviso
  `vigias-recorrentes`, e a âncora do batedor ganha a seção `FALHAS RECORRENTES (30 DIAS)`.
  Cada erro do `vigias/ERROS.md` recebe uma impressão digital: vigia mais causa, com
  caminho, id e número normalizados. É o mecanismo do reef, enxertado. Com 2 ou mais
  ocorrências em 30 dias, a falha aparece como `recorrente xN em 30 dias, desde DD/MM,
  ultima DD/MM`, e só sai da lista quando alguém escreve `[vigia]: RESOLVIDO` no
  `ERROS.md`. Antes, cada ocorrência chegava como novidade: o backup externo falhou 5
  vezes entre 11 e 25/09 sem aparecer como repetição.

## 1.32.0 — 2026-09-30

Seis travas para defeitos que já se repetiram aqui. Cada uma nasceu de uma
observação registrada, pelo `semear`.

- **Turno que promete e não faz é barrado no `Stop`.** O hook novo
  `gate-turno-prometido` (ligado por padrão) sai 2 em dois casos:
  - o turno diz "vou despachar" e não chama `Agent`, `Task`, `SendMessage` nem
    `Workflow`;
  - o turno diz "CI rodando" ou "aguardando o build" sem vigia: nem `Bash` ou
    `PowerShell` em background, nem `Monitor`, nem `ScheduleWakeup`.

  Não disparam: passado, negação, código, aspas e lista. Para desligar:
  `node scripts/setup.cjs --desligar gate-turno-prometido`.
- **Critério de pronto tem de falhar antes do trabalho.** O
  `marcar --estagio plano` roda a `prova:` de cada tarefa num worktree
  descartável. Prova que já passa na base é recusada (exit 2), porque um critério
  assim não prova nada. A exceção se declara: `prova-na-base: verde — <motivo>`.
  Peça nova: `scripts/conferir-prova.cjs`.
- **A base do agente virou um comando.** `scripts/preparar-worktree.cjs --hash <H>
  [--exige <arquivo>]` leva o worktree ao hash do briefing por fast-forward e
  recusa divergência real. O `conferir-entrega` passa a exigir `--base` (exit 2
  sem ele), nos dois motores.
- **Design só é aprovado com varredura.** O `scripts/varrer.cjs --slug <s>
  <termos>` registra em `docs/rainforest/varredura/<slug>.txt` o que o repo já
  sabia: branches, commits, Issues e ideias. A seção `## Varredura` do design tem
  de citar esse arquivo.
- **Edição literal sem corromper.** `scripts/substituir.cjs --arquivo F --de <arq>
  --para <arq> [--ocorrencias N]` troca byte a byte e confere a contagem antes de
  gravar. Texto com `$`, crase ou contrabarra entra literal, e `--para` vazio
  apaga o trecho.
- **Comandos reais contra as travas.** 50 comandos legítimos (curados) passam por
  cada gate de Bash, nos contextos principal e subagente. Um gate que comece a
  barrar comando legítimo deixa a bateria vermelha. O extrator dos candidatos é
  `scripts/extrair-corpus-comandos.cjs`.

## 1.30.2 — 2026-09-29

- **Livro de repos: três indicados avaliados.** `strands-agents/harness-sdk` e
  `Human-Agent-Society/reef` enxertam, e `reconurge/flowsint` vale voltar. Nada muda no
  que o plugin executa; a versão sobe para o registro chegar a quem atualiza. Relatório:
  `relatorios/2026-09-29-batedor-strands-reef-flowsint.md`.

## 1.30.1 — 2026-09-29

- **Backup externo com o banco da memória aberto.** Quando a ronda do sentinela
  coincidia com uma sessão do Claude Code aberta, o `rainforest.db` estava em uso, e o
  `Compress-Archive` não conseguia ler o arquivo. O zip inteiro falhava, e em seis
  dias (11, 21, 22, 23, 25 e 29/09) nem o FOCO.md nem as ideias foram para o
  backup externo. Agora o `backup.cjs gravar` tira uma cópia consistente do banco com
  `VACUUM INTO`, por uma conexão só de leitura, e zipa a cópia. Se a cópia falhar, o
  zip sai com os outros itens, e o comando sai 2 com `RECUSADO: rainforest.db ficou
  fora do backup: <motivo>`, linha que continua indo para o `vigias/ERROS.md`.
- **`backup.cjs conferir` prova o banco por restauração.** O `rainforest.db` do zip é
  aberto e precisa passar no `PRAGMA integrity_check`, porque a cópia nunca tem o hash
  do arquivo vivo. Os demais arquivos continuam conferidos por hash.

## 1.30.0 — 2026-09-29

- **Bloqueio por variável diz que a causa é a variável (#350).** Com outra sessão no
  mesmo diretório, `git -C "$H" switch -c x` (ou `cd "$TMP"` antes do `git`) continua
  barrado, porque o gate não sabe para onde o comando vai. Antes, a mensagem só dizia
  "move o HEAD deste checkout". Agora ela explica que o alvo usa variável, substituição
  ou `cd` que o gate não resolve e manda usar o caminho literal. Com o caminho literal,
  o gate compara o repositório de verdade, e um clone de outro repo passa.
- **`--body-file` com variável tem mensagem própria (#350).** `gh pr create --body-file
  "$SP/pr.md"` continua barrado pelo `gate-fechar-issue`, mas a mensagem agora diz
  "variável que o gate não resolve" em vez de culpar um caminho relativo que não
  existe, e pede o caminho literal.
- **Por que nenhum gate expande variável.** A rodada 9 tentou resolver `$VAR`
  estaticamente no `gate-fechar-issue`, e quatro revisões acharam bypass (crase colada,
  array, `read`/`declare`, heredoc como atribuição falsa). Na trava de sessão
  co-locada, um bypass desses liberaria mover o HEAD da outra sessão.

## 1.29.1 — 2026-09-29

- **Abertura sonda uma bridge WhatsApp por conta (#356).** Com duas contas no
  `~/.whatsapp-mcp/accounts.json` (pessoal 3005, trabalho 3006), o hook de abertura
  sondava só a `WHATSAPP_API_BASE_URL` e anunciava o resultado como o WhatsApp inteiro
  — dizia FORA com a de trabalho de pé. Agora, quando a porta declarada é de uma das
  contas, sonda todas e nomeia cada uma; só a conta caída vira aviso na tela.

## 1.29.0 — 2026-09-28

- **Mensagem do bloqueio de `bash $t` (#337).** `bash $t` sem aspas continua barrado
  pelo `gate-fechar-issue` (resolver a variável estaticamente abriu bypass nas quatro
  revisões da rodada 9), mas a mensagem agora diz o que fazer: rodar um arquivo cujo
  caminho está numa variável se faz com aspas, `bash "$t"`, que passa. Antes ela mandava
  "rodar o `gh` diretamente" num comando sem `gh`.
- **Eval de gatilho sob demanda (#302).** A suíte de 21 casos (7 pares de skills que
  colidem) entra em `evals/`, e `scripts/eval-gatilho.sh` roda a trava com
  `--ablation none` — onde o disparo da skill conta no score, ao contrário do
  `with-without` que deixava a eval passar sem a skill disparar. Cada caso roda 3 vezes
  e passa pela maioria (o disparo oscila entre rodadas); `mutacao <skill>` sabota a
  `description` numa cópia e exige a trava vermelha; `baseline` mede se a skill
  acrescenta. Fica **fora do CI** (~US$ 20 por trava completa). A bateria prova o
  mecanismo com um `claude` falso; **nenhuma rodada paga foi feita ainda**, então a
  premissa de que o grader de disparo pontua sob `--ablation none` segue por confirmar.

## 1.28.1 — 2026-09-28

**Vigia que não chega ao Claude não sai mais com sucesso.** De 2026-09-02 a
2026-09-28 nenhum vigia mandou mensagem: o `claudeExe` do `vigia.config.json`
apontava para o `claude.exe` que o WinGet tinha removido, a chamada falhava sem
chegar ao log, e a tarefa agendada saía com 0 — nem linha no `ERROS.md`. Agora o
`run-vigia.ps1`:

- confere o `claudeExe` configurado; se o arquivo sumiu, registra no `ERROS.md` e
  usa o `claude` do PATH, para a ronda não se perder por config velho;
- conta a saída do `claude -p` e lê o exit code: saída vazia ou exit ≠ 0 viram linha
  no `ERROS.md` e **exit 1** da tarefa (o backup do estado roda assim mesmo).

**`-Teste` não envia mais de verdade.** O "não envie" do modo de teste era só texto no
prompt, e uma ronda de teste do jardineiro foi parar no grupo. Agora o `-Teste` tira
as tools de envio (WhatsApp e Gmail) da sessão por `--disallowedTools`, e o prefixo
avisa o modelo que a ausência delas não é bridge fora do ar.

**Falha do backup externo diz o motivo.** Cinco linhas `backup externo falhou (exit 2):
System.Management.Automation.RemoteException` (11 a 25/09, sem zip nos dias 21–23)
não traziam causa nenhuma: o PowerShell 5.1 embrulha cada linha de stderr do node, e o
registro pegava a última, que era vazia. Agora o `ERROS.md` recebe a linha `RECUSADO`
do `backup.cjs` e o log do vigia guarda o stderr inteiro. A causa da falha intermitente
em si ainda não é conhecida — a próxima ocorrência vai dizê-la.

Bateria nova: `scripts/testa-run-vigia-claude.sh`, que executa o script com `claude`
falso e uma porta simulando a bridge — contra a versão anterior ela fica vermelha
nos três casos de falha e no caso do `-Teste`.

## 1.28.0 — 2026-09-28

**Subagente não escreve mais no GitHub.** Em 2026-09-13 e em 2026-09-28, um revisor
fechou uma Issue de verdade (`gh issue close 12`) enquanto testava um gate — nas duas
vezes com a proibição escrita no briefing, uma por stub que não entrou no PATH, outra
por `alias` num script (alias não expande em script). O gate novo
`gate-subagente-sem-gh.cjs` nega, dentro de subagente, todo `gh` que escreve no GitHub:
`issue close|comment|edit|create|reopen|delete…`, `pr create|edit|merge|close|comment…`,
`release`, `repo`, `gist`, `alias set`, `extension install`, `workflow run`, `run rerun`,
qualquer família que não é do `gh` (alias ou extensão, como `gh co 12`), e `gh api` com método diferente de GET ou
com campo (`-f`/`-F`, que viram POST) — `gh api graphql` só com `mutation`. Leitura (`view`, `list`, `checks`, `api` GET)
passa, e a janela principal passa sempre.

- **Onde ele olha:** o comando (inclusive atrás de `timeout`/`stdbuf`/`env`, com flag
  global como `-R o/r` antes do subcomando, contrabarra e aspas ANSI-C), `bash -c` legível
  (e nega o ilegível, `bash -c "$x"`), corpo de heredoc, e o **script que o subagente
  manda rodar** — lido antes de rodar em `bash`/`sh`/`source`/`python3`/`node`, `./x.sh`,
  `bash < x.sh` e `cat x.sh | bash`, pela forma de shell, pela forma de chamada
  (`execFileSync('gh', ['issue', 'close'…`) e com variável no lugar do `gh`; também
  `pwsh`/`powershell` com `.ps1`, e código inline em `node -e`, `python -c`,
  `pwsh -Command` e `cmd /c`, inclusive `--eval="..."` e flags agrupadas
  (`python -Bc`, `perl -we`); `pwsh -EncodedCommand`, ilegível, nega.
- **Limite declarado:** a leitura de script é textual. Pega o jeito comum de chamar
  (`os.system("gh …")`, `execSync(…)`, `system 'gh', …`, `$(gh …)`, crase), não a
  evasão deliberada (função apelidada, comando montado por concatenação). O alvo é o
  agente que roda `gh` sem perceber, não o que tenta burlar.
- **Isenção:** bateria `testa-*` rastreada pelo git, mesmo alterada — as baterias citam
  `gh issue close` como texto de teste. Bateria nova precisa de `git add` antes de rodar,
  e a mensagem diz isso. `scripts/fechar-issue.cjs` é negado pelo nome.
- **Toggle `subagente-sem-gh`** (padrão ligado). O perfil dos agentes
  (`referencias/perfil-de-trabalho.md`, aplicado aos `agents/*.md`) explica a regra e
  como medir um gate sem executar `gh`: payload JSON no stdin do hook.
- `semContrabarra` saiu do `gate-fechar-issue.cjs` para `hooks/lib/tokens-comando.cjs`,
  e os dois gates usam a mesma.

## 1.27.0 — 2026-09-28

**Seis defeitos abertos fechados numa rodada** (Issues #346, #344, #342, #341, #340,
#339). A #337 (`bash $VAR` sem aspas) e a #302 (eval de gatilho) continuam abertas:
as duas pedem outro desenho, não conserto.

- **`stdbuf --output L` não escapa mais do `gate-bateria-sem-timeout`** (#346). A
  forma longa com espaço deixava o `L` passar por comando e a bateria ia para
  segundo plano (exit 0); agora sai 2, como `-oL`, `-o L` e `--output=L`. O `stdbuf`
  entrou na lista comum de wrappers dos gates, que agora olham o comando depois
  dele. `stdbuf -oL gh issue close 12` já era barrado antes, pela busca de sequência,
  e ganhou caso de regressão.
- **`gh pr create --body-file /c/...` lê o arquivo** (#344). No Git Bash o caminho
  MSYS virava `C:\c\...` e o gate barrava com "não consegui ler o arquivo de corpo do
  PR" com o arquivo existindo; agora o caminho é normalizado como o do `cd`.
- **Contrabarra fora de aspas não esconde mais o subcomando** (#339). `bash -c "gh
  issue \\\<quebra>close 12"` (três contrabarras) executava `gh issue close 12` e o
  gate saía 0. Metade era a leitura das aspas duplas, que agora é uma passada só,
  como no bash. A outra metade apareceu na medição e era mais larga do que a issue:
  `gh issue \close 12`, sem wrapper nenhum, também saía 0, e na revisão apareceram as
  aspas ANSI-C (`gh issue $'close' 12`, `$'clo\x73e'`). O gate passou a comparar o
  subcomando sem contrabarra e com os escapes do ANSI-C resolvidos. Um efeito colateral: `echo hi \gh issue close 12` agora
  é barrado, como `echo hi gh issue close 12` já era.
- **Veredito grava o transcrito com `~`** (#340). `estado.cjs veredito` gravava o
  caminho absoluto, que começa pela pasta pessoal, num arquivo versionado de repo
  público. Agora grava `~/.claude*/projects/...` (também quando o disco ou o usuário
  chegam em outra caixa, como o Git Bash entrega), e a conferência D12/D14 continua
  sobre o caminho real. Os 10 estados que já estavam na main foram reescritos.
- **R5 do `testa-saude.sh` diz quando a falha é do próprio teste** (#342). O servidor
  de teste escuta na porta que o sistema der e grava essa porta; se ele não subir, o
  R5 reprova com `fixture: servidor node nao subiu` em vez de acusar o `saude.cjs`.
- **Nenhuma bateria roda duas vezes na varredura** (#341). `testa-gate-publicacao-destino.sh`
  rodava outras duas baterias que o varredor já roda. O bloco saiu, e o teste (n) do
  `testa-varrer-baterias.sh` passou a barrar qualquer `testa-*.sh` que execute outra
  `testa-*.sh` (por `bash`/`sh`/`source`/`.`/`exec` ou pelo caminho direto), além da
  casca `.cjs` que já barrava.

## 1.26.0 — 2026-09-27

**Subagente já não deixa bateria sem `timeout` ir para segundo plano.** Em 2026-09-27,
10 de 14 subagentes numa sessão tiveram comando empurrado para segundo plano, e em
quase todos o motivo foi bateria rodada sem o parâmetro `timeout` do Bash. O gate
novo `gate-bateria-sem-timeout.cjs` nega execução dentro de subagente em dois casos:
uma bateria (`testa-*.sh`, `testa-*.cjs`, `varrer-baterias.sh`, `conferir-mutacao.cjs`,
`conferir-fluxo.cjs mutacoes`) sem `tool_input.timeout` > 120000, e a varredura
completa (`varrer-baterias.sh` sem `--so`), que passa do teto de 10 minutos. A
mensagem de bloqueio sugere `timeout: 600000`. Ler arquivo (`cat`, `grep`, `sed`)
não é barrado.

- **Toggle `bateria-sem-timeout`** (padrão ligado): desliga o gate para o projeto se
  necessário. Mesma forma do `busca-na-raiz` e `agente-folha`. Janela principal vê e
  pode parar qualquer execução.
- **Texto acompanha o mecanismo** (`referencias/perfil-de-trabalho.md`): a linha
  "Nada seu fica rodando depois da resposta" agora cita o gate. Os `agents/*.md` são
  atualizados por `node scripts/perfil.cjs --aplicar`.
- **Fora do gate**: checagem de sintaxe (`bash -n`, `node --check`), leitura de bateria
  (`cat`, `grep`, `git add/diff/log`, mensagem de commit ou corpo de PR que cita o nome)
  e bateria cujo nome só existe em runtime (`for f in …; do bash $f`, `find -exec {}`,
  `xargs {}`). `stdbuf --output L` (opção longa com espaço) ainda escapa: issue #346.
- **Skill `executar` (`skills/executar/SKILL.md`)** deixa claro que o laço de baterias
  inteiro é rodado pela integração; o agente cola o placar das baterias que a tarefa
  toca.

## 1.24.0 — 2026-09-26

**Os gates fecharam um buraco e pararam de barrar um `Edit` que só preserva o que já
estava no arquivo.** O `bash $t` sem aspas (#337) continua barrado: quatro revisões acharam
jeito de esconder `bash -c` atrás da variável em cada versão da resolução, e a issue segue
aberta.

- **Contrabarra dupla dentro das aspas duplas de um wrapper** deixou de esconder o comando
  (#313): `bash -c "gh issue \\<quebra>close 12"` passava; agora o gate faz a mesma
  redução de escape que o bash faz antes de juntar a linha.
- **O gate de publicação mede o que a edição introduz** (#322): um `Edit` que preserva um
  dado sensível já presente no `old_string` (a linha do trailer `Co-Authored-By`, por
  exemplo) não é mais barrado. A comparação é pelo valor, não pelo trecho redigido: trocar
  um e-mail por outro, ou acrescentar um segundo na mesma linha, continua barrado. A isenção
  do `noreply@` no conferidor já existia e não mudou.

**O fluxo passou a achar o próprio estado onde ele mora.**

- **O veredito do revisor é gravado no worktree** quando o estado do fluxo só existe lá
  (#329). Se o estado estiver em mais de um worktree, ou em nenhum, o hook avisa em stderr
  e não grava — antes saía em silêncio.
- **Tarefa acrescentada por emenda ao plano recebe carimbo** (#312): o teto do carimbo lê
  o arquivo do plano, como a validação de `mutacao` já fazia; o número gravado no
  `plano ok` fica de reserva quando o arquivo não existe.

**Medição.**

- **As baterias em Node entram no CI** (#335): o varredor descobre `testa-*.cjs` em
  `scripts/` e `hooks/` e as roda com `node`. As cascas `.sh` que chamavam `.cjs`
  saíram, inclusive a `hooks/testa-portaria.sh`, que rodava as da portaria por glob;
  uma bateria nova falha se alguma `.sh` voltar a chamar uma `.cjs`. Antes, duas
  baterias (`testa-estagio-ativo` e `testa-conferir-cobertura-fixtures`) nunca
  rodavam no CI, e cada `.cjs` nova dependia de alguém lembrar da casca.
- **A checagem de duplicata do `/saude` mede só o plugin versionável** (#323): arquivo
  gitignorado (as cópias em `.claude/marketplaces/`, por exemplo) não conta mais. No
  checkout principal, o aviso caía de 811 grupos para 0.

## 1.23.0 — 2026-09-22

**Os gates de texto pararam de deixar passar `bash -c` escondido atrás de palavra
reservada, e pararam de barrar `bash "$t"`.** Antes, `for t in x; do bash -c "gh
issue close 12"; done` passava pelo gate de fechar issue, enquanto o mesmo `bash -c`
sem o laço era barrado: `do`, `then`, `else`, `elif`, `if`, `while`, `until`, `!` e
`coproc` tiravam o `bash` da posição de comando. E o inverso: rodar uma lista de baterias com
`for t in ...; do bash "$t"; done` era recusado como "comando encapsulado".

- **Palavra reservada é pulada** na posição de comando, nos três gates de texto e no
  gate de worktree.
- **Variável entre aspas duplas como último argumento é caminho de script**:
  `bash "$t"`, `bash "${t}"` e `bash "$t" 2>&1` passam. Sem aspas (`bash $t`) ou com
  argumento depois (`bash "$f" "gh ..."`, que com `f=-c` vira `bash -c`) continuam
  barrados.
- **Parâmetro especial é ilegível**: `set -- -c "<cmd>"; bash "$@"`, `bash "$*"` e
  `eval "$@"` passavam como se fossem caminho de script, e agora são barrados.
- **Pipe com stderr (`|&`) e continuação de linha** deixaram de esconder comando: `echo
  hi |& bash -c "<cmd>"`, `bash -c "gh issue \<quebra>close 12"` e a mesma quebra sem
  wrapper nenhum passavam, e passavam também na 1.22.0 — são buracos antigos, achados
  pela revisão desta rodada.
- **E-mail em TLD reservado** (`.invalid`, `.example`, `.test`, `.localhost`, RFC 2606)
  deixa de ser achado do gate de publicação, desde que seja o último rótulo
  (com `.test` no meio, como em `foo.test.com`, continua pego).

**O `conferir-entrega` em Python voltou a valer o mesmo que o de Node.** Ele tinha
parado em agosto: faltavam `--escopo`, o exit 69 de "não deu para verificar",
a reprovação de commit vazio e o BOM no `git status`. As quatro foram portadas, e o
CI passou a rodar a bateria contra o gêmeo em passo próprio, para ele não congelar
de novo em silêncio.

## 1.22.0 — 2026-09-22

**A régua do `/regua` não pode mais ser mexida depois que o loop começa.** Antes,
"a régua é imutável" era uma frase na skill: nada impedia o builder (ou uma edição
distraída) de afrouxar um mecanismo no meio das rodadas, e o crítico julgaria
contra a régua nova sem ninguém perceber.

- **Selada pelo commit.** O manifesto em `docs/rainforest/reguas/<slug>.md` vale
  como foi commitado pela primeira vez. `node scripts/conferir-regua.cjs validar
  --slug <slug>` confere o formato antes de selar; `conferir` recusa (exit 1)
  régua alterada, apagada ou adicionada mais de uma vez no histórico; `mostrar` é
  o único caminho que a imprime, e só imprime depois de conferir. Clone raso sai
  2 — no CI, use `fetch-depth: 0`.
- **Keep/discard automático.** A partir da 2ª rodada, um segundo crítico cego
  compara o novo com o melhor guardado. Perdeu, o commit fica e o ponteiro não
  anda; a próxima rodada parte do melhor. Estagnação em 3 rodadas vira a quarta
  condição de parada.
- **Log de rodadas versionado**, um TSV com SHA, veredito, status e lacuna de
  cada rodada.

O que o selo **não** cobre está escrito: manipulação deliberada de histórico por
quem tem escrita no repositório (rebase, squash, branch órfã). Ele vigia o
builder e os fluxos normais de git, não quem reescreve o histórico de propósito.

## 1.21.1 — 2026-09-21

**A limpeza de branches para de mandar procurar no GitHub o que só existe no
disco.** A listagem do `limpar` rotulava toda branch fora da `main` como "o remoto
está de pé", inclusive as que nunca tiveram remoto. Agora elas saem num grupo
próprio, `viva-so-local`: os commits só existem na sua máquina, o script não sabe
dizer se é trabalho em andamento ou tentativa descartada, e quem decide é você,
olhando e apagando à mão. Nada que antes era protegido passou a ser removido.

## 1.21.0 — 2026-09-21

**A instrução de comportamento de uma skill passa a ter trava.** Até agora, uma
frase que manda o agente fazer (ou não fazer) alguma coisa podia sumir de um
`SKILL.md` numa reescrita e nada ficava vermelho — o CI conferia sintaxe, links e
tamanho de injeção, nunca conteúdo de instrução.

- **Quinze invariantes em sete skills.** Cada skill protegida declara, num
  `invariantes.json` ao lado do `SKILL.md`, as frases que não podem sumir do corpo
  dela. Apagar uma deixa o CI vermelho nomeando a skill e a frase.
- **Assertiva negativa.** Uma entrada `tipo: "nao_deve"` trava a **ausência** de uma
  formulação já rejeitada — é guarda prospectiva contra reintroduzir um vocabulário
  que o usuário mandou sumir.
- **Degraus.** Uma frase pode ser exigida no corpo inteiro, só no bloco de regras,
  na referência da regra, ou no núcleo que a abertura de sessão injeta — este último
  pega a frase que continua no arquivo mas parou de chegar na sessão.

Enxertado do `openai/openai-developers-for-claude`, que afirma frase de
comportamento no corpo de cada skill dele. O que não veio de lá é a segunda fonte:
aqui a bateria declara as quinze frases por escrito e compara com o que lê de
produção, para que encurtar a frase declarada até ela casar com um `SKILL.md`
reescrito não seja o conserto barato.

## 1.20.0 — 2026-09-19

**A memória deixa de só acumular.** Duas coisas que não existiam passam a existir,
e as duas rodam sozinhas numa passada de manutenção que abre junto com a sessão:

- **Reconciliação.** Observação que corrige, repete ou complementa uma antiga agora
  atualiza ou funde-se a ela, em vez de virar mais uma linha ao lado. **Nada é
  apagado**: a substituída ganha um ponteiro, sai da injeção e da busca, e continua
  na tabela — fusão ruim se desfaz.
- **Consolidação automática em resumos.** Era manual e nunca tinha rodado uma vez.
  Passa a agrupar por origem a partir de 30 dias — pela sessão quando ela existe, e
  por `(projeto, dia)` para as 10.092 observações importadas do claude-mem, que não
  têm sessão nenhuma e são 88% do acervo.

**Aviso na abertura quando o pipeline para.** Captura ou manutenção paradas há mais
de 48 h viram uma linha na abertura da sessão, com há quantas horas e o comando que
religa. O silêncio de 13 dias que ninguém viu (#282) é o que ela existe para matar —
aviso que só aparece quando alguém pergunta não é aviso.

A busca de parecidas continua no FTS5, sem índice vetorial: medido em 200 sondagens
com o CLI real, o recall ficou em 82,0% global (74,6% em português, 89,2% em inglês).
O relatório está em `relatorios/2026-09-18-recall-fts5-reconciliacao.md`.

Nada disso mexe no `observar.cjs`: a captura não ganhou chamada de LLM nenhuma no
caminho da escrita, que é onde ela já tinha parado calada uma vez.

## 1.19.2 — 2026-09-19

**Este arquivo.** O plugin passa a trazer notas de atualização, e o contrato de
como mantê-las: versão nova entra aqui no mesmo commit que sobe o `version` do
`plugin.json`.

Ganhou versão própria porque a catraca `conferir-versao.cjs` exige número maior
em toda PR que não seja só estado de fluxo — e ela está certa: sem bump não há
versão nova para o `claude plugin update` buscar, e notas que ninguém baixa não
resolvem o problema que elas existem para resolver.

Junto, um adendo ao design do contrato de território (`docs/rainforest/design/`),
que não muda comportamento nenhum.

## 1.19.1 — 2026-09-17

**Rota com emoji de status por etapa** (Issue #299).

A regra 4 já mandava fechar cada etapa com "Fechamos [n]/[total]", mas não dizia em
que **formato** acompanhar o todo. Em tarefa longa o checkpoint contava o avanço e
não mostrava o mapa, e a pessoa perdia de vista quantas etapas faltavam e onde
estava. Agora a elaboração da regra 4 traz a rota — uma linha por etapa com marcador
de status — e a `modo-dev` aponta para ela.

Muda o que você vê na resposta; não muda comando, gate nem dado.

## 1.19.0 — 2026-09-17

Cinco issues fechadas, todas de trava que prometia mais do que cumpria.

- **Regra 6 agora diz em que repo "conserta na hora" vale** (#291). A regra mandava
  consertar defeito na hora e não dizia **onde**: o conserto saía no repositório do
  vizinho. Passou a ser explícita — defeito que atrapalha no repo **da sessão**
  conserta na hora; repo alheio é Issue + `Q`, nunca commit.
- **`gate-agente-em-voo` para de repetir o aviso a cada turno** (#298). O gate
  prometia avisar **uma** vez e, em sessão interativa, repetia no turno seguinte.
  A memória era de slot único e duas sessões alternando se sobrescreviam; virou mapa
  por sessão, com assinatura dos agentes em voo.
- **`gate-verificador-staged` volta a respeitar o marcador `dados-de-exemplo`** (#293).
  O marcador era ignorado e o toggle anunciado no cabeçalho do arquivo não existia —
  duas promessas sem implementação.
- **Mutantes de `testa-foco.sh` passam a morrer pelo comportamento certo** (#292).
  Os mutantes dos itens 9 e 13 morriam por `MODULE_NOT_FOUND`, não pela mutação:
  a bateria parecia provar e não provava nada.
- **Achados da revisão do ciclo anterior** (#294): catraca que rodava em cópia, `.pyc`
  no caminho de teste e conversão de caminho do MSYS.

## Antes da 1.19.0

Sem notas escritas. Para ver o que cada release carregou:

```
git log --grep="^Versao " --format="%ad %s" --date=short
```
