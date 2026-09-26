# Notas de atualização

O que mudou em cada versão publicada, do ponto de vista de quem **usa** o plugin —
não o log de commits. A versão instalada aparece em `/plugin` → Installed Plugins,
e atualizar é `/plugin` → Browse Plugins → Update Marketplace, depois Update no
`rainforest-mind`.

Este arquivo começa na **1.19.0**. As versões anteriores não têm notas escritas: o
que existe delas é o commit de release (`git log --grep="^Versao "`), e reescrever
29 releases de memória produziria nota bonita e errada. Versão nova daqui em diante
entra aqui no mesmo commit que sobe o `version` do `plugin.json`.

## 1.24.0 — 2026-09-26

**Os gates pararam de barrar o que já era legível, e fecharam dois buracos.**

- **`bash $t` sem aspas passa quando o valor está escrito no próprio comando** (#337):
  `for t in a b; do bash $t; done`, `for t in scripts/testa-*.sh; do bash $t; done` e
  `f=x.sh; bash $f` deixam de ser "comando encapsulado". Continuam barrados `bash $CMD`
  sem atribuição visível, valor que começa com `-` ou tem espaço (`f=-c; bash $f "gh ..."`),
  lista com `$(...)` e qualquer comando que mexa em `IFS`.
- **Contrabarra dupla dentro das aspas duplas de um wrapper** deixou de esconder o comando
  (#313): `bash -c "gh issue \\<quebra>close 12"` passava; agora o gate faz a mesma
  redução de escape que o bash faz antes de juntar a linha.
- **O gate de publicação mede o que a edição introduz** (#322): um `Edit` que preserva um
  dado sensível já presente no `old_string` (a linha do trailer `Co-Authored-By`, por
  exemplo) não é mais barrado. A comparação é pelo valor, não pelo trecho redigido: trocar
  um e-mail por outro, ou acrescentar um segundo na mesma linha, continua barrado. A isenção
  do `noreply@` no conferidor já existia e não mudou.

**O fluxo passou a achar o próprio estado onde ele mora.**

- **O veredito do revisor é gravado no worktree** quando o estado do fluxo só existe lá
  (#329). Se o estado estiver em mais de um worktree, ou em nenhum, o hook avisa em stderr
  e não grava — antes saía em silêncio.
- **Tarefa acrescentada por emenda ao plano recebe carimbo** (#312): o teto do carimbo lê
  o arquivo do plano, como a validação de `mutacao` já fazia; o número gravado no
  `plano ok` fica de reserva quando o arquivo não existe.

**Medição.**

- **As baterias em Node entram no CI** (#335): o varredor descobre `testa-*.cjs` em
  `scripts/` e `hooks/` e as roda com `node`. As cascas `.sh` que só chamavam uma
  `.cjs` saíram. Antes, 13 baterias nunca rodavam no CI.
- **A checagem de duplicata do `/saude` mede só o plugin versionável** (#323): arquivo
  gitignorado (as cópias em `.claude/marketplaces/`, por exemplo) não conta mais. No
  checkout principal, o aviso caía de 811 grupos para 0.

## 1.23.0 — 2026-09-22

**Os gates de texto pararam de deixar passar `bash -c` escondido atrás de palavra
reservada, e pararam de barrar `bash "$t"`.** Antes, `for t in x; do bash -c "gh
issue close 12"; done` passava pelo gate de fechar issue, enquanto o mesmo `bash -c`
sem o laço era barrado: `do`, `then`, `else`, `elif`, `if`, `while`, `until`, `!` e
`coproc` tiravam o `bash` da posição de comando. E o inverso: rodar uma lista de baterias com
`for t in ...; do bash "$t"; done` era recusado como "comando encapsulado".

- **Palavra reservada é pulada** na posição de comando, nos três gates de texto e no
  gate de worktree.
- **Variável entre aspas duplas como último argumento é caminho de script**:
  `bash "$t"`, `bash "${t}"` e `bash "$t" 2>&1` passam. Sem aspas (`bash $t`) ou com
  argumento depois (`bash "$f" "gh ..."`, que com `f=-c` vira `bash -c`) continuam
  barrados.
- **Parâmetro especial é ilegível**: `set -- -c "<cmd>"; bash "$@"`, `bash "$*"` e
  `eval "$@"` passavam como se fossem caminho de script, e agora são barrados.
- **Pipe com stderr (`|&`) e continuação de linha** deixaram de esconder comando: `echo
  hi |& bash -c "<cmd>"`, `bash -c "gh issue \<quebra>close 12"` e a mesma quebra sem
  wrapper nenhum passavam, e passavam também na 1.22.0 — são buracos antigos, achados
  pela revisão desta rodada.
- **E-mail em TLD reservado** (`.invalid`, `.example`, `.test`, `.localhost`, RFC 2606)
  deixa de ser achado do gate de publicação, desde que seja o último rótulo
  (`x@foo.test.com` continua pego).

**O `conferir-entrega` em Python voltou a valer o mesmo que o de Node.** Ele tinha
parado em agosto: faltavam `--escopo`, o exit 69 de "não deu para verificar",
a reprovação de commit vazio e o BOM no `git status`. As quatro foram portadas, e o
CI passou a rodar a bateria contra o gêmeo em passo próprio, para ele não congelar
de novo em silêncio.

## 1.22.0 — 2026-09-22

**A régua do `/regua` não pode mais ser mexida depois que o loop começa.** Antes,
"a régua é imutável" era uma frase na skill: nada impedia o builder (ou uma edição
distraída) de afrouxar um mecanismo no meio das rodadas, e o crítico julgaria
contra a régua nova sem ninguém perceber.

- **Selada pelo commit.** O manifesto em `docs/rainforest/reguas/<slug>.md` vale
  como foi commitado pela primeira vez. `node scripts/conferir-regua.cjs validar
  --slug <slug>` confere o formato antes de selar; `conferir` recusa (exit 1)
  régua alterada, apagada ou adicionada mais de uma vez no histórico; `mostrar` é
  o único caminho que a imprime, e só imprime depois de conferir. Clone raso sai
  2 — no CI, use `fetch-depth: 0`.
- **Keep/discard automático.** A partir da 2ª rodada, um segundo crítico cego
  compara o novo com o melhor guardado. Perdeu, o commit fica e o ponteiro não
  anda; a próxima rodada parte do melhor. Estagnação em 3 rodadas vira a quarta
  condição de parada.
- **Log de rodadas versionado**, um TSV com SHA, veredito, status e lacuna de
  cada rodada.

O que o selo **não** cobre está escrito: manipulação deliberada de histórico por
quem tem escrita no repositório (rebase, squash, branch órfã). Ele vigia o
builder e os fluxos normais de git, não quem reescreve o histórico de propósito.

## 1.21.1 — 2026-09-21

**A limpeza de branches para de mandar procurar no GitHub o que só existe no
disco.** A listagem do `limpar` rotulava toda branch fora da `main` como "o remoto
está de pé", inclusive as que nunca tiveram remoto. Agora elas saem num grupo
próprio, `viva-so-local`: os commits só existem na sua máquina, o script não sabe
dizer se é trabalho em andamento ou tentativa descartada, e quem decide é você,
olhando e apagando à mão. Nada que antes era protegido passou a ser removido.

## 1.21.0 — 2026-09-21

**A instrução de comportamento de uma skill passa a ter trava.** Até agora, uma
frase que manda o agente fazer (ou não fazer) alguma coisa podia sumir de um
`SKILL.md` numa reescrita e nada ficava vermelho — o CI conferia sintaxe, links e
tamanho de injeção, nunca conteúdo de instrução.

- **Quinze invariantes em sete skills.** Cada skill protegida declara, num
  `invariantes.json` ao lado do `SKILL.md`, as frases que não podem sumir do corpo
  dela. Apagar uma deixa o CI vermelho nomeando a skill e a frase.
- **Assertiva negativa.** Uma entrada `tipo: "nao_deve"` trava a **ausência** de uma
  formulação já rejeitada — é guarda prospectiva contra reintroduzir um vocabulário
  que o usuário mandou sumir.
- **Degraus.** Uma frase pode ser exigida no corpo inteiro, só no bloco de regras,
  na referência da regra, ou no núcleo que a abertura de sessão injeta — este último
  pega a frase que continua no arquivo mas parou de chegar na sessão.

Enxertado do `openai/openai-developers-for-claude`, que afirma frase de
comportamento no corpo de cada skill dele. O que não veio de lá é a segunda fonte:
aqui a bateria declara as quinze frases por escrito e compara com o que lê de
produção, para que encurtar a frase declarada até ela casar com um `SKILL.md`
reescrito não seja o conserto barato.

## 1.20.0 — 2026-09-19

**A memória deixa de só acumular.** Duas coisas que não existiam passam a existir,
e as duas rodam sozinhas numa passada de manutenção que abre junto com a sessão:

- **Reconciliação.** Observação que corrige, repete ou complementa uma antiga agora
  atualiza ou funde-se a ela, em vez de virar mais uma linha ao lado. **Nada é
  apagado**: a substituída ganha um ponteiro, sai da injeção e da busca, e continua
  na tabela — fusão ruim se desfaz.
- **Consolidação automática em resumos.** Era manual e nunca tinha rodado uma vez.
  Passa a agrupar por origem a partir de 30 dias — pela sessão quando ela existe, e
  por `(projeto, dia)` para as 10.092 observações importadas do claude-mem, que não
  têm sessão nenhuma e são 88% do acervo.

**Aviso na abertura quando o pipeline para.** Captura ou manutenção paradas há mais
de 48 h viram uma linha na abertura da sessão, com há quantas horas e o comando que
religa. O silêncio de 13 dias que ninguém viu (#282) é o que ela existe para matar —
aviso que só aparece quando alguém pergunta não é aviso.

A busca de parecidas continua no FTS5, sem índice vetorial: medido em 200 sondagens
com o CLI real, o recall ficou em 82,0% global (74,6% em português, 89,2% em inglês).
O relatório está em `relatorios/2026-09-18-recall-fts5-reconciliacao.md`.

Nada disso mexe no `observar.cjs`: a captura não ganhou chamada de LLM nenhuma no
caminho da escrita, que é onde ela já tinha parado calada uma vez.

## 1.19.2 — 2026-09-19

**Este arquivo.** O plugin passa a trazer notas de atualização, e o contrato de
como mantê-las: versão nova entra aqui no mesmo commit que sobe o `version` do
`plugin.json`.

Ganhou versão própria porque a catraca `conferir-versao.cjs` exige número maior
em toda PR que não seja só estado de fluxo — e ela está certa: sem bump não há
versão nova para o `claude plugin update` buscar, e notas que ninguém baixa não
resolvem o problema que elas existem para resolver.

Junto, um adendo ao design do contrato de território (`docs/rainforest/design/`),
que não muda comportamento nenhum.

## 1.19.1 — 2026-09-17

**Rota com emoji de status por etapa** (Issue #299).

A regra 4 já mandava fechar cada etapa com "Fechamos [n]/[total]", mas não dizia em
que **formato** acompanhar o todo. Em tarefa longa o checkpoint contava o avanço e
não mostrava o mapa, e a pessoa perdia de vista quantas etapas faltavam e onde
estava. Agora a elaboração da regra 4 traz a rota — uma linha por etapa com marcador
de status — e a `modo-dev` aponta para ela.

Muda o que você vê na resposta; não muda comando, gate nem dado.

## 1.19.0 — 2026-09-17

Cinco issues fechadas, todas de trava que prometia mais do que cumpria.

- **Regra 6 agora diz em que repo "conserta na hora" vale** (#291). A regra mandava
  consertar defeito na hora e não dizia **onde**: o conserto saía no repositório do
  vizinho. Passou a ser explícita — defeito que atrapalha no repo **da sessão**
  conserta na hora; repo alheio é Issue + `Q`, nunca commit.
- **`gate-agente-em-voo` para de repetir o aviso a cada turno** (#298). O gate
  prometia avisar **uma** vez e, em sessão interativa, repetia no turno seguinte.
  A memória era de slot único e duas sessões alternando se sobrescreviam; virou mapa
  por sessão, com assinatura dos agentes em voo.
- **`gate-verificador-staged` volta a respeitar o marcador `dados-de-exemplo`** (#293).
  O marcador era ignorado e o toggle anunciado no cabeçalho do arquivo não existia —
  duas promessas sem implementação.
- **Mutantes de `testa-foco.sh` passam a morrer pelo comportamento certo** (#292).
  Os mutantes dos itens 9 e 13 morriam por `MODULE_NOT_FOUND`, não pela mutação:
  a bateria parecia provar e não provava nada.
- **Achados da revisão do ciclo anterior** (#294): catraca que rodava em cópia, `.pyc`
  no caminho de teste e conversão de caminho do MSYS.

## Antes da 1.19.0

Sem notas escritas. Para ver o que cada release carregou:

```
git log --grep="^Versao " --format="%ad %s" --date=short
```
