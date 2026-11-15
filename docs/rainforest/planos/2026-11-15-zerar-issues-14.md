# Plano: Rodada 14 — gh escondido do gate de fechamento e segmentador do heredoc

Design: docs/rainforest/design/2026-11-15-zerar-issues-14.md

## O que não pode quebrar
- Toda forma que o `gate-fechar-issue` barra hoje continua barrando: as seções existentes de `bash hooks/testa-gate-fechar-issue.sh` e de `node hooks/testa-gate-subagente-sem-gh.cjs` seguem verdes.
- `bash -c 'echo hi'`, `bash -c 'echo hi' x`, `builtin echo x`, `echo "$IFS"`, `echo "${x:-a}"` e `cat <<< $'texto'` saem 0.
- Nenhuma expansão de variável além do `$IFS` (D1 da zerar-issues-12).

## Tarefas

### 1. `bash -c`: o script é só a primeira palavra; `exec -a`, `builtin` e `cmd //c` [tipo: implementar]
atende: D1, D2
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
busca:
- catalogo | listar --raiz hooks/lib | estendo a função desempacotarWrapperDeString de hooks/lib/tokens-comando.cjs:875 e a função posicaoDeComando de hooks/lib/tokens-comando.cjs:275
desfecho: estender
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: const interno = desempacota(palavraDoScript(current.resto));
  para: const interno = desempacota(current.resto);
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: testa-gate-fechar-issue.sh, seção "(#699/#703/#708) bash -c com argumento posicional, --, exec -a, builtin e cmd //c"
prova: `node -e "const t=require('./hooks/lib/tokens-comando.cjs');const r=t.desempacotarWrapperDeString('bash -c \"gh issue close 12\" x');process.exit(r.interno==='gh issue close 12'?0:1)"`
Implementação:
- Em `desempacotarWrapperDeString`, no ramo dos wrappers de `WRAPPERS_DE_COMANDO`, depois de achar a flag `-c`, o `resto` passa por uma função nova, `palavraDoScript(resto)`. Ela pula um `--` isolado e devolve só a primeira palavra do shell: trechos citados e nus colados, até o primeiro espaço fora de aspas, com as aspas como estavam, para o `desempacota` tirá-las. A linha que desempacota fica exatamente como o `de:` acima.
- `FLAGS_COM_VALOR` ganha `exec: -a`, e `WRAPPERS_QUE_REPASSAM` ganha `builtin`.
- No ramo `cmd`, aceite `//c` e `//k` além de `/c` e `/k`.
- No `gate-fechar-issue.cjs`, `mistaComGh` (linha 1664) passa a olhar só os tokens da palavra do script (`palavraDoScript`), e não `depois` inteiro.
pronto quando: com o payload real de PreToolUse (Bash) em `node hooks/gate-fechar-issue.cjs`:
- saem 2: `bash -c "gh issue close 12" x`, `bash -c 'gh pr merge 5' x`, `sh -c "gh issue close 12" _`, `bash -c 'gh issue close 12' x y`, `bash -c "gh issue close 12" -- x`, `bash -c -- 'gh pr merge 5'`, `exec -a x bash -c 'gh issue close 12'`, `builtin eval 'gh issue close 12'`, `cmd //c bash -c "echo"' \"; gh issue close 12'` e `eval "echo"' \"; gh issue close 12'`;
- saem 0: `bash -c 'echo hi' x`, `bash -c -- 'echo hi'`, `bash -c 'echo hi' x -I"C:\x"` e `builtin echo x`.

Isso é provado pela seção nova de `bash hooks/testa-gate-fechar-issue.sh`, com o placar `0 falha(s)`.

### 2. Segmentador do `gate-subagente-sem-gh` sem o caractere do delimitador [tipo: implementar]
atende: D5
arquivos: `hooks/lib/heredoc.cjs`, `hooks/gate-subagente-sem-gh.cjs`, `hooks/testa-gate-subagente-sem-gh.cjs`
depende de: nenhuma
paralela: sim
busca:
- catalogo | listar --raiz hooks/lib | estendo hooks/lib/heredoc.cjs, ao lado da função corpoDeHeredoc de hooks/lib/heredoc.cjs:138, e uso a nova na função segmentosParaGate de hooks/gate-subagente-sem-gh.cjs:209
desfecho: estender
mutacao:
  arquivo: `hooks/gate-subagente-sem-gh.cjs`
  de: const depois = fechado ? restoDepoisDoHeredoc(cmd, heredoc.fim) : '';
  para: const depois = fechado ? cmd.slice(heredoc.fim - 1) : '';
  bateria: `node hooks/testa-gate-subagente-sem-gh.cjs`
  fixture: testa-gate-subagente-sem-gh.cjs, caso "(#706) segmentosParaGate não cola o último caractere do delimitador"
prova: `node -e "const {segmentosParaGate}=require('./hooks/gate-subagente-sem-gh.cjs');const s=segmentosParaGate('cat > novo.md <<\'EOF\' && gh pr create --title t --body-file novo.md\nx termo\nEOF');process.exit(s[s.length-1].trim().endsWith('novo.md')?0:1)"`
Implementação: `hooks/lib/heredoc.cjs` exporta `restoDepoisDoHeredoc(cmd, fim)`, com o texto do comando que vem depois da linha do delimitador. Ele preserva a quebra de linha que separa o próximo comando, quando há um, e nunca devolve caractere do delimitador. No `gate-subagente-sem-gh.cjs`, a linha 335 fica exatamente como o `de:` acima. Investigue o que `corpoDeHeredoc` devolve em `fim` nos dois casos: delimitador no fim do comando, e delimitador seguido de `\n` e de mais um comando.
pronto quando: `segmentosParaGate` (do `gate-subagente-sem-gh.cjs`) sobre os três comandos da tabela da #706 (delimitadores `EOF`, `FIM`, `EOF2`) devolve o último segmento ` gh pr create --title t --body-file novo.md`, e sobre `cat <<EOF\nx\nEOF\ngh pr create --title t --body-file a.md` mantém o `gh pr create` num segmento próprio. Isso é provado pelos casos novos de `node hooks/testa-gate-subagente-sem-gh.cjs`, com `falhou: 0`.

### 3. `$IFS`, resíduos da #692 e o heredoc na cópia do `gate-fechar-issue` [tipo: implementar]
atende: D3, D4, D5
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 1, 2
paralela: nao
busca:
- catalogo | listar --raiz hooks | estendo a função segmentosParaGate de hooks/gate-fechar-issue.cjs:230 e uso restoDepoisDoHeredoc de hooks/lib/heredoc.cjs, da tarefa 2
desfecho: estender
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: return trocado;
  para: return s;
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `1200000`
  fixture: testa-gate-fechar-issue.sh, seção "(#694) $IFS divide a palavra"
prova: `node -e "const cp=require('child_process');const r=cp.spawnSync(process.execPath,['hooks/gate-fechar-issue.cjs'],{input:JSON.stringify({tool_name:'Bash',tool_input:{command:'gh\$IFS issue close 12'},cwd:process.cwd()}),encoding:'utf8'});process.exit(r.status===2?0:1)"`
Implementação:
- (D3) Função nova `trocarIfsPorEspaco(s)`, cuja última linha é exatamente `return trocado;`. Ela troca `$IFS` e `${IFS}` fora de aspas simples por um espaço, só na cópia que o gate analisa. O comando que vai para as mensagens não muda.
- (D4a) Na contagem de parênteses do P4, a expansão `${...}` é pulada inteira, com as chaves balanceadas.
- (D4b) No ramo `<<<`, a palavra que começa com `$'` ou `$"` é lida até a aspa que fecha, com o escape do ANSI-C no caso do `$'`.
- (D4c) Com `FERRAMENTA === "PowerShell"`, a crase escapa o caractere seguinte e não abre substituição.
- (D4d) O `TETO_SEGMENTACAO` vira um orçamento de caracteres varridos, somados em todas as recursões. Estourado o orçamento, o gate barra como ilegível se `temGhLiteralQueEscreve` acha `gh` de escrita no comando, e libera se não acha.
- (D5) A linha 522 usa `restoDepoisDoHeredoc` da tarefa 2.
pronto quando: com o payload real de PreToolUse em `node hooks/gate-fechar-issue.cjs`:
- saem 2 (Bash): `gh$IFS issue close 12`, `gh${IFS}issue${IFS}close${IFS}12`, `echo "$(echo ')'; gh${IFS}issue close 12)"`, `echo "$(echo ${x:-)} ; gh issue close 12)"`, `echo "$(printf %s ${y/)/} && gh issue close 12)"`, `bash <<<$'gh issue close 12'`, `bash <<< $'gh issue close 12'` e `bash <<<$"gh issue close 12"`;
- sai 2 (PowerShell): ``echo `"; gh issue close 12``;
- saem 0: `echo "$IFS"`, `IFS=: read a b <<< "x:y"`, `echo "${x:-a}"` e `cat <<< $'texto'`, e, no PowerShell, ``Write-Host "a`tb"``;
- um comando com 3000 `$(true)` planos sai 0;
- 16 níveis de `"$(echo ..)"` com 400 KB e um `gh issue close 12` saem 2, em menos de 5 s medidos pela bateria.

Isso é provado pelas seções novas de `bash hooks/testa-gate-fechar-issue.sh`, com `0 falha(s)`.

### 4. Versão 2.16.0 e registro [tipo: docs]
atende: D6, D7
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3
paralela: nao
mutacao: n/a
  motivo: número de versão e texto de registro; não há comportamento a inverter. A coerência se confere pela bateria de versão e pela leitura contra o design.
pronto quando: os manifestos e o selo dizem 2.16.0, e `bash scripts/testa-versao.sh` sai com 0 falhas. A entrada `## 2.16.0 — 2026-11-15` do CHANGELOG descreve D1 a D5 e o modelo de ameaça da D6, e não promete expandir variável além do `$IFS`.
