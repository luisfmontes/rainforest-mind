# Plano: Gate: subagente não escreve no GitHub (direto nem por script)

Design: docs/rainforest/design/gate-subagente-sem-gh.md

## O que não pode quebrar
- A janela principal (payload sem `agent_id`) nunca é barrada por este gate: `gh issue close 12`, `gh pr create`, `node scripts/fechar-issue.cjs 12 ...` saem 0 sem `agent_id`.
- Leitura continua livre em subagente: `gh issue view 12`, `gh issue list`, `gh pr view 1`, `gh pr checks 1`, `gh run view 1`, `gh api repos/o/r/issues/1` (GET) saem 0.
- Bateria versionada roda em subagente: `bash hooks/testa-gate-fechar-issue.sh` e `node hooks/testa-gate-bateria-sem-timeout.cjs` com `agent_id` saem 0 no gate novo.
- Os outros gates de `Bash` e suas baterias continuam verdes (`testa-gate-fechar-issue.sh`, `testa-gate-mensagem-commit.sh`, `testa-gate-staging-total.sh`, `testa-gate-bateria-sem-timeout.cjs`).
- O gate nunca derruba a sessão por erro próprio: payload malformado, arquivo ilegível ou git ausente saem 0.

## Tarefas

### 1. Gate novo: comando direto, wrapper e heredoc [tipo: implementar]
atende: D1, D2, D3, D6
arquivos: `hooks/gate-subagente-sem-gh.cjs`, `hooks/testa-gate-subagente-sem-gh.cjs`, `hooks/hooks.json`, `hooks/lib/config.cjs`, `hooks/lib/tokens-comando.cjs`, `hooks/gate-fechar-issue.cjs`, `scripts/testa-conferir-categoria.sh`, `hooks/testa-titulo-sessao-registro.sh`
depende de: nenhuma
paralela: nao
mutacao:
  arquivo: `hooks/gate-subagente-sem-gh.cjs`
  de: `  issue: new Set(["close", "comment", "edit", "create", "reopen", "delete", "transfer", "pin", "unpin", "lock", "unlock"]),`
  para: `  issue: new Set([]),`
  bateria: `node hooks/testa-gate-subagente-sem-gh.cjs`
  fixture: testa-gate-subagente-sem-gh.cjs, caso "(D2) gh issue close 12 em subagente"
pronto quando: com o payload PreToolUse real (`{"tool_name":"Bash","agent_id":"a1","cwd":...,"tool_input":{"command":...}}`), saem **2** em subagente: `gh issue close 12`, `gh issue comment 12 -b x`, `gh pr merge 1`, `gh pr create -t t -b b`, `gh release create v1`, `gh workflow run x.yml`, `gh run rerun 1`, `gh api -X PATCH repos/o/r/issues/1 -f state=closed`, `gh api repos/o/r/issues/1/comments -f body=x` (campo sem `-X` = POST), `gh issue \close 12`, `gh issue $'close' 12`, `stdbuf -oL gh issue close 12`, `bash -c "gh issue close 12"`, `bash -c "$x"`, `eval "$x"`, e `cat > /tmp/x.sh <<'EOF'` com `gh issue close 12` no corpo; saem **0**: os mesmos sem `agent_id`, as leituras da seção "O que não pode quebrar", `gh api -X GET repos/o/r/issues -f state=open`, `echo "gh issue close 12"` (texto citado de echo). A mensagem de bloqueio (stderr) nomeia o comando visto, diz que escrita no GitHub é da janela principal e mostra como medir um gate pelo payload no stdin — conferido por `grep` na saída de um caso. Toggle `subagente-sem-gh` em `hooks/lib/config.cjs` (padrão ligado); com ele desligado no projeto, `gh issue close 12` em subagente sai 0. Hook registrado em `hooks/hooks.json` no matcher `Bash` do `PreToolUse`, e as contagens de `testa-conferir-categoria.sh` (48 peças, 18 guia) e `testa-titulo-sessao-registro.sh` (PreToolUse 13) atualizadas com a linha de histórico. A normalização de token (`semContrabarra`) sai de `gate-fechar-issue.cjs` para `hooks/lib/tokens-comando.cjs` e os dois gates a usam. Provado por `node hooks/testa-gate-subagente-sem-gh.cjs` imprimindo cada caso, mais `bash hooks/testa-gate-fechar-issue.sh`, `bash scripts/testa-conferir-categoria.sh` e `bash hooks/testa-titulo-sessao-registro.sh` com 0 falhas.

### 2. Script executado é lido, com isenção de bateria rastreada [tipo: implementar]
atende: D4, D5
arquivos: `hooks/gate-subagente-sem-gh.cjs`, `hooks/testa-gate-subagente-sem-gh.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/gate-subagente-sem-gh.cjs`
  de: `function arquivoIsento(caminho, cwd) {`
  para: `function arquivoIsento(caminho, cwd) { return true;`
  bateria: `node hooks/testa-gate-subagente-sem-gh.cjs`
  fixture: testa-gate-subagente-sem-gh.cjs, caso "(D4) bash script avulso com gh issue close"
pronto quando: com o payload PreToolUse real em subagente e arquivos reais numa caixa de areia (`mktemp -d` com `git init`): `bash /tmp/.../x.sh` onde `x.sh` tem `gh issue close 12` → **2**, com `x.sh:<linha>` na mensagem; o mesmo com `sh`, `source`, `. x.sh`, `./x.sh` (caminho direto) e caminho relativo resolvido contra o `cwd` do payload → 2; `node y.cjs` onde `y.cjs` tem `execFileSync('gh', ['issue', 'close', '12'])` → 2; o `.sh` que só tem `gh issue view 12` → 0; a linha `# gh issue close 12` comentada → 0; arquivo inexistente → 0. Isenção: `hooks/testa-a.sh` rastreado (commitado) com `gh issue close 12` como texto → 0, e alterado depois do commit → continua 0; o mesmo arquivo só no stage (`git add`, sem commit) → 0; não rastreado → 2, com a mensagem dizendo para dar `git add`; arquivo rastreado que não se chama `testa-*` → 2. `node scripts/fechar-issue.cjs 12 --comando x --saida y` em subagente → 2 pelo nome, mesmo versionado; sem `agent_id` → 0. Na árvore real, em subagente, `bash hooks/testa-gate-fechar-issue.sh` e `node hooks/testa-gate-bateria-sem-timeout.cjs` → 0. Provado por `node hooks/testa-gate-subagente-sem-gh.cjs` imprimindo cada caso.

### 3. Texto acompanha o mecanismo [tipo: docs]
atende: D6
arquivos: `referencias/perfil-de-trabalho.md`, `agents/arqueologo.md`, `agents/auditor-de-seguranca.md`, `agents/depurador.md`, `agents/documentador.md`, `agents/executor.md`, `agents/planejador.md`, `agents/resolvedor-de-build.md`, `agents/revisor.md`, `agents/tester.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: texto de registro, perfil e versão, sem comportamento a inverter; a falsificação é a coerência com o gate real
pronto quando: com o gate das tarefas 1 e 2 na árvore, `referencias/perfil-de-trabalho.md` ganha uma linha que diz o que o gate barra (escrita no GitHub por `gh` em subagente, direto, em wrapper, heredoc ou script lido antes de rodar), a isenção (bateria `testa-*` rastreada) e o porquê (dois fechamentos reais por revisor), e `node scripts/perfil.cjs --aplicar` propaga para os `agents/*.md` — conferido por `node scripts/perfil.cjs --conferir` saindo 0; a tabela de hooks do README ganha a linha de `gate-subagente-sem-gh.cjs` coerente com D2-D5; o CHANGELOG ganha a versão minor sobre `origin/main` descrevendo o efeito medido (o que sai 2 em subagente, o que continua 0); `bash scripts/testa-versao.sh` com 0 falhas.

## Emendas da integração (2026-09-28)
- **Tarefa 1:** a sondagem da integração achou `gh -R o/r issue close 12`, `gh issue -R o/r close 12` e `gh api -XPOST` saindo 0. Família e verbo passam a ser os dois primeiros posicionais (com `-R`/`--repo`/`--hostname` consumindo valor) e `-X<METODO>` colado conta como método; casos "(integração)" na bateria. A mutação declarada continua valendo (vermelha, exit 0).
- **Tarefa 2:** a sondagem achou `python3 x.py`, `bash < x.sh`, `cat x.sh | bash` e o `gh` atrás de variável no script (`G=gh; $G issue close 12`) saindo 0. Interpretadores ganham `python3`/`python2`/`py`/`zsh`/`dash`/`ksh`; `<` redirecionado aponta o arquivo; `cat <arquivos> | <interpretador>` sem `-c` lê os arquivos do `cat`; variável sozinha na posição do `gh` conta como `gh`. Casos "(integração)" na bateria; `cat x.sh | grep` continua 0. A mutação declarada continua valendo (vermelha, exit 0).
- **Revisão 1 (reprovada):** o revisor achou saindo 0 em subagente `gh alias set co "issue close" && gh co 12`, `node -e "...execSync('gh issue close 12')"`, `python -c "...os.system('gh issue close 12')"`, `pwsh x.ps1` e `./x.ps1`. Conserto: `alias set|import|delete`, `gist` e `extension install|upgrade|exec` entram em `VERBOS_ESCRITA`; em posição de comando, família fora das embutidas do `gh` (alias ou extensão) conta como escrita; código inline de `node -e|-p`, `python -c`, `perl|ruby -e`, `pwsh -Command|-c` e `cmd /c` é varrido (`pwsh -EncodedCommand` é ilegível → 2); `pwsh`/`powershell`/`perl`/`ruby` viram interpretadores de arquivo e `.ps1` extensão de script; arquivo lido sem achado cai na W2 em vez de retornar. Casos "(revisão)" na bateria (80/0). Mutações `if (false)` na família desconhecida e no ramo inline: as duas vermelhas (exit 0).
