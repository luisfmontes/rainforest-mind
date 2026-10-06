# Plano: Zerar issues: #396–#405, #407, #408

Design: docs/rainforest/design/2026-10-06-zerar-issues-16.md

Base: `a85f9315` (origin/main).

Nota para quem executa: nas linhas que este plano dita como literais (alvo de mutação), nenhum caso de teste pode ler o texto do fonte — o teste exercita o comportamento; a forma literal existe só para a catraca achar a linha.

## O que não pode quebrar
- Toda bateria existente segue verde e sem perder caso (contagem de `ok` não cai em bateria alterada).
- `gate-subagente-sem-gh` segue barrando `bash scripts/$b.sh` em subagente (D1 vale só no `gate-fechar-issue`).
- `gate-fechar-issue` segue barrando `gh issue close 1` e `eval "$x"` com variável.
- `conferir-mutacao.cjs` mantém os códigos de saída documentados (0, 1, 2, 3, 4, 5, 69) e a cópia descartável (#266).
- `conferir-entrega` aceita snapshot de `--sujo-antes` sem cabeçalho exatamente como hoje; `.cjs` e `.py` seguem gêmeos (a bateria roda contra os dois).
- O plano real que a bateria do `conferir-fluxo` usa de fixture segue passando no `cobertura`, e este plano também.
- Nenhuma bateria grava fora de `mktemp -d`.
- `claude plugin validate .claude-plugin/plugin.json` sai 0.

## Tarefas

### 1. gate-fechar-issue: script com variável no caminho não é ilegível [tipo: implementar]
atende: D1, D2
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base barra os comandos novos, mas a bateria da base não tem os casos que o medem
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `if (opcoes.scriptComVariavel === 'desconhecido' && caminhoComVariavelELiteral(current.tok + coladoNoToken)) {`
  para: `if (opcoes.scriptComVariavel === 'nunca' && caminhoComVariavelELiteral(current.tok + coladoNoToken)) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, casos "405-1 laco com bash scripts/$b.sh passa" e "405-2 bash scripts/$b.sh passa"`
pronto quando: com o payload PreToolUse real (`{"cwd":…,"tool_name":"Bash","tool_input":{"command":…}}`, montado por `node -e JSON.stringify` com valores por argv) dos comandos `for b in a b; do bash scripts/$b.sh; done`, `bash scripts/$b.sh` e `bash "scripts/$b.sh"`, `node hooks/gate-fechar-issue.cjs` sai 0; `gh issue close 1` segue saindo 2 e `eval "$x"` segue saindo 2 com "comando encapsulado"; o `gate-subagente-sem-gh` com `agent_id` e `bash scripts/$b.sh` segue saindo 2 (caso novo em `hooks/testa-gate-fechar-issue.sh` chamando o outro gate). Em `tokens-comando.cjs`, o ramo de caminho de script ganha, antes da linha `if (contemConstrucaoIlegivel(current.tok + coladoNoToken)) {` existente, a linha literal do `de:` acima com corpo `return { interno: null, ilegivel: false };`, onde `caminhoComVariavelELiteral` só aceita token que mistura texto literal com expansão (emenda da integração: a primeira entrega, com `contemConstrucaoIlegivel`, liberava `bash $CMD` e `bash "$@"` — 33 casos vermelhos); `desempacotarWrapperDeString` recebe `opcoes = {}` como último parâmetro e o `gate-fechar-issue` passa `{ scriptComVariavel: 'desconhecido' }` — provado por `bash hooks/testa-gate-fechar-issue.sh` imprimindo os casos novos como ok e `0 falha(s)`

### 2. gate-fechar-issue: --body-file criado por heredoc no mesmo comando [tipo: implementar]
atende: D3, D4
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 1
paralela: nao
prova-na-base: verde — a base barra por ilegível, e a bateria da base não tem os casos que o medem
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const corpoCriado = corpoDeHeredocQueCria(COMANDO_INTEIRO, caminhoResolvido, cwdSegmento);`
  para: `const corpoCriado = null;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: `testa-gate-fechar-issue.sh, caso "407-1 heredoc cria o body-file com palavra de fechamento: decide pelo conteudo"`
pronto quando: com o payload PreToolUse real do comando `cat > x.md <<'EOF'` / `Closes #12` / `EOF` / `gh pr create --title t --body-file x.md` (x.md ausente no disco), o gate decide pelo corpo do heredoc com as mesmas regras do arquivo existente — sai com a mesma decisão e mensagem que dá para um `x.md` existente com `Closes #12` (bloqueio citando fechamento) — e com corpo sem palavra de fechamento sai 0; com `gh pr create --body-file y.md` sem y.md e sem heredoc que o crie, sai 2 e o stderr contém `grave o corpo antes`; a função `corpoDeHeredocQueCria(comando, caminho, cwdSegmento)` usa `corpoDeHeredoc` de `hooks/lib/heredoc.cjs` e reconhece `cat > P <<`, `cat >| P <<` e `tee P <<`; a linha literal do `de:` acima fica no ramo de arquivo ilegível — provado por `bash hooks/testa-gate-fechar-issue.sh` imprimindo os casos novos como ok e `0 falha(s)`

### 3. gate novo: subagente não instala nem desliga gate [tipo: implementar]
atende: D5, D6, D7, D8
arquivos: `hooks/gate-subagente-sem-instalar.cjs`, `hooks/testa-gate-subagente-sem-instalar.cjs`, `hooks/gate-subagente-sem-gh.cjs`
emenda da revisão: a primeira versão partia o comando por `;&|` e olhava só a primeira palavra (contornos por `bash -c`, `sudo`, `env`, PowerShell passavam) e achava o verbo em qualquer posição (`yarn test`, `npm test -- add` barrados); o gate passa a usar o `segmentosParaGate` exportado pelo `gate-subagente-sem-gh` e a decidir pelo subcomando, com os contornos e os legítimos do revisor como casos da bateria
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-gate-subagente-sem-instalar.cjs`
mutacao:
  arquivo: `hooks/gate-subagente-sem-instalar.cjs`
  de: `const ehSubagente = Object.prototype.hasOwnProperty.call(ev, 'agent_id');`
  para: `const ehSubagente = false;`
  bateria: `node hooks/testa-gate-subagente-sem-instalar.cjs`
  fixture: `testa-gate-subagente-sem-instalar.cjs, caso "subagente npm install x nega com exit 2"`
pronto quando: com o payload PreToolUse real de subagente (`agent_id`, `agent_type`, `cwd`, `tool_name: "Bash"`, `tool_input.command`), `node hooks/gate-subagente-sem-instalar.cjs` sai 2 para cada comando de D6 (um caso por gerenciador, incluindo `npm install x`, `pip install x`, `uv add x`, `winget install x`, `Install-Module x` em PowerShell) e para D7 (`touch .rainforest-gate-off`, `echo 1 > .rainforest-gate-off`, `export RAINFOREST_GATE_OFF=1`, `RAINFOREST_GATE_OFF=1 git commit -m x`, `$env:RAINFOREST_GATE_OFF=1` em PowerShell, `Write` com `file_path` terminando em `.rainforest-gate-off`); sai 0 para `npm test`, `npm run build`, `pip list`, `uv run x`, e para `npm install x` sem `agent_id`; com `RAINFOREST_GATE_OFF=1` no ambiente do hook, `npm install x` em subagente segue saindo 2; com `{"subagente-sem-instalar": false}` em `.rainforest/config.json` do projeto, sai 0. A detecção é a linha literal do `de:` acima, seguida de `if (!ehSubagente) process.exit(0);` — provado por `node hooks/testa-gate-subagente-sem-instalar.cjs` imprimindo todos os casos como ok e nenhuma falha

### 4. hook novo: aviso de fluxo no primeiro Edit de código [tipo: implementar]
atende: D9, D10, D11, D12
arquivos: `hooks/aviso-fluxo.cjs`, `hooks/testa-aviso-fluxo.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-aviso-fluxo.cjs`
mutacao:
  arquivo: `hooks/aviso-fluxo.cjs`
  de: `if (sessaoJaAvisada(memoria, sessionId)) process.exit(0);`
  para: `if (false) process.exit(0);`
  bateria: `node hooks/testa-aviso-fluxo.cjs`
  fixture: `testa-aviso-fluxo.cjs, caso "segunda edicao de codigo na mesma sessao e silencio"`
pronto quando: num repositório git de caixa (`mktemp`) com `docs/rainforest/estado/` e nenhum fluxo aberto para a branch, o payload PreToolUse real (`session_id`, `cwd`, `tool_name: "Edit"`, `tool_input.file_path` = `<repo>/scripts/x.cjs`) faz `node hooks/aviso-fluxo.cjs` sair 0 com stdout JSON cujo `hookSpecificOutput.additionalContext` contém `fluxo rainforest`; a segunda chamada com o mesmo `session_id` sai 0 com stdout vazio; `file_path` `.md` ou sob `docs/` → stdout vazio; com um estado de fluxo aberto casando a branch (`fluxo/<slug>`) → stdout vazio; com `agent_id` → vazio; repositório com `docs/plans/x.gates.json` e sem `docs/rainforest/` → aviso nomeando o trilho protheus (`/protheus:trabalhar`); repositório sem nenhum dos dois → vazio; `{"aviso-fluxo": false}` no config → vazio. A memória vai em `<git-dir>/rainforest-aviso-fluxo.json` e a linha literal do `de:` acima decide o silêncio — provado por `node hooks/testa-aviso-fluxo.cjs` imprimindo todos os casos como ok e nenhuma falha

### 5. chave idioma e hook de compactação; chaves novas no config [tipo: implementar]
atende: D13
arquivos: `hooks/idioma-session-start.cjs`, `hooks/testa-idioma-session-start.cjs`, `hooks/lib/config.cjs`, `hooks/testa-config.sh`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-idioma-session-start.cjs`
mutacao:
  arquivo: `hooks/idioma-session-start.cjs`
  de: `if (!idioma) process.exit(0);`
  para: `if (true) process.exit(0);`
  bateria: `node hooks/testa-idioma-session-start.cjs`
  fixture: `testa-idioma-session-start.cjs, caso "source compact com idioma no config emite a linha"`
pronto quando: com o payload SessionStart real (`{"session_id":…,"cwd":<projeto de caixa>,"hook_event_name":"SessionStart","source":"compact"}`) e `{"idioma":"português do Brasil"}` em `<projeto>/.rainforest/config.json`, `node hooks/idioma-session-start.cjs` sai 0 com stdout JSON cujo `hookSpecificOutput.additionalContext` é `Responda ao usuário em português do Brasil.`; sem a chave, stdout vazio e exit 0; idioma de 500 caracteres é recusado pelo config (cai no padrão `null`, stdout vazio); a saída nunca passa de 200 B. `hooks/lib/config.cjs` ganha as chaves `idioma` (`tipo: 'texto'`, `padrao: null`, string não vazia até 60 caracteres), `aviso-fluxo` e `subagente-sem-instalar` (boolean, padrão true), e `node scripts/setup.cjs` lista as três — provado por `node hooks/testa-idioma-session-start.cjs` e `bash hooks/testa-config.sh` imprimindo os casos como ok e nenhuma falha

### 6. conferir-fluxo cobertura recusa plano que a execução não consome [tipo: implementar]
atende: D14, D15
arquivos: `scripts/conferir-fluxo.cjs`, `hooks/lib/contar-ocorrencias.cjs`, `scripts/testa-conferir-fluxo.sh`, `skills/plano/SKILL.md`, `scripts/testa-estado.sh`, `scripts/testa-estado-territorio.sh`
emenda da integração: as duas baterias de estado montam caixa com cópia do `conferir-fluxo.cjs` e passam a copiar a dependência nova `contar-ocorrencias.cjs` (a varredura completa as pegou vermelhas)
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base aceita os planos defeituosos, mas a bateria da base não tem os fixtures
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: `if (paralela === 'sim' && dependeDe !== 'nenhuma') {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-fluxo.sh`
  fixture: `testa-conferir-fluxo.sh, caso "cobertura recusa paralela sim com depende de"`
pronto quando: com o design e o plano reais da bateria (cópia em caixa) mutados um caso por vez, `node scripts/conferir-fluxo.cjs cobertura` sai 2 com a mensagem do caso para: `paralela: sim` + `depende de: 1`; duas paralelas com o mesmo caminho em `arquivos:`; `[tipo: implementacao]`; linha `prioridade: alta` no corpo da tarefa; `de:` que casa 2 vezes no `arquivo:` (a mensagem traz a contagem); `arquivos:` com `../fora.cjs` e com caminho absoluto; `de:` que casa 0 vezes sai 0 com o aviso `ainda nao casa` no stdout; e o plano real sem mutação segue saindo 0. `hooks/lib/contar-ocorrencias.cjs` exporta `contarOcorrencias(texto, trecho)` = `texto.split(trecho).length - 1`, usado pelo `cobertura`; o template de `skills/plano/SKILL.md` lista as recusas novas — provado por `bash scripts/testa-conferir-fluxo.sh` imprimindo os casos novos como ok e nenhuma falha

### 7. runner exige as suítes obrigatórias [tipo: implementar]
atende: D16
arquivos: `scripts/varrer-baterias.sh`, `scripts/baterias-obrigatorias.txt`, `scripts/testa-varrer-baterias.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base não tem a lista nem o caso
mutacao:
  arquivo: `scripts/varrer-baterias.sh`
  de: `[ "$faltou" = 1 ] && exit 1`
  para: `[ "$faltou" = 9 ] && exit 1`
  bateria: `bash scripts/testa-varrer-baterias.sh`
  fixture: `testa-varrer-baterias.sh, caso "obrigatoria ausente sai FALTOU e exit 1"`
pronto quando: com `RFM_BATERIAS_OBRIGATORIAS` apontando para um arquivo de caixa que lista `hooks/testa-nao-existe.sh` e `hooks/testa-gate-worktree.sh`, `bash scripts/varrer-baterias.sh --listar` sai 1 com `FALTOU hooks/testa-nao-existe.sh` e sem `FALTOU hooks/testa-gate-worktree.sh`; com a lista real (`scripts/baterias-obrigatorias.txt`), `--listar` sai 0; com `--shard 1/2` a conferência vale só para as obrigatórias do shard 1 (`node scripts/repartir-baterias.cjs`) e a união dos dois shards cobre a lista; com `--so`, a conferência não roda. A lista real tem as baterias de todos os `hooks/gate-*.cjs`, `scripts/testa-estado.sh`, `scripts/testa-conferir-fluxo.sh`, `scripts/testa-conferir-mutacao.sh` e `scripts/testa-conferir-entrega.sh` — provado por `bash scripts/testa-varrer-baterias.sh` imprimindo os casos novos como ok e nenhuma falha

### 8. catraca: bash resolvido, 126/127 é ambiente [tipo: implementar]
atende: D17
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base sai 4 no caso novo, que ela não tem
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (baselineRes.r.status === 126 || baselineRes.r.status === 127) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: `testa-conferir-mutacao.sh, caso "bateria com comando inexistente sai 69 nao-verificavel"`
pronto quando: com `--bateria 'comando-que-nao-existe-xyz && true'` numa raiz de caixa, `node scripts/conferir-mutacao.cjs` sai 69 com stderr começando por `nao-verificavel: bateria nao executa`, não 4; `comandoDaBateria()` obtém o bash por `caminhoExecutavel('bash')` e, quando o caminho resolvido casa `/\\(system32|windowsapps)\\/i`, sai 69 com `nao-verificavel: bash do WSL` (caso com `RFM_BASH` de caixa apontando para um caminho falso `…\System32\bash.exe`, se `caminhoExecutavel` aceitar sobrescrita por ambiente; senão, por função exportada testada direto) — provado por `bash scripts/testa-conferir-mutacao.sh` imprimindo os casos novos como ok e `0 falha(s)`

### 9. mutação no lugar toma lock e confere a restauração [tipo: implementar]
atende: D18
arquivos: `scripts/conferir-cobertura-fixtures.cjs`, `scripts/testa-conferir-cobertura-fixtures.cjs`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base não tem lock nem o caso
mutacao:
  arquivo: `scripts/conferir-cobertura-fixtures.cjs`
  de: `const EXIT_LOCK_OCUPADO = 69;`
  para: `const EXIT_LOCK_OCUPADO = 0;`
  bateria: `node scripts/testa-conferir-cobertura-fixtures.cjs`
  fixture: `testa-conferir-cobertura-fixtures.cjs, caso "lock de pid vivo sai 69 sem mutar"`
pronto quando: numa raiz git de caixa, com `<git-dir>/rainforest-mutacao.lock` contendo o pid do próprio processo da bateria (vivo), `node scripts/conferir-cobertura-fixtures.cjs` sai 69 com `nao-verificavel: outra mutacao em curso neste worktree` e o fonte fica byte a byte igual; com lock de pid inexistente, retoma e roda; ao fim de uma rodada normal, o lock some e o sha256 do fonte é o do início; o `catch` do lock sai por `process.exit(EXIT_LOCK_OCUPADO)` com a linha literal do `de:` — provado por `node scripts/testa-conferir-cobertura-fixtures.cjs` imprimindo os casos novos como ok e nenhuma falha

### 10. baterias de memória e backup nunca tocam a raiz real [tipo: teste]
atende: D19
arquivos: `scripts/testa-memoria-degradacao.sh`, `scripts/testa-memoria-migracao-atomica.sh`, `scripts/testa-backup-gravar.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base só falha com RFM_ROOT real herdado, que o critério não pode montar sem tocar a pasta do usuário
mutacao: n/a
  motivo: a tarefa altera só baterias; o comportamento é da própria bateria, e o critério a exerce com um RFM_ROOT herdado de caixa
pronto quando: com `RFM_ROOT` exportado apontando para uma pasta de caixa `R` que contém um arquivo sentinela, `bash scripts/testa-memoria-degradacao.sh` e `bash scripts/testa-memoria-migracao-atomica.sh` terminam com os casos ok e `R/sentinela` intacto (a bateria usa seu próprio `mktemp -d`); com `RFM_ROOT` apontando para a raiz real resolvida (`node -e "console.log(require('./hooks/lib/raiz.cjs').resolverRaiz())"`, simulada por `RFM_RAIZ_REAL_FALSA` de caixa), as três saem 69 antes de gravar; `testa-backup-gravar.sh` passa `RFM_BACKUP_DESTINO` de caixa no caso da linha 162 e lê o exit antes do `|| true` — provado por rodar as três baterias com `RFM_ROOT=R` e conferir `ls R` igual antes e depois

### 11. limpar revalida no instante e lê a base [tipo: implementar]
atende: D20, D21, D22
arquivos: `scripts/limpar-worktrees.cjs`, `scripts/testa-limpar-worktrees.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base remove no caso novo, que ela não tem
mutacao:
  arquivo: `scripts/limpar-worktrees.cjs`
  de: `if (agora.mudou) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-limpar-worktrees.sh`
  fixture: `testa-limpar-worktrees.sh, caso "(r) worktree fica sujo entre a listagem e a remocao: nao remove"`
pronto quando: num repo de caixa com um worktree limpo, `RFM_LIMPAR_APOS_LISTAR` (comando que o script roda entre a classificação e a remoção, só para teste) escrevendo um arquivo no worktree, `node scripts/limpar-worktrees.cjs --remover` não remove o worktree e imprime `mudou desde a listagem`; worktree com arquivo modificado há 2 min é listado `em-uso-recente` e não é removido, e com mtime de 20 min atrás (`touch -d`) segue a regra de hoje; fluxo com `em_voo` na branch e concluído em `origin/main` (estado commitado na base de caixa) não segura a remoção e a linha diz `fluxo concluido na base`. A revalidação é `const agora = revalidar(item);` seguida da linha literal do `de:` — provado por `bash scripts/testa-limpar-worktrees.sh` imprimindo os casos novos como ok e nenhuma falha

### 12. conferir-entrega lê só o stdout, snapshot com toplevel, vizinhas [tipo: implementar]
atende: D23, D24, D25
arquivos: `scripts/conferir-entrega.cjs`, `scripts/conferir-entrega.py`, `scripts/testa-conferir-entrega.sh`, `skills/executar/SKILL.md`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base reprova o caso de stderr e aceita o snapshot alheio, mas a bateria da base não tem os casos
mutacao:
  arquivo: `scripts/conferir-entrega.cjs`
  de: `const saida = String(r.stdout || "").trimEnd();`
  para: `const saida = \`${r.stdout || ""}${r.stderr || ""}\`.trimEnd();`
  bateria: `bash scripts/testa-conferir-entrega.sh`
  fixture: `testa-conferir-entrega.sh, caso "warning do git em stderr com arvore limpa sai 0"`
pronto quando: com `GIT_TRACE=1` no ambiente (todo git escreve no stderr; emenda da integração: um `git` de caixa no PATH não é visto por `caminhoExecutavel`, que só aceita `.exe` no Windows), uma entrega limpa e commitada faz `node scripts/conferir-entrega.cjs` sair 0 (e o `.py` também); um snapshot de `--sujo-antes` com `# toplevel: <outra pasta>` sai 2 com `RECUSADO: snapshot de outra arvore`, e sem cabeçalho segue como hoje; `--gravar-sujo-antes <arq> --principal <dir>` grava o cabeçalho e o porcelain; com `--escopo 'a.cjs'` e um diff que toca `b.cjs` citado por `scripts/testa-b.sh`, a saída tem `vizinhas de b.cjs: scripts/testa-b.sh` e o exit não muda por isso; exit ≠ 0 do git sai 69. `skills/executar/SKILL.md` troca o `git status --porcelain >` à mão pelo `--gravar-sujo-antes` — provado por `bash scripts/testa-conferir-entrega.sh` (que roda os dois gêmeos) imprimindo os casos novos como ok e nenhuma falha

### 13. payload por JSON.stringify: worktree, git-verificacao, staging-total [tipo: teste]
atende: D26
arquivos: `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-git-verificacao.sh`, `hooks/testa-gate-staging-total.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — tarefa de bateria; a base não tem os casos com aspas
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `if (process.env.RAINFOREST_GATE_OFF) process.exit(0);`
  para: `if (true) process.exit(0);`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: `testa-gate-staging-total.sh, caso "comando com aspas duplas no campo: git add -A barra"`
pronto quando: nas três baterias, nenhum payload sai de `printf`/`esc()` (`grep -nE "printf '\\{|esc\\(\\)" <bateria>` vazio) e todo payload vem de `node -e '…JSON.stringify(…)'` com valores por argv; cada uma tem um caso com aspas duplas dentro do campo avaliado (ex.: `git commit -m "msg com \"aspas\""` combinado com o que o gate barra) que sai 2 com o gate ligado e fica vermelho com o gate desligado (`RAINFOREST_GATE_OFF=1` só no ambiente do hook, nos gates que o honram); a contagem de `ok` de cada bateria não cai — provado por rodar as três baterias e depois cada uma com o gate desligado, lendo o caso das aspas falhar

### 14. payload por JSON.stringify: repo-alheio, verificador-staged, review-codex, fuga-de-escotilha [tipo: teste]
atende: D26
arquivos: `hooks/testa-gate-repo-alheio.sh`, `hooks/testa-gate-verificador-staged.sh`, `hooks/testa-gate-review-codex.sh`, `hooks/testa-fuga-de-escotilha.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — tarefa de bateria; a base não tem os casos com aspas
mutacao:
  arquivo: `hooks/gate-repo-alheio.cjs`
  de: `if (process.env.RAINFOREST_GATE_OFF) process.exit(0);`
  para: `if (true) process.exit(0);`
  bateria: `bash hooks/testa-gate-repo-alheio.sh`
  fixture: `testa-gate-repo-alheio.sh, caso "comando com aspas duplas no campo: escrita no repo alheio barra"`
pronto quando: nas quatro baterias, nenhum payload sai de `printf`/`esc()`/concatenação de string e todo payload vem de `node -e '…JSON.stringify(…)'` com valores por argv (em `testa-fuga-de-escotilha.sh`, o caminho deixa de ser interpolado no fonte JS); cada uma tem um caso com aspas duplas no campo avaliado que sai com a decisão de bloqueio do gate e fica vermelho com o gate desligado; a contagem de `ok` de cada bateria não cai — provado por rodar as quatro baterias e depois cada uma com o gate desligado, lendo o caso das aspas falhar

### 15. saude avisa skill divergente entre config dirs [tipo: implementar]
atende: D27
arquivos: `scripts/saude.cjs`, `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
prova-na-base: verde — a base não tem a checagem nem o caso
mutacao:
  arquivo: `scripts/saude.cjs`
  de: `if (hashes.size > 1) {`
  para: `if (false) {`
  bateria: `RFM_TESTA_SAUDE_ANINHADA=1 bash scripts/testa-saude.sh`
  timeout: `900000`
  fixture: `testa-saude.sh, caso "skills-divergentes: duas copias diferentes avisam"`
pronto quando: com uma HOME de caixa contendo `.claude/plugins`, `.claude-personal/plugins`, `.claude/skills/x/SKILL.md` (`aaa`) e `.claude-personal/skills/x/SKILL.md` (`bbbbbb`), `node scripts/saude.cjs --json` traz um achado `skills-divergentes` nível `aviso` cujo detalhe nomeia `x` e os dois tamanhos (3 e 6 B); cópias iguais ou skill numa pasta só não geram o achado; nada é escrito na HOME — provado por `bash scripts/testa-saude.sh` imprimindo os casos novos como ok e nenhuma falha
emenda do verificar: a bateria da catraca pula a seção K (que roda a bateria inteira de novo numa cópia da pasta e estourava o teto de 300 s); o caso N1, que é o desta tarefa, não depende dela.

### 16. memória exibe a data local [tipo: implementar]
atende: D28
arquivos: `hooks/lib/memoria-sessao.cjs`, `hooks/testa-memoria-escada.cjs`, `hooks/testa-memoria-session-start.sh`, `scripts/lib/utilidade.cjs`, `scripts/testa-utilidade.sh`
emenda da integração: a linha servida passou a mostrar a data local e `acharAlvo` (utilidade) buscava só o dia UTC — busca o dia e os vizinhos; o caso 9a da bateria fixa `TZ=America/Sao_Paulo` e fica vermelho sem o conserto
depende de: nenhuma
paralela: sim
prova-na-base: verde — as fixtures da base usam 10:00Z, que não muda de dia em UTC-3
mutacao:
  arquivo: `hooks/lib/memoria-sessao.cjs`
  de: `const d = new Date(iso);`
  para: `const d = new Date(String(iso).slice(0, 10));`
  bateria: `node hooks/testa-memoria-escada.cjs`
  fixture: `testa-memoria-escada.cjs, caso "observacao das 23h20 locais (02:20Z) sai com o dia local"`
pronto quando: com `TZ=America/Sao_Paulo` no ambiente do processo e uma observação de `criada_em: "2026-10-06T02:20:59.000Z"`, `formatarObservacao` produz `[2026-10-05 (…)]` e `montarLegendaMemoria` produz `05/10`; `criada_em: "2026-10-05"` (só data) sai `2026-10-05`; valor inválido sai como hoje. `dataLocalDeIso(iso)` começa pela linha literal do `de:` — provado por `node hooks/testa-memoria-escada.cjs` e `bash hooks/testa-memoria-session-start.sh` imprimindo os casos novos como ok e nenhuma falha

### 17. registro dos hooks novos, versão 1.42.0 e documentação [tipo: configurar]
atende: D29
arquivos: `hooks/hooks.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`, `scripts/baterias-obrigatorias.txt`, `scripts/testa-conferir-categoria.sh`, `hooks/testa-ferramentas-nao-toca-abertura.sh`, `hooks/testa-titulo-sessao-registro.sh`, `docs/rainforest/relatorios/2026-10-06-zerar-issues-16-integracao.md`
emenda da integração: registrar três hooks muda as contagens que essas baterias guardam (SessionStart 7, PreToolUse 15, 53 peças / 21 guias), com prova de que o `idioma-session-start` fica mudo na abertura; o relatório de integração registra a rodada
depende de: 3, 4, 5, 7
paralela: nao
mutacao: n/a
  motivo: registro e versão; o comportamento dos hooks é medido nas tarefas 3, 4 e 5
pronto quando: `hooks/hooks.json` tem o `gate-subagente-sem-instalar` em PreToolUse com `matcher: "Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit"` (emenda da revisão: sem os dois últimos o ramo de escrita do hook nunca recebia MultiEdit/NotebookEdit), o `aviso-fluxo` em PreToolUse com `matcher: "Write|Edit|MultiEdit|NotebookEdit"` e o `idioma-session-start` em SessionStart com `matcher: "compact"`; `claude plugin validate .claude-plugin/plugin.json` sai 0; `node scripts/conferir-versao.cjs` sai 0 com 1.42.0 nos dois manifestos; a lista de obrigatórias inclui as baterias novas das tarefas 3, 4 e 5 — provado por esses três comandos e pela leitura do `hooks.json`
