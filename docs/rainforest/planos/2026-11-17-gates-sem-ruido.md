# Plano: Gates sem ruído — menos bloqueio falso exibido como "hook error"

Design: docs/rainforest/design/2026-11-17-gates-sem-ruido.md

## O que não pode quebrar

- Todo caso hoje VERMELHO (exit 2) nas baterias `hooks/testa-gate-agente-em-voo.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-fechar-issue.sh` e `hooks/testa-gate-staging-total.sh` continua exit 2 — nenhum caso existente é apagado nem tem o exit esperado trocado. Cada executor mede a linha de base no PRÓPRIO worktree, antes de editar (rodar a bateria da tarefa e guardar a linha final `== resultado: N ok, M falha(s) ==`), e compara com ela no fim.
- `mascararCorposDeHeredoc(cmd)` chamado SEM o segundo argumento devolve exatamente o mesmo texto de hoje: `gate-worktree.cjs`, `gate-publicacao-destino.cjs` e `gate-mensagem-commit.cjs` não mudam de comportamento pela tarefa 4.
- Sessão não interativa (`claude -p`, SDK, ou sem nenhum sinal de modo) continua barrada pelo `gate-agente-em-voo` exatamente como hoje (D16 do lote-4, D13 do zerar-issues-6).
- As baterias não dependem do ambiente de quem as roda: nenhuma passa ou falha porque a sessão que a roda tem `CLAUDE_CODE_ENTRYPOINT=cli` (a janela do Claude Code tem; o CI não).

## Regra de parada (D5 e D6 leem gramática de shell)

O conjunto de formas aceitas é o que o design lista, e só ele. Achado do `revisar` que mostre contorno dentro das formas novas se conserta **apertando** (a forma volta a barrar), nunca acrescentando parser. Falso positivo fora das formas listadas fica fora desta rodada: vira ideia com o comando que o reproduz.

## Tarefas

As tarefas 1 a 4 rodam em paralelo. A 2 e a 3 importam `hooks/lib/heredoc.cjs`, que a 4 muda, mas a 4 só ACRESCENTA uma opção e uma função exportada; a 2 e a 3 usam só o que já existe hoje (`corpoDeHeredoc`, `posicoesDeOperadorHeredoc`, `mascararCorposDeHeredoc` sem opção).

### 1. gate-agente-em-voo só barra em sessão não interativa [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-agente-em-voo.cjs`, `hooks/testa-gate-agente-em-voo.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks | reaproveito toplevel de hooks/gate-agente-em-voo.cjs:72 e o main de hooks/gate-agente-em-voo.cjs:168; nenhuma lib detecta modo interativo (rg CLAUDE_CODE_ENTRYPOINT em hooks e scripts: só scripts/testa-jornada-origem.cjs, que lê entrypoint de transcript)
- doc | https://code.claude.com/docs/en/hooks | o hook herda o ambiente do processo pai; o payload do Stop não tem campo de modo interativo, mas traz transcript_path
desfecho: estender
O que fazer:
- Função nova no próprio gate, `function sessaoInterativa(ev)`, que devolve booleano:
  1. `const v = process.env.CLAUDE_CODE_ENTRYPOINT;` — se `v` é string não vazia, devolve `v === "cli"` (comparação exata, sem trocar caixa) e NÃO olha o transcript. Variável ausente ou vazia (`""`) conta como ausente.
  2. Sem a variável: se `ev.transcript_path` não é string não vazia, devolve `false`. Senão lê o arquivo com `fs.readFileSync(ev.transcript_path, "utf8")` dentro de `try` (erro → `false`), separa por `\n`, olha só as primeiras 50 linhas (o transcript pode ter centenas de MB; o `entrypoint` sai nos primeiros registros de usuário e assistente), faz `JSON.parse` de cada linha dentro de `try` (linha que não parseia é pulada) e pega o campo `entrypoint` DE NÍVEL RAIZ do primeiro objeto que o tem como string. Devolve `entrypoint === "cli"`. Nenhum objeto com o campo nas 50 linhas → `false`. Nunca usar regex sobre o texto: texto de usuário com `"entrypoint":"cli"` não pode forjar o modo.
- No `main`, logo depois das saídas de emergência (`RAINFOREST_GATE_OFF`) e do toggle do `/setup`, e ANTES de qualquer leitura de estado ou de git, entra a linha literal `if (sessaoInterativa(ev)) process.exit(0);`.
- O docblock do topo ganha um parágrafo "Sessão interativa (2026-11-17, gates-sem-ruido D3)" com a medição do design (121 bloqueios em 7 dias, 6 sessões, todas `entrypoint: "cli"`; sessões `sdk-cli` com zero) e a regra acima.
- Bateria: `unset CLAUDE_CODE_ENTRYPOINT` logo depois do `set -u` (senão, rodada de dentro do Claude Code, todo caso que espera exit 2 vira exit 0). A função `pay()` ganha um 4º argumento opcional `transcript_path`, que entra no JSON só quando não vazio. Os `.jsonl` de fixture são gravados em `$RAIZ` (caminho nativo, já usado pela bateria) com `printf`, uma linha por registro. Os casos que precisam da variável a passam só no próprio comando (`CLAUDE_CODE_ENTRYPOINT=cli node "$HOOK"`), e para isso `checa()` ganha um 5º argumento opcional com o valor da variável (vazio = não passa).
mutacao:
  arquivo: `hooks/gate-agente-em-voo.cjs`
  de: `if (sessaoInterativa(ev)) process.exit(0);`
  para: `if (false) process.exit(0);`
  bateria: `bash hooks/testa-gate-agente-em-voo.sh`
  fixture: testa-gate-agente-em-voo.sh, seção "gates-sem-ruido D3: sessão interativa"
prova-na-base: verde — o critério precisa do repositório de fixture com estado `em_voo` que a bateria monta (git init, branch fluxo/lote-teste, JSON de estado); não há payload real que reproduza isso fora dela
pronto quando: com o payload de Stop que o harness manda (`session_id`, `cwd` da fixture com 1 agente em `em_voo`, `stop_hook_active: false`), provado por `bash hooks/testa-gate-agente-em-voo.sh` imprimindo `ok` em cada caso abaixo e a linha final `== resultado: N ok, 0 falha(s) ==` (ou o formato de placar que a bateria já usa):
  - legítimos que passam: `CLAUDE_CODE_ENTRYPOINT=cli` → exit 0 e stderr vazio; sem a variável e com `transcript_path` apontando para um `.jsonl` cuja primeira linha é `{"type":"user","entrypoint":"cli"}` → exit 0; o mesmo com duas linhas inválidas antes → exit 0.
  - continuam barrando (contornos e modo headless): `CLAUDE_CODE_ENTRYPOINT=sdk-cli` → exit 2; variável ausente e sem `transcript_path` → exit 2; `transcript_path` inexistente → exit 2; transcript com `"entrypoint":"sdk-cli"` → exit 2; transcript cuja única ocorrência de `"entrypoint":"cli"` está DENTRO de uma string (`{"type":"user","message":"\"entrypoint\":\"cli\""}`) → exit 2; `CLAUDE_CODE_ENTRYPOINT=CLI` → exit 2; `CLAUDE_CODE_ENTRYPOINT=sdk-cli` com transcript dizendo `cli` → exit 2 (a variável, quando existe, vence).
  - todos os casos que já existiam continuam com o exit de antes.

### 2. gate-mensagem-commit lê a mensagem do heredoc citado em `git commit -F -` [tipo: implementar]
atende: D4
arquivos: `hooks/gate-mensagem-commit.cjs`, `hooks/testa-gate-mensagem-commit.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks/lib | reaproveito corpoDeHeredoc de hooks/lib/heredoc.cjs:138 (devolve corpo, fim, delimitadorQuotado, fechado) e posicoesDeOperadorHeredoc de hooks/lib/heredoc.cjs:258
- catalogo | listar --raiz hooks | estendo o main de hooks/gate-mensagem-commit.cjs:296 e leFlagsCommit de hooks/gate-mensagem-commit.cjs:183
desfecho: estender
O que fazer:
- Função nova `function mensagemDeHeredoc(cmd, cmdMascarado)` que devolve a string da mensagem ou `null`. `cmdMascarado` é a saída de `mascararCorposDeHeredoc(cmd)`, que preserva o comprimento: todo índice achado nele vale no `cmd` original.
  1. No `cmdMascarado`, achar o índice `k` do primeiro casamento de `/\bgit\b[^\n;|&]*?\bcommit\b/`. Sem casamento → `null`.
  2. A linha lógica vai de `k` até a próxima quebra de linha `\n` do `cmdMascarado` (ou o fim). Nesse trecho, a partir de `k`, achar o primeiro índice `p` de `posicoesDeOperadorHeredoc(cmd)` com `p > k` e `p` antes dessa quebra. Sem `p` → `null`.
  3. Entre `k` e `p` no texto original não pode haver `;`, `|` nem `&` (o heredoc tem de alimentar o próprio `git commit`). Se houver → `null`.
  4. `const h = corpoDeHeredoc(cmd, p)`. Se `h === null`, ou `h.delimitadorQuotado !== true`, ou `h.fechado !== true` → `null`. Here-string (`<<<`) já devolve `null` em `corpoDeHeredoc`. `<<-` é tratado pelo próprio `corpoDeHeredoc`.
  5. Devolve `h.corpo` sem a quebra de linha final (`.replace(/\r?\n$/, "")`).
- No `main`, depois de `leFlagsCommit`: `const mensagemHeredoc = fFile === "-" ? mensagemDeHeredoc(cmd, cmdParaAnalise) : null;` e a recusa vira a linha literal `if (fFile === "-" && mensagemHeredoc === null) {` (mesma mensagem de hoje). Quando `mensagemHeredoc` não é `null`, ela entra no lugar do conteúdo de arquivo: o mesmo caminho que hoje trata o `conteudo` lido de `-F <arquivo>` (primeira linha é assunto, resto é corpo), sem ler arquivo nenhum.
- O docblock do topo troca a frase "`-F -` (le de stdin) e heredoc como fonte de `-F -` sao mensagem NAO RESOLVIVEL" pela regra nova, citando gates-sem-ruido D4 e os 38 bloqueios da semana medida.
mutacao:
  arquivo: `hooks/gate-mensagem-commit.cjs`
  de: `if (fFile === "-" && mensagemHeredoc === null) {`
  para: `if (fFile === "-") {`
  bateria: `bash hooks/testa-gate-mensagem-commit.sh`
  fixture: testa-gate-mensagem-commit.sh, seção "gates-sem-ruido D4: heredoc citado no -F -"
prova: `node -e "const r=require('child_process').spawnSync('node',['hooks/gate-mensagem-commit.cjs'],{input:JSON.stringify({tool_name:'Bash',tool_input:{command:'git commit -F - <<\'EOF\'\nAssunto curto da sonda\nEOF'},cwd:process.cwd()}),encoding:'utf8'});process.exit(r.status)"`
pronto quando: com o comando que a sessão escreve de verdade (`git commit -q -F - <<'EOF'` + assunto + linha em branco + corpo + `EOF`, 38 bloqueios na semana medida), o gate lê a mensagem do heredoc — provado pela `prova:` acima saindo 0 depois da tarefa (sai 2 na base, medido) e por `bash hooks/testa-gate-mensagem-commit.sh` imprimindo `ok` em cada caso abaixo e nenhuma falha no placar final:
  - legítimos que passam: `git commit -F - <<'EOF'` com assunto de 30 colunas → exit 0; o mesmo com `<<"EOF"` → exit 0; `cd x && git add a && git commit -q -F - <<'EOF'` com assunto, linha em branco e corpo → exit 0.
  - a regra continua valendo dentro do heredoc: assunto de 80 colunas no heredoc citado → exit 2 com "acima do limite de 72"; assunto terminando em ponto → exit 2.
  - contornos que continuam barrando: `<<EOF` sem aspas → exit 2; heredoc citado sem linha de fechamento → exit 2; `git commit -F - <<< 'msg'` → exit 2; `printf 'msg' | git commit -F -` → exit 2; `cat <<'EOF' | git commit -F -` (heredoc antes do commit) → exit 2; `git commit -F - ; cat <<'EOF'` (heredoc depois de `;`) → exit 2; `cat <<'EOF' > m.txt` numa linha e `git commit -F -` na linha seguinte → exit 2.

### 3. gate-fechar-issue julga o segmento do `gh pr merge` quando o que vem antes é inerte [tipo: implementar]
atende: D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks | reaproveito segmentosParaGate de hooks/gate-fechar-issue.cjs:259, comandoUnicoSemShell de hooks/gate-fechar-issue.cjs:1129 e analisarPrMerge de hooks/gate-fechar-issue.cjs:1355; o cwd do merge já vem de cwdPorSegmento (hooks/lib/cwd-efetivo.cjs) pelo main
desfecho: estender
O que fazer: função nova `function segmentoDoMerge(comando)`, que devolve o texto do segmento `gh pr merge` isolado ou `null`. Ela lê a variável de módulo `FERRAMENTA` (já global no arquivo, setada no `main`). Passos, nesta ordem; qualquer falha devolve `null`:
  1. `FERRAMENTA === "PowerShell"` → `null`.
  2. Se o comando inteiro (dentro ou fora de aspas, critério único) contém algum de `$`, crase, `(`, `)`, `{`, `}`, `<`, `\`, `#` ou `\r` → `null`. O `>` só pode aparecer como parte do texto exato ` 2>&1` (ver passo 5); outro `>` → `null`.
  3. Dividir com um laço próprio, curto, que só acompanha aspas simples e duplas (sem escape, porque `\` já foi recusado no passo 2): fora de aspas, `;`, `\n`, `&&`, `||` e `|` separam partes e são guardados como separadores; `&` sozinho fora de `2>&1` → `null`. Aspa não fechada → `null`. Cada parte é aparada (`trim`); parte vazia → `null`.
  4. Conferência cruzada com o segmentador do gate: cada parte aparada tem de aparecer, aparada, na lista que `segmentosParaGate(comando)` devolve (comparando strings aparadas); se alguma não aparece → `null`. Assim o laço do passo 3 nunca vê um corte que o gate não vê.
  5. Exatamente uma parte começa pelos tokens `gh pr merge` (separados por espaço, nada antes de `gh`). Senão → `null`. Dessa parte tira-se um ` 2>&1` final, se houver, e o resto tem de passar em `comandoUnicoSemShell`.
  6. Se o separador logo depois do merge é `|`: a parte seguinte tem de casar `/^(tail|head) -\d+$/`, e o separador depois dela (se houver) não pode ser `|`. Qualquer outro `|` depois do merge → `null`.
  7. Cada parte ANTES do merge tem de casar `/^cd [^\s'"]+$/` (um só token literal, sem aspas) ou `/^gh pr (view|checks|status)( [^\s>]+)*$/` (só tokens sem espaço interno; aspas são permitidas dentro do token, mas nunca `$` nem crase, que o passo 2 já tirou).
  8. Nenhuma parte, antes ou depois do merge, começa por `export`, `set`, `alias`, `unalias`, `function`, `source`, `.`, `eval`, `exec`, nem tem como primeiro token algo com `=` (atribuição como `GH_REPO=x`).
  9. Devolve o texto da parte do merge sem o ` 2>&1` final.
- No call site da linha 1535 entra a linha literal `const forma = analisarPrMerge(segmentoDoMerge(textoDoComando) ?? textoDoComando);`. As partes depois do merge continuam sendo analisadas pelo laço do `main`, que já percorre todos os segmentos (por isso `gh pr merge 5; gh issue close 12` segue barrando pelo `gh issue close`).
- Bateria: seção nova "gates-sem-ruido D5: merge julgado pelo segmento", usando a função `pm` que já existe. Os `cd` dos casos legítimos apontam para `$SBP_WIN`, o diretório que a bateria já cria, para o `cwdPorSegmento` não cair em diretório inexistente; o caso `cd` para diretório inexistente fica só entre os que barram se o gate barrar por outro motivo, e não entra como legítimo.
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const forma = analisarPrMerge(isolado !== null && segmentoConfere(isolado, segmento) ? isolado : textoDoComando);`
  para: `const forma = analisarPrMerge(textoDoComando);`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, seção "gates-sem-ruido D5: merge julgado pelo segmento"
  timeout: `1200000`
prova: `node -e "const r=require('child_process').spawnSync('node',['hooks/gate-fechar-issue.cjs'],{input:JSON.stringify({tool_name:'Bash',tool_input:{command:'cd /tmp && gh pr merge 5 --repo dono/repo --squash'},cwd:process.cwd()}),encoding:'utf8'});process.exit(/sozinho/.test(r.stderr)?1:0)"`
pronto quando: com os comandos que a sessão escreve de verdade (31 bloqueios "não está sozinho" na semana medida), o merge passa a ser conferido pela descrição do PR em vez de recusado pela forma — provado pela `prova:` acima saindo 0 (sai 1 na base, medido) e por `bash hooks/testa-gate-fechar-issue.sh` (com o stub de `gh` da própria bateria, função `pm`; `D` abaixo é `$SBP_WIN`) imprimindo `ok` em cada caso abaixo e nenhuma falha no placar final:
  - legítimos que passam (descrição do PR sem palavra-chave): `cd D && gh pr merge 5 --repo dono/repo --squash` → exit 0; `gh pr merge 5 --squash 2>&1 | tail -2` → exit 0; `gh pr view 5 --json state; gh pr merge 5 --squash` → exit 0; `gh pr merge 5 --squash; echo fim` → exit 0.
  - a conferência de evidência continua valendo no segmento: `cd D && gh pr merge 5 --squash` com descrição `Closes #321` sem marcador → exit 2.
  - contornos que continuam barrando: `export GH_REPO=dono/outro; gh pr merge 5` → exit 2; `GH_REPO=dono/outro gh pr merge 5` → exit 2; `cd "$D" && gh pr merge 5` → exit 2; `(cd D; gh pr merge 5)` → exit 2; `gh pr merge 5 | sh` → exit 2; `gh pr merge 5 | tail -2 | sh` → exit 2; `git checkout outra && gh pr merge 5` → exit 2; `alias gh=x; gh pr merge 5` → exit 2; `gh pr merge 5 > log.txt` → exit 2; `gh pr merge 5 && gh pr merge 6` → exit 2; `cd D && gh pr merge 5` pela ferramenta PowerShell → exit 2; `gh pr merge 5; gh issue close 12` → exit 2.
  - todos os casos da seção `(#496-Q1)` continuam com o exit de antes.

### 4. gate-staging-total lê como texto o script não-shell escrito por heredoc [tipo: implementar]
atende: D6
arquivos: `hooks/lib/heredoc.cjs`, `hooks/gate-staging-total.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks/lib | estendo mascararCorposDeHeredoc de hooks/lib/heredoc.cjs:476 e alvoDoRedirecionamentoEhExecutadoDepois de hooks/lib/heredoc.cjs:311 (o conjunto EXECUTAM_ARQUIVO já separa os interpretadores)
desfecho: estender
O que fazer:
- Em `hooks/lib/heredoc.cjs`:
  1. Constante nova `const INTERPRETADORES_NAO_SHELL = new Set(["node", "python", "python3", "py", "perl", "ruby", "deno", "bun"]);`, exportada.
  2. Função nova `function executoresDoAlvo(cmd, i, fimDoHeredoc)`, exportada, com o MESMO laço de `alvoDoRedirecionamentoEhExecutadoDepois` (mesmos alvos, mesma varredura do texto depois do heredoc), mas que em vez de devolver `true` no primeiro achado junta TODOS os executores num array e devolve o array no fim: `"./"` para o alvo citado como `./x`/`.\x`, e o nome normalizado (`normalizarExecutavel`) do comando que executa o arquivo nos outros casos. Nenhuma execução → array vazio. `alvoDoRedirecionamentoEhExecutadoDepois` não muda.
  3. `mascararCorposDeHeredoc(cmd, opcoes = {})`: o cálculo de `dado` não muda. Quando `dado` é falso, `opcoes.scriptNaoShell === true`, o delimitador é citado (`heredoc.delimitadorQuotado`), fechado (`heredoc.fechado`), `!linhaDoHeredocTemInterpretador(fora, i)`, e `const ex = executoresDoAlvo(fora, i, fimDoHeredoc)` tem `ex.length > 0` e TODO elemento em `INTERPRETADORES_NAO_SHELL` (qualquer `"./"` ou shell veta), então o corpo é mascarado linha a linha preservando o comprimento: em cada linha, só os trechos que casam `/\bgit\b[^'"`;|&)\n]*/g` ficam visíveis, e todo outro caractere que não seja `\n` vira espaço.
- Em `hooks/gate-staging-total.cjs`, a linha 337 vira a linha literal `const cmdParaAnalise = mascararCorposDeHeredoc(cmd, { scriptNaoShell: true });`.
- O docblock de `mascararCorposDeHeredoc` ganha um parágrafo sobre a opção (gates-sem-ruido D6, com o comando reproduzido do design) dizendo que só o `gate-staging-total` a usa.
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `const cmdParaAnalise = mascararCorposDeHeredoc(cmd, { scriptNaoShell: true });`
  para: `const cmdParaAnalise = mascararCorposDeHeredoc(cmd);`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "gates-sem-ruido D6: script não-shell escrito por heredoc"
prova: `d=$(mktemp -d) && git init -q "$d" && node -e "const r=require('child_process').spawnSync('node',['hooks/gate-staging-total.cjs'],{input:JSON.stringify({tool_name:'Bash',tool_input:{command:'cat > t.cjs <<\'EOF\'\nconst m=s.match(/([a-z0-9-]+'+String.fromCharCode(92)+'.(cjs|cmd))/i);\nEOF\nnode t.cjs'},cwd:process.argv[1]}),encoding:'utf8'});process.exit(r.status)" "$(cygpath -w "$d" 2>/dev/null || echo "$d")"`
pronto quando: com o comando exato que o gate barrou nesta sessão (heredoc citado gravando um `.cjs` com o regex `/([a-z0-9-]+\.(cjs|cmd))/i`, executado por `node` num repositório que não é worktree linkado — o gate sai antes em worktree linkado), o gate deixa passar — provado pela `prova:` acima saindo 0 (sai 2 na base, medido) e por `bash hooks/testa-gate-staging-total.sh` imprimindo `ok` em cada caso abaixo e nenhuma falha no placar final, todos com cwd num `git init` temporário em caminho nativo (`cygpath -m`):
  - legítimos que passam: o regex acima em `.cjs` executado por `node` → exit 0; o mesmo corpo gravado em `.py` e executado por `python` → exit 0; corpo JS com `execSync('git status')` executado por `node` → exit 0; `digit add -A` dentro de string JS executado por `node` → exit 0.
  - contornos que continuam barrando: corpo JS com `execSync('git add -A')` executado por `node` → exit 2; corpo com `os.system("git commit -am x")` executado por `python3` → exit 2; o MESMO corpo do regex executado por `bash t.cjs` → exit 2 (shell segue analisado inteiro, D11 do zerar-issues-4); executado por `./t.cjs` → exit 2; executado por `node t.cjs; bash t.cjs` → exit 2; heredoc SEM aspas executado por `node` com `$(git add -A)` no corpo → exit 2.
  - casos vizinhos de outros gates: `bash hooks/testa-gate-worktree.sh` e `bash hooks/testa-gate-mensagem-commit.sh` com o mesmo placar que deram no worktree desta tarefa antes da edição (a chamada sem opção não mudou).

### 6. Aperto da D5: cada merge conferido pelo próprio texto, `cd` só literal seguro [tipo: implementar]
atende: D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 3
busca:
- catalogo | listar --raiz hooks | estendo segmentoDoMerge e verificarComandoGh de hooks/gate-fechar-issue.cjs (tarefa 3) e reaproveito tokensComAspas e normalizarExecutavel que o arquivo já importa
desfecho: estender
Origem: revisão de segurança automática do commit da tarefa 3 (decisão registrada com `estado.cjs decidir`). Dois desvios: (1) `gh pr merge 5 --squash; gh pr me''rge 6 --body "Closes #12"` — a segunda parte não contém o texto `merge`, então `segmentoDoMerge` devolve o texto do merge 5, e o merge 6 é conferido com os argumentos do 5; (2) `cd ~`, `cd -` e `cd x*` passam no `/^cd [^\s'"]+$/` e deixam o repositório do merge incerto.
O que fazer:
- Em `segmentoDoMerge`, dois apertos:
  1. Toda parte que NÃO é o merge e NÃO é uma das leituras permitidas antes dele (`gh pr view|checks|status`) é tokenizada com `tokensComAspas(parte).map((t) => t.v)`; se o primeiro token, sem contrabarra e normalizado com `normalizarExecutavel`, é `gh` → `null`. Isso troca a checagem por substring `merge` que a tarefa 3 pôs (mantenha-a também; ela só aperta).
  2. A regra do `cd` antes do merge passa a ser `/^cd (?!-)[A-Za-z0-9._\/:-]+$/` (sem `~`, sem glob, sem começar por `-`).
- Função nova `function segmentoConfere(isolado, segmento)`: devolve `true` só quando `isolado` e `segmento`, ambos aparados e sem um ` 2>&1` final, são iguais. No call site, a linha da tarefa 3 vira as duas linhas literais `const isolado = segmentoDoMerge(textoDoComando);` e `const forma = analisarPrMerge(isolado !== null && segmentoConfere(isolado, segmento) ? isolado : textoDoComando);` (o `segmento` é o primeiro parâmetro de `verificarComandoGh`).
- No ramo do merge, depois de `analisarPrMerge`: se `repo` é nulo, `ref` não começa por `https://`, e `cwdSegmento` é nulo/vazio, barra com a mensagem "não sei em que repositório o merge roda (cd incerto); use --repo dono/repo ou a URL do PR".
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const SEG_MERGE_ANTES_OK = [/^cd (?!-)[A-Za-z0-9._\/:-]+$/, /^gh pr (view|checks|status)( [^\s>]+)*$/];`
  para: `const SEG_MERGE_ANTES_OK = [/^cd [^\s'"]+$/, /^gh pr (view|checks|status)( [^\s>]+)*$/];`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, seção "gates-sem-ruido D5 aperto: cada merge pelo próprio texto"
  timeout: `1200000`
prova-na-base: verde — o defeito só existe depois da tarefa 3; na base do plano o merge composto já barrava pela forma
Alvo da mutação trocado em 2026-11-17: o `segmentoConfere` e a recusa de `gh` em outra parte se cobrem (a catraca deu VERDE invertendo o primeiro, `RECUSADO: bateria VERDE com o comportamento invertido`); a regex do `cd` é a única que decide sozinha, pelo caso `cd ~`.
pronto quando: com os comandos dos dois desvios, o gate barra — provado por `bash hooks/testa-gate-fechar-issue.sh` (stub `pm`, `D` = `$SBP_WIN`) imprimindo `ok` em cada caso abaixo e nenhuma falha no placar final:
  - barram: `gh pr merge 5 --squash; gh pr me''rge 6 --body "Closes #12"` → exit 2; `gh pr merge 5 --squash; g\h pr merge 6 --body "Closes #12"` → exit 2; `gh pr merge 5 --squash; "gh" pr merge 6 --body "Closes #12"` → exit 2; `cd ~ && gh pr merge 5 --squash` → exit 2; `cd - && gh pr merge 5 --squash` → exit 2; `cd x* && gh pr merge 5 --squash` → exit 2.
  - continuam passando: os quatro legítimos da seção `gates-sem-ruido D5` (mesmo exit 0).
  - todos os casos que já existiam continuam com o exit de antes.

### Tarefa 7 descartada (2026-11-17)

O aperto da D6 foi descartado depois de medido. Com o gate da `main` (antes da D6), da tarefa 4 e da tarefa 7, num `git init` temporário: `spawnSync('git',['add','-A'])` por node, `node t.cjs; sh < t.cjs` e `node t.cjs; cp t.cjs x.sh; bash x.sh` saem 0 nas três versões — já passavam antes da D6, então não são contorno das formas novas e a regra de parada não pede aperto. `execSync('git add -A')` por node sai 0 na `main`, 2 com a tarefa 4 e 0 com a tarefa 7: a tarefa 7 desfazia um ganho. Os buracos antigos viram Issue. Decisão registrada com `estado.cjs decidir`.

### 5. Versão 2.17.0, CHANGELOG e README [tipo: docs]
atende: D1, D2, D3, D4, D5, D6
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`, `README.en.md`
depende de: 1, 2, 3, 4, 6
mutacao: n/a
  motivo: tarefa de texto e número de versão; não há comportamento a inverter
O que fazer:
- `"version": "2.17.0"` em `.claude-plugin/plugin.json` e em `.codex-plugin/plugin.json`; a badge da linha 7 do `README.md` passa a dizer `2.17.0` no texto e no `alt`.
- `CHANGELOG.md`: entrada `## 2.17.0 — 2026-11-17` logo acima da `## 2.16.1`, do ponto de vista de quem usa, uma bala por comportamento novo (D3, D4, D5, D6) com o número medido no design (121 bloqueios de agente em voo em sessão interativa; 38 de heredoc no commit; 31 de merge "não está sozinho"; o script node lido como shell), e uma bala dizendo que migrar os gates para mod foi avaliado e descartado, com o motivo da D2 (o mod recebe o mesmo comando e o fim de turno em mod não bloqueia).
- `README.md` e `README.en.md`, tabela de gates: atualizar as linhas de `gate-staging-total.cjs`, `gate-fechar-issue.cjs` e `gate-mensagem-commit.cjs` (README.md linhas 188, 191 e 192, e as equivalentes do README.en.md) com a regra nova de cada um em uma frase; acrescentar, logo abaixo da linha do `gate-mensagem-commit.cjs`, uma linha nova `gate-agente-em-voo.cjs` | "fim de turno com agente registrado em voo, só em sessão não interativa (`claude -p`, SDK)" (em inglês no README.en.md).
pronto quando: com o diff das tarefas 1 a 4 integrado, as duas `plugin.json` e a badge dizem 2.17.0, e a entrada nova do CHANGELOG cita os números do design e o descarte do mod — provado por `node -e "const fs=require('fs');const a=require('./.claude-plugin/plugin.json').version,b=require('./.codex-plugin/plugin.json').version;const c=fs.readFileSync('CHANGELOG.md','utf8');const i=c.indexOf('## 2.17.0');const s=c.slice(i,c.indexOf('## 2.16.1'));const r=fs.readFileSync('README.md','utf8');process.exit(a==='2.17.0'&&b==='2.17.0'&&i>0&&/121/.test(s)&&/38/.test(s)&&/31/.test(s)&&/\bmods?\b/.test(s)&&r.includes('vers%C3%A3o-2.17.0')&&r.includes('gate-agente-em-voo.cjs')?0:1)"` saindo 0; e as quatro linhas da tabela batem com D3–D6 (lidas pelo `revisar`, que cita cada linha conferida).
