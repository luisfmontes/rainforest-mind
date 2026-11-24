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
  1. vem logo depois de `<` (ou `0<`), separado ou colado (`sh < t.cjs`, `sh <t.cjs`), e o comando dono do `<` é executor (`EXECUTAM_ARQUIVO`) sem argumento posicional antes do `<` (só flags);
  2. é argumento de `cat` e o mesmo trecho segue, por `|`, para um executor sem argumento posicional (`cat t.cjs | sh`, `cat t.sh | bash -s`).
  - **Porquê:** shell e interpretadores leem script do stdin quando não recebem arquivo de script; `sh < arquivo` é a forma medida, e `cat arquivo | sh` é a mesma execução por outro caminho. Com argumento posicional (`python script.py < dados.txt`), o stdin é dado do script, e o heredoc continua dado.
  - **Modelo de ameaça:** fica fora o arquivo lido por variável (`sh < "$f"`) e por substituição (`sh <(cat t.cjs)`): o nome não aparece literal. *(suposição: `<(...)` é raro em comando de agente.)*

- **D3 — O nome do alvo segue cópia e renomeação (#722, forma 4).** Antes de procurar executores, o conjunto de alvos cresce pelos comandos depois do heredoc: `cp`, `mv`, `ln`, `install` com um alvo entre os argumentos de origem acrescentam o nome-base do destino (último argumento que não é flag); `cat <alvo> > <novo>` e `cat <alvo> >> <novo>` acrescentam `<novo>`. Repete até não crescer (cadeia `cp a b; mv b c; bash c`), com teto de 10 voltas.
  - **Porquê:** o que importa é se o CONTEÚDO gravado chega a um executor, não o nome.
  - **Modelo de ameaça:** fica fora a cópia por ferramenta que o gate não lê como cópia (`rsync`, `dd`, `tee`, `node -e 'fs.copyFileSync(...)'`) e destino em diretório (`cp t.cjs d/` com `bash d/t.cjs` funciona porque o nome-base é o mesmo; `cp t.cjs d/` com outro nome não existe).

- **D4 — `alvoDoRedirecionamentoEhExecutadoDepois` passa a ser `executoresDoAlvo(...).length > 0`.** As duas funções repetem a mesma varredura; com D2 e D3 só na segunda, elas divergiriam e o corpo podia ser mascarado como dado (primeira diz "não executado") mesmo com executor achado pela segunda.
  - **Porquê:** uma régua só para "o arquivo deste heredoc é executado adiante".

- **D5 — O corpo de script não-shell também mostra `git` em lista de strings (#722, forma 1).** Em `mascaraSoGit`, além do trecho `git ...` corrido, uma sequência de literais de string que começa pelo literal `'git'`/`"git"`/`` `git` `` e segue por literais separados por vírgula, colchete ou espaço fica visível com aspas, vírgulas e colchetes trocados por espaço (comprimento preservado): `spawnSync('git',['add','-A'])` vira `` git    add   -A `` para a análise de shell. Vale para JavaScript (`spawn`, `spawnSync`, `execFile`, `execFileSync`) e Python (`subprocess.run(["git","add","-A"])`).
  - **Porquê:** é a forma idiomática de chamar processo sem shell nas duas linguagens; a busca por texto da D6 de `gates-sem-ruido` não a via.
  - **Modelo de ameaça:** fica fora o comando montado por concatenação ou variável (`['git', op, '-A']`), já fora pela D6 de `gates-sem-ruido`.

- **D6 — Versão 2.17.3 (PATCH).** Consertos de cobertura de gate existente, sem contrato novo.

- **D7 — Operador colado ao nome se separa antes da busca (forma 5).** Os tokens do trecho depois do heredoc passam por uma separação que parte cada token em `|`, `;`, `&`, `(`, `)`, `{`, `}`, `<` e `>` colados (`t.sh;` vira `t.sh` + `;`, `t.cjs|sh` vira `t.cjs` + `|` + `sh`, `<t.cjs` vira `<` + `t.cjs`). D2 e D3 usam a mesma lista.
  - **Porquê:** o nome do arquivo e o operador colado são duas coisas para o bash; para a busca do alvo eram uma só.
  - **Modelo de ameaça:** separar também parte texto entre aspas que contém esses caracteres (`"a;b"`); o efeito é só achar executor a mais, o lado de barrar.

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
