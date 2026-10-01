# Plano: Seis travas do semear de 2026-09-30

Design: docs/rainforest/design/2026-09-30-semear-travas.md

## Base e apuração (antes das tarefas)

Base conferida: `git rev-parse HEAD` = `9d9b0d583e388760643954c81705ab6f1bc38479`, design presente. O plano é escrito no worktree do planejador, branch `worktree-agent-a61201e296af22bc0`, e não toca a `main` nem a `fluxo/semear-travas`.

**Achado que contradiz o briefing (primeiro item, não nota de rodapé):**
- CONFIRMADO: o CI tem **um só** runner, `windows-latest`, com Node 24 (`.github/workflows/baterias.yml`, matriz `node: ['24']`, `runs-on: windows-latest`). Não existe job Linux. "Rodar no CI Windows e Linux" não é verificável neste repo: toda bateria nova tem de ser escrita portátil (`cygpath` com fallback, `mktemp`, nada de caminho fixo), mas só o Windows prova. Ver "Premissas".
- CONFIRMADO: `conferir-entrega.cjs` tem **gêmeo Python** (`scripts/conferir-entrega.py`) e o CI roda a mesma bateria contra os dois (`baterias.yml`, passo final). D2 muda os dois ou o CI fica vermelho.
- CONFIRMADO: `marcar --estagio plano` hoje não lê `tipo` nem `prova` (`extrairTarefas`, `conferir-fluxo.cjs:332`, regex da linha 342, devolve só `numero`, `nome`, `atende`, `mutacao`).
- CONFIRMADO: `conferir-mutacao.cjs:655` recusa `--de` que casa mais de uma vez. Todo `de:` deste plano tem de ser único no arquivo.
- CONFIRMADO: `cmdCreep` (`conferir-fluxo.cjs`) recusa arquivo tocado que não case com nenhum `arquivos:`. Por isso cada fixture e cada bateria nova está nomeada.
- CONFIRMADO: `skills/*/SKILL.md` têm teto de 16384 B e 500 linhas (`scripts/testa-teto-skills.sh:12-13`). `skills/executar/SKILL.md` está com 15341 B (folga de 1043 B); a tarefa 3 tem de ser neutra ou encolher.
- CONFIRMADO: `scripts/validar-colhidas.py:139-141` exige os itens `(j)` e `(k)` em `agents/executor.md` (existem, `executor.md:195` e `:231`). A tarefa 3 não pode apagá-los.

**Fatos que sustentam o plano (CONFIRMADO, com origem):**
- `estado.cjs:1206` `conferirFechamento`; o design roda `conferir-fluxo design` em `:1257`, o plano roda `cobertura` em `:1268` (o briefing dizia ~1256/~1258). As recusas se acumulam em `recusas[]`.
- `conferir-fluxo design` só é chamado por `estado.cjs` (grep em `scripts/`, `hooks/`, `.github/`). Logo D4 não reconfere design já aprovado **por construção**: a checagem só roda em `marcar --estagio design`. Nenhuma lista de isenção é necessária.
- `estado.cjs:745` empresta `extrairTarefas` de `conferir-fluxo.cjs` (`module.exports` em `conferir-fluxo.cjs:920`). Sandboxes de bateria copiam scripts avulsos (ex.: `testa-estado.sh:25`), então peça nova chamada pelo `estado.cjs` deve seguir o padrão `if (fs.existsSync(PORTOES))` (plugin antigo não inventa trava).
- `conferir-entrega.cjs:472` e `conferir-entrega.py:352`: sem `--base` só `aviso`. Única chamada de bateria sem `--base`: `scripts/testa-conferir-entrega.sh:228-231`. `hooks/lib/ponte-corpo.cjs:173` já cita `--base <hash>`.
- Prosa do ff-only a trocar: `agents/executor.md` (bloco "Antes de tudo", lista de "hashes velhos conhecidos"), `arqueologo.md`, `depurador.md`, `documentador.md`, `resolvedor-de-build.md`, `skills/executar/SKILL.md` (linhas ~65, ~85-86, ~98), `skills/rainforest-mind/references/regra-11.md` (~147-152).
- Convenção de caminho de script para agente: o agente nem sempre está no repo do plugin (`agents/executor.md:19-21` resolve `Despacho:` > `$CLAUDE_PLUGIN_ROOT` > raiz do repo). Decisão técnica desta tarefa: o **briefing** leva o comando de preparo literal com caminho absoluto; o agente não resolve caminho nenhum.
- Formato real de transcrição (`scripts/fixtures/utilidade/transcrito-sessao.jsonl`): linhas com `type` no topo (`user`/`assistant`/`system`/`attachment`) mais `message.role`; linha 3 = `user` com `content` string; linha 4 = `assistant` com `tool_use` `Bash`; linha 5 = `user` com `tool_result`; linha 6 = `assistant` com `text`. Envelope: `parentUuid, isSidechain, uuid, timestamp, userType, entrypoint, cwd, sessionId, version, gitBranch`.
- Bloqueio de hook em transcrição real local (1 amostra lida, caminhos omitidos): linha `user` com `content[0].type = "tool_result"`, `content` string começando `PreToolUse:Bash hook error:`, e chave de topo `toolDenialKind`.
- Payload real de `PreToolUse:Bash` de subagente: `hooks/fixtures/busca-raiz/payload-bash-subagente.json` (captura ao vivo de 2026-09-24; campos `agent_id`, `agent_type`, `tool_name`, `tool_input.command`, `tool_use_id`, `cwd`, `session_id`, `transcript_path`). Janela principal = mesmo payload sem `agent_id`/`agent_type` (INFERIDO: os gates testam `hasOwnProperty('agent_id')`, `gate-busca-raiz.cjs:137`).
- `varrer-baterias.sh` descobre por quatro globs: `scripts/testa-*.sh`, `hooks/testa-*.sh`, `scripts/testa-*.cjs`, `hooks/testa-*.cjs` (pisos 15/5/1/10). Toda bateria nova abaixo cai num deles, sem mexer no runner.
- `scripts/conferir-publicacao.cjs <arquivo>` sai 2 com telefone, e-mail, caminho de home, credencial e termos de `~/.rainforest/termos-proibidos.txt` (o arquivo existe). É o varredor de segredo que a fixture do D5 usa.
- As cinco ideias existem e estão `plantada` em `~/.rainforest/ideias.jsonl`: `briefing-que-proibe-background-nao-impede-o-background`, `rainforest-conferir-mutacao-envenena-o-pycache`, `catraca-bateria-vai-para-o-cmd-no-windows`, `limpar-remove-worktree-limpo-de-outra-sessao-sem-perguntar` (as quatro do D7) e `checador-deterministico-de-conformidade-de-regra-no-stop` (a que o D3 manda colher). Resolução no código: #347 = merge `c630a3e5` (`fluxo/agente-sem-background`, `git log --grep=347`); `conferir-mutacao.cjs:350-371` (bateria com `;`/`&&`/`||` recusada sob cmd.exe, `bash -c` quando há Git Bash) e `:352`/`:385` (`PYTHONDONTWRITEBYTECODE`, D25); `limpar-worktrees.cjs:197-208` (lê `locked`).

**Suposições (INFERIDO, cada uma dita onde pesa):**
- O transcrição já contém a última resposta do assistente quando o hook `Stop` roda (precedente: `gate-review-codex.cjs:54-71` lê `type === 'assistant'` no `Stop`). LACUNA: não há captura real de payload `Stop` no repo; só a de `SubagentStop` (`hooks/fixtures/veredito-revisor/`). Risco na tarefa 10.
- `ScheduleWakeup` e `Monitor` são nomes de ferramenta vindos do design D3; `Agent`/`Task` são confirmados pelo matcher `Task|Agent` em `hooks/hooks.json`.
- `gate-repo-alheio.cjs` avalia ferramentas de escrita (`:166-167`), não Bash; fica fora do replay do D5 como o briefing lista. `ferramentas-consulta.cjs` e `portaria.cjs` idem (não barram comando Bash por conteúdo). O executor da tarefa 13 confere isso lendo o arquivo e, se algum deles barrar Bash, inclui.

## Decisão do usuário (parar aqui, não seguir como se escolhido)

**U1. Conteúdo da fixture `hooks/fixtures/corpus-comandos/legitimos.jsonl` antes do commit (tarefa 12).** O repositório é público e a fonte são transcrições reais de clientes. Recomendação: a **janela principal** cura (não agente), roda o varredor e o usuário lê o diff de uma página antes do `git add`. Alternativa rejeitada: agente curando sozinho (não vê o que é cliente). A tarefa 12 não fecha sem a palavra dele.

Decisões técnicas assumidas sem consultar (reversíveis, sem impacto de produto): `gate-turno-prometido` nasce com `padrao: true` em `config.cjs` (o design manda bloquear, e há chave para desligar); léxico do D3 começa restrito às frases do design; `prova:` roda um worktree destacado por prova, timeout padrão 120 s (`RFM_PROVA_TIMEOUT_MS`); exit 126/127 de `prova:` conta como "prova que não executa" (recusa), timeout e ambiente contam como 69; `preparar-worktree.cjs` recusa rodar fora de worktree linkado (proteção: um agente perdido no checkout principal moveria a branch do usuário).

## O que não pode quebrar
- `bash scripts/testa-conferir-entrega.sh` verde contra `.cjs` e contra o gêmeo (`CONFERIR="python scripts/conferir-entrega.py"`).
- `bash scripts/testa-conferir-fluxo.sh`, `bash scripts/testa-estado.sh`, `bash scripts/testa-portoes-gate.sh`, `bash scripts/testa-recibo-fechar.sh`, `bash hooks/testa-ledger-fluxos.sh` continuam verdes: as fixtures que marcam plano ou design ganham o que as novas travas exigem, nunca o contrário.
- Catraca de bytes da abertura: `skills/rainforest-mind/SKILL.md` (núcleo antes de `<!-- detalhe -->`) **não é editado**; `node scripts/orcamento.cjs` segue ≤ 15600 B (hoje 15264 B, medido); `description` de agentes e skills não muda. `bash scripts/testa-teto-skills.sh` segue verde.
- `bash scripts/testa-conferir-categoria.sh`: peça nova em `hooks.json` ou `scripts/conferir-*.cjs` leva `// @categoria: sensor` na linha 2.
- `agents/executor.md` mantém os itens `(j)` e `(k)`.
- Design e plano já aprovados não são reconferidos (D1 e D4 só agem em `marcar`).
- Stop hook nunca gera laço: `stop_hook_active === true` sai 0.
- Nada de caminho de cliente, nome ou segredo em fixture versionada (repo público).
- CI já gasta 18-19 min de um teto de 35 (`baterias.yml`): cada bateria nova tem de rodar em ≤ 60 s medidos localmente, a do D5 em ≤ 120 s.
- A versão **não** é bumpada neste plano (fica para o `fechar`).
- Bateria com mais de 2 min leva `timeout` explícito na chamada do Bash; `scripts/varrer-baterias.sh` sem `--so` é da integração, não do agente.

## Convenção dos blocos `mutacao:` deste plano
`de:` é texto copiado do fonte. Quando a tarefa **cria** o arquivo, ou escreve a linha num arquivo existente, o `de:` é **o literal exato que a própria tarefa escreve**: o executor copia este texto para o código dele (nome de variável incluso) e depois inverte. Nesses casos `grep -F -c '<de>' <arquivo>` dá 0 **antes** da tarefa, por construção; nas tarefas 2, 5, 7 e 10 a linha existente que o literal novo substitui ou acompanha é única (contagem colada no relato) e garante que o `de:` fica único depois. Só a tarefa 13 tem `de:` já presente no fonte (contagem 1).

## Tarefas

### 1. preparar-worktree.cjs, o único passo de base do agente [tipo: implementar]
atende: D2
arquivos: `scripts/preparar-worktree.cjs`, `scripts/testa-preparar-worktree.sh`
depende de: nenhuma
paralela: sim
escopo: CLI `node scripts/preparar-worktree.cjs --hash <H> [--exige <arquivo>]...` (flag `--exige` repetível), rodada de dentro do worktree do agente. Ordem fixa: (a) recusa com exit 1 se o cwd não é worktree linkado (git-dir contém `worktrees`, mesma prova de `conferir-entrega.cjs`) e não move branch nenhuma; (b) resolve `H` com `git rev-parse --verify H^{commit}`; (c) HEAD == H: segue; senão `git merge-base --is-ancestor HEAD H` exit 0 faz `git merge --ff-only H`, exit ≠ 0 é divergência real (exit 1, nada editado, imprime HEAD encontrado e H esperado); (d) relê `HEAD` e exige == H; (e) cada `--exige` tem de existir no worktree, senão exit 1 nomeando o arquivo. stdout de sucesso: `base-ok <12 primeiros do hash> <toplevel>`. Exit 2 = uso (sem `--hash`, flag desconhecida), 69 = git ausente (`nao-verificavel:` na primeira linha do stderr, convenção do repo). Sem `git -C` (usar `cwd` do spawn): o `-C` sobe para o repo pai em silêncio.
mutacao:
  arquivo: `scripts/preparar-worktree.cjs`
  de: `if (!ancestral) falha(1, "divergencia real: HEAD nao e ancestral do hash do briefing");`
  para: `if (!ancestral) process.exit(0);`
  bateria: `bash scripts/testa-preparar-worktree.sh`
  fixture: testa-preparar-worktree.sh, caso "ramo divergente: exit 1 e HEAD intacto"
pronto quando: com um repositório descartável (`mktemp`, `git init`) de commits A<B<C e um worktree linkado criado em A, o comando roda de dentro do worktree e a base chega ao hash do briefing — provado por `bash scripts/testa-preparar-worktree.sh` (com `timeout: 300000` na chamada do Bash) imprimindo exatamente estas linhas, cada uma vinda de execução do script real:
  (1) `  ok    worktree em A avanca ate C com --hash C` e `  ok    HEAD final == hash do briefing` (cola também `git rev-parse HEAD` do worktree igual a C);
  (2) `  ok    ramo divergente: exit 1 e HEAD intacto`;
  (3) `  ok    checkout principal recusado, branch intacta` (rodado no repo principal da fixture, `git rev-parse HEAD` igual antes e depois);
  (4) `  ok    --exige arquivo ausente: exit 1 nomeando o arquivo` e `  ok    sem --hash: exit 2`;
  (5) última linha `== resultado: N ok, 0 falha(s) ==` com N >= 8.

### 2. --base obrigatório em conferir-entrega (cjs e gêmeo Python) [tipo: implementar]
atende: D2
arquivos: `scripts/conferir-entrega.cjs`, `scripts/conferir-entrega.py`, `scripts/testa-conferir-entrega.sh`
depende de: nenhuma
paralela: sim
escopo: no `.cjs`, `base` passa a `exige: true` em `OPCOES` (linha existente `base: { dest: "base" },`, contagem 1 no arquivo), a ajuda move `--base` para "Opcoes obrigatorias", e o ramo `else` do aviso "sem --base para conferir" (`:472`) sai (ficaria código morto). No `.py`, `--base` ganha `required=True` e o `else` do aviso (`:352`) sai. A bateria troca os casos de `testa-conferir-entrega.sh:228-231` ("sem --base ainda roda, com aviso", exit 0) por "sem --base sai 2 e o stderr cita `--base`".
mutacao:
  arquivo: `scripts/conferir-entrega.cjs`
  de: `base: { dest: "base", exige: true },`
  para: `base: { dest: "base" },`
  bateria: `bash scripts/testa-conferir-entrega.sh`
  fixture: testa-conferir-entrega.sh, caso "sem --base -> exit 2 (era aviso e exit 0)"
pronto quando: com o worktree de entrega real que a bateria monta (`$WT`, `$BASE`, `$HEAD_ANTES`), a chamada sem `--base` é recusada e com `--base` segue aprovando, nos dois motores — provado por:
  (1) `bash scripts/testa-conferir-entrega.sh` imprimindo `  ok    sem --base -> exit 2 (era aviso e exit 0)` e a linha `  ok    worktree real, base certa, tudo limpo -> aprovado` e terminando `0 falha(s) ==`;
  (2) `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` com as mesmas duas linhas e `0 falha(s) ==`;
  (3) `grep -c "briefing devia ter fixado" scripts/conferir-entrega.cjs scripts/conferir-entrega.py` devolvendo `scripts/conferir-entrega.cjs:0` e `scripts/conferir-entrega.py:0`.

### 3. A base do agente passa a ser o comando, não a prosa [tipo: docs]
atende: D2
arquivos: `agents/executor.md`, `agents/arqueologo.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/resolvedor-de-build.md`, `skills/executar/SKILL.md`, `skills/rainforest-mind/references/regra-11.md`, `scripts/testa-preparar-worktree.sh`
depende de: 1, 2
paralela: nao
escopo: nos cinco `agents/*.md`, o parágrafo "Antes de tudo, se despachado em worktree" troca a lista de hashes velhos e o `--ff-only` em prosa por: rodar o comando de preparo que o **briefing traz** (forma `node <caminho absoluto do briefing>/preparar-worktree.cjs --hash <hash do briefing> [--exige <arquivo>]...`), colar a saída, e `exit` diferente de 0 = PARE e reporte; briefing sem esse comando = PARE e reporte como primeiro achado. Continuam: `git rev-parse --show-toplevel` colado, "nunca `git -C`", e a reconferência do pai antes de commitar. Em `skills/executar/SKILL.md`, o bullet do briefing (`--is-ancestor`/`ff-only`, ~:85-86) vira "o briefing leva o comando de preparo literal com caminho absoluto, montado com `git rev-parse`, nunca digitado"; o trecho ~:65 e ~:98 acompanha; a nota de integração diz que `--base` é obrigatório. Em `regra-11.md` a lista (2) (~:147-152) vira o comando. Cuidado de bytes: `executar/SKILL.md` tem 1043 B de folga e teto duro de 16384 B; editar encolhendo. A seção nova de `testa-preparar-worktree.sh` liga a prosa ao script: para cada um dos sete arquivos, toda flag `--x` citada perto de `preparar-worktree.cjs` é aceita pelo script, e a forma canônica roda num worktree de fixture com HEAD atrasado.
mutacao: n/a
  motivo: tarefa de texto sem comportamento a inverter; a falsificação é a coerência entre a prosa e o script da tarefa 1 (flags reais, comando que funciona) e a ausência da instrução antiga divergente, medidas abaixo.
pronto quando: com os sete arquivos editados, a instrução de base é uma só e coincide com o script real — provado por:
  (1) `grep -c "hashes velhos" agents/executor.md agents/arqueologo.md agents/depurador.md agents/documentador.md agents/resolvedor-de-build.md skills/executar/SKILL.md skills/rainforest-mind/references/regra-11.md` devolvendo `:0` nos sete;
  (2) `bash scripts/testa-preparar-worktree.sh` imprimindo `  ok    prosa dos 7 arquivos so cita flags que o script aceita` e `  ok    comando canonico da prosa leva worktree atrasado ate o hash` e `0 falha(s) ==`;
  (3) `grep -c "(j)" agents/executor.md` e `grep -c "(k)" agents/executor.md` ambos >= 1 (o `validar-colhidas.py` não quebra);
  (4) `bash scripts/testa-teto-skills.sh` sem `FALHA` e `node scripts/orcamento.cjs` terminando em `Total: ` com valor <= 15600 B.

### 4. conferir-prova.cjs: a `prova:` executa na base e tem de falhar [tipo: implementar]
atende: D1
arquivos: `scripts/conferir-prova.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-prova.sh`, `scripts/testa-conferir-categoria.sh`
depende de: nenhuma
paralela: sim
escopo: (a) `extrairTarefas` em `conferir-fluxo.cjs` passa a devolver também `tipo` (do `[tipo: X]` do cabeçalho, minúsculo, vazio se ausente), `prova` (string do comando, só da linha inteira `prova: \`<comando>\`` com um único par de crases; `null` se ausente), `provaMalformada` (linha `prova:` que não casa a forma) e `provaNaBase` (texto da linha `prova-na-base: verde — <motivo>`, separador travessão; `null` se ausente). Campos antigos intocados. (b) `scripts/conferir-prova.cjs` (`// @categoria: sensor` na linha 2): `node scripts/conferir-prova.cjs plano --slug <s> [--plano <arquivo>]`. Tarefa de tipo `implementar`, `teste` ou sem tipo: com `prova-na-base: verde — <motivo não vazio>` é aceita sem executar e o motivo vai ao stdout; sem `prova` nem `prova-na-base`, ou com `prova` malformada, é recusada nomeando a tarefa; com `prova`, roda `bash -c <comando>` num `git worktree add --detach <tmp> HEAD` descartável (um por prova, cwd do worktree, stdout/stderr capturados e truncados, timeout padrão 120 s sobrescrevível por `RFM_PROVA_TIMEOUT_MS`): saída 0 é recusa (exit 2, nomeia tarefa e comando: o critério já passa na base), 126/127 é recusa ("a prova não executa"), timeout ou falha de ambiente é exit 69 (`nao-verificavel:`), qualquer outro exit ≠ 0 é aceito. Tipos `docs`, `pesquisar`/`pesquisa`, `configurar` são isentos. O worktree é removido (`worktree remove --force` e `prune`) em todo caminho de saída, sinal incluso. Exit 1 = erro de uso, como `conferir-fluxo.cjs`.
mutacao:
  arquivo: `scripts/conferir-prova.cjs`
  de: `if (resultado.status === 0) {`
  para: `if (resultado.status !== 0) {`
  bateria: `bash scripts/testa-conferir-prova.sh`
  fixture: testa-conferir-prova.sh, caso "prova que sai 0 na base: exit 2 nomeando a tarefa"
pronto quando: com um plano no formato real (copiado de `docs/rainforest/planos/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md` e ganhando `prova:` por `awk`, como `plano_no_formato` de `testa-conferir-fluxo.sh`) num repositório descartável com commit, as recusas e aceites saem pelo motivo certo — provado por `bash scripts/testa-conferir-prova.sh` (com `timeout: 300000`) imprimindo:
  (1) `  ok    prova que sai 0 na base: exit 2 nomeando a tarefa` e `  ok    prova que sai 1 na base: aceita, exit 0`;
  (2) `  ok    tipo docs sem prova: isento` e `  ok    implementar sem prova nem prova-na-base: exit 2`;
  (3) `  ok    prova-na-base com motivo: aceita sem executar (sentinela ausente)` e `  ok    prova-na-base sem motivo: exit 2`;
  (4) `  ok    comando inexistente (127): exit 2, a prova nao executa`;
  (5) `  ok    timeout: exit 69 e git worktree list igual ao de antes` e `  ok    prova que grava arquivo nao deixa rastro no repo (status limpo)`;
  (6) `bash scripts/testa-conferir-fluxo.sh` segue terminando `0 falha(s) ==` (a extensão de `extrairTarefas` não quebrou os campos antigos).

### 5. O `marcar --estagio plano` chama a prova [tipo: implementar]
atende: D1
arquivos: `scripts/estado.cjs`, `scripts/testa-conferir-prova.sh`, `scripts/testa-conferir-fluxo.sh`, `scripts/testa-portoes-gate.sh`, `scripts/testa-estado.sh`, `scripts/testa-recibo-fechar.sh`, `hooks/testa-ledger-fluxos.sh`, `skills/plano/SKILL.md`
depende de: 4
paralela: nao
escopo: em `conferirFechamento`, junto das outras checagens do estágio `plano`, `const PROVA = path.join(__dirname, 'conferir-prova.cjs');` (ao lado de `PORTOES`/`RECIBO`, `:1188`) e, com `fs.existsSync(PROVA)` e plano em disco, `const r = rodarChecador(PROVA, ['plano', '--slug', slug, '--plano', docDoEstagio('planos', slug, estado)], estagio);` seguido de `if (r) recusas.push(r);` (as recusas se acumulam, como hoje). A linha existente `const r = rodarChecador(CHECADOR, args, estagio);` (contagem 1) fica intacta. As baterias que marcam plano em sandbox com o `estado.cjs` real ganham `prova-na-base: verde — fixture de bateria` na cópia do plano (mesmo ponto onde `plano_no_formato` injeta `mutacao:`); só as que ficarem vermelhas são editadas. `skills/plano/SKILL.md` documenta no template e na seção de campos: `prova:` (linha inteira, um par de crases, comando que tem de FALHAR na base), `prova-na-base: verde — <motivo>` e a isenção por tipo; cabe na folga (3124 B).
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `const r = rodarChecador(PROVA, ['plano', '--slug', slug, '--plano', docDoEstagio('planos', slug, estado)], estagio);`
  para: `const r = null;`
  bateria: `bash scripts/testa-conferir-prova.sh`
  fixture: testa-conferir-prova.sh, caso "marcar plano ok com prova verde na base: exit 2 pelo estado.cjs"
pronto quando: com um fluxo real de sandbox (estado iniciado por `estado.cjs`, design aprovado, plano em disco com tarefa `implementar` cuja `prova:` sai 0 na base), o `marcar` recusa, e com a prova vermelha na base fecha — provado por:
  (1) `bash scripts/testa-conferir-prova.sh` imprimindo `  ok    marcar plano ok com prova verde na base: exit 2 pelo estado.cjs`, `  ok    marcar plano ok com prova vermelha na base: exit 0` e `  ok    a recusa do marcar cita a prova (nao outra checagem)`;
  (2) `bash scripts/testa-conferir-fluxo.sh`, `bash scripts/testa-estado.sh` (com `timeout: 600000`), `bash scripts/testa-portoes-gate.sh`, `bash scripts/testa-recibo-fechar.sh` e `bash hooks/testa-ledger-fluxos.sh` cada uma terminando sem nenhuma linha `FALHA`;
  (3) `bash scripts/testa-teto-skills.sh` sem `FALHA` (plano/SKILL.md cabe no teto).

### 6. varrer.cjs: a varredura do que o repo já sabia vira arquivo [tipo: implementar]
atende: D4
arquivos: `scripts/varrer.cjs`, `scripts/testa-varrer.sh`
depende de: nenhuma
paralela: sim
escopo: `node scripts/varrer.cjs --slug <s> <termo>...` (um ou mais termos) grava `docs/rainforest/varredura/<slug>.txt` com a data, os termos, **cada comando executado** e sua saída, nesta ordem de fontes: Issues abertas e fechadas (`gh issue list --state all --search <termo> --json number,title,state`), PRs em todos os estados (`gh pr list --state all ...`), branches remotas (`git ls-remote --heads origin` filtrado pelo termo), `git log --all --grep=<termo> --oneline`, e `ideias.jsonl` (raiz resolvida por `hooks/lib/raiz.cjs`, como `ideias.cjs:32-39`) **só `id` e `titulo`**: o arquivo é versionado em repo público e `descricao`/`contexto` são dado privado. O estado vem de uma constante `const ESTADO_TODOS = "all";` usada nos dois `gh`. O executável do `gh` é sobrescrevível por `RFM_VARRER_GH` (a bateria usa dublê em Node; nenhum acesso à rede nem ao `gh` real na bateria). `gh` ausente ou sem autenticação: exit 69 (`nao-verificavel:`) e **nenhum arquivo gravado** (varredura que não olhou não é varredura). Sem `--slug` ou sem termo: exit 2. Só lê; escreve apenas o `.txt`.
mutacao:
  arquivo: `scripts/varrer.cjs`
  de: `const ESTADO_TODOS = "all";`
  para: `const ESTADO_TODOS = "open";`
  bateria: `bash scripts/testa-varrer.sh`
  fixture: testa-varrer.sh, caso "Issue FECHADA com o termo aparece na varredura (o caso #253)"
pronto quando: com um repositório descartável que tem uma branch e um commit citando o termo, um `ideias.jsonl` de sandbox (`RFM_ROOT`) com uma ideia que tem `descricao` secreta, e um dublê de `gh` que só devolve a Issue fechada quando chamado com `--state all`, o arquivo gravado traz tudo isso e nada mais — provado por `bash scripts/testa-varrer.sh` (com `timeout: 300000`) imprimindo:
  (1) `  ok    Issue FECHADA com o termo aparece na varredura (o caso #253)` e `  ok    PR fechado e branch remota e commit aparecem`;
  (2) `  ok    ideia sai so com id e titulo (descricao secreta ausente do .txt)`;
  (3) `  ok    gh ausente: exit 69 e nenhum arquivo gravado`;
  (4) `  ok    o .txt cita cada comando executado` e `  ok    sem termo: exit 2`;
  (5) `== resultado: N ok, 0 falha(s) ==`.

### 7. O design só é aprovado com `## Varredura` que cita arquivo real [tipo: implementar]
atende: D4
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`, `scripts/testa-estado.sh`, `scripts/testa-portoes-gate.sh`, `skills/brainstorm/SKILL.md`
depende de: 4, 5, 6
paralela: nao
escopo: em `cmdDesign` (`conferir-fluxo.cjs:77`), `'## Varredura',` entra em `secoes_obrigatorias` (ao lado da linha existente `'## Em aberto',`, contagem 1) e a seção tem de citar literalmente `docs/rainforest/varredura/<slug>.txt` do próprio slug, cujo arquivo (sob `RAIZ`) existe e não está vazio: `if (!fs.existsSync(arquivoVarredura) || fs.statSync(arquivoVarredura).size === 0) {` recusa com exit 2 nomeando o caminho. A exigência vive só em `cmdDesign`, que só o `marcar --estagio design` chama (grep em `scripts/`, `hooks/`, `.github/`), então design aprovado antes da entrega não é reconferido. As fixtures de bateria que escrevem design em disco e marcam (`"Decisões fechadas"` aparece em `testa-conferir-fluxo.sh` ×2, `testa-estado.sh:1418`, `testa-portoes-gate.sh` ×2) ganham a seção e um `.txt` não vazio **na cópia de sandbox** (os designs reais versionados não são reescritos). `skills/brainstorm/SKILL.md` (6030 B, folga grande) manda rodar `node scripts/varrer.cjs --slug <slug> <termo>...` antes de gravar o design e citar o arquivo em `## Varredura`.
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `if (!fs.existsSync(arquivoVarredura) || fs.statSync(arquivoVarredura).size === 0) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: testa-conferir-fluxo.sh, caso "design cita varredura inexistente ou vazia: exit 2"
pronto quando: com um design no formato real (cópia de `docs/rainforest/design/2026-08-21-gate-de-sessao-co-locada-e-catraca-de-mutacao.md` num sandbox) o `design` recusa nos três defeitos e aceita o design certo, e um design **antigo** marcado antes continua marcado — provado por:
  (1) `bash scripts/testa-conferir-fluxo.sh` (com `timeout: 600000`) imprimindo `  ok    design sem secao Varredura: exit 2`, `  ok    design cita varredura inexistente ou vazia: exit 2`, `  ok    design com varredura real e nao vazia: exit 0` e `  ok    design ja aprovado nao e reconferido (estado.cjs so roda a checagem no marcar)`;
  (2) com este mesmo design (anterior à trava, cuja seção `## Varredura` descreve varredura manual e não cita `.txt`), `node scripts/conferir-fluxo.cjs design --slug 2026-09-30-semear-travas; echo $?` devolvendo `2` (a trava é real) **e** o estado dele seguindo aprovado, pois nada o reconfere: `node -e "console.log(require('./docs/rainforest/estado/2026-09-30-semear-travas.json').design.status)"` imprimindo `aprovado`;
  (3) `bash scripts/testa-estado.sh` e `bash scripts/testa-portoes-gate.sh` sem nenhuma linha `FALHA`.

### 8. substituir.cjs: edição literal com asserção [tipo: implementar]
atende: D6
arquivos: `scripts/substituir.cjs`, `scripts/testa-substituir.sh`
depende de: nenhuma
paralela: sim
escopo: `node scripts/substituir.cjs --arquivo <F> --de <arquivo-com-o-texto-antigo> --para <arquivo-com-o-texto-novo> [--ocorrencias N]` (padrão 1). `--de` e `--para` são **caminhos de arquivo** cujo conteúdo é o literal (nada passa pelo shell); um `\n` final de cada um é removido uma vez (heredoc sempre o acrescenta). Conta as ocorrências de `de` em `F`; `const esperado = ...` vem de `--ocorrencias`; divergência sai 1 **sem alterar `F`**; troca por `split`/`join` (nunca `String.replace`: `$` e `` $` `` no texto novo corrompem, registrado em memória do usuário); grava em temporário + rename; relê e confere que o texto novo está presente na contagem esperada e que o antigo sumiu (pulando este segundo teste quando o novo contém o antigo); `de` vazio, arquivo ausente ou flag desconhecida = exit 2. Preserva o restante do arquivo byte a byte.
mutacao:
  arquivo: `scripts/substituir.cjs`
  de: `if (ocorrencias !== esperado) falha(1, "contagem divergente");`
  para: `if (false) falha(1, "contagem divergente");`
  bateria: `bash scripts/testa-substituir.sh`
  fixture: testa-substituir.sh, caso "contagem divergente: exit 1 e arquivo byte a byte intacto"
pronto quando: com um arquivo-alvo real (um `.cjs` com contrabarra, `$` e crase, copiado de `scripts/ideias.cjs` para o sandbox) e de/para gravados por heredoc, a troca é exata e a contagem errada não grava — provado por `bash scripts/testa-substituir.sh` imprimindo:
  (1) `  ok    contagem divergente: exit 1 e arquivo byte a byte intacto` (comparação por `cmp` antes/depois);
  (2) `  ok    texto novo com $ e contrabarra entra literal` e `  ok    texto novo com dollar-crase nao insere o arquivo inteiro`;
  (3) `  ok    --ocorrencias 3 troca as tres` e `  ok    novo contem o antigo: troca uma vez e nao acusa residuo`;
  (4) `  ok    resto do arquivo preservado byte a byte` e `== resultado: N ok, 0 falha(s) ==`.

### 9. O `substituir.cjs` é citado onde se edita [tipo: docs]
atende: D6
arquivos: `scripts/contrato-plugin-codex.cjs`, `skills/modo-dev/SKILL.md`, `agents/executor.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/resolvedor-de-build.md`, `scripts/testa-substituir.sh`
depende de: 3, 8
paralela: nao
escopo: uma frase curta em cada arquivo: edição por literal com risco de escape (contrabarra, `$`, crase) usa `node scripts/substituir.cjs --arquivo F --de <arq> --para <arq> [--ocorrencias N]` com asserção de contagem; sem hook que obrigue (o design descartou). `modo-dev` (13464 B, folga de 2920 B) leva a explicação de uma linha do porquê (`literal-com-escape-e-erro-que-nao-da-erro`, três vezes num dia). Depende da tarefa 3 porque os mesmos quatro agentes são editados lá.
mutacao: n/a
  motivo: texto sem comportamento a inverter; a falsificação é a coerência com as flags reais do script da tarefa 8.
pronto quando: com os cinco arquivos editados, a forma de invocação que eles ensinam é a que o script aceita e a mesma troca feita por ela preserva texto com contrabarra — provado por:
  (1) `bash scripts/testa-substituir.sh` imprimindo `  ok    prosa dos 5 arquivos so cita flags que o script aceita` (seção nova, que lê as flags após `substituir.cjs` nos cinco arquivos e roda cada uma contra o script) e `0 falha(s) ==`;
  (2) `bash scripts/testa-teto-skills.sh` sem `FALHA`; `bash scripts/testa-perfil.sh` sem `FALHA` (lê `agents/executor.md`);
  (3) `grep -c "(j)" agents/executor.md` >= 1.

### 10. gate-turno-prometido: o turno que promete e não faz é barrado [tipo: implementar]
atende: D3
arquivos: `hooks/gate-turno-prometido.cjs`, `hooks/testa-gate-turno-prometido.cjs`, `hooks/fixtures/turno-prometido/promete-sem-despachar.jsonl`, `hooks/fixtures/turno-prometido/promete-e-despacha.jsonl`, `hooks/fixtures/turno-prometido/despacho-so-no-turno-anterior.jsonl`, `hooks/fixtures/turno-prometido/promessa-antes-do-tool-result.jsonl`, `hooks/fixtures/turno-prometido/espera-ci-sem-vigia.jsonl`, `hooks/fixtures/turno-prometido/espera-ci-com-background.jsonl`, `hooks/fixtures/turno-prometido/passado-despachei.jsonl`, `hooks/fixtures/turno-prometido/passado-e-promessa-na-mesma-mensagem.jsonl`, `hooks/fixtures/turno-prometido/aguardando-a-build-sem-vigia.jsonl`, `hooks/fixtures/turno-prometido/bloco-de-codigo.jsonl`, `hooks/fixtures/turno-prometido/citacao-no-texto.jsonl`, `hooks/fixtures/turno-prometido/espera-ci-com-powershell-background.jsonl`, `hooks/fixtures/turno-prometido/lista-de-estado.jsonl`, `hooks/fixtures/turno-prometido/promete-e-dispara-workflow.jsonl`, `hooks/fixtures/turno-prometido/promete-e-envia-mensagem.jsonl`, `hooks/fixtures/turno-prometido/negacao-de-despacho.jsonl`, `hooks/fixtures/turno-prometido/aspa-solta-antes-da-promessa.jsonl`, `hooks/fixtures/turno-prometido/crase-solta-antes-da-promessa.jsonl`, `hooks/lib/config.cjs`, `hooks/hooks.json`, `hooks/testa-config.sh`, `hooks/testa-titulo-sessao-registro.sh`
depende de: nenhuma
paralela: sim
escopo: hook `Stop` (`// @categoria: sensor` na linha 2), lê o payload do stdin e a transcrição em `transcript_path`. Saídas 0 em silêncio: chave `gate-turno-prometido` desligada (`require('./lib/config.cjs').ligado(...)`, como `gate-agente-em-voo.cjs:152`), `stop_hook_active === true`, payload com `agent_id`, payload ou transcrição ilegível (um aviso no stderr, nunca derruba a sessão). O **turno** = linhas da transcrição depois da última mensagem `user` que não seja `tool_result` (conteúdo string, ou array sem bloco `tool_result`); linhas com `isSidechain: true` ignoradas. Caso (a): o último bloco `text` do turno promete despacho no futuro ou em andamento ("vou despachar", "despachando", "disparo agora" e as variantes do design) e o turno não tem `tool_use` `Agent` nem `Task`: exit 2 com mensagem em português dizendo o que fazer (despachar agora, ou dizer de quem é a bola). Caso (b): o texto diz que espera máquina ("CI rodando", "aguardando o CI/build") e o turno não tem `Bash` com `input.run_in_background === true`, nem `Monitor`, nem `ScheduleWakeup`: exit 2. Passado ("despachei", "já despachado") não dispara. `hooks/lib/config.cjs` ganha a chave `'gate-turno-prometido'` (`tipo: 'boolean'`, `padrao: true`, `descricao` em uma linha), logo depois de `'gate-agente-em-voo'` (a linha existente `'subagente-sem-gh': {` tem contagem 1 e fica intacta). `hooks/hooks.json` registra o hook em um novo grupo `Stop` após o de `gate-agente-em-voo` (`hooks/gate-agente-em-voo.cjs` aparece 1 vez no arquivo). As fixtures `.jsonl` são escritas **no formato real**: a mesma forma e o mesmo envelope das linhas 3 a 6 de `scripts/fixtures/utilidade/transcrito-sessao.jsonl`, nunca esquema inventado; a bateria tem um caso que confere o conjunto de chaves de cada linha das fixtures contra o envelope da fixture real. Se `hooks/testa-config.sh` enumerar chaves, ela é atualizada.
mutacao:
  arquivo: `hooks/gate-turno-prometido.cjs`
  de: `if (ev.stop_hook_active === true) process.exit(0);`
  para: `if (ev.stop_hook_active === false) process.exit(0);`
  bateria: `node hooks/testa-gate-turno-prometido.cjs`
  fixture: testa-gate-turno-prometido.cjs, caso "promete sem despachar com stop_hook_active true: exit 0 (sem laco)"
pronto quando: com o payload de `Stop` (`{"session_id":"s1","cwd":"<sandbox>","transcript_path":"<fixture>","hook_event_name":"Stop"}`) e as transcrições-fixture no formato real, o hook barra só o que prometeu sem fazer — provado por `node hooks/testa-gate-turno-prometido.cjs` (com `timeout: 120000`) imprimindo:
  (1) `  ok   o comando registrado em hooks.json (com CLAUDE_PLUGIN_ROOT resolvido) barra promete-sem-despachar.jsonl: exit 2` (o comando lido do próprio `hooks.json`, não digitado);
  (2) `  ok   promete-e-despacha.jsonl: exit 0` e `  ok   despacho-so-no-turno-anterior.jsonl: exit 2` e `  ok   promessa-antes-do-tool-result.jsonl: exit 0` (prova a fronteira do turno);
  (3) `  ok   espera-ci-sem-vigia.jsonl: exit 2`, `  ok   espera-ci-com-background.jsonl: exit 0`, `  ok   passado-despachei.jsonl: exit 0`;
  (4) `  ok   promete sem despachar com stop_hook_active true: exit 0 (sem laco)`, `  ok   payload com agent_id: exit 0`, `  ok   transcricao ausente ou ilegivel: exit 0`, `  ok   chave desligada: exit 0`;
  (5) `  ok   fixtures no formato real (chaves de cada linha cobrem o envelope de transcrito-sessao.jsonl)` e `ok: N   falhou: 0`;
  (6) `bash hooks/testa-config.sh` e `bash scripts/testa-conferir-categoria.sh` sem nenhuma linha `FALHA`.
LACUNA declarada: não há captura real de payload `Stop` nem prova de que a última resposta já está na transcrição no instante do hook; o `verificar` deve registrar uma sessão real (`claude -p`) em que o hook dispara, ou dizer que não foi medido.

### 11. extrair-corpus-comandos.cjs: candidatos de comando a partir de transcrições locais [tipo: implementar]
atende: D5
arquivos: `scripts/extrair-corpus-comandos.cjs`, `scripts/testa-extrair-corpus-comandos.cjs`, `scripts/fixtures/corpus/projetos/p1/sessao.jsonl`, `scripts/fixtures/corpus/projetos/p1/sessao/subagents/agent-x.jsonl`
depende de: nenhuma
paralela: sim
escopo: `node scripts/extrair-corpus-comandos.cjs [--raiz <dir>]... [--max N] > candidatos.jsonl`. Sem `--raiz`, lê `~/.claude*/projects/**/*.jsonl` (todo diretório do home que comece por `.claude`), **somente leitura** (nada é gravado nas raízes nem no repo; a saída vai só ao stdout). Para cada `tool_use` `Bash` de linha `assistant`, casa o `tool_result` pelo `tool_use_id`; descarta o comando cujo resultado é bloqueio de hook (`const bloqueado = /^PreToolUse:[A-Za-z]+ hook error:/.test(texto);`, forma vista em transcrição real) ou que não tem resultado; deduplica por comando; emite `{"id":"<8 primeiros do sha1>","comando":"...","contexto":"principal"|"subagente"}` (subagente = arquivo sob `/subagents/` ou `isSidechain: true`). Resumo no stderr (lidos, emitidos, bloqueados) com o aviso de que a saída carrega dado local e nunca se commita sem curadoria. As fixtures seguem o formato real (`type` no topo, `message.role`, `tool_use` com `id`, `tool_result` com `tool_use_id`, bloqueio com `toolDenialKind`).
mutacao:
  arquivo: `scripts/extrair-corpus-comandos.cjs`
  de: `const bloqueado = /^PreToolUse:[A-Za-z]+ hook error:/.test(texto);`
  para: `const bloqueado = false;`
  bateria: `node scripts/testa-extrair-corpus-comandos.cjs`
  fixture: testa-extrair-corpus-comandos.cjs, caso "comando bloqueado por hook nao vira candidato"
pronto quando: com a pasta-fixture `scripts/fixtures/corpus/projetos` (uma sessão com Bash liberado, Bash bloqueado por hook, Bash sem resultado, outra ferramenta, e um arquivo de subagente) o extrator devolve exatamente os liberados e não toca no disco de origem — provado por `node scripts/testa-extrair-corpus-comandos.cjs` imprimindo:
  (1) `  ok   comando liberado vira candidato com contexto principal` e `  ok   comando do arquivo de subagente vem com contexto subagente`;
  (2) `  ok   comando bloqueado por hook nao vira candidato` e `  ok   Bash sem tool_result nao vira candidato` e `  ok   outra ferramenta e ignorada`;
  (3) `  ok   mesmo comando duas vezes sai uma so`;
  (4) `  ok   somente leitura: hash de todos os arquivos da raiz igual antes e depois`;
  (5) `ok: N   falhou: 0`.

### 12. Curadoria da fixture legitimos.jsonl (janela principal, com a palavra do usuário) [tipo: configurar]
atende: D5
arquivos: `hooks/fixtures/corpus-comandos/legitimos.jsonl`, `hooks/fixtures/corpus-comandos/esperados.json`
depende de: 11
paralela: nao
escopo: **feita pela janela principal, não por agente** (lê transcrição de cliente; ver decisão U1). Roda o extrator da tarefa 11 sobre as transcrições locais, e curadoria à mão escolhe de 40 a 60 comandos Bash reais e variados, substituindo caminho de cliente, nome e segredo por equivalentes sintéticos consistentes. Formato de linha: `{"id":"c001","comando":"..."}`. Entra obrigatoriamente o comando âncora `{"id":"c-ancora-add","comando":"git add scripts/estado.cjs"}` (a tarefa 13 o usa na mutação). `esperados.json` nasce `[]`; cada entrada futura é `{"id","gate","contexto","motivo","issue"}` (`issue` é número, ou `null` até a janela abrir a Issue do achado, como manda o design).
mutacao: n/a
  motivo: arquivo de dado curado, sem comportamento a inverter; o que ele faz é medido pela tarefa 13 (replay contra os gates e varredura de segredo) e pelo varredor abaixo.
pronto quando: com o `legitimos.jsonl` curado e lido pelo usuário, nada nele tem forma de segredo, caminho de home, e-mail, telefone ou termo proibido, e a âncora está presente — provado por:
  (1) `node scripts/conferir-publicacao.cjs hooks/fixtures/corpus-comandos/legitimos.jsonl` devolvendo exit 0;
  (2) `grep -n -i -E 'C:(\\\\|/)+Users|/c/Users|Microsiga|protheus|token|senha|passw|secret|api[_-]?key|Bearer |ghp_|sk-[A-Za-z0-9]|AKIA|BEGIN [A-Z ]*PRIVATE' hooks/fixtures/corpus-comandos/legitimos.jsonl` sem nenhuma linha (exit 1);
  (3) `wc -l hooks/fixtures/corpus-comandos/legitimos.jsonl` entre 40 e 60 e `grep -F -c '"comando":"git add scripts/estado.cjs"' hooks/fixtures/corpus-comandos/legitimos.jsonl` devolvendo `1`;
  (4) a palavra do usuário (U1) registrada na mensagem do commit da fixture.

### 13. Replay: cada comando legítimo contra cada gate de Bash [tipo: teste]
atende: D5
arquivos: `hooks/testa-corpus-comandos.cjs`, `hooks/fixtures/corpus-comandos/esperados.json`
depende de: 11, 12
paralela: nao
escopo: `hooks/testa-corpus-comandos.cjs` (descoberto pelo glob `hooks/testa-*.cjs`). Para cada um dos dez gates `gate-worktree`, `gate-staging-total`, `gate-verificador-staged`, `gate-mensagem-commit`, `gate-fechar-issue`, `gate-git-verificacao`, `gate-publicacao-destino`, `gate-busca-raiz`, `gate-bateria-sem-timeout`, `gate-subagente-sem-gh` (`hooks/<nome>.cjs`), para cada comando de `legitimos.jsonl` e nos dois contextos, roda o gate como processo real com o payload no stdin: base = `hooks/fixtures/busca-raiz/payload-bash-subagente.json` (real) com `tool_input.command` trocado; contexto principal = mesmo payload sem `agent_id`/`agent_type`; `cwd` e `CLAUDE_PROJECT_DIR`/`RFM_ROOT` apontam para um repositório de sandbox (`mktemp` + `git init` + commit), nunca para `~/.rainforest` nem `~/.claude*`. Exit 2 fora de `esperados.json` é FALHA (imprime id, gate, contexto, primeira linha do stderr); entrada de `esperados` que não barrou mais também é FALHA (a lista apodrece). Com `RFM_CORPUS_LOCAL=<arquivo>` (mesmo formato) roda também esse corpus, sem `esperados`, e lista cada bloqueio como achado. A bateria inclui um caso que roda o varredor de segredo sobre a própria fixture (`conferir-publicacao.cjs`, exit 0) para o CI repetir a tarefa 12 sempre. Imprime o tempo gasto. O executor confere em `hooks/gate-repo-alheio.cjs`, `ferramentas-consulta.cjs` e `portaria.cjs` se algum barra `Bash` por conteúdo; se barrar, entra na lista. Achado que a bateria revelar vira linha em `esperados.json` com `issue: null` e sai no relato para a janela principal abrir a Issue; **não se conserta o gate aqui** (fora de escopo do design).
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `const CAMINHO_TOTAL = new Set([".", "./", ":/", "*", "-A", "--all", "-u", "--update"]);`
  para: `const CAMINHO_TOTAL = new Set([".", "./", ":/", "*", "-A", "--all", "-u", "--update", "scripts/estado.cjs"]);`
  bateria: `node hooks/testa-corpus-comandos.cjs`
  fixture: testa-corpus-comandos.cjs, caso "c-ancora-add nao e barrado por gate-staging-total em nenhum contexto"
pronto quando: com o `legitimos.jsonl` curado (40 a 60 comandos reais) e os payloads reais, nenhum gate barra comando legítimo sem registro, e um gate que passasse a barrar a âncora deixa a bateria vermelha — provado por `node hooks/testa-corpus-comandos.cjs` (com `timeout: 300000`) imprimindo:
  (1) uma linha `  ok   <gate>: N comando(s) x 2 contexto(s), 0 bloqueio(s) fora de esperados` para cada um dos dez gates;
  (2) `  ok   c-ancora-add nao e barrado por gate-staging-total em nenhum contexto`;
  (3) `  ok   esperados.json sem entrada apodrecida` e `  ok   fixture passa no varredor de segredo (conferir-publicacao exit 0)`;
  (4) `  ok   RFM_CORPUS_LOCAL com git add -A lista o bloqueio como achado` (arquivo temporário de 3 comandos, um deles `git add -A`);
  (5) `tempo: <s> s` com valor <= 120 (medido localmente) e `ok: N   falhou: 0`.

### 14. Colher as cinco ideias resolvidas (janela principal, no fechar) [tipo: configurar]
atende: D7, D3
arquivos: `docs/rainforest/planos/2026-09-30-semear-travas.md`
depende de: 10
paralela: nao
escopo: **feita pela janela principal no `fechar`, não por agente**: `node scripts/ideias.cjs colher --id <id>` com `{"resultado":"..."}` no stdin (arquivo temporário fora do repo), escreve em `~/.rainforest/ideias.jsonl`, fora do worktree (porta única de escrita; o agente não escreve ali). Cinco colheitas, cada `resultado` citando a evidência já conferida: `briefing-que-proibe-background-nao-impede-o-background` (PR #347, merge `c630a3e5`, `fluxo/agente-sem-background`); `rainforest-conferir-mutacao-envenena-o-pycache` (`conferir-mutacao.cjs:352,385`, D25); `catraca-bateria-vai-para-o-cmd-no-windows` (`conferir-mutacao.cjs:350-371`); `limpar-remove-worktree-limpo-de-outra-sessao-sem-perguntar` (`limpar-worktrees.cjs:197-208`, lê `locked`); `checador-deterministico-de-conformidade-de-regra-no-stop` (tarefa 10 deste fluxo, `hooks/gate-turno-prometido.cjs`, com o hash do commit dela). O arquivo do plano em `arquivos:` é só o único caminho que a tarefa toca no repo (marca de conclusão opcional); a colheita em si não entra em diff.
mutacao: n/a
  motivo: ação de dados do usuário feita pela janela principal, sem código a inverter; a falsificação é o estado real do `ideias.jsonl` depois.
pronto quando: com o `~/.rainforest/ideias.jsonl` real, as cinco ideias deixam de estar `plantada` e cada `resultado` cita evidência que existe — provado por `node -e "const l=require('fs').readFileSync(require('os').homedir()+'/.rainforest/ideias.jsonl','utf8').split('\n').filter(Boolean).map(x=>JSON.parse(x));for(const id of ['briefing-que-proibe-background-nao-impede-o-background','rainforest-conferir-mutacao-envenena-o-pycache','catraca-bateria-vai-para-o-cmd-no-windows','limpar-remove-worktree-limpo-de-outra-sessao-sem-perguntar','checador-deterministico-de-conformidade-de-regra-no-stop'])console.log(id,l.find(o=>o.id===id).status)"` imprimindo as cinco linhas terminadas em `colhida`.

### 15. Registrar as seis travas em docs/travas-mecanicas.md e README [tipo: docs]
atende: D1, D2, D3, D4, D5, D6
arquivos: `docs/travas-mecanicas.md`, `README.md`
depende de: 1, 2, 4, 5, 6, 7, 8, 10, 13
paralela: nao
escopo: `docs/travas-mecanicas.md` ganha uma linha por peça nova na tabela de scripts (`conferir-prova.cjs`, `preparar-worktree.cjs`, `varrer.cjs`, `substituir.cjs`, `extrair-corpus-comandos.cjs`), a linha de `conferir-entrega.cjs` passa a dizer que `--base` é obrigatório (exit 2), `conferir-fluxo.cjs` passa a citar `## Varredura` no `design`, e o hook novo entra na seção de gates com o evento `Stop`, os dois casos e a saída de emergência (chave `gate-turno-prometido`); `README.md` cita o hook ao lado de `gate-review-codex.cjs` (`README.md:180`). Cada linha diz o exit code real da peça. **Sem bump de versão nem CHANGELOG** (ficam para o `fechar`).
mutacao: n/a
  motivo: documentação sem comportamento a inverter; a falsificação é a coerência com o comportamento real das peças (arquivos existem, exit codes documentados batem com os devolvidos).
pronto quando: com `docs/travas-mecanicas.md` e `README.md` editados, cada arquivo citado existe e cada exit code declarado é o que a peça devolve — provado por:
  (1) `bash scripts/testa-mapa-regras.sh` sem nenhuma linha `FALHA` (todo arquivo citado existe);
  (2) `node scripts/preparar-worktree.cjs; echo $?` devolvendo `2`, `node scripts/substituir.cjs; echo $?` devolvendo `2`, `node scripts/varrer.cjs; echo $?` devolvendo `2`, e `node scripts/conferir-prova.cjs; echo $?` devolvendo `1`, e para cada um a linha da tabela em `docs/travas-mecanicas.md` que o descreve traz esse mesmo número (`grep -n "preparar-worktree" docs/travas-mecanicas.md` etc. mostrando o exit citado);
  (3) `bash scripts/testa-conferir-categoria.sh` e `bash scripts/testa-teto-skills.sh` sem `FALHA`.

## Ordem de execução (derivada das dependências)
- Onda 1, paralelas (arquivos disjuntos, conferido): tarefas 1, 2, 4, 6, 8, 10, 11.
- Onda 2: 3 (após 1, 2), 5 (após 4), 12 (após 11, **janela principal, com U1**). A 7 espera a 5 porque as duas editam as baterias de estado/fluxo (`conferir-fluxo.cjs` é tocado por 4 e 7, nunca em paralelo; `hooks.json` só pela 10).
- Onda 3: 7 (após 4, 5, 6), 9 (após 3, 8), 13 (após 11, 12).
- Onda 4: 15 (após todas as de código) e 14 (janela principal, no `fechar`, após 10).

Paralelas: 1, 2, 4, 6, 8, 10, 11.

## Premissas do briefing aceitas sem conferir (quem despachou é quem corrige)
1. "Rodar no CI Windows e Linux": **contradita** acima (só Windows). Escrevi as baterias portáteis e cobrei a prova só no Windows. Se existe job Linux fora de `.github/workflows/baterias.yml`, avise.
2. Que gravar `ideias.jsonl` fora do worktree na tarefa 14 é ação da janela principal: aceito, conforme o briefing.
3. Que o repo segue público (motivo da curadoria do D5): aceito do design; não conferi a visibilidade no GitHub.
4. Que nenhum outro ponto fora de `estado.cjs` chama `conferir-fluxo design` (CI externo, tarefa agendada, `/saude`): conferi `scripts/`, `hooks/`, `.github/`, `commands/` e `skills/`; não conferi tarefas agendadas do Windows nem `vigias/`.
5. O nome e a existência de `ScheduleWakeup` e `Monitor` como ferramentas (vêm do design, não os abri).
6. Que `python` existe na máquina de quem executa a tarefa 2 (o CI garante; a máquina local não conferi).
7. Que a transcrição contém a última resposta no instante do `Stop` (ver LACUNA da tarefa 10).
