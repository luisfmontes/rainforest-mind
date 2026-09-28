# Plano: Zerar as Issues abertas, rodada 10 — stdbuf longo (#346), --body-file MSYS (#344), R5 intermitente (#342), bateria em dobro (#341), transcrito absoluto (#340), três contrabarras (#339)

Design: docs/rainforest/design/zerar-issues-10.md

## O que não pode quebrar
- Tudo que os três gates de texto (`gate-fechar-issue`, `gate-mensagem-commit`, `gate-staging-total`) barram hoje continua barrado, incluindo os casos (#313a)-(#313e) e os de regressão da #337 (`bash $t` sem aspas → 2).
- `gate-bateria-sem-timeout` continua barrando as formas de `stdbuf` que já barrava (`--output=L`, `-oL`, `-o L`, `-i0 -o0 -e0`) e continua liberando bateria com `timeout` na frente e checagem de sintaxe (`bash -n`, `node --check`).
- `estado.cjs veredito` continua recusando (exit 2, sem gravar) transcrito fora de `subagents/`, sem `Slug:` do mesmo slug ou fora da pasta real de sessão (D12/D14).
- `bash scripts/varrer-baterias.sh` continua sem rede nem credencial, e nenhuma bateria roda duas vezes.
- `gate-fechar-issue` continua bloqueando `--body-file` relativo com cwd incerto e arquivo que não existe.

## Tarefas

### 1. `stdbuf` na lib comum de wrappers (#346) [tipo: implementar]
atende: D1
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/gate-bateria-sem-timeout.cjs`, `hooks/testa-gate-bateria-sem-timeout.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `  stdbuf: new Set(["-i", "-o", "-e", "--input", "--output", "--error"]),`
  para: `  stdbuf: new Set(["-i", "-o", "-e"]),`
  bateria: `node hooks/testa-gate-bateria-sem-timeout.cjs`
  fixture: testa-gate-bateria-sem-timeout.cjs, caso "(#346) stdbuf --output L (forma longa com espaco)"
pronto quando: com o payload PreToolUse real de subagente (`agent_id` presente, `tool_name: "Bash"`), `stdbuf --output L bash hooks/testa-x.sh` sai **2** (hoje 0), e também `--input 0` e `--error L`; `--output=L`, `-oL`, `-o L` e `-i0 -o0 -e0` continuam saindo 2; o mesmo comando com `tool_input.timeout: 600000` sai 0 *(emenda de 2026-09-28, integração: o critério original dizia "`timeout 600 stdbuf ...` sai 0", mas o gate mede o parâmetro `timeout` da ferramenta Bash, não o comando `timeout` — `timeout 600 bash hooks/testa-x.sh` já saía 2 na base; medido)* — provado por `node hooks/testa-gate-bateria-sem-timeout.cjs` imprimindo cada caso. A entrada `stdbuf` em `FLAGS_COM_VALOR` é a linha exata do `de:` acima, `stdbuf` entra em `WRAPPERS_QUE_REPASSAM`, e o ramo `if (cmd.v === "stdbuf")` do gate usa `pularFlagsDoWrapper(toks, posCmd + 1, "stdbuf")` no lugar do laço com `/^-[ioe]$/`. Como a lib é comum, `bash hooks/testa-gate-fechar-issue.sh`, `bash hooks/testa-gate-mensagem-commit.sh` e `bash hooks/testa-gate-staging-total.sh` terminam com 0 falhas, e `stdbuf -oL gh issue close 12` no `gate-fechar-issue` sai 2 (caso novo).

### 2. `--body-file` com caminho MSYS (#344) [tipo: implementar]
atende: D2
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: `      arquivo = normalizarMsys(arquivo);`
  para: `      arquivo = arquivo;`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `600000`
  fixture: testa-gate-fechar-issue.sh, secao "(#344) --body-file com caminho MSYS"
pronto quando: com o payload PreToolUse real de `gh pr create --title t --body-file /c/<caminho de um arquivo real em mktemp>` e o arquivo contendo `closes #N` sem evidência comentada, o gate sai **2** com a razão de evidência (e não "não consegui ler o arquivo"), e com o mesmo arquivo trazendo a evidência exigida sai com o mesmo exit que o caminho `C:/...` — provado por `bash hooks/testa-gate-fechar-issue.sh` com os dois caminhos lado a lado. A linha exata do `de:` fica logo depois de obter `arquivo`, antes de `if (!path.isAbsolute(arquivo) && cwdSegmento == null)`; `normalizarMsys` vem de `hooks/lib/cwd-efetivo.cjs`. Fora do win32 `normalizarMsys` devolve o caminho como veio: a bateria converte o caminho de `mktemp` para a forma `/c/...` só no win32 e, nas outras plataformas, o caso afirma que o caminho POSIX absoluto é lido — o caso roda (não pula) nas duas.

### 3. R5 separa falha de fixture de falha do `saude.cjs` (#342) [tipo: teste]
atende: D3
arquivos: `scripts/testa-saude.sh`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: a mudança é no próprio fixture da bateria (espera, porta e mensagem), não em código de produção; não há ramo de produto a inverter. A falsificação é outra: forçar o servidor a não subir tem de dar a mensagem de fixture, e o CI tem de ficar verde 5 vezes seguidas
pronto quando: com o servidor do R5 impedido de subir (porta já ocupada por outro `listen` na mesma porta, ou o `node` do servidor trocado por `true`, feito numa cópia descartável do script), o R5 reprova com a mensagem que começa por `FALHA R5. fixture:` e diz que o servidor não subiu — nunca com `aviso|porta ... não responde`; na árvore real, `bash scripts/testa-saude.sh` termina com `0 falha(s)`. O servidor escuta na porta 0 (ou re-sorteia quando o `listen` dá `EADDRINUSE`) e grava a porta real no arquivo `pronto`, que o fixture lê para montar o `poda.pid` e o `ANTHROPIC_BASE_URL`; o laço de espera, se o `pronto` não aparecer, cai na falha de fixture em vez de seguir. A prova do CI (5 reexecuções seguidas verdes do job `baterias`) é feita no PR, no `verificar`, com `gh run rerun`.

### 4. Nenhuma bateria `.sh` roda outra bateria (#341, e o cosmético da #339) [tipo: configurar]
atende: D4
arquivos: `hooks/testa-gate-publicacao-destino.sh`, `scripts/testa-varrer-baterias.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/testa-varrer-baterias.sh`
  de: `execucoes_sh_em() {`
  para: `execucoes_sh_em() { return 0;`
  bateria: `bash scripts/testa-varrer-baterias.sh`
  fixture: testa-varrer-baterias.sh, secao "Teste (n)", contraprova de caixa de areia com `.sh` que executa outra `testa-*.sh`
pronto quando: com a árvore real, `hooks/testa-gate-publicacao-destino.sh` não executa mais `testa-gate-staging-total.sh` nem `testa-conferir-publicacao.sh` (o bloco "Verificação: ... continua verde" sai), e na saída completa de `bash scripts/varrer-baterias.sh` o cabeçalho de cada uma dessas duas baterias aparece **uma** vez — provado por `bash scripts/varrer-baterias.sh 2>&1 | grep -c -- '^----- .*testa-gate-staging-total.sh -----'` igual a 1 (o executor confere o formato real do cabeçalho antes de fixar o grep). O teste (n) ganha a função que começa na linha exata `execucoes_sh_em() {`, que acha `testa-*.sh` **executando** outra `testa-*` (`bash`/`sh`/`source`/`.`/`exec` seguido do caminho, com ou sem variável de diretório na frente), sem pegar menção a caminho que não é execução — como o payload da linha 221 de `testa-gate-publicacao-destino.sh`, que só cita `scripts/testa-conferir-publicacao.sh` como alvo de Edit; numa caixa de areia com `hooks/testa-a.sh` contendo `bash "$SRC/hooks/testa-b.sh"`, a checagem acha; na árvore real, não acha nada. Teste (m): o `chmod +x` do `i=5` aponta para o arquivo que foi criado, e `bash scripts/testa-varrer-baterias.sh 2>&1 >/dev/null | grep -c 'testa-cjs-verde-5'` dá 0.

### 5. `transcrito` gravado com `~` (#340) [tipo: implementar]
atende: D5
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`, `docs/rainforest/estado/2026-09-12-multihost-sobre-1-11.json`, `docs/rainforest/estado/2026-09-23-contrato-de-veredito.json`, `docs/rainforest/estado/2026-09-24-beads-por-cima-do-ideias.json`, `docs/rainforest/estado/2026-09-24-revisor-folha.json`, `docs/rainforest/estado/2026-09-25-busca-na-raiz.json`, `docs/rainforest/estado/2026-09-25-veredito-fora-da-linha.json`, `docs/rainforest/estado/2026-09-25-vigiar-whatsapp.json`, `docs/rainforest/estado/2026-09-26-memoria-encurta.json`, `docs/rainforest/estado/agente-sem-background.json`, `docs/rainforest/estado/zerar-issues-9.json`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `transcrito: caminhoComTil(path.resolve(transcrito))`
  para: `transcrito: path.resolve(transcrito)`
  bateria: `bash scripts/testa-estado.sh`
  fixture: testa-estado.sh, caso "(#340) veredito grava transcrito com ~"
pronto quando: com um transcrito na pasta real de sessão (o mesmo arranjo que os casos D12/D14 da bateria já montam, com `HOME`/`USERPROFILE` apontando para a caixa de areia), `node scripts/estado.cjs veredito ... --transcrito <caminho absoluto>` grava no JSON um `transcrito` que começa por `~/` e termina com o mesmo sufixo do caminho real (`/.claude*/projects/.../subagents/agent-<id>.jsonl`), com `/` como separador; um transcrito fora da pasta pessoal fica como `path.resolve` (a função só troca o prefixo `os.homedir()`); as recusas D12/D14 continuam saindo 2 sem gravar — provado por `bash scripts/testa-estado.sh`. Nos 10 arquivos de estado listados, o valor de `transcrito` é reescrito para a forma `~/...` (só esse campo, por script, JSON reformatado igual ao que o `estado.cjs` grava), e `git grep -nE '"transcrito": *"(/|[A-Za-z]:)' -- docs/rainforest/estado/` sai vazio. O comentário do cabeçalho de `estado.cjs` ("o caminho absoluto fica no campo `transcrito`") passa a dizer `~`.

### 6. Continuação de linha na mesma passada das aspas duplas (#339) [tipo: implementar]
atende: D6
arquivos: `hooks/lib/tokens-comando.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/lib/tokens-comando.cjs`
  de: `      if (prox === "\n") {`
  para: `      if (false) {`
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  timeout: `600000`
  fixture: testa-gate-fechar-issue.sh, secao "(#339) N contrabarras antes da quebra, entre aspas duplas"
pronto quando: com o payload PreToolUse real de `bash -c "gh issue ` + N contrabarras + quebra de linha + `close 12"` para N = 1, 2, 3 e 4, o exit do `gate-fechar-issue` é 2 exatamente nos N em que o bash real, com um `gh` falso no PATH que registra a chamada, executa `gh issue close 12` — a bateria roda o bash real e o gate para cada N e compara os dois lado a lado (N=3 hoje sai 0 e o bash executa: é o caso que tem de virar). `reduzEscapeAspasDuplas` passa a tratar, na mesma passada, `\` + quebra de linha (some) com a linha exata do `de:` acima, ao lado de `\\`, `\"`, `\$` e `` \` ``; `colapsaContinuacaoDeLinha` continua rodando para o que não veio de aspas duplas. Os casos (#313a)-(#313e) continuam verdes; `bash hooks/testa-gate-mensagem-commit.sh` e `bash hooks/testa-gate-staging-total.sh` terminam com 0 falhas. *(Emenda de 2026-09-28, integração: a passada única sozinha não fecha o N=3 — o que sobra dela é `gh issue \close 12`, e o `bash -c` tira a contrabarra fora de aspas na segunda leitura. Medido: `gh issue \close 12` SEM wrapper já saía 0 na base, e também `gh \issue close 12` e `gh issue cl\ose 12`. Conserto no mesmo defeito: `indiceSequencia` do `gate-fechar-issue.cjs` compara o token sem contrabarra (`semContrabarra`), casos (#339b) → 2. Com isso a passada única ficou mascarada na bateria do gate, e ganhou medição própria: (#339c) compara `reduzEscapeAspasDuplas` (exportada) com o `printf` do bash real para N = 1..4. Segunda mutação, re-rodada na integração com exit 0: em `hooks/gate-fechar-issue.cjs`, `.every((s, idx) => semContrabarra(s).toLowerCase()` → `.every((s, idx) => s.toLowerCase()` deixa vermelhos (#339 N=3) e os três (#339b). O controle (hd) passou de exit 0 para 2: `echo hi \gh issue close 12` cai na política de `echo hi gh issue close 12`, que a base já barrava.)*

### 7. CHANGELOG e README acompanham a entrega [tipo: docs]
atende: D7
arquivos: `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4, 5, 6
paralela: nao
mutacao: n/a
  motivo: texto de registro, sem comportamento a inverter; a falsificação é a coerência com o diff real
pronto quando: com o diff real da branch contra `origin/main`, o CHANGELOG ganha uma entrada de versão minor sobre a de `origin/main` no momento do `fechar` que descreve cada uma das seis correções pelo efeito medido (o comando que antes saía 0 e agora sai 2, o campo que agora grava `~`, a bateria que deixou de rodar em dobro), sem prometer o que o diff não faz — conferido lendo `git diff origin/main...HEAD --stat` contra a entrada; a linha da 1.26.0 que diz "`stdbuf --output L` ... ainda escapa: issue #346" fica como histórico, e a entrada nova diz que fechou; o README só muda se algum trecho dele descreve comportamento alterado (o executor procura `stdbuf`, `body-file`, `transcrito` e as duas baterias removidas do bloco e decide pelo que achar).
