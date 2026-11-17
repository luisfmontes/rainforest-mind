# Gates sem ruído: menos bloqueio falso que aparece como "hook error"

## Objetivo

Cortar os bloqueios de gate que não protegem nada — trava em sessão onde o risco não existe,
e forma de shell que o gate não lê e por isso recusa — sem abrir nenhum vetor que o modelo de
ameaça de cada gate hoje fecha. Medido antes: 7 dias de transcripts das duas contas (~2.300
turnos, ~29 mil chamadas de ferramenta) deram ~120 bloqueios do `gate-agente-em-voo`, ~100 do
`gate-fechar-issue`, ~63 do `gate-mensagem-commit` e ~13 do `gate-staging-total`, todos exibidos
ao Luís como "hook error".

Pedido do Luís em 2026-11-17 ("cara esta dando mt erro de hooks... talvez mudar pra mods?"),
com a recomendada aceita ("1 recomendado / 2 tudo me incomoda, faz o recomendado / abre o fluxo
no modo automatico"). Rodada sob `executar-autonomo`: decisões abaixo marcadas
"decidido pela sessão" quando a delegação as cobriu.

## Decisões fechadas

- **D1 — Alvo e convivência: serve ao Luís e a quem usa o plugin, em toda sessão interativa; cada conserto substitui o comportamento atual dos quatro gates, sem chave para o antigo, e nenhum gate é desligado** — porquê: os comportamentos cortados só produzem bloqueio que o modelo contorna reescrevendo o comando; não há o que preservar. Decidido pela sessão (delegação "faz o recomendado").

- **D2 — Não migrar gates para mod nesta rodada** — porquê: medido na referência de mods do build 2.1.326 (`plugin-authoring/types/claude-code.d.ts`): um `deny` em `on('tool.call')` recebe a mesma string de comando, então o parser que recusa `;`/`|`/heredoc recusaria igual; `turn.complete` só devolve texto e não bloqueia (fim de turno bloqueante só existe embrulhando o hook clássico, `classic.Stop`); e a ponte Codex não roda mods. O ganho real do mod (sem um `node` por hook por chamada) é desempenho, não ruído — fica plantado como ideia.

- **D3 — `gate-agente-em-voo` só barra em sessão não interativa; em sessão interativa sai com exit 0 em silêncio** — porquê: a razão do gate (Issue #180, design lote-4 D16) é que "agente em background morre com o turno — em sessão não interativa, sempre". Em sessão interativa a notificação do agente abre turno novo, e terminar o turno para esperá-la é o padrão do harness. Medido em 2026-11-17: os 121 bloqueios dos últimos 7 dias vieram de 6 sessões, todas com `entrypoint: "cli"` no transcript (até 36 numa sessão só); sessões `sdk-cli` tiveram zero. Detecção: interativa = `CLAUDE_CODE_ENTRYPOINT` igual a `cli`, ou, sem a variável, o primeiro `"entrypoint"` do `transcript_path` do payload igual a `cli`. Qualquer outro valor, ausência dos dois ou falha de leitura = não interativa = barra como hoje (falha fechada). Herda intactos D16 (lote-4) e D13 (zerar-issues-6) para o caso não interativo.
  **Modelo de ameaça:** protege contra turno de sessão `claude -p`/SDK acabando com agente registrado em `em_voo` (o agente morre e a entrega some). Fica fora: sessão interativa em que o usuário fecha a janela com agente rodando (o harness avisa, e isso não é turno acabando) e o rastro `em_voo` velho em sessão interativa (o `/saude` e o `estado.cjs` seguem mostrando).

- **D4 — `gate-mensagem-commit` lê a mensagem de `git commit -F -` quando o stdin é um heredoc com delimitador CITADO ligado ao próprio `git commit`** — porquê: 38 dos ~74 bloqueios da semana foram "mensagem via `-F -` ou heredoc não é resolvível", e o heredoc citado é literal (sem expansão de `$`, crase ou `$(...)`), logo o texto do comando é a mensagem que o git recebe. Lê com `corpoDeHeredoc` de `hooks/lib/heredoc.cjs` e aplica as mesmas checagens de assunto e corpo que `-F <arquivo>` aplica. Heredoc **não** citado, here-string (`<<<`), pipe (`printf ... | git commit -F -`) e heredoc ligado a outro comando da linha continuam barrando como hoje.
  **Modelo de ameaça:** o gate protege a forma da mensagem (assunto ≤ 72, sem ponto final, corpo em diff grande), não segurança; o risco de ler errado é aprovar mensagem fora do formato. Fica fora: corpo não citado com expansão (o texto do comando não é o que o git recebe).

- **D5 — `gate-fechar-issue` julga o segmento do `gh pr merge` em vez do comando inteiro quando a linha é uma sequência simples e o que vem ANTES do merge é inerte** — porquê: 31 bloqueios da semana foram "'gh pr merge' não está sozinho no comando", nas formas `cd <caminho> && gh pr merge N ...`, `gh pr merge N --squash 2>&1 | tail -2; <outro comando>` e `gh pr view N ...; gh pr merge N ...`. Regra: a linha se divide por `;`, `&&`, `||`, `|` e quebra de linha em segmentos (o `segmentosParaGate` que o gate já usa); o segmento do merge, sem um `2>&1` final e sem o pipe para `tail -N`/`head -N` que o segue, tem que passar no `comandoUnicoSemShell` atual e na lista de formas permitidas (#496); cada segmento ANTES do merge tem que ser `cd <caminho literal>` ou leitura de `gh pr view|checks|status` sem `$`, crase, redirecionamento ou atribuição; segmentos DEPOIS do merge seguem sendo analisados por conta própria pelo laço do `main`, como hoje. Qualquer outra coisa — subshell, `$(...)`, crase, atribuição de variável ou `export` em qualquer segmento, heredoc, wrapper (`bash -c`, `eval`, `pwsh -Command`), PowerShell com aspas — cai na recusa atual. O `cwd` do merge é o de `cwdPorSegmento`, como já é para `--body-file`.
  **Modelo de ameaça:** protege contra o merge de PR que fecha Issue sem comentário de evidência, inclusive quando algo na linha muda o repo, o PR ou o ambiente que o `gh` usa (`GH_REPO`, `cd` para outro repo sem `--repo`, alias, função). Fica fora: o que já estava fora (GH_REPO exportado em linha anterior ou no ambiente, lote-b D4). Os outros bloqueios do gate ("comando encapsulado com variável", corpo de PR ilegível) ficam como estão — três revisões de segurança seguidas fecharam esses caminhos, e afrouxá-los é outra rodada.

- **D6 — `gate-staging-total` lê como texto, não como shell, o corpo de heredoc citado que vira arquivo executado por interpretador que não é shell** — porquê: reproduzido em 2026-11-17 com o comando exato que ele barrou nesta sessão (`cd <dir> && cat > tally.cjs <<'EOF' ...js... EOF` + `timeout 115 node tally.cjs 7`): exit 2, "comando dinâmico ... Segmento: `[a-z0-9-]+\.`" — o gate tokenizou JavaScript como shell e achou um "wrapper" num regex. Trocando o `node tally.cjs` por `echo ok`, exit 0. A D11 de zerar-issues-4 (corpo que alimenta arquivo executado adiante não se mascara) segue valendo para `bash`/`sh`/`zsh`/`ksh`/`dash`/`pwsh`/`powershell`/`cmd`/`eval`/`source`/`.`; para `node`, `python`/`python3`/`py`, `perl`, `ruby`, `deno` e `bun`, o corpo é procurado por texto (`git` seguido, na mesma linha, de `add` com `-A`/`--all`/`.`/`-u`, ou de `commit` com `-a`/`--all`/`-am`) e só barra se achar — nunca por "conteúdo não resolvível".
  **Modelo de ameaça:** protege contra staging em massa escondido num script escrito e executado na mesma linha. Fica fora: script que monta o comando git por concatenação de strings (`'git '+'add -A'`) — o gate não executa código, e a busca por texto é o que era alcançável com garantia.

## Avaliado e descartado

- **Migrar os gates para mod** (pedido original): ver D2 — a medição na referência de mods mostrou que os bloqueios seriam os mesmos.
- **Afrouxar "comando encapsulado com variável" do `gate-fechar-issue`** (~30 na semana): três revisões de segurança seguidas acharam jeitos de esconder o `gh` dentro de wrapper (design gate-crase, rodadas 13–14). A recusa é o modelo de ameaça funcionando.
- **Bloquear por recusa estruturada em JSON (`permissionDecision: "deny"`, exit 0) para tirar o rótulo "hook error"**: medido em 2026-11-17 numa sessão `claude -p --model haiku` com hook de sonda passado por `--settings` (scratchpad, sem tocar config): o `tool_result` do deny JSON chegou como `PreToolUse:Bash hook error: MOTIVO-JSON: recusado pela sonda` (`is_error: true`) e o do exit 2 como `PreToolUse:Bash hook error: [node .../hook.cjs]: MOTIVO-EXIT2: ...`. O rótulo é o mesmo; só some o caminho do script. A doc oficial (code.claude.com/docs/en/hooks) não descreve rótulo diferente para o deny. Ganho cosmético não paga a troca em ~20 gates.
- **Subir o limite de 72 colunas do assunto** (~25 na semana): é convenção do git, não falha de leitura; o bloqueio diz o número exato e a correção custa uma reescrita.

## Resíduos aceitos da revisão (2026-11-17)

- **Vários `git commit` no mesmo comando** (achado 2; rodada 5, achado 5, para o que vem depois da linha de fechamento): `mensagemDeHeredoc` e `achaGitCommit` só conferem o primeiro. A família já existia na base (`git commit -m "ok" && git commit -m "ruim."`), e o gate protege formato de mensagem, não segurança.
- **Staging por script não-shell que a busca por texto não vê** (achado 3, preexistente): `node t.cjs; bash t.cjs` com `execSync('git add -A')`, `node - <<'EOF'`/`python - <<'EOF'` e a forma em argv (`execFileSync('git', ['add','-A'])`). Passavam na base; registrados na Issue #722.
- **Só `entrypoint` `cli` conta como interativo** (achado 5): `claude-vscode` e desktop continuam barrando. É a falha fechada que a D3 escolheu; um sinal mais largo (`CLAUDE_CODE_SESSION_ATTENDED`) precisa de medição própria.
- **Formas raras que continuam barrando** (achado 7): `| tail -n 2`, merge pela ferramenta PowerShell, `git commit -F - 2>&1 <<'EOF'` e `<<\EOF`.
- **`$`, `(`, crase ou `<` entre `git commit` e o `<<` barram mesmo entre aspas** (rodada 2, achado 3): `git commit --author="Nome <email>" -F - <<'EOF'` e `git -C "$DIR" commit -F - <<'EOF'` barram. Na base todo `-F -` barrava; aceitar exigiria ler aspas no trecho, e a saída é `-F <arquivo>` ou `-m`.
- **Formas raras de `-F -` que barram por a forma canônica ser estreita** (rodada 3, achado 5): `git commit -F - 0<<'EOF'` e uma linha com `<<` aritmético (`x=$((1<<3)); git commit -F - <<'EOF'`). A saída é `-F <arquivo>`.
- **Heredoc com continuação `\` e comando na linha seguinte** (rodada 3): a máscara de `hooks/lib/heredoc.cjs` trata a linha seguinte como corpo, e nenhum gate vê o comando. Defeito da base, de lib compartilhada por vários gates; registrado na Issue #724 (abre contorno no `gate-staging-total`).
- **D4 só lê a forma direta** (rodada 4): depois de três reprovações de leituras genéricas de heredoc, o `-F -` só é lido quando a primeira linha do comando casa uma lista branca literal. Barram, como na base: commit fora da primeira linha (`cat > n.md <<'A'` antes, `git add a && \` + quebra), `git -C dir commit`, `--trailer "k: v"` ou `--author="Nome <email>"` na linha, e qualquer coisa depois do delimitador além de `&& git push`. A saída é `-F <arquivo>` ou `-m`.
- **Implementação final da D4** (rodada 5): a leitura não usa `corpoDeHeredoc` nem `posicoesDeOperadorHeredoc`, como o texto da D4 acima previa; é a lista branca `LINHA0_HEREDOC` da primeira linha, com o corpo lido linha a linha até o delimitador (`mensagemDeHeredoc(cmd)`). O modelo de ameaça da D4 não muda.
- **Achados [baixa] da rodada 5 que ficam** (já existiam na base ou falham fechados):
  - `-F` com valor que começa por `-` e não é só `-` (`-F -> /dev/null`, `-F -$X`): o arquivo não existe, e o gate sai inativo. Só `-F -<` foi fechado.
  - O stage do "corpo obrigatório" é medido no `cwd` do evento, antes dos `git add`/`cd` do próprio comando, para `-m` e `-F <arquivo>` também.
  - Flag curta agrupada (`git commit -aF - <<'EOF'`) barra; a saída é separar as flags.
  - `--cleanup=strip`/`scissors` reescrevem a mensagem depois da checagem, e `--amend`/`--no-edit` saem sem conferir, como com `-F <arquivo>`.

## Fora de escopo

- `gate-pergunta-memoria` e `aviso-fluxo`: os bloqueios deles são a regra funcionando (memória que responde a Q, edição sem fluxo); medir falso positivo exige outra amostra.
- Hooks cancelados por timeout (`conta-aviso-sessao`, `memoria-assunto-*`, PostToolUse:Bash): não separei timeout de interrupção do usuário; vira ideia com o comando de medição.
- Bloqueios de versões anteriores à 2.16.x: muitos já foram tratados nas rodadas 13–15.

## Varredura

docs/rainforest/varredura/2026-11-17-gates-sem-ruido.txt — achou o histórico do `gate-fechar-issue` (#496 lista de formas, #690 crases, #711 here-string, #718 gh escondido) e as decisões herdadas: lote-4 D16 e zerar-issues-6 D13 (agente em voo, intactas), zerar-issues-4 D11 (máscara de heredoc permissiva por exceção), lote-b D4 (GH_REPO fora do modelo). Mudou o desenho: D5 restringe o que vem antes do merge a uma lista inerte em vez de aceitar qualquer segmento, e D6 mantém a D11 inteira para interpretador de shell.

## Em aberto

(nada)
