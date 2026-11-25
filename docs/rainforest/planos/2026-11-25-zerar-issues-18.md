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
  de: `} else if (!aspa && c === "$" && cmd[i + 1] === "'" && dialeto === "bash") {`
  para: `} else if (false) {`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: testa-gate-staging-total.sh, seção "rodada 18", caso "#736 $'\' engole o heredoc barra"
prova-na-base: verde — os casos só existem na seção que esta tarefa escreve; contra a lib da base o `git add -A` da #736 sai 0 (sonda de 2026-11-25)
pronto quando: `bash hooks/testa-gate-staging-total.sh` e `bash hooks/testa-cwd-efetivo.sh` com `ok` nos casos `#736` e 0 falhas no placar das duas.

### 2. Comentário e continuação de linha do dialeto [tipo: implementar]
atende: D2
arquivos: `hooks/lib/cwd-efetivo.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-cwd-efetivo.sh`
depende de: 1
busca:
- catalogo | inicioDePalavra/comentario em hooks/lib/cwd-efetivo.cjs | nada; o segmentador nao lia comentario
- catalogo | leitura de # com contrabarra em hooks/gate-fechar-issue.cjs:segmentosParaGate | nao reuso; esta dentro do segmentador proprio do gate (design, Avaliado e descartado)
desfecho: estender
O que fazer:
- `inicioDePalavra(cmd, i, esc)`: começo do texto, ou caractere anterior em `[\s;&|()<>]` sem corrida ímpar de `esc` antes dele.
- Em `segmentosComAspas`, `#` fora de aspas em começo de palavra abre a aspa `"#"`, que guarda tudo até a quebra; a quebra fecha e segue para a fronteira.
- `colapsaContinuacaoDoDialeto(cmd, dialeto)` substitui `colapsaContinuacaoDeLinhaNoTopo` quando `leEscape`: contrabarra (bash) ou crase (PowerShell) + LF/CRLF some fora de aspas simples, de `$'...'` e de comentário.
- Casos na seção nova: `comentario com aspa: echo hi # don't` (2), `comentario com aspa dupla` (2), `comentario com contrabarra no fim` (2), `bash -c com comentario e aspa` (2), e os controles `echo a#b'; git add -A'` (0), `echo $#'; git add -A'` (0), `git add a.txt # sem -A` (2), `git status # add -A' x` (0).
- `hooks/testa-cwd-efetivo.sh`: `echo hi # don't` + quebra + `git add -A` dá 2 segmentos; `echo hi #x\` + quebra + `git add -A` dá 2 segmentos.
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `    else if (c === "#" && inicioDePalavra(cmd, i, esc)) aspa = "#";`
  para: `    else if (false) aspa = "#";`
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

### 4. Versão 2.17.4 [tipo: docs]
atende: D1, D2, D3
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 3
O que fazer:
- Versão 2.17.4 nos dois `plugin.json` e no selo do `README.md`.
- Entrada 2.17.4 no `CHANGELOG.md`: o segmentador dos gates lê escape, `$'...'` e comentário como o bash e o PowerShell (#736); o texto de wrapper chamado pelo PowerShell segue na leitura antiga.
mutacao: n/a
  motivo: troca de número de versão e texto de changelog, sem comportamento a inverter
prova: `grep -q '"version": "2.17.4"' .claude-plugin/plugin.json`
pronto quando: com os manifestos que o cache lê para instalar, provado por `grep -c '"version": "2.17.4"' .claude-plugin/plugin.json .codex-plugin/plugin.json` imprimindo 1 em cada, e `grep -c '^## 2.17.4' CHANGELOG.md` imprimindo 1.
