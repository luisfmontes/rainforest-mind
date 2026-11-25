# Rodada 17: heredoc com continuação de linha e staging por script não-shell

## Objetivo

Fechar cinco formas de esconder staging em massa dos gates, todas medidas em 2026-11-24 na base `3b1ecacf` contra `hooks/gate-staging-total.cjs` num repositório de `git init` (o gate sai cedo em worktree linkado). Cada uma sai exit 0 e o bash executa `git add -A`:

1. **#724** — `cat <<'A' \` + quebra + `> /dev/null; git add -A` + corpo + `A`. A continuação junta as duas linhas físicas numa lógica, e o corpo começa depois dela. `mascararCorposDeHeredoc` (`hooks/lib/heredoc.cjs`) começa a máscara na primeira quebra física e apaga a linha do `git add -A`.
2. **#722, spawn em array** — corpo `require('child_process').spawnSync('git',['add','-A'])` gravado em `t.cjs` e rodado por `node`. A máscara de script não-shell (`mascaraSoGit`) só guarda texto `git ...` corrido; com o comando em lista de strings sobra só `git`.
3. **#722, `sh < arquivo`** — o arquivo gravado é executado por shell via redirecionamento de entrada. `executoresDoAlvo` só conta o alvo como argumento de executor ou `./alvo`.
4. **#722, cópia** — `cp t.cjs x.sh && bash x.sh` e `cat t.cjs > x.sh && bash x.sh`: o arquivo executado tem outro nome.
5. **Operador colado ao nome (achado da sonda)** — `bash t.sh; true` sai 0: `tokensComAspas` devolve `t.sh;` como um token, e o nome não casa com o alvo `t.sh`. É o mesmo defeito que fazia `node t.cjs; sh < t.cjs` passar na primeira sonda.

Controles na mesma sonda: `cat <<'A' > /dev/null; git add -A` numa linha só e `bash t.sh` com o mesmo corpo saem 2; `node t.cjs` com corpo sem `git`, `cat > nota.md <<'EOF'`, `python script.py < dados.txt`, `cp nota.md copia.md` e `spawnSync('git',['status'])` saem 0.

Pedido do Luís em 2026-11-24 (rodada própria para #722 e #724, recomendada aceita). Modo autônomo: as decisões são a recomendada; as marcadas *(suposição)* ele revisa no PR.

## Decisões fechadas

- **D1 — A máscara do corpo começa depois da linha LÓGICA do heredoc (#724).** Nos dois ramos de `mascararCorposDeHeredoc` (corpo de dado e corpo de script não-shell), o início passa de `fora.indexOf("\n", i) + 1` para `fimDaLinhaLogica(fora, i) + 1`, a mesma função que `corpoDeHeredoc`, `linhaDoHeredocTemInterpretador` e os leitores de alvo já usam.
  - **Porquê:** a máscara e o leitor do corpo precisam concordar sobre onde o corpo começa; hoje discordam exatamente na continuação.
  - **Modelo de ameaça:** protege contra comando escondido na continuação da linha que abre o heredoc, em todo gate que chama a máscara (`gate-staging-total`, `gate-mensagem-commit`, `gate-worktree`, `gate-publicacao-destino`). Fica fora: continuação ANTES do `<<` (`cat \` + quebra + `<<'A'`), em que a linha lógica começa numa linha física anterior; `corpoDeHeredoc` já trata o corpo a partir do `<<`, e a máscara não apaga nada antes dele.

- **D2 — Executor por redirecionamento de entrada e por pipe de `cat` (#722, forma 3).** Em `executoresDoAlvo`, o alvo conta como executado também quando:
  1. vem logo depois de `<` (ou `0<`), separado ou colado (`sh < t.cjs`, `sh <t.cjs`, `< t.cjs sh`), e o comando do trecho é executor (`EXECUTAM_ARQUIVO`) sem argumento posicional (só flags e redirecionamentos);
  2. é argumento ou stdin de `cat` e o mesmo trecho segue, por `|`, para um executor que lê o stdin (`cat t.cjs | sh`, `cat < t.cjs | sh`, `cat t.sh | bash -s`).
  - **Executor que lê o stdin mesmo com posicional (emenda da revisão de segurança automática, 2026-11-24):** shell com `-s` (`sh -s arg < t.cjs`: `arg` é argumento do script), `-` como arquivo (`node - arg`) e `/dev/stdin` como primeiro posicional (`bash /dev/stdin < t.sh`). O `-s` só vale para shell: em `python -s` é outra flag.
  - **Porquê:** shell e interpretadores leem script do stdin quando não recebem arquivo de script; `sh < arquivo` é a forma medida, e `cat arquivo | sh` é a mesma execução por outro caminho. Com argumento posicional (`python script.py < dados.txt`), o stdin é dado do script, e o heredoc continua dado.
  - **Redirecionamento não é argumento (emenda de 2026-11-24, executar):** em todo o reconhecimento de executor, `2>&1`, `>&2`, `<&0` e `&>arq` contam como redirecionamento, e o alvo de `>`, `>>`, `<`, `2>` não conta como argumento. Na base, `bash 2>/dev/null t.sh` e `bash 2>&1 t.sh` saíam 0: o token anterior ao alvo era `/dev/null` ou `1`.
  - **Revisão 1 (2026-11-24):** flag com valor não é posicional (`bash -o pipefail < t.sh`, `bash -O extglob t.sh`, `python -W ignore t.py`, `node -r x`); o arquivo lido por qualquer comando (argumento ou stdin: `head -n 5 t.sh`, `sed ... t.sh`, `cat < t.sh`) que segue por pipe até um executor que lê o stdin conta, atravessando `|`, `|&`, `( )` e `{ }` (`cat t.sh | head | bash`, `cat t.sh | { sh; }`); e `-` só é o script quando vem antes de qualquer posicional (`node - arg` executa; `python3 tool.py -` lê dado). `deno run` e `bun run` pulam o subcomando.
  - **Modelo de ameaça:** fica fora o arquivo lido por variável (`sh < "$f"`) e por substituição (`sh <(cat t.cjs)`): o nome não aparece literal. *(suposição: `<(...)` é raro em comando de agente.)*

- **D3 — O nome do alvo segue cópia e renomeação (#722, forma 4).** Antes de procurar executores, o conjunto de alvos cresce pelos comandos depois do heredoc: `cp`, `mv`, `ln`, `install` com um alvo entre os argumentos de origem acrescentam o nome-base do destino (último argumento que não é flag); `cat <alvo> > <novo>`, `cat <alvo> >> <novo>` e `cat < <alvo> > <novo>` (revisão 1) acrescentam `<novo>`. Repete até não crescer (cadeia `cp a b; mv b c; bash c`), com teto de 10 voltas.
  - **Porquê:** o que importa é se o CONTEÚDO gravado chega a um executor, não o nome.
  - **Modelo de ameaça:** fica fora a cópia por ferramenta que o gate não lê como cópia (`rsync`, `dd`, `tee`, `node -e 'fs.copyFileSync(...)'`) e destino em diretório (`cp t.cjs d/` com `bash d/t.cjs` funciona porque o nome-base é o mesmo; `cp t.cjs d/` com outro nome não existe).

- **D4 — `alvoDoRedirecionamentoEhExecutadoDepois` passa a ser `executoresDoAlvo(...).length > 0`.** As duas funções repetem a mesma varredura; com D2 e D3 só na segunda, elas divergiriam e o corpo podia ser mascarado como dado (primeira diz "não executado") mesmo com executor achado pela segunda.
  - **Porquê:** uma régua só para "o arquivo deste heredoc é executado adiante".

- **D5 — O corpo de script não-shell também mostra `git` em lista de strings (#722, forma 1).** Em `mascaraSoGit`, além do trecho `git ...` corrido, uma sequência de literais de string que começa pelo literal `'git'`/`"git"`/`` `git` `` e segue por literais separados por vírgula, colchete ou espaço fica visível com aspas, vírgulas e colchetes trocados por espaço (comprimento preservado). O literal inicial aceita caminho e `.exe` (`'/usr/bin/git'`, `'git.exe'`), e entre os literais vale também chave, parêntese, comentário de bloco e chave de objeto (`{args: [...]}` do `Deno.Command`) (revisão 1); só o miolo dos literais fica visível. A sequência pode atravessar quebras de linha (`spawnSync('git', [` + quebra + `'add', '-A'])`, a forma que um formatador produz): dentro dela a quebra vira espaço, para a análise ler um comando só. Exemplo: `spawnSync('git',['add','-A'])` vira `` git    add   -A `` para a análise de shell. Vale para JavaScript (`spawn`, `spawnSync`, `execFile`, `execFileSync`) e Python (`subprocess.run(["git","add","-A"])`).
  - **Porquê:** é a forma idiomática de chamar processo sem shell nas duas linguagens; a busca por texto da D6 de `gates-sem-ruido` não a via.
  - **Modelo de ameaça:** fica fora o comando montado por concatenação ou variável (`['git', op, '-A']`), já fora pela D6 de `gates-sem-ruido`.

- **D6 — Versão 2.17.3 (PATCH).** Consertos de cobertura de gate existente, sem contrato novo.

- **D7 — Operador colado ao nome se separa antes da busca (forma 5).** Os tokens do trecho depois do heredoc passam por uma separação que parte cada token em `|`, `;`, `&`, `(`, `)`, `{`, `}`, `<` e `>` colados (`t.sh;` vira `t.sh` + `;`, `t.cjs|sh` vira `t.cjs` + `|` + `sh`, `<t.cjs` vira `<` + `t.cjs`). O dígito de descritor só se separa no começo do token (`2>log` vira `2>` + `log`; `t2>log` vira `t2` + `>` + `log`, como no bash). A quebra de linha entre dois tokens vira separador de comando. D2 e D3 usam a mesma lista.
  - **Porquê:** o nome do arquivo e o operador colado são duas coisas para o bash; para a busca do alvo eram uma só.
  - **Modelo de ameaça:** separar também parte texto entre aspas que contém esses caracteres (`"a;b"`); o efeito é só achar executor a mais, o lado de barrar.

- **D8 — Executor e cópia na própria linha do heredoc (emenda de 2026-11-24, executar).** A busca de executores e de cópias (D2, D3) lê também o resto da linha lógica que abre o heredoc, depois do delimitador: `cat > t.cjs <<'EOF' && node t.cjs` e `cat > t.cjs <<'EOF' && cp t.cjs x.sh` (com `bash x.sh` depois) saíam 0 na base, porque a busca só lia o texto depois do fechamento. `bash` na mesma linha já barrava por `linhaDoHeredocTemInterpretador`.
  - **Porquê:** o `&&` roda depois do `cat` terminar de ler o corpo, então `node t.cjs` executa o arquivo já gravado.
  - **Modelo de ameaça:** a mesma de D2 e D3.

- **D9 — Execução por caminho e por texto de `-c`/`eval` (revisão 1).** O arquivo conta como executado quando é o COMANDO do trecho com caminho (`./x`, `../x`, `d/x`, `$PWD/x`, `/tmp/x`), e quando aparece no texto passado a `-c` ou a `eval` (`bash -c 'bash t.sh'`): esse texto é tokenizado como comando no lugar do token. Na base os dois saíam 0. E a linha do heredoc grava também os arquivos de `tee` (`tee t.sh <<'A' > /dev/null`) e o alvo de `>` sem espaço antes ou com `>|` (`cat>t.sh<<'A'`).
  - **Porquê:** o bash executa arquivo com barra no nome sem procurar no PATH; `-c` e `eval` rodam o texto como comando.
  - **Modelo de ameaça:** fica fora o nome sem barra na posição de comando (`t.sh` só roda se estiver no PATH).

- **D10 — Linha lógica de verdade (revisão 1, preexistente).** `fimDaLinhaLogica` varre a linha: `\\` + quebra é contrabarra escapada (a linha acaba), `#` em início de palavra abre comentário onde `\` não continua, e quebra dentro de aspas, `$'...'` ou `$(...)` não encerra a linha. A D1 depende dela, e nos três casos o corpo começava onde o bash não começa.
  - **Porquê:** as variantes da mesma classe da #724 que o revisor mediu no bash real.
  - **Modelo de ameaça:** aspa dupla com `$(...)` aninhado com aspas dentro fica aproximada; o desvio só atrasa o início do corpo (mais texto analisado).

- **D11 — `<<` que não é operador (revisão 1, preexistente).** `posicoesDeOperadorHeredoc` pula `$'...'` (onde `\'` não fecha) e `${...}`, e `#` depois de `)` também abre comentário. `echo ${x:-<<'A'}` e `(true)#<<'A'` faziam o gate mascarar como corpo o comando da linha seguinte.
  - **Modelo de ameaça:** `echo $'\' <<'A''` já não é lido como heredoc pela lib, mas o segmentador do próprio `gate-staging-total` lê `$'\'` como aspa aberta e perde a linha seguinte: defeito de outro arquivo, anterior à rodada, na Issue #736.

- **D12 — Heredoc no stdin de interpretador não-shell (revisão 1, preexistente).** `node - <<'A'` e `python - <<'A'` executam o corpo. No `gate-staging-total` (`scriptNaoShell`), esse corpo deixa de ser dado e passa pela máscara de script não-shell (só `git ...` visível), como o arquivo gravado e rodado por `node`. Os outros três gates seguem tratando-o como dado, como antes.
  - **Porquê:** o design `2026-11-17-gates-sem-ruido` registrou a forma como achado da #722, e esta rodada fecha a #722.
  - **Modelo de ameaça:** `python script.py <<'A'` continua dado (o stdin é do script).

## Avaliado e descartado

- **Ler o corpo de script não-shell como shell de novo:** desfaz a D6 de `gates-sem-ruido` (regex de JavaScript lido como "comando dinâmico"), e a análise de shell também não vê a forma em array.
- **Barrar todo heredoc citado cujo arquivo é copiado:** falso positivo em fluxo comum (gravar e copiar um arquivo de dado).

## Fora de escopo

- Continuação antes do `<<` (D1), leitura por variável e por `<(...)` (D2), cópia por ferramenta fora da lista (D3), lista montada por variável (D5).

## Varredura

docs/rainforest/varredura/2026-11-24-zerar-issues-17.txt. Só #722 e #724 abertas no tema. Seguem valendo a D6 de `2026-11-17-gates-sem-ruido` (corpo de interpretador não-shell lido como texto), a D5 de `2026-09-30-semear-travas`, a D26 de `2026-10-06-zerar-issues-16` e a D3 de `zerar-issues-5` (âncoras intactas em `hooks/gate-staging-total.cjs`). Nenhuma âncora em `hooks/lib/heredoc.cjs`.

## Em aberto

(nada)

## Pronto quando

- A sonda desta rodada (os cinco buracos e os controles), transcrita como seção nova de `bash hooks/testa-gate-staging-total.sh`, sai com os buracos em exit 2 e os controles como estão.
- Um caso de continuação de linha (#724) em cada bateria de gate que usa a máscara: `hooks/testa-gate-mensagem-commit.sh`, `hooks/testa-gate-worktree.sh` e `hooks/testa-gate-publicacao-destino.sh`, cada um com o comando que o gate barra escondido na linha de continuação → exit 2.
- As baterias inteiras desses quatro gates com 0 falhas.
