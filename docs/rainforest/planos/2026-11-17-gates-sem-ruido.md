# Plano: Gates sem ruído — menos bloqueio falso exibido como "hook error"

Design: docs/rainforest/design/2026-11-17-gates-sem-ruido.md

## O que não pode quebrar

- Todo caso hoje VERMELHO (exit 2) nas baterias `hooks/testa-gate-agente-em-voo.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-fechar-issue.sh` e `hooks/testa-gate-staging-total.sh` continua exit 2 — nenhum caso existente é apagado nem tem o exit esperado trocado. Linha de base medida antes da tarefa 1, na base `e1461e15`.
- `mascararCorposDeHeredoc(cmd)` chamado SEM o segundo argumento devolve exatamente o mesmo texto de hoje: `gate-worktree.cjs`, `gate-publicacao-destino.cjs` e `gate-mensagem-commit.cjs` não mudam de comportamento pela tarefa 4.
- Sessão não interativa (`claude -p`, SDK, ou sem nenhum sinal de modo) continua barrada pelo `gate-agente-em-voo` exatamente como hoje (D16 do lote-4, D13 do zerar-issues-6).
- As baterias não dependem do ambiente de quem as roda: nenhuma passa ou falha porque a sessão que a roda tem `CLAUDE_CODE_ENTRYPOINT=cli` (a janela do Claude Code tem; o CI não).

## Regra de parada (D5 e D6 leem gramática de shell)

O conjunto de formas aceitas é o que o design lista, e só ele. Achado do `revisar` que mostre contorno dentro das formas novas se conserta **apertando** (a forma volta a barrar), nunca acrescentando parser. Falso positivo fora das formas listadas fica fora desta rodada: vira ideia com o comando que o reproduz.

## Tarefas

As tarefas 1 a 4 rodam em paralelo. A 2 e a 3 importam `hooks/lib/heredoc.cjs`, que a 4 muda, mas a 4 só ACRESCENTA uma opção e uma função exportada. A 2 e a 3 usam só o que já existe hoje (`corpoDeHeredoc`, `posicoesDeOperadorHeredoc`, `mascararCorposDeHeredoc` sem opção).

### 1. gate-agente-em-voo só barra em sessão não interativa [tipo: implementar]
atende: D1, D3
arquivos: `hooks/gate-agente-em-voo.cjs`, `hooks/testa-gate-agente-em-voo.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks | reaproveito toplevel de hooks/gate-agente-em-voo.cjs:65 e o main de hooks/gate-agente-em-voo.cjs:135; nenhuma lib detecta modo interativo (rg CLAUDE_CODE_ENTRYPOINT em hooks e scripts: só scripts/testa-jornada-origem.cjs, que lê entrypoint de transcript)
- doc | https://code.claude.com/docs/en/hooks | o hook herda o ambiente do processo pai; o payload do Stop não tem campo de modo interativo, mas traz transcript_path
desfecho: estender
O que fazer: uma função `sessaoInterativa(ev)` no próprio gate devolve `true` quando `process.env.CLAUDE_CODE_ENTRYPOINT === "cli"`, ou, sem a variável, quando o primeiro campo `"entrypoint"` encontrado nas primeiras 50 linhas do arquivo `ev.transcript_path` vale `"cli"`. Qualquer erro de leitura, arquivo ausente, valor diferente de `cli` (inclusive `sdk-cli`) → `false`. No `main`, logo depois das saídas de emergência e do toggle, e ANTES de qualquer leitura de estado, entra a linha literal `if (sessaoInterativa(ev)) process.exit(0);`. O docblock do topo ganha um parágrafo "Sessão interativa (2026-11-17, gates-sem-ruido D3)" com a medição do design (121 bloqueios, 6 sessões, todas `cli`). A bateria ganha `unset CLAUDE_CODE_ENTRYPOINT` logo depois do `set -u` e os casos novos passam a variável só no próprio comando do caso.
mutacao:
  arquivo: `hooks/gate-agente-em-voo.cjs`
  de: `if (sessaoInterativa(ev)) process.exit(0);`
  para: `if (false) process.exit(0);`
  bateria: `bash hooks/testa-gate-agente-em-voo.sh`
  fixture: testa-gate-agente-em-voo.sh, seção "gates-sem-ruido D3: sessão interativa"
prova-na-base: verde — o critério precisa do repositório de fixture com estado `em_voo` que a bateria monta (git init, branch fluxo/lote-teste, JSON de estado); não há payload real que reproduza isso fora dela
pronto quando: com o payload de Stop que o harness manda (`session_id`, `cwd` da fixture com 1 agente em `em_voo`, `stop_hook_active: false`), provado por `bash hooks/testa-gate-agente-em-voo.sh` imprimindo `ok` em cada caso abaixo e a linha final `0 falha(s)`:
  - legítimos que passam: `CLAUDE_CODE_ENTRYPOINT=cli` → exit 0 e stderr vazio; sem a variável e com `transcript_path` apontando para um `.jsonl` cuja primeira linha tem `"entrypoint":"cli"` → exit 0.
  - continuam barrando (contornos e modo headless): `CLAUDE_CODE_ENTRYPOINT=sdk-cli` → exit 2; variável ausente e sem `transcript_path` → exit 2; `transcript_path` inexistente → exit 2; transcript com `"entrypoint":"sdk-cli"` → exit 2; `CLAUDE_CODE_ENTRYPOINT=CLI` (caixa diferente) → exit 2; `CLAUDE_CODE_ENTRYPOINT=sdk-cli` com transcript dizendo `cli` → exit 2 (a variável, quando existe, vence).
  - todos os casos que já existiam continuam com o exit de antes.

### 2. gate-mensagem-commit lê a mensagem do heredoc citado em `git commit -F -` [tipo: implementar]
atende: D4
arquivos: `hooks/gate-mensagem-commit.cjs`, `hooks/testa-gate-mensagem-commit.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks/lib | reaproveito corpoDeHeredoc de hooks/lib/heredoc.cjs:138 (devolve corpo, fim, delimitadorQuotado, fechado) e posicoesDeOperadorHeredoc de hooks/lib/heredoc.cjs:258
- catalogo | listar --raiz hooks | estendo o main de hooks/gate-mensagem-commit.cjs:269 e leFlagsCommit de hooks/gate-mensagem-commit.cjs:179
desfecho: estender
O que fazer: quando `leFlagsCommit` devolve `fFile === "-"`, procurar no texto ORIGINAL do comando (não no mascarado) um operador heredoc (`posicoesDeOperadorHeredoc`) na MESMA linha lógica do `git commit` achado, depois do `git commit`. Se existe, com `delimitadorQuotado === true` e `fechado === true`, o `corpo` dele é a mensagem e segue pelas mesmas checagens que o conteúdo de `-F <arquivo>` segue (assunto, ponto final, corpo em diff grande). Senão (heredoc sem aspas, sem fechamento, here-string `<<<`, pipe para o `git commit`, heredoc em outra linha), barra como hoje. Forma prescrita da trava: a variável `mensagemHeredoc` recebe o corpo ou `null`, e a condição de recusa vira a linha literal `if (fFile === "-" && mensagemHeredoc === null) {`. O docblock do topo troca a frase "`-F -` (le de stdin) e heredoc como fonte de `-F -` sao mensagem NAO RESOLVIVEL" pela regra nova, citando D4.
mutacao:
  arquivo: `hooks/gate-mensagem-commit.cjs`
  de: `if (fFile === "-" && mensagemHeredoc === null) {`
  para: `if (fFile === "-") {`
  bateria: `bash hooks/testa-gate-mensagem-commit.sh`
  fixture: testa-gate-mensagem-commit.sh, seção "gates-sem-ruido D4: heredoc citado no -F -"
prova: `node -e "const r=require('child_process').spawnSync('node',['hooks/gate-mensagem-commit.cjs'],{input:JSON.stringify({tool_name:'Bash',tool_input:{command:'git commit -F - <<\'EOF\'\nAssunto curto da sonda\nEOF'},cwd:process.cwd()}),encoding:'utf8'});process.exit(r.status)"`
pronto quando: com o comando que a sessão escreve de verdade (`git commit -q -F - <<'EOF'` + assunto + linha em branco + corpo + `EOF`, 38 bloqueios na semana medida), o gate lê a mensagem do heredoc — provado pela `prova:` acima saindo 0 depois da tarefa (sai 2 na base) e por `bash hooks/testa-gate-mensagem-commit.sh` imprimindo `ok` em cada caso abaixo e `0 falha(s)`:
  - legítimos que passam: `git commit -F - <<'EOF'` com assunto de 30 colunas → exit 0; o mesmo com `<<"EOF"` → exit 0; `cd x && git add a && git commit -q -F - <<'EOF'` com assunto e corpo → exit 0.
  - a regra continua valendo dentro do heredoc: assunto de 80 colunas no heredoc citado → exit 2 com "acima do limite de 72"; assunto terminando em ponto → exit 2.
  - contornos que continuam barrando: `<<EOF` sem aspas → exit 2; heredoc citado sem linha de fechamento → exit 2; `git commit -F - <<< 'msg'` → exit 2; `printf 'msg' | git commit -F -` → exit 2; `cat <<'EOF' > m.txt` numa linha e `git commit -F -` na linha seguinte → exit 2.

### 3. gate-fechar-issue julga o segmento do `gh pr merge` quando o que vem antes é inerte [tipo: implementar]
atende: D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks | reaproveito segmentosParaGate de hooks/gate-fechar-issue.cjs:259, comandoUnicoSemShell de hooks/gate-fechar-issue.cjs:1129 e analisarPrMerge de hooks/gate-fechar-issue.cjs:1262; o cwd do merge já vem de cwdPorSegmento (hooks/lib/cwd-efetivo.cjs) pelo main
desfecho: estender
O que fazer: função nova `segmentoDoMerge(comando)` devolve o texto do segmento `gh pr merge` isolado, ou `null`. Devolve texto só quando TODAS valem: (a) o comando, fora de aspas, se divide em partes por `;`, `&&`, `||`, `|` e quebra de linha, sem `(`, `)`, `{`, `}`, `$`, crase, `<` ou `>` fora de aspas em parte nenhuma, exceto o `2>&1` previsto em (c); (b) exatamente uma parte começa por `gh pr merge` (tokens literais, sem nada antes do `gh`); (c) essa parte, sem um ` 2>&1` final, passa em `comandoUnicoSemShell`; (d) se a parte seguinte vem por `|`, ela é `tail -<N>` ou `head -<N>` (N só dígitos) e nada mais vem por `|` depois; (e) cada parte ANTES do merge é `cd <um só token literal>` ou `gh pr view|checks|status` seguido só de tokens sem `$`, crase e redirecionamento; (f) nenhuma parte, antes ou depois, contém `=` num token antes do primeiro espaço (atribuição), nem começa por `export`, `set`, `alias`, `function`, `source` ou `.`. Ferramenta PowerShell → `null` sempre. No call site da linha 1535 entra a linha literal `const forma = analisarPrMerge(segmentoDoMerge(textoDoComando) ?? textoDoComando);`. As partes depois do merge continuam sendo analisadas pelo laço do `main`, que já percorre todos os segmentos.
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `const forma = analisarPrMerge(segmentoDoMerge(textoDoComando) ?? textoDoComando);`
  para: `const forma = analisarPrMerge(textoDoComando);`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, seção "gates-sem-ruido D5: merge julgado pelo segmento"
  timeout: `1200000`
prova: `node -e "const r=require('child_process').spawnSync('node',['hooks/gate-fechar-issue.cjs'],{input:JSON.stringify({tool_name:'Bash',tool_input:{command:'cd /tmp && gh pr merge 5 --repo dono/repo --squash'},cwd:process.cwd()}),encoding:'utf8'});process.exit(/sozinho/.test(r.stderr)?1:0)"`
pronto quando: com os comandos que a sessão escreve de verdade (31 bloqueios "não está sozinho" na semana medida), o merge passa a ser conferido pela descrição do PR em vez de recusado pela forma — provado pela `prova:` acima saindo 0 (sai 1 na base) e por `bash hooks/testa-gate-fechar-issue.sh` (com o stub de `gh` da própria bateria, função `pm`) imprimindo `ok` em cada caso abaixo e `0 falha(s)`:
  - legítimos que passam (descrição do PR sem palavra-chave): `cd /c/x && gh pr merge 5 --repo dono/repo --squash` → exit 0; `gh pr merge 5 --squash 2>&1 | tail -2` → exit 0; `gh pr view 5 --json state; gh pr merge 5 --squash` → exit 0; `gh pr merge 5 --squash; echo fim` → exit 0.
  - a conferência de evidência continua valendo no segmento: `cd /c/x && gh pr merge 5 --squash` com descrição `Closes #321` sem marcador → exit 2.
  - contornos que continuam barrando: `export GH_REPO=dono/outro; gh pr merge 5` → exit 2; `GH_REPO=dono/outro gh pr merge 5` → exit 2; `cd "$D" && gh pr merge 5` → exit 2; `(cd x; gh pr merge 5)` → exit 2; `gh pr merge 5 | sh` → exit 2; `gh pr merge 5 | tail -2 | sh` → exit 2; `git checkout outra && gh pr merge 5` → exit 2; `alias gh=x; gh pr merge 5` → exit 2; `gh pr merge 5 > log.txt` → exit 2; `gh pr merge 5 && gh pr merge 6` → exit 2; os mesmos `cd x && gh pr merge 5` pela ferramenta PowerShell → exit 2; `gh pr merge 5; gh issue close 12` → exit 2 (o segmento seguinte barra por conta própria).
  - todos os casos da seção `(#496-Q1)` continuam com o exit de antes.

### 4. gate-staging-total lê como texto o script não-shell escrito por heredoc [tipo: implementar]
atende: D6
arquivos: `hooks/lib/heredoc.cjs`, `hooks/gate-staging-total.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: nenhuma
busca:
- catalogo | listar --raiz hooks/lib | estendo mascararCorposDeHeredoc de hooks/lib/heredoc.cjs:395 e alvoDoRedirecionamentoEhExecutadoDepois de hooks/lib/heredoc.cjs:311 (o conjunto EXECUTAM_ARQUIVO já separa os interpretadores)
desfecho: estender
O que fazer: `mascararCorposDeHeredoc(cmd, opcoes)` ganha a opção `{ scriptNaoShell: true }`. Sem ela, nada muda. Com ela, um heredoc com delimitador citado, fechado e sem interpretador na linha, cujo alvo de redirecionamento é executado adiante SÓ por `node`, `python`, `python3`, `py`, `perl`, `ruby`, `deno` ou `bun` (nunca por `./x`, nem por shell), tem o corpo mascarado linha a linha preservando o comprimento: em cada linha, só o trecho que começa na palavra `git` e vai até a primeira aspa, crase, `;`, `|`, `&`, `)` ou fim de linha fica visível; o resto vira espaço. Assim o `git add -A` dentro de `execSync('git add -A')` continua sendo visto pelo gate como comando, e o JavaScript em volta deixa de ser lido como shell. Para isso, `alvoDoRedirecionamentoEhExecutadoDepois` passa a ter uma irmã que devolve o NOME do executor (ou `"./"` para execução direta), sem mudar a função existente. No `gate-staging-total.cjs`, a linha 337 vira a linha literal `const cmdParaAnalise = mascararCorposDeHeredoc(cmd, { scriptNaoShell: true });`.
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `const cmdParaAnalise = mascararCorposDeHeredoc(cmd, { scriptNaoShell: true });`
  para: `const cmdParaAnalise = mascararCorposDeHeredoc(cmd);`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "gates-sem-ruido D6: script não-shell escrito por heredoc"
prova: `d=$(mktemp -d) && git init -q "$d" && node -e "const r=require('child_process').spawnSync('node',['hooks/gate-staging-total.cjs'],{input:JSON.stringify({tool_name:'Bash',tool_input:{command:'cat > t.cjs <<\'EOF\'\nconst m=s.match(/([a-z0-9-]+'+String.fromCharCode(92)+'.(cjs|cmd))/i);\nEOF\nnode t.cjs'},cwd:process.argv[1]}),encoding:'utf8'});process.exit(r.status)" "$(cygpath -w "$d" 2>/dev/null || echo "$d")"`
pronto quando: com o comando exato que o gate barrou nesta sessão (heredoc citado gravando um `.cjs` com o regex `/([a-z0-9-]+\.(cjs|cmd))/i`, executado por `node` num repositório que não é worktree linkado), o gate deixa passar — provado pela `prova:` acima saindo 0 (sai 2 na base) e por `bash hooks/testa-gate-staging-total.sh` imprimindo `ok` em cada caso abaixo e `0 falha(s)`, todos com cwd num `git init` temporário:
  - legítimos que passam: o regex acima em `.cjs` executado por `node` → exit 0; o mesmo corpo gravado em `.py` e executado por `python` → exit 0; corpo JS com `execSync('git status')` executado por `node` → exit 0.
  - contornos que continuam barrando: corpo JS com `execSync('git add -A')` executado por `node` → exit 2; corpo com `git commit -am x` executado por `python3` → exit 2; o MESMO corpo do regex executado por `bash t.cjs` → exit 2 (shell segue analisado inteiro, D11 do zerar-issues-4); executado por `./t.cjs` → exit 2; heredoc SEM aspas executado por `node` com `$(git add -A)` no corpo → exit 2.
  - casos vizinhos de outros gates: `bash hooks/testa-gate-worktree.sh` e `bash hooks/testa-gate-mensagem-commit.sh` com o mesmo número de `ok` da linha de base (a chamada sem opção não mudou).

### 5. Versão 2.17.0, CHANGELOG e README [tipo: docs]
atende: D1, D2, D3, D4, D5, D6
arquivos: `.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md`, `README.en.md`
depende de: 1, 2, 3, 4
mutacao: n/a
  motivo: tarefa de texto e número de versão; não há comportamento a inverter
pronto quando: com o diff das tarefas 1 a 4 integrado, `.claude-plugin/plugin.json` diz `"version": "2.17.0"`, e a entrada `## 2.17.0 — 2026-11-17` do `CHANGELOG.md` descreve, do ponto de vista de quem usa, os quatro comportamentos novos com os números do design (121 bloqueios de agente em voo em sessão interativa; 38 de heredoc no commit; 31 de merge "não está sozinho"; o falso positivo do script node) e diz que migrar para mod foi avaliado e descartado com o motivo da D2 — provado por `node -e "const v=require('./.claude-plugin/plugin.json').version;const c=require('fs').readFileSync('CHANGELOG.md','utf8');const s=c.split('## ')[1]||'';process.exit(v==='2.17.0'&&s.startsWith('2.17.0')&&/121/.test(s)&&/mod/.test(s)?0:1)"` saindo 0; e as linhas do README que descrevem `gate-agente-em-voo`, `gate-mensagem-commit`, `gate-fechar-issue` (merge) e `gate-staging` batem com D3–D6 (lidas pelo `revisar`, que cita cada linha conferida).
