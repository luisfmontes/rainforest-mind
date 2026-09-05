# Lote 4 — guardas que afirmam o que nao mediram

## Objetivo
Fechar as dez Issues abertas do repositorio (#170, #173, #174, #175, #176, #180,
#181, #182, #184, #185) mais um defeito medido em campo nesta sessao, todos da
mesma familia: guarda que **afirma** algo que nao mediu — falso positivo que
barra trabalho legitimo, falso negativo que libera, ou mensagem tranquilizadora
que descreve um mundo diferente do que o codigo olhou.

## Decisões fechadas

- **D1 — Issue cujo diagnostico se provou errado recebe a correcao ANTES de ser
  fechada** — porque: a #182 acusa `conferir-mutacao.cjs` de criar worktree
  temporario, e o arquivo nao cria worktree nenhum (ver D13). Fechar sem
  corrigir deixa no acervo um diagnostico errado com aparencia de resolvido, e o
  proximo que grepar por "worktree travado" vai para o arquivo errado. O lote
  tambem e um fluxo so, com uma tarefa por alvo de arquivo — os defeitos tocam
  alvos disjuntos, e e isso que permite despachar em paralelo sem dois agentes
  na mesma arvore.

- **D2 — #173 e #185 viram uma tarefa unica** — porque: as duas moram em
  `hooks/gate-publicacao-destino.cjs` + `scripts/conferir-publicacao.cjs`
  (array `PADROES`, linhas 45-159), e consertar uma sem a outra deixa o mesmo
  commit de merge barrado pelo motivo vizinho.

- **D3 — O gate de publicacao passa a julgar o que o commit INTRODUZ** — porque:
  hoje ele julga o conteudo total do indice (`git show :<arquivo>`,
  `gate-publicacao-destino.cjs:187`) e por isso barra merge de conteudo que ja
  esta publicado na `main`. Regra: achado cujo **trecho identico** ja existe no
  mesmo arquivo em algum pai do commit (`HEAD`, e `MERGE_HEAD` quando houver)
  nao barra. Conteudo novo continua barrado. Nao ha hoje nenhuma leitura de
  `MERGE_HEAD` no repo inteiro — a lacuna e real, nao hipotese.

- **D4 — Indirecao nao e credencial** — porque: `${VAR}`, `$VAR`, `%VAR%` e
  `${{ secrets.X }}` sao referencia, nao segredo: o valor nao esta no arquivo. O
  padrao `[credencial]` (`conferir-publicacao.cjs:130-152`, cujo `so_se` hoje so
  isenta "prosa curta seguida de mais palavras") ganha isencao para a forma de
  indirecao na posicao do valor. PAT literal continua barrado.

- **D5 — Sequencia dentro de hash hexadecimal nao e telefone** — porque: o
  alfabeto hex e a forma de telefone se cruzam, e **todo** arquivo de
  `docs/rainforest/estado/*.json` carrega `head`/`base` com SHA-1. O padrao
  `[telefone]` (`conferir-publicacao.cjs:72-95`) ganha isencao quando o
  casamento esta dentro de um token hexadecimal de 7 a 40 caracteres. O filtro
  `dentroDeDumpHex` ja existe ao lado e nao cobre este caso.

- **D6 — A mensagem do gate diz o que o bloqueio fez, nao so o que achou** —
  porque: hoje (`gate-publicacao-destino.cjs:119-141`) ela manda "corrija o
  conteudo e rode de novo" sem dizer que o `PreToolUse` abortou a **chamada
  inteira** — o `git add` antes do `&&` nao rodou, e o indice ficou com a versao
  velha, o que se le como "minha correcao nao funcionou". E as duas saidas
  oferecidas nao valem no mesmo comando: o hook avalia antes de o `touch` rodar,
  e o prefixo `RAINFOREST_GATE_OFF=1` entra no ambiente do comando, nao no do
  hook. A mensagem passa a dizer as duas coisas, com a forma em duas chamadas
  escrita.

- **D7 — Wrapper citado na posicao de comando conta como wrapper** — porque:
  `"env" FOO=1 git add -A` hoje deixa `posicaoDeComando`
  (`hooks/lib/tokens-comando.cjs:200`, `!toks[i].q &&
  WRAPPERS_QUE_REPASSAM.has(...)`) parada no proprio `"env"`, e os tres gates por
  texto liberam com exit 0. E o irmao do R20, que ja fez o mesmo para o nome
  citado **na** posicao de comando (`ehComando`, linhas 69-74). Contraprova
  obrigatoria: wrapper citado como **argumento** (`grep -rn "env FOO=1 git add"
  docs/`) continua liberado.

- **D8 — #174 estende o gate que ja existe, nao cria um novo** — porque: o
  `hooks/gate-fechar-issue.cjs` ja esta registrado e ja cobre `gh issue close`,
  `gh pr create`, `gh pr edit` e `gh pr merge`, com regex de nove palavras-chave
  **so em ingles** (linha 211-212) e leitura de `--body-file` ja implementada
  (linhas 279-332). Faltam duas coisas, e as duas sao extensao: (1) o verbo
  portugues antes de `#N` (`fecha|fecham|fechada|encerra|encerrada|conclui|
  corrige|resolvida`, com o `a ` opcional) vira recusa nomeada; (2) `gh issue
  create` e `gh issue comment` entram na lista de subcomandos verificados —
  hoje nao sao olhados por ramo nenhum. Referencia deliberada ("Segue #73")
  continua passando: barra-se a palavra-chave **falsa**, nunca a ausencia de
  palavra-chave.

- **D9 — `conferir-versao.cjs` mede o repositorio do cwd, nao a pasta de
  instalacao** — porque: `RAIZ = __dirname/..` (linha 40) + `git -C RAIZ` (linha
  46) faz o script medir a si mesmo, e no plugin instalado a pasta-mae nunca e
  repositorio git — o guarda escrito para o incidente de 2026-08-26 nao dispara
  para ninguem que instala. `RAIZ` passa a sair de `git rev-parse
  --show-toplevel` do cwd, com queda para `__dirname/..` so quando o cwd nao e
  repositorio. E as duas recusas se separam: "nao e repositorio git" e "este
  repositorio nao e um plugin".

- **D10 — A bateria do `conferir-versao.cjs` roda o script de FORA do clone** —
  porque: todo caso atual de `scripts/testa-conferir-versao.sh` roda com o cwd
  dentro do repositorio do plugin, que e exatamente a unica configuracao em que
  o defeito nao aparece; o caso "pasta sem git" (linhas 113-120) hoje **afirma o
  defeito** como se fosse o comportamento certo e precisa ser reescrito junto.

- **D11 — `limpar-branches --remoto` apaga toda classe com remoto vivo** —
  porque: o filtro e literalmente uma classe (`limpar-branches.cjs:530`) e a
  classe `mergeada-por-squash`, cuja definicao diz "o remoto ainda existe", fica
  de fora — e o script entao **afirma** "(nenhuma tinha remoto vivo para
  apagar)". Vira `Set` com as duas classes, no filtro e na dica (`else if`,
  linha 536); a frase do caso vazio para de afirmar mais do que se sabe. A flag
  `--remoto` hoje nao aparece em nenhum caso de `scripts/testa-limpar-branches.sh`:
  ganha o primeiro.

- **D12 — A secao 9 do `testa-triagem.sh` afirma FORMA, nao NUMERO** (P1 da
  #170) — porque: o que ela prova e que o classificador reconhece um fonte de
  dezenas de funcoes curtas como `logica`; `nfunc >= 100` prova isso e nao fica
  vermelho quando o fonte de outro dono muda (219 -> 223). P2 (congelar o fonte
  como fixture) foi descartada: copiar fonte de cliente para dentro do repo
  publico e custo de privacidade sem ganho de garantia.

- **D13 — O conserto da #182 vai para `limpar-worktrees.cjs`, nao para
  `conferir-mutacao.cjs`** — porque: a Issue atribui a `conferir-mutacao.cjs` a
  criacao de worktree temporario, e o arquivo **nao cria worktree nenhum** —
  `grep -n worktree scripts/conferir-mutacao.cjs` nao devolve linha, e a mutacao
  e feita in-place com restauracao por handler de processo (`armarRestauracao`,
  linhas 122-147). As entradas travadas em `C:/tmp/` sao do isolamento do
  **harness** (`worktree-agent-<hash>` no TMPDIR), nao nossas. O que e nosso:
  `limpar-worktrees.cjs` nao reconhece registro travado cujo diretorio sumiu —
  ganha a classe, o destravamento, a poda e o relato de falha; e a Issue recebe
  a correcao do diagnostico.

- **D14 — Agente que edita nao se retoma por `SendMessage`** (#181) — porque: na
  retomada o worktree isolado ja nao existe e o agente passa a commitar na
  branch de quem despachou, derrubando em silencio as tres garantias das regras
  11 e 12. Retomada continua valendo para agente de leitura, que nao tem
  worktree a perder.

- **D15 — A conferencia de base do briefing deixa de ser lista de hashes** —
  porque: a lista envelhece a cada merge do coordenador e ja causou duas paradas
  numa rodada so. Vira regra que nao envelhece: `git merge-base --is-ancestor
  HEAD <base>` — exit 0 autoriza o `--ff-only`, exit != 0 e divergencia real e
  para. E o agente confere, na primeira acao, que o toplevel dele **nao e** o
  worktree de quem despachou.

- **D16 — Despacho de agente fica registrado no estado, e o fim do turno com
  agente em voo e barrado uma vez** (#180) — porque: hoje o estagio que despacha
  aposta que o turno dura mais que o agente, e essa aposta e perdida em toda
  sessao nao interativa (medido: `killed.system: 1` no `revisar`). Antes de
  despachar, o estagio grava `parcial` com `em_voo`; na volta, a baixa. Um hook
  `Stop` novo le esse registro e barra o fim do turno **uma vez** (respeitando
  `stop_hook_active`, para nao virar laco), dizendo qual agente esta em voo.
  Fica mecanico, nao prosa.

- **D17 — `bash <script>` deixa de ser "ilegivel" para o gate de fechamento de
  Issue** — porque: medido nesta sessao, `bash hooks/testa-config.sh` e
  `sh <script>` sao bloqueados por `gate-fechar-issue.cjs`
  (`tokens-comando.cjs:447-452`, postura W1: token que nao e flag nem `-c` vira
  `ilegivel: true`). O comando que o proprio `CONTRIBUTING.md` prescreve para
  rodar as baterias e barrado pelo gate do repositorio, e nenhum `gh` pode se
  esconder ali: o wrapper executa um **arquivo**, nao uma string. `bash -c
  "..."` com variavel continua ilegivel; `-EncodedCommand`, `eval` e `source`
  continuam ilegiveis.

## Avaliado e descartado
- **P2 da #173 (reconhecer `MERGE_HEAD` e limitar aos arquivos tocados)** — a
  propria Issue a chama de remendo de D3; com o delta implementado ela nao
  acrescenta garantia, so um segundo caminho de decisao no mesmo hook.
- **P2 da #170 (congelar o `.prw` real como fixture)** — ver D12.
- **Consertar a #182 em `conferir-mutacao.cjs`** — refutado por leitura: o
  arquivo nao cria worktree (ver D13).
- **Gate novo para a #174** — refutado por leitura: o gate ja existe e ja le
  `--body-file`; criar outro duplicaria a saida de emergencia, o toggle de
  `/setup` e a tokenizacao (ver D8).
- **Saida 2 da #180 (esperar o agente em foreground quando a sessao nao e
  interativa)** — serializa o que hoje e paralelo, e o paralelismo e o ponto do
  estagio `executar`. O registro + `Stop` mantem o paralelo e ainda assim nao
  deixa o turno acabar em silencio.

## Fora de escopo
- **P5 da #173 (saida de emergencia por commit, nao versionada)** — desenho de
  produto do dono do plugin, nao conserto de defeito; D6 documenta a forma em
  duas chamadas que ja existe.
- **Reescrever `posicaoDeComando` para wrapper com variavel (`"$WRAPPER" git
  ...`)** — o modelo de ameaca do lote 3 ja classificou como residual (so um
  adversario escreve), e D7 nao muda essa classificacao.
- **Atualizar a contagem agregada de casos no `README.md`** — numero de prosa
  sem mecanismo que o valide; mexer nele aqui so o desatualiza noutro lugar.

## Em aberto
- (vazio)
