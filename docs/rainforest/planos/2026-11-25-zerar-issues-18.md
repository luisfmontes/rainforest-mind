# Plano: Rodada 18 — o segmentador lê escape, `$'...'` e comentário como o shell (#736)

Design: docs/rainforest/design/2026-11-25-zerar-issues-18.md

## O que não pode quebrar

- Todo caso existente de `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh`, `hooks/testa-gate-fechar-issue.sh`, `hooks/testa-gate-bateria-sem-timeout.sh` e `hooks/testa-gate-subagente-sem-gh.cjs` mantém o exit esperado. Nenhum caso é apagado.
- A assinatura `segmentosComAspas(cmd, ehPowerShell)` continua valendo para quem não passa o terceiro argumento: o dialeto sai de `ehPowerShell`.
- O texto de cada segmento continua um trecho do comando de entrada, sem a continuação de linha: `cwdDoSegmento` (`hooks/gate-fechar-issue.cjs`) casa segmentos por texto.

## Tarefas

A execução é na janela principal, não por executor haiku: é a lib de segmentação que cinco gates compartilham, e o estágio revisar tem foco em segurança. As tarefas são seriais e na ordem, porque todas tocam `hooks/lib/cwd-efetivo.cjs` ou a mesma seção nova de `hooks/testa-gate-staging-total.sh`. A seção nova fica logo antes de `echo "== resultado:` e abre com `echo "== rodada 18 (#736): escape, \$'...' e comentario no segmentador =="`. Os casos usam os ajudantes da bateria (`gate`, `b`, `p`, `hd`, `BS`).

### 1. Escape e `$'...'` do bash no segmentador [tipo: implementar]
atende: D1
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: nenhuma
busca:
- catalogo | segmentosComAspas em hooks/lib/cwd-efetivo.cjs | estendo; é a função que os gates já chamam
- catalogo | colapsaContinuacaoDeLinha em hooks/lib/tokens-comando.cjs | não reuso; serve também o desempacotador e o gate-fechar-issue (design, D2)
desfecho: estender
O que fazer:
- Em `segmentosComAspas(cmd, ehPowerShell = false, opcoes = {})`: `dialeto` vem de `opcoes.dialeto` ou de `ehPowerShell`, e `leEscape = dialeto !== "sem-escape"`. Antes da cadeia de aspas e fronteiras: a contrabarra do bash fora de aspas simples leva o caractere seguinte junto (`atual += c + cmd[i + 1]`), e `$'` fora de aspas abre a aspa `"$'"`, em que a contrabarra leva o seguinte e `'` fecha.
- `hooks/testa-cwd-efetivo.sh`, bloco novo antes do resultado: `echo \' ; git add -A` dá 2 segmentos e o segundo é ` git add -A`; `echo $'a\'; git add -A'` dá 1 segmento; com `{ dialeto: "sem-escape" }`, `echo \' ; x` dá 1 segmento (leitura antiga).
- Casos na seção nova da bateria de staging (exit): `#736 $'\' engole o heredoc` (2), `#736 $'\' dentro de ${}` (2), `escape fora de aspas: echo \' ; git add -A` (2), e os controles `echo \$'a\'; git add -A` (2), `echo "$'"; git add -A` (2), `echo 'a; git add -A'` (0), `echo $'a; git add -A'` (0), e os falsos positivos da base `echo $'a\'; git add -A'` (0) e `echo "a\"; git add -A ; echo b"` (0).
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `    else if (c === "$" && cmd[i + 1] === "'" && dialeto === "bash" && dolarLivre) {`
  para: `    else if (false) {`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "#736 $'\' engole o heredoc barra"
prova-na-base: verde — os casos só existem na seção que esta tarefa escreve; contra a lib da base o `git add -A` da #736 sai 0 (sonda de 2026-11-25)
pronto quando: `bash hooks/testa-gate-staging-total.sh` e `bash hooks/testa-cwd-efetivo.sh` com `ok` nos casos `#736` e 0 falhas no placar das duas.

### 2. Comentário e continuação de linha do dialeto [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: 1
busca:
- catalogo | comentario em hooks/lib/cwd-efetivo.cjs | nada; o segmentador nao lia comentario
- catalogo | leitura de # com contrabarra em hooks/gate-fechar-issue.cjs:segmentosParaGate | nao reuso; esta dentro do segmentador proprio do gate (design, Avaliado e descartado)
desfecho: estender
O que fazer:
- `abreComentario(antes, esc)`: começo do texto, ou último caractere já emitido em `[\s;&|(]` sem corrida ímpar de `esc` antes dele.
- `colapsaContinuacaoDoDialeto` devolve `{ texto, comentario }`, com 1 em cada caractere de comentário (a quebra que fecha fica fora). Em `segmentosComAspas`, caractere marcado vai para o segmento sem efeito de aspa nem de fronteira.
- `colapsaContinuacaoDoDialeto(cmd, dialeto)` substitui `colapsaContinuacaoDeLinhaNoTopo` quando `leEscape`: contrabarra (bash) ou crase (PowerShell) + LF/CRLF some fora de aspas simples, de `$'...'` e de comentário.
- Casos na seção nova: `comentario com aspa: echo hi # don't` (2), `comentario com aspa dupla` (2), `comentario com contrabarra no fim` (2), `bash -c com comentario e aspa` (2), e os controles `echo a#b'; git add -A'` (0), `echo $#'; git add -A'` (0), `git add a.txt # sem -A` (2), `git status # add -A' x` (0).
- `hooks/testa-cwd-efetivo.sh`: `echo hi # don't` + quebra + `git add -A` dá 2 segmentos; `echo hi #x\` + quebra + `git add -A` dá 2 segmentos.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `    else if (c === "#" && abreComentario(saida, esc)) {`
  para: `    else if (false) {`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "comentario com contrabarra no fim barra"
prova-na-base: verde — casos novos; contra a lib da base `echo hi # don't` + quebra + `git add -A` sai 0 (sonda de 2026-11-25)
pronto quando: `bash hooks/testa-gate-staging-total.sh` e `bash hooks/testa-cwd-efetivo.sh` com `ok` nos casos de comentário e 0 falhas.

### 3. O dialeto chega ao segmentador [tipo: implementar]
atende: D3
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/gate-staging-total.cjs`, `hooks/gate-mensagem-commit.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-mensagem-commit.sh`
depende de: 2
busca:
- catalogo | dialetoDoWrapper em hooks/gate-fechar-issue.cjs:1813 | nao reuso; so Bash/PowerShell e mora no gate (design, D3)
desfecho: estender
O que fazer:
- `dialetoDoWrapper(nome, dialetoDeFora)` exportada pela lib: `"sem-escape"` quando `dialetoDeFora !== "bash"`; senão `bash`/`sh`/`zsh`/`ksh`/`dash`/`ash`/`eval` → `"bash"`, `pwsh`/`powershell`/`iex`/`invoke-expression`/`&` → `"powershell"`, o resto → `"sem-escape"`.
- `gate-staging-total`: `segmentos(cmd, ehPowerShell)` e `cwdPorSegmento(cmd, cwd, ehPowerShell)` com `ehPowerShell = ev.tool_name === "PowerShell"`; `analisaSegmentoGit(segTexto, ferramenta, dialeto)` segmenta o interno com `dialetoDoWrapper(toks[pos].v, dialeto)`.
- `gate-mensagem-commit`: `achaGitCommit` segmenta com `ferramenta === "PowerShell"`, e `analisaSegmentoCommit` faz o mesmo que o de staging com o interno.
- Casos na seção nova: PowerShell `echo hi # don't` + quebra + `git add -A` (2), PowerShell `` echo `'; git add -A `` (2), PowerShell `echo $'a\'; git add -A` (2), PowerShell `bash -c 'echo \''; git add -A'` (2), Bash `pwsh -Command "echo \`'; git add -A"` (2), e os falsos positivos da base PowerShell `` echo "a`"; git add -A" `` (0) e Bash `cmd /c "echo a\" & git add -A"` (0; medido no Git Bash: o cmd imprime `a\" & echo RODOU` e não roda o segundo comando).
- `hooks/testa-gate-mensagem-commit.sh`: `gate "#736 git commit pelado depois de comentario com aspa -> exit 2" 2 "$(payload "$R1" Bash $'echo hi # don\x27t\ngit commit')"`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `  if (dialetoDeFora !== "bash") return "sem-escape";`
  para: `  if (false) return "sem-escape";`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "PowerShell bash -c com aspa dobrada barra"
prova-na-base: verde — casos novos ou que já saíam 2 pela leitura antiga; a mutação mede que a leitura nova não piora o PowerShell
pronto quando: `bash hooks/testa-gate-staging-total.sh` e `bash hooks/testa-gate-mensagem-commit.sh` com `ok` nos casos `#736` e 0 falhas.

### 5. Comentário só onde o shell abre (revisão de segurança) [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: 3
busca:
- catalogo | colapsaContinuacaoDoDialeto em hooks/lib/cwd-efetivo.cjs | estendo; é a função da tarefa 2
desfecho: estender
O que fazer:
- Em `colapsaContinuacaoDoDialeto`, fora de aspas: `crase` alterna na crase do bash, `chaves` conta `${` e desconta `}`, e `#` só abre comentário com `!crase && chaves === 0`. No PowerShell, `<#` abre comentário que fecha em `#>`.
- `abreComentario` não aceita `)`, `<` nem `>` antes do `#`.
- Casos na seção nova, depois do comentário `# Revisao de seguranca do commit 8ffea4b2`: PowerShell `echo <# x #>; git add -A` (2), PowerShell `<#` em duas linhas (2), `` echo `echo #`; git add -A `` (2), `echo ${x:-a #}; git add -A` (2), PowerShell `echo ${a #}; git add -A` (2), `echo $(true)#; git add -A` (2), `cat <(true)#; git add -A` (2), `echo a\` + quebra + `#x; git add -A` (2), e o controle PowerShell `echo <# git add -A #> hi` (0).
- `hooks/testa-cwd-efetivo.sh`: `(736j)` e `(736k)`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `    else if (c === "`" && dialeto === "bash") alternaCrase();`
  para: `    else if (false) alternaCrase();`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "# dentro de crase nao passa da crase barra"
prova-na-base: verde — casos novos; contra o commit 8ffea4b2 as quatro formas da revisão de segurança saem 0 (achado da revisão automática, conferido no shell em 2026-11-25)
pronto quando: `bash hooks/testa-gate-staging-total.sh` e `bash hooks/testa-cwd-efetivo.sh` com `ok` nos casos da revisão de segurança e 0 falhas.

### 6. `$$` e trecho neutro (segunda revisão de segurança) [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: 5
busca:
- catalogo | colapsaContinuacaoDoDialeto em hooks/lib/cwd-efetivo.cjs | estendo; é a função das tarefas 2 e 5
desfecho: estender
O que fazer:
- `CLASSE = { normal, comentario, neutro, ansi }`; o colapso devolve `{ texto, classe }` e marca com `ansi` o `$` que abre `$'`. O segmentador usa `classe` para comentário, trecho neutro e abertura de `$'`, sem decidir sozinho.
- `dolares` conta a corrida de `$` sem escape; `$'` e `${` só abrem com `dolaresAntes % 2 === 0`.
- `#` em começo de palavra com `crase || chaves > 0` abre o estado `#?`: os caracteres até a quebra saem `neutro`. No segmentador, aspa, escape e `$` neutros vão para o segmento sem efeito; a fronteira segue valendo.
- Casos na seção nova, depois do comentário `# Revisao de seguranca do commit a0b55385`: `echo $${ # don't` + quebra + `git add -A` (2), `echo $$'a\'; git add -A #'` (2), `bash <<'EOF'` com crase solta no corpo e `echo hi # don't` + quebra + `git add -A` depois (2), e o controle `echo $$$'a\'; git add -A'` (0).
- `hooks/testa-cwd-efetivo.sh`: `(736l)` e `(736m)`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `    const dolarLivre = dolaresAntes % 2 === 0;`
  para: `    const dolarLivre = true;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "$$' e PID e aspa simples barra"
prova-na-base: verde — casos novos; contra o commit a0b55385 `echo $${ # don't` + quebra + `git add -A`, `echo $$'a\'; git add -A #'` e a crase solta no corpo de `bash <<'EOF'` saem 0 (sonda de 2026-11-25)
pronto quando: `bash hooks/testa-gate-staging-total.sh` e `bash hooks/testa-cwd-efetivo.sh` com `ok` nos casos da segunda revisão de segurança e 0 falhas.

### 7. Leitura exata de `#` em `${}` e em crase, incerteza para o cwd (terceira revisão de segurança) [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/gate-worktree.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: 6
busca:
- catalogo | estado.incerto em hooks/lib/cwd-efetivo.cjs:resolverMovedor e hooks/gate-worktree.cjs:alvosBashEscrita | reuso; é o caminho conservador que já existe para `cd` não resolvível
desfecho: estender
O que fazer:
- Em `colapsaContinuacaoDoDialeto`: `#` dentro de `${...}` (sem incerteza) é literal; `#` em começo de palavra dentro de crase abre o estado ``"#`"``, que fecha na crase (e zera `crase`) ou na quebra (e liga `incerto`); quebra fora de aspas com `crase || chaves > 0` liga `incerto`; com `incerto`, `#` em começo de palavra abre o neutro `#?`. O retorno ganha `incerto`.
- `segmentosComAspas` põe `segmentos.incerto = true` quando o colapso devolve `incerto`; `cwdPorSegmento`, `alvosBash` e `alvosBashEscrita` começam o `estado` com `incerto: segmentos.incerto === true`.
- Casos na seção nova, depois do comentário `# Revisao de seguranca do commit bcd7e602`: `echo ${x:-#}'; git add -A; '` (0), `` echo `echo #`'; git add -A; ' `` (0), `echo ${x:-# '}'}; git add -A` (2), crase em duas linhas com `#` (2), `` echo `echo # a'`; git add -A `` (2).
- `hooks/testa-cwd-efetivo.sh`: `(736n)` e `(736o)`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `    else if (c === "#" && !incerto && (topo() === "{" || topo() === "((")) {`
  para: `    else if (false) {`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "# dentro de ${} nao passa da chave barra"
prova-na-base: verde — casos novos; contra o commit bcd7e602 `echo ${x:-#}'; cd x; '` fabrica o segmento `cd x` (achado da revisão automática, conferido no bash em 2026-11-25)
pronto quando: `bash hooks/testa-gate-staging-total.sh`, `bash hooks/testa-cwd-efetivo.sh` e `bash hooks/testa-gate-worktree.sh` com 0 falhas, e `ok` nos casos `(736n)` e `(736o)`.

### 8. Aninhamento em pilha e aspa aberta no fim (quarta revisão de segurança) [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: 7
busca:
- catalogo | colapsaContinuacaoDoDialeto e segmentosComAspas em hooks/lib/cwd-efetivo.cjs | estendo; são as funções das tarefas 1 a 7
desfecho: estender
O que fazer:
- `pilha` no lugar de `crase` e `chaves`: `${` e `$(` empilham, `}` e `)` desempilham quando batem com o topo, a crase alterna no topo. O `#` olha `topo()`. No estado de comentário em crase, contrabarra leva o caractere seguinte.
- Em `segmentosComAspas`, `inicioAspa` guarda onde a aspa abriu; aspa aberta no fim (com `leEscape`) acrescenta `segmentosComAspas(cmd.slice(inicioAspa + 1), ...)` e liga `leituraIncerta`.
- Emenda da quinta revisão (commit 8a5bdc2c): `fechaCrase` desempilha até a crase mais recente; o comentário é ``"#`"`` com crase em qualquer nível (`pilha.includes`), e `#` com `pilha.length > 1` liga `incerto`. Casos depois do comentário `# Revisao de seguranca do commit 8a5bdc2c` e `(736r)`.
- Casos na seção nova, depois do comentário `# Revisao de seguranca do commit 6f2abe19`: crase escapada no comentário (2), crase dentro de `${}` (2), aspa aberta no fim (2).
- `hooks/testa-cwd-efetivo.sh`: `(736p)` e `(736q)`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `  if (leEscape && aspa && inicioAspa >= 0) {`
  para: `  if (false) {`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "aspa aberta no fim: o texto depois dela e analisado barra"
prova-na-base: verde — casos novos; contra o commit 6f2abe19 a crase escapada no comentário e a crase dentro de `${}` saem 0 (achado da revisão automática, conferido no bash em 2026-11-25)
pronto quando: `bash hooks/testa-gate-staging-total.sh` e `bash hooks/testa-cwd-efetivo.sh` com `ok` nos casos `(736p)` e `(736q)` e 0 falhas.

### 9. Redirecionamento antes do comando, espaço do bash, aritmética e `<#` no meio (revisão do fluxo) [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`, `hooks/testa-gate-mensagem-commit.sh`
depende de: 8
busca:
- catalogo | colapsaContinuacaoDoDialeto, abreComentario e segmentosComAspas em hooks/lib/cwd-efetivo.cjs | estendo; são as funções das tarefas 1 a 8
desfecho: estender
O que fazer:
- Em `segmentosComAspas`, separador (`;`, `&`, `|`) escapado com `<` ou `>` em qualquer ponto antes dele na linha (`<<\;`, `2>\;`, `>out\;`, `> "a b"\;`, `>$(echo a b)\;`): o texto depois do escape vira segmento também, e a linha sai incerta. Falha fechado, porque o alvo pode ter aspa ou `$( )` com espaço.
- `abreComentario` aceita o espaço do dialeto: no bash só espaço, tab e quebra (CR, NBSP, BOM e FF são letra); no PowerShell o `\s` do JavaScript mais U+0085, menos o BOM (medido em 2026-11-25).
- Emenda da revisão automática do commit bf7dfb13: casos depois do comentário `# Revisao de seguranca do commit bf7dfb13`.
- `$((` e `((` no começo de token empilham `"(("`, que `))` desempilha; dentro dele o `#` é literal.
- PowerShell: `<#` só abre comentário de bloco no começo de token (`abreComentario`).
- Casos depois do comentário `# Revisao do fluxo (revisor, rodada 18)` (14 que barram, 5 controles), `(736s)` a `(736u)` em `testa-cwd-efetivo.sh`, e dois `#736` em `testa-gate-mensagem-commit.sh`.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `      if (!aspa && ";&|".includes(cmd[i + 1]) && /[<>]/.test(cmd.slice(0, i)) && cmd.slice(i + 2).trim()) {`
  para: `      if (false) {`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "<<\\; antes do comando barra"
prova-na-base: verde — casos novos; contra o commit a29d6af2 os 17 ataques da revisão saem 0 (medido com o gate do commit a29d6af2 em 2026-11-25; o bash roda o `git` em todos)
pronto quando: `bash hooks/testa-gate-staging-total.sh`, `bash hooks/testa-cwd-efetivo.sh` e `bash hooks/testa-gate-mensagem-commit.sh` com 0 falhas e `ok` nos casos `(736s)`, `(736t)` e `(736u)`.

### 4. Versão 2.17.4 [tipo: docs]
atende: D1, D2, D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 9
O que fazer:
- Versão 2.17.4 nos dois `plugin.json` e no selo do `README.md`.
- Entrada 2.17.4 no `CHANGELOG.md`: o segmentador dos gates lê escape, `$'...'` e comentário como o bash e o PowerShell (#736); o texto de wrapper chamado pelo PowerShell segue na leitura antiga.
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
prova: `grep -q '"version": "2.17.4"' .claude-plugin/plugin.json`
pronto quando: com os manifestos que o cache lê para instalar, provado por `grep -c '"version": "2.17.4"' .claude-plugin/plugin.json .codex-plugin/plugin.json` imprimindo 1 em cada, e `grep -c '^## 2.17.4' CHANGELOG.md` imprimindo 1.
