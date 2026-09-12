# Plano: absorver do data-skills (Rootz) as 14 decisões

Design: docs/rainforest/design/2026-09-12-absorver-data-skills.md
**Base:** `origin/main` @ `10251507` · **Branch:** `fluxo/absorver-data-skills`

Quinze tarefas, quatorze decisões. **Fan-out em três ondas**, separadas por
arquivo compartilhado, não por tema:

- **Onda 1** (arquivos disjuntos entre si e de tudo que vem depois):
  T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11.
- **Onda 2** (tocam arquivo que a onda 1 acabou de mudar ou criar):
  T12 (linhas novas na tabela de travas dependem de T1, T2, T3, T5),
  T13 (`conferir-publicacao` chama o `conferir-duplicacao` de T8),
  T14 (texto de `executar`/`revisar`/`fechar` descreve o que T5 e T7 fizeram).
- **Onda 3**: T15 fecha o lote rodando tudo.

**Restrições que valem para todas:** o repo é público — nenhum caminho desta
máquina em código, teste ou fixture; e-mail em `git config` de bateria é
`test@<email>`. Toda asserção de bateria tem os dois ramos (`if/else`). Bloco
`mutacao` com `de:`/`para:` **literais**. Bateria nova segue a forma de
`hooks/testa-gate-staging-total.sh`: caixa de areia em `mktemp -d` com caminho
nativo (`cygpath -m`), `RFM_ROOT` descartável, contador `ok`/`falhou`, exit ≠ 0
se `falhou > 0`. Plataforma: Windows + Git Bash, que é onde o CI roda
(`runs-on: windows-latest`). Gate novo e script novo já nascem com as duas
linhas de D11 (`Protege contra:` / `Não protege contra:`) no docblock.

## O que não pode quebrar

- Todas as baterias `scripts/testa-*.sh` e `hooks/testa-*.sh` continuam
  verdes (o CI roda todas).
- `estado.cjs`: os fluxos abertos hoje (`docs/rainforest/estado/*.json`)
  continuam legíveis; flags hoje aceitas por cada subcomando continuam
  aceitas; `--json` sem `carimbos` continua válido.
- `limpar-branches.cjs` e `limpar-worktrees.cjs` **sem** `--forcar`/`--remover`
  continuam só listando, com a mesma saída.
- `conferir-*`: exit 0 e exit 2 mantêm o significado de hoje; o 69 é **novo**,
  nunca substitui um 2.
- Catraca de bytes: `regra-12.md` ≤ 10.500 B e `rainforest-mind/SKILL.md`
  ≤ 11.000 B (`hooks/testa-contexto-sessao.sh` mede).
- Commit com `-m "assunto"` curto, tocando até 3 arquivos e até 150 linhas,
  **continua passando** sem corpo — o gate de T1 não pode virar fricção no
  commit pequeno, que é o que ele quer incentivar.

## Tarefas

### 1. Gate de mensagem de commit [tipo: implementar]
atende: D2
arquivos: `hooks/gate-mensagem-commit.cjs`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/hooks.json`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-mensagem-commit.cjs`
  de: o `process.exit(2)` do ramo "corpo obrigatório ausente" (diff em stage acima de 3 arquivos ou 150 linhas, mensagem sem parágrafo depois da linha em branco)
  para: `process.exit(0)`
  bateria: `bash hooks/testa-gate-mensagem-commit.sh`
  fixture: `testa-gate-mensagem-commit.sh`, caso "4 arquivos, so assunto -> exit 2"
pronto quando: com o payload real de `PreToolUse` (`tool_name: "Bash"`, `tool_input.command`) para `git commit -m "Assunto"` num repo de caixa de areia com **4 arquivos** em stage, o hook sai **2** e o stderr traz a forma esperada (assunto até 72 colunas sem ponto final, linha em branco, corpo com o porquê) **e** o número medido (`4 arquivo(s), N linha(s)`); com **3 arquivos e 20 linhas** e a mesma mensagem, sai **0**; com assunto de 80 colunas, sai **2**; com assunto terminando em ponto, sai **2**; com `-m "Assunto" -m "corpo que explica"` e 4 arquivos, sai **0**; com `-F <arquivo>` cujo conteúdo tem corpo, sai **0**; com `-F -` ou heredoc (mensagem não resolvível pelo hook), sai **2** dizendo "use -F <arquivo>"; com `--amend --no-edit`, `-C <rev>` e `-c <rev>`, sai **0**; trailer (`Co-Authored-By:`, `Claude-Session:`) **não conta** como corpo — provado por `bash hooks/testa-gate-mensagem-commit.sh` listando cada caso com `ok` e terminando em `falhou=0`. O gate está registrado no bloco `PreToolUse` de `hooks/hooks.json` depois de `gate-git-verificacao.cjs` — provado por `node -e "const h=require('./hooks/hooks.json');console.log(h.hooks.PreToolUse[0].hooks.map(x=>x.command).join('\n'))" | grep -c gate-mensagem-commit` devolvendo `1`.

### 2. Frase de confirmação no `limpar` [tipo: implementar]
atende: D3
arquivos: `scripts/limpar-branches.cjs`, `scripts/limpar-worktrees.cjs`, `scripts/testa-limpar-branches.sh`, `scripts/testa-limpar-worktrees.sh`, `skills/limpar/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/limpar-branches.cjs`
  de: a comparação `frase !== esperada` que recusa o `-D` quando `--confirmo` não bate com a frase derivada dos alvos
  para: `false`
  bateria: `bash scripts/testa-limpar-branches.sh`
  fixture: `testa-limpar-branches.sh`, caso "--remover --forcar sem --confirmo nao apaga sumiu-divergente"
pronto quando: com um repo de caixa de areia contendo uma branch `sumiu-divergente` (remoto apagado, commit fora da base), `node scripts/limpar-branches.cjs --remover --forcar` **sem** `--confirmo` sai **2**, não apaga nada (`git branch --list <nome>` ainda a mostra) e o stdout imprime a frase esperada na forma literal `CONFIRMO apagar branches <nome1>,<nome2>` (nomes em ordem alfabética, separados por vírgula, sem espaço); com `--confirmo "CONFIRMO apagar branches <nome>"` **exato**, sai 0 e a branch some; com a frase citando **outro** nome, sai 2 e nada some. Para worktrees: `node scripts/limpar-worktrees.cjs --remover` sobre worktree **sujo** continua **não removendo** (comportamento atual); `--remover-sujo <dir>` sem `--confirmo` sai 2 e imprime `CONFIRMO apagar worktree sujo <caminho-como-o-git-worktree-list-imprime>`; com a frase exata, remove (`git worktree list` não o mostra mais); com frase de outro caminho, sai 2 e o worktree fica — provado por `bash scripts/testa-limpar-branches.sh` e `bash scripts/testa-limpar-worktrees.sh`, cada uma terminando em `falhou=0`. `skills/limpar/SKILL.md` descreve `--confirmo` e diz que a frase é **digitada pelo usuário e repassada verbatim** — provado por `grep -c -- '--confirmo' skills/limpar/SKILL.md` ≥ 2.

### 3. Frase de confirmação ao fechar Issue [tipo: implementar]
atende: D3
arquivos: `scripts/fechar-issue.cjs`, `scripts/testa-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/fechar-issue.cjs`
  de: a comparação `frase !== \`CONFIRMO fechar issue #${n}\`` que recusa sem `gh issue close`
  para: `false`
  bateria: `bash scripts/testa-fechar-issue.sh`
  fixture: `testa-fechar-issue.sh`, caso "sem --confirmo nao chama gh issue close"
pronto quando: com um `gh` dublê no `PATH` da caixa de areia que grava cada invocação em arquivo, `node scripts/fechar-issue.cjs 12 --comando "x" --saida "y"` **sem** `--confirmo` sai **2**, imprime `CONFIRMO fechar issue #12` como frase esperada e o arquivo do dublê **não** contém `issue close`; com `--confirmo "CONFIRMO fechar issue #12"` o dublê registra `issue comment` **e depois** `issue close 12`; com `--confirmo "CONFIRMO fechar issue #13"` sai 2 e o dublê não registra `close` — provado por `bash scripts/testa-fechar-issue.sh` terminando em `falhou=0`, e `bash hooks/testa-gate-fechar-issue.sh` continuando verde (a mensagem do gate já aponta para `fechar-issue.cjs`; ela não muda).

### 4. Racionalizações nas regras 9, 10 e 12 [tipo: docs]
atende: D4
arquivos: `skills/rainforest-mind/references/regra-09.md`, `skills/rainforest-mind/references/regra-10.md`, `skills/rainforest-mind/references/regra-12.md`, `skills/rainforest-mind/references/regra-12-acervo.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa de texto; a falsificação é coerência com o acervo e a catraca de bytes, abaixo
pronto quando: cada uma das três regras tem uma seção `## Racionalizações` com tabela `| Pensamento | Realidade |` de 3 a 6 linhas, e **cada linha** da coluna Realidade cita uma data `AAAA-MM-DD` que existe num bloco `>` da própria regra ou do acervo dela (a desculpa só entra se já custou algo medido) — provado por, para cada regra, `grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' <trecho da tabela>` devolvendo só datas que `grep -c "^> <data>" regra-NN.md regra-NN-acervo.md` encontra ≥ 1. `regra-12.md` cabe na catraca **depois** da tabela (hoje tem 329 B de folga): ao menos um bloco `>` dela migra para `regra-12-acervo.md` e o parágrafo que o perdeu ganha `(acervo: <data>)` — provado por `bash hooks/testa-contexto-sessao.sh` terminando verde com a linha `maior reference (...) cabe na catraca`.

### 5. Exit 69 = "não pude verificar" [tipo: implementar]
atende: D5
arquivos: `scripts/conferir-entrega.cjs`, `scripts/conferir-mutacao.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/conferir-ponte.cjs`, `scripts/testa-conferir-entrega.sh`, `scripts/testa-conferir-mutacao.sh`, `scripts/testa-conferir-fluxo.sh`, `scripts/testa-conferir-ponte.sh`, `skills/rainforest-mind/references/regra-14.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-entrega.cjs`
  de: o `process.exit(69)` (ou `return 69`) do ramo `worktree '<wt>' nao existe`
  para: `process.exit(2)` (ou `return 2`)
  bateria: `bash scripts/testa-conferir-entrega.sh`
  fixture: `testa-conferir-entrega.sh`, caso "worktree sumiu -> exit 69 e stderr abre com nao-verificavel:"
pronto quando: `node scripts/conferir-entrega.cjs --worktree <dir-que-nao-existe> --base <hash>` sai **69** e a **primeira linha** do stderr é `nao-verificavel: worktree '<dir>' nao existe`; `conferir-mutacao.cjs` com `--bateria "<comando-inexistente>"` (o `spawn` devolve `error`) sai 69 com `nao-verificavel: bateria nao executa — <mensagem>`, enquanto bateria que **roda e pendura** continua saindo 4 e padrão ambíguo continua 4; `conferir-fluxo.cjs creep` com `git` indisponível no `PATH` da caixa de areia sai 69; `conferir-ponte.cjs` com a CLI ausente sai 69 — e em **nenhum** dos quatro um caso que hoje sai 2 (reprovação) passa a sair 69 — provado pelas quatro baterias terminando em `falhou=0`, cada uma com ao menos um caso `exit 69` novo e os casos `exit 2` antigos intactos. `regra-14.md` ganha o parágrafo que nomeia o 69 como bloqueio de ambiente (nem aprovação, nem reprovação, nem `flaky`) e o gesto: anunciar em uma linha e não redespachar — provado por `grep -c 'nao-verificavel' skills/rainforest-mind/references/regra-14.md` ≥ 1 e `bash hooks/testa-contexto-sessao.sh` verde.

### 6. Teto de tamanho para toda skill [tipo: teste]
atende: D7
arquivos: `scripts/testa-teto-skills.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/testa-teto-skills.sh`
  de: `TETO_LINHAS=500`
  para: `TETO_LINHAS=100`
  bateria: `bash scripts/testa-teto-skills.sh`
  fixture: `testa-teto-skills.sh`, o laço sobre `skills/*/SKILL.md` (com 100, `analisar` com 306 linhas reprova)
pronto quando: com o repositório como está, `bash scripts/testa-teto-skills.sh` imprime uma linha `ok <skill> <linhas>L <bytes>B` por SKILL.md em `skills/*/` e sai **0**; com uma skill de caixa de areia de 501 linhas (ou 16.385 B) apontada por `SKILLS_DIR`, imprime `FALHA <skill>: 501 linhas > 500` (ou `... B > 16384`) e sai **1**; a mensagem de falha diz **o que fazer** (mover referência para `references/` ou arquivo irmão, como o `skill-author` do data-skills manda) — provado pela própria bateria nas duas configurações, e `grep -c 'testa-teto-skills' .github/workflows/*.yml` não precisa mudar porque o CI já roda `scripts/testa-*.sh` por glob.

### 7. Veredito por tarefa carimbado [tipo: implementar]
atende: D8
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: a chamada `git merge-base --is-ancestor <hash_base> HEAD` no aviso de retomada (em `proximo` e `ler`)
  para: `true` (aviso nunca dispara)
  bateria: `bash scripts/testa-estado.sh`
  fixture: `testa-estado.sh`, caso "carimbo com hash_base fora do HEAD -> proximo avisa"
pronto quando: `node scripts/estado.cjs marcar --slug <s> --estagio executar --status parcial --json '{"carimbos":[{"tarefa":1,"hash_base":"<sha>"}]}'` grava em `docs/rainforest/estado/<s>.json`, dentro de `executar.carimbos`, um objeto `{tarefa:1, hash_base:"<sha>", iteracao:1, sessao:"<CLAUDE_SESSION_ID ou 'desconhecida'>", ts:"<ISO>"}`; um segundo `marcar` com a mesma tarefa grava `iteracao:2` **sem apagar** a 1; `--json` sem `carimbos` continua aceito e não toca o campo; `node scripts/estado.cjs proximo --slug <s>` num repo em que `hash_base` **não** é ancestral do HEAD imprime no stderr `aviso: tarefa 1 aceita na base <sha7>, que nao esta neste HEAD — re-conferir antes de retomar` e **mantém exit 0**; com `hash_base` ancestral, não imprime aviso — provado por `bash scripts/testa-estado.sh` terminando em `falhou=0`, e `node scripts/estado.cjs ler --slug 2026-09-12-absorver-data-skills` continuando a ler este fluxo sem erro.

### 8. `conferir-duplicacao` e avisos no `/saude` [tipo: implementar]
atende: D9
arquivos: `scripts/conferir-duplicacao.cjs`, `scripts/testa-conferir-duplicacao.sh`, `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-duplicacao.cjs`
  de: o `process.exit(2)` do ramo "dois arquivos com o mesmo hash"
  para: `process.exit(0)`
  bateria: `bash scripts/testa-conferir-duplicacao.sh`
  fixture: `testa-conferir-duplicacao.sh`, caso "dois .cjs identicos -> exit 2 nomeando os dois"
pronto quando: `node scripts/conferir-duplicacao.cjs --raiz <dir>` sobre uma árvore com dois arquivos byte a byte iguais (fora de `fixtures/`, `node_modules/`, `.git/`) sai **2** e imprime os dois caminhos na mesma linha; sobre a árvore real do plugin sai **0** (não há duplicata hoje — se houver, o achado é da tarefa e se corrige antes de fechar); `--funcoes` lista nomes `function <x>` e `exports.<x>` que aparecem em dois ou mais `scripts/*.cjs` e sai 0 (é inventário, não veredito); `node scripts/saude.cjs` em raiz de dados descartável com um `settings.json` de usuário contendo `"Bash(bash -c *)"` em `permissions.allow` emite `aviso allowlist: padrao largo 'Bash(bash -c *)' anula os gates de Bash — remova ou estreite`, e com allowlist limpa emite `ok allowlist` — provado por `bash scripts/testa-conferir-duplicacao.sh` e `bash scripts/testa-saude.sh`, ambas em `falhou=0`.

### 9. Modelo de ameaça nos gates e plataforma no README [tipo: docs]
atende: D11
arquivos: `hooks/gate-worktree.cjs`, `hooks/gate-staging-total.cjs`, `hooks/gate-git-verificacao.cjs`, `hooks/gate-publicacao-destino.cjs`, `hooks/gate-repo-alheio.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/gate-review-codex.cjs`, `hooks/gate-agente-em-voo.cjs`, `hooks/portaria.cjs`, `README.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: tarefa de texto em docblock; a falsificação é coerência entre o que o docblock declara e o que a bateria do gate prova
pronto quando: cada um dos nove arquivos tem no docblock de abertura uma linha começando com ` * Protege contra:` e outra com ` * Não protege contra:` (ou `Nao protege contra:`), e o termo principal da linha "Protege contra" aparece numa asserção de **exit 2** da bateria correspondente (`hooks/testa-<gate>.sh`) — provado por um laço `for g in hooks/gate-*.cjs hooks/portaria.cjs` com `grep -c 'Protege contra:'` e `grep -c 'protege contra:'` ambos ≥ 1 por arquivo, e a inspeção termo↔bateria colada no relatório da tarefa, gate a gate. `README.md` ganha, na seção "Travas mecânicas", uma frase declarando a plataforma em que as baterias rodam (Windows + Git Bash, que é o `runs-on: windows-latest` do CI) e que Linux e macOS **não são medidos** — provado por `grep -n 'windows-latest' .github/workflows/*.yml` e `grep -in 'git bash' README.md` devolverem, os dois, ao menos uma linha, e a frase do README nomear o mesmo sistema do `runs-on`.

### 10. Convenção: afirmação medida leva data e comando de re-verificação [tipo: docs]
atende: D12
arquivos: `skills/rainforest-mind/SKILL.md`, `docs/rainforest/README.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: convenção de texto; a falsificação é caber na catraca e a mesma forma aparecer nos dois lugares
pronto quando: `docs/rainforest/README.md` ganha a seção `## Afirmação medida` com a forma do bloco (`> AAAA-MM-DD: <o que foi medido> — re-verificar: <comando>`), um exemplo real tirado de uma reference existente e o porquê (medição que não diz como se re-mede vira lenda quando o ambiente muda); `skills/rainforest-mind/SKILL.md`, seção "Como este arquivo é lido", ganha **uma frase** apontando para essa seção, sem passar de 11.000 B (hoje 10.137 B) — provado por `bash hooks/testa-contexto-sessao.sh` verde na linha `SKILL.md cabe na catraca`, e `grep -c 're-verificar:' docs/rainforest/README.md skills/rainforest-mind/SKILL.md` devolvendo ≥ 2 e ≥ 1 respectivamente.

### 11. Paridade ao portar, no `modo-dev` [tipo: docs]
atende: D13
arquivos: `skills/modo-dev/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: texto de skill; a falsificação é coerência com o design e o teto de D7
pronto quando: a seção "Despachar: a forma do briefing" ganha um parágrafo **Porte** que fixa o critério de sucesso como "saída byte a byte igual à do original sobre os fixtures do original" para bash→cjs e py→cjs, diz que "testes verdes" **não** é o critério, e cita o par `conferir-entrega.cjs`/`conferir-entrega.py` deste repo como caso em que a paridade já é a regra — provado por `grep -n 'byte a byte' skills/modo-dev/SKILL.md` devolver a linha, e `wc -l skills/modo-dev/SKILL.md` ≤ 500 com `wc -c` ≤ 16384 (o teto de T6).

### 12. Mapa regra → trava, com bateria [tipo: implementar]
atende: D6
arquivos: `docs/travas-mecanicas.md`, `scripts/testa-mapa-regras.sh`
depende de: 1, 2, 3, 5
paralela: nao
mutacao:
  arquivo: `docs/travas-mecanicas.md`
  de: a linha da tabela "Regra → trava" da regra 17
  para: (linha removida)
  bateria: `bash scripts/testa-mapa-regras.sh`
  fixture: `testa-mapa-regras.sh`, o laço que exige uma linha por regra `1..17` lida do `SKILL.md`
pronto quando: `docs/travas-mecanicas.md` tem a seção `## Regra → trava` com uma tabela `| Regra | Trava | Vale por disciplina |` de **17 linhas**, uma por regra do `skills/rainforest-mind/SKILL.md`, em que cada linha tem **ou** o nome de um hook/script/`exigir` existente em `hooks/` ou `scripts/` **ou** a marca `disciplina` na terceira coluna, nunca ambos vazios; as travas de T1 (`gate-mensagem-commit.cjs`), T2/T3 (`--confirmo`) e T5 (exit 69) aparecem na tabela; `bash scripts/testa-mapa-regras.sh` lê os números de regra do `SKILL.md` (`^\*\*(\d+)\.`), confere que cada um tem linha, que todo hook/script citado existe em disco, e sai **0**; removendo uma linha, ou citando `hooks/gate-inexistente.cjs`, sai **1** nomeando a regra ou o arquivo — provado pela bateria nas duas configurações (a segunda em cópia na caixa de areia, apontada por `TRAVAS_MD`).

### 13. `conferir-publicacao` lê o commit [tipo: implementar]
atende: D10
arquivos: `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`
depende de: 8
paralela: nao
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: a leitura `git show <rev>:<path>` do modo `--commit`
  para: `fs.readFileSync(<path>)` (volta a ler o disco)
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: `testa-conferir-publicacao.sh`, caso "segredo so no commit, disco limpo -> --commit acha"
pronto quando: num repo de caixa de areia em que um arquivo rastreado tem um e-mail **no commit** mas já foi limpo **no disco**, `node scripts/conferir-publicacao.cjs --commit HEAD` sai **2** apontando o arquivo e a linha do commit, enquanto `node scripts/conferir-publicacao.cjs <arquivo>` (modo atual, disco) sai 0 — os dois modos coexistem e o antigo não muda; `--commit origin/main..HEAD` varre todos os arquivos tocados no range; arquivo cujo conteúdo em disco difere do commit gera achado `diverge-do-commit`; o modo `--commit` também chama `conferir-duplicacao.cjs --raiz <toplevel>` e propaga exit 2 se houver duplicata — provado por `bash scripts/testa-conferir-publicacao.sh` em `falhou=0`, com os casos antigos intactos.

### 14. Texto de `executar`, `revisar` e `fechar` [tipo: docs]
atende: D5, D8, D14
arquivos: `skills/executar/SKILL.md`, `skills/revisar/SKILL.md`, `skills/fechar/SKILL.md`
depende de: 5, 7
paralela: nao
mutacao: n/a
  motivo: texto de skill que descreve mecanismos entregues em T5 e T7; a falsificação é casar com a interface real desses scripts
pronto quando: `skills/executar/SKILL.md`, seção "Integração confere na fonte", diz o que fazer com exit **69** de `conferir-entrega`/`conferir-mutacao` (bloqueio de ambiente, regra 14: anunciar e não redespachar, nem marcar `flaky`), mostra o `--json` com `carimbos` **na forma exata que T7 aceita** (`{"carimbos":[{"tarefa":N,"hash_base":"<sha>"}]}`), e ganha, na seção da catraca, a frase que fixa a ordem gate mecânico → tester → revisor, sequencial; `skills/revisar/SKILL.md` trata 69 do mesmo jeito; `skills/fechar/SKILL.md`, passo 5, ganha o item "outra pessoa faz o release lendo só o README?" — provado por: o `--json` colado no `executar` **executa sem erro** contra o `estado.cjs` de T7 num slug de caixa de areia (`node scripts/estado.cjs marcar ... --json '<o json copiado do SKILL.md>'` sai 0); `grep -c 'exit 69\|69' skills/executar/SKILL.md skills/revisar/SKILL.md` ≥ 1 cada; `grep -c 'lendo só o README' skills/fechar/SKILL.md` ≥ 1; e `bash scripts/testa-teto-skills.sh` (T6) verde para as três.

### 15. Fechar o lote: tudo verde num PR só [tipo: teste]
atende: D1
arquivos: `docs/rainforest/estado/2026-09-12-absorver-data-skills.json`
depende de: 12, 13, 14
paralela: nao
mutacao: n/a
  motivo: tarefa de verificação do conjunto; não introduz comportamento a inverter
pronto quando: com a branch `fluxo/absorver-data-skills` contendo as 14 tarefas, `for f in scripts/testa-*.sh hooks/testa-*.sh; do bash "$f" >/dev/null 2>&1 || echo "VERMELHA $f"; done` não imprime nenhuma linha; `node scripts/conferir-fluxo.cjs cobertura --slug 2026-09-12-absorver-data-skills` e `node scripts/conferir-fluxo.cjs creep --slug 2026-09-12-absorver-data-skills` saem 0; `node scripts/conferir-publicacao.cjs --commit origin/main..HEAD` (T13) sai 0; e `git log --oneline origin/main..HEAD | wc -l` ≥ 15 (um commit por tarefa no mínimo, que é o "por partes" de D2 aplicado a este próprio lote) — tudo colado no `--json` de fechamento do `executar`.
