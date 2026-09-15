# Zerar as Issues abertas, rodada 4 — as cinco que não colidem

## Objetivo

Na abertura desta sessão havia **8** Issues abertas. A **#240** foi fechada fora
do fluxo, com evidência: os três critérios falsificáveis dela já passam no código
de hoje (o bloco 6 do núcleo injetado contém a triagem e a palavra `Issue`,
`node scripts/orcamento.cjs` sai 0 em 14927/15000 B, e `references/regra-06.md`
existe com o zero-padding que o ponteiro imprime). Ela foi entregue pelo fluxo
`triagem-de-achado-e-portaria` e ninguém tinha fechado o registro.

Das **7** que sobraram, **5** fecham aqui: **#258**, **#257**, **#253**, **#249**
e **#244**. As outras duas ficam para a rodada seguinte, e o motivo está em "Fora
de escopo".

## O que foi medido, e em quê

Base: `origin/main` @ `14c471ed`, nesta máquina, 2026-09-14.

**#258 reproduzido, e a causa raiz não é a que a Issue supôs.** A Issue descreve
dois sintomas e propõe quatro direções. Rodando o gate real por stdin, com o
payload que o harness manda, o que bloqueia não é "heredoc" nem "citar comando
git":

| Entrada | Hoje |
|---|---|
| `cat > x.md <<'EOF'` + corpo citando `git add -A` + `EOF` | passa (exit 0) |
| corpo com crase, `$(`, `$VAR` ou `\|` | passa (exit 0) |
| corpo com **`Medido (folga de 2 B). Ele sobe.`** | **bloqueia (exit 2)** |
| `git -C <dir> add f.txt` | passa (exit 0) |
| `git add -A` | bloqueia (exit 2) — correto |
| `bash <<'EOF'` + `git add -A` + `EOF` | bloqueia (exit 2) — correto |

O gatilho é o `.` que abre frase depois de um parêntese de fechamento: o
tokenizador o lê como o builtin `source`, `desempacotarWrapperDeString` devolve
`ilegível`, e `analisaSegmentoGit` responde `{ incerto: true }`. **É exatamente a
Issue #239**, fechada no PR #247 — e a correção de lá (`corpoDeHeredoc`) ficou
dentro de `hooks/gate-fechar-issue.cjs`, sem ser exportada. O `gate-staging-total`
nunca a recebeu.

Isso muda o tamanho da tarefa: não há mecanismo novo a inventar, há um mecanismo
já revisado e com bateria a **compartilhar**.

**O segundo sintoma do #258 é consequência do primeiro, não um defeito
independente.** `hooks/gate-staging-total.cjs:329` faz `dirC = null` no ramo
`incerto`. O `-C` do comando é descartado antes de a mensagem ser montada, e a
mensagem cai no `cwdDoEvento` — daí "Repo: C:/Projetos/rainforest-mind" com os
690 não-rastreados do projeto. A resolução de `-C` **já existe** e está certa
(linha 348, `const dir = dirC || ...`); ela só não é alcançada quando o bloqueio
vem por ilegibilidade.

**#257 medido contra o regex real.** `hooks/lib/autorizacao-usuario.cjs:173`. As
formas bem escritas casam; `subagens`, `subgentes`, `sub agens` não. O arquivo
exporta só `autorizado` e `temNegacaoExplicita` — a medição isolada do regex
precisa passar pela porta pública, e é assim que a bateria deve medir.

**#244 não precisa de código.** `scripts/conferir-versao.cjs` já compara semver
por componente contra `origin/main`, já recusa com exit 2 citando os dois
números, e já trata `origin/main` irresolvível como pulo. A etapa 1 é **fiação de
CI**: um passo a mais no job que já roda.

## Decisões fechadas

- **D1 — #258, causa raiz: `corpoDeHeredoc` sai de `gate-fechar-issue.cjs` para
  `hooks/lib/heredoc.cjs`, e o `gate-staging-total.cjs` passa a usá-la.** A
  função se move sem mudar de comportamento; o `gate-fechar-issue.cjs` passa a
  importá-la. No `gate-staging-total.cjs`, o corpo de heredoc cujo comando
  receptor **não** é interpretador não gera segmento; quando é interpretador
  (`bash`, `sh`, `zsh`, `ksh`, `dash`, `pwsh`, `powershell`, `cmd`, `eval`,
  `source`, `.`), o corpo entra e é analisado como hoje — **porquê:** a classe
  inteira de falso positivo se fecha de uma vez (parêntese-ponto, crase, `$(`,
  `&&`, e qualquer prosa futura), e fecha com código que já passou por revisão e
  já tem bateria no #247. Inventar um detector novo aqui seria escrever pela
  segunda vez o que este repositório já aprendeu a escrever uma vez.

- **D2 — O `gate-mensagem-commit.cjs` não muda.** Ele recusa `-F -` justamente
  por **ver** o heredoc; a extração vai para uma lib nova e é chamada só por quem
  a quer — **porquê:** é a mesma decisão que o #247 tomou (D1 de lá), pelo mesmo
  motivo, e mexer no segmentador compartilhado mudaria o contrato de um gate que
  não tem defeito.

- **D3 — RETRATADA em 2026-09-14, antes de virar código.** O que está escrito abaixo
  supunha que o segundo sintoma da #258 acontecia; **ele não reproduz**. Seis formas
  medidas contra o gate real por stdin, `cwd` no checkout principal, sobre `14c471ed`,
  incluindo a linha literal da Issue — todas saem 0, nenhuma imprime linha `Repo:`. A
  frase "é consequência do primeiro", na seção de medição acima, era **inferência, não
  medição**, e está errada pelo mesmo motivo: eu li o código e deduzi o caminho, em vez
  de rodar. A tarefa 2 foi retirada e o sintoma virou a **Issue #261**, que pede a linha
  de comando exata de quando aconteceu. Fica registrado em vez de apagado porque a
  decisão existiu e governou uma tarefa.

  <details><summary>Texto original da D3</summary>

  **Texto original:** #258, segundo defeito — o `-C` sobrevive ao ramo `incerto`. A linha
  `dirC = null;` do ramo de ilegibilidade sai; quando o segmento traz
  `git -C <caminho>` resolvível, a mensagem cita **aquele** repositório. Não
  sendo resolvível (variável, subshell, `~`), a mensagem diz que não deu para
  resolver o destino, em vez de nomear o do projeto — **porquê:** um bloqueio que
  lista 690 arquivos do repositório errado não é conservador, é ruído: quem lê
  não consegue nem conferir se o bloqueio procede, e a saída de menor esforço
  passa a ser desligar o gate. O aviso continua bloqueando; só para de mentir
  sobre onde.


  </details>

- **D4 — #257: a autorização casa por distância de edição, ancorada no verbo.**
  Dentro da mesma janela de proximidade que o arquivo já usa depois de
  `autorizo`/`autorizar`/`autorizando`, um token que **comece por `sub`** e fique
  a **≤ 2 edições** de `subagente`/`subagentes` conta como a forma. As formas
  exatas de hoje continuam casando pelo caminho de hoje — **porquê:** o docblock
  do arquivo defende "listar o que QUALIFICA é finito; listar o que desqualifica,
  não", e essa postura fica de pé: distância de edição é uma lista finita de
  qualificadores, só que descrita por medida em vez de por enumeração.
  `submarinos` fica a 5 edições e não entra. A negação explícita, a cláusula
  subordinada e o filtro de voz-do-usuário não são tocados: o erro caro continua
  sendo abrir.

- **D5 — #257: a recusa culpa a digitação, não o estágio.** Quando a linha do
  usuário tem `autoriz*` seguido de um token que começa por `sub` mas fora da
  tolerância, a portaria recusa dizendo que **quase** reconheceu a autorização e
  cita o que foi lido, em vez de `sem estágio ativo — abra um fluxo`
  (`hooks/portaria.cjs:800`) — **porquê:** o custo do defeito não é redigitar, é
  a mensagem mandar resolver uma condição diferente e mais cara. A alternativa
  impressa hoje descreve literalmente o que o usuário acabou de fazer, o que faz
  a recusa parecer quebrada em vez de específica.

- **D6 — #253: visibilidade do remoto consultada por `gh`, com cache em disco.**
  Antes de bloquear, o `gate-publicacao-destino.cjs` resolve o remoto do
  repositório e consulta `gh repo view <owner/repo> --json isPrivate`, guardando
  o resultado em cache sob a pasta de dados do rainforest. **Privado: passa.
  Público, `gh` ausente, ou visibilidade desconhecida: bloqueia como hoje** —
  **porquê:** é a única das três opções que não exige o usuário manter uma lista
  à mão, e a lista é justamente o que envelhece calado. O custo é uma chamada de
  rede na primeira gravação por repositório. A falha fecha para o lado de
  bloquear, que é o lado seguro: um repositório público novo nunca passa por
  omissão de cadastro.

- **D7 — #249: o laço das baterias vira `scripts/varrer-baterias.sh`, e o YAML o
  chama.** O bloco `run:` de `.github/workflows/baterias.yml` (o laço, a guarda
  de piso de 15 e o placar) move-se para o script **sem mudar uma linha da
  lógica**; o YAML vira uma chamada. O script aceita `--so <caminho>` para rodar
  uma bateria só — **porquê:** o `verificar` deste fluxo precisa citar **um**
  comando cujo exit 0 signifique "as 114 passaram"; hoje ele cita a ferramenta e
  mede a ferramenta, que foi como `testa-orcamento.sh` ficou vermelha por dois
  commits sem ninguém ver. O `--so` é acessório e entra porque sem ele a
  re-rodada custa dez minutos para ler uma bateria.

- **D8 — #244: só a etapa 1.** `node scripts/conferir-versao.cjs` entra como
  passo do job de PR que já existe. Nenhum job novo, nenhuma permissão de escrita,
  nenhum minuto de Actions a mais além do próprio passo — **porquê:** a etapa 1
  já mata o modo de falha silencioso (esquecer o bump vira check vermelho no PR,
  não descoberta semanas depois), e a etapa 2 carrega `contents: write`, laço de
  push e a política de qual componente subir, que é onde a automação vira
  julgamento. Julgamento automático erra calado — que é o defeito que a Issue quer
  fechar, não mudar de lugar. A etapa 2 fica plantada para quando a 1 provar não
  bastar.

- **D9 — Versão 1.14.1, PATCH.** Nenhum contrato novo: três gates param de
  bloquear o que já deviam deixar passar, a autorização passa a aceitar o que o
  usuário já queria dizer, o laço da CI muda de arquivo sem mudar de lógica, e o
  conferidor de versão passa a ser chamado onde já podia ser — **porquê:** é a
  mesma classificação do lote de consertos de instrumento de 1.13.1, e pelo mesmo
  critério. O bump entra neste PR, não depois: com a D8 ligada, o PR nasce
  vermelho até o número subir, e esse vermelho→verde é a prova de que a trava
  morde.

- **D10 — #260: `token` sozinho deixa de ser evidência de credencial, e o achado passa a mostrar o trecho casado com o valor redigido.** A régua `credencial` de `scripts/conferir-publicacao.cjs` exige qualificador (`access_token`, `auth_token`, `refresh_token`, `api_token`, `bearer`) ou valor com cara de segredo; as demais palavras da lista continuam disparando sozinhas. Cada achado ganha `trecho`, impresso na saída de texto e no JSON, e mostrar a chave é **opt-in por régua** — **porquê:** este repositório é sobre tokenizar linha de comando (`tokens-comando.cjs`, `tokensComAspas`, `posicaoDeComando`), e `const token = toks[i]` era bloqueado com `pode_ser_falso: false`, a marca reservada para achado sem dúvida. Custou rodadas em três tarefas deste próprio fluxo. E a mensagem nomeava só a régua, nunca o trecho: um executor gastou duas rodadas culpando o nome `dist` e "certas estruturas `const ... = ...`". O opt-in existe porque a primeira versão da redação tomava o último grupo capturante como valor e mostrava o resto, o que na régua `jid-whatsapp` imprimia o número completo — uma correção de mensagem virando vazamento. Entrou a pedido do Luís em 2026-09-14, depois de a Issue ser aberta no meio do fluxo.

- **D11 — a máscara de heredoc é permissiva por exceção, não por regra: quatro condições, e o padrão é analisar.** Trocar o corpo de um heredoc por espaços só acontece quando o `<<` é operador (e não texto dentro de aspas ou de comentário), o delimitador está citado, ele fecha em linha própria, e o corpo não alimenta interpretador nem arquivo executado adiante. **Porquê:** a primeira versão exigia só a última condição e abriu **oito** formas de atravessar o gate, todas medidas como exit 2 em `14c471ed` e exit 0 depois dela — inclusive `echo "a << b"` numa linha apagando o staging em massa da linha seguinte, e o mesmo pela ferramenta PowerShell, que não tem heredoc nenhum. No bash de verdade a primeira forma varre o arquivo de outra sessão, que é o incidente de 2026-08-09 que este gate existe para impedir. Duas causas: `indexOf("<<")` não distingue operador de texto, e corpo **não citado** expande `$(...)` e crase, logo executa — nunca foi dado. A #258 pedia isenção para o heredoc **citado**, e era só isso que cabia conceder. Achada pela auditoria de segurança deste mesmo lote, em 2026-09-14, antes de o `revisar` fechar.

- **D12 — `autoriza` na terceira pessoa concede só quando abre a oração.** A tolerância de digitação da D4 veio junto com o verbo em terceira pessoa nas três expressões que decidem concessão, para cobrir o imperativo `autoriza subagens`. Aceita em qualquer posição, porém, a terceira pessoa é **descritiva**: seis frases passaram a autorizar despacho de subagente sem o usuário ter autorizado nada, duas delas frases em que ele está **negando** (`ninguem autoriza subagente sem eu ver antes`, `a doc autoriza subagentes nesse caso, mas eu nao quero`) e uma que é pergunta sobre o mecanismo. **Porquê:** primeira pessoa e infinitivo comprometem quem fala em qualquer posição — não há frase descritiva natural com `autorizo` ou `autorizar` que não conceda. A terceira pessoa, não: ela só compromete no imperativo, e imperativo abre a oração. As seis davam `false` em `14c471ed`. Mesma auditoria, mesma data.

## Avaliado e descartado

- **#258: estreitar o detector de "dinâmico" no próprio
  `gate-staging-total.cjs`** — é reescrever o #239 de novo, num segundo arquivo,
  com uma segunda bateria e uma segunda chance de errar. A função já existe,
  revisada; compartilhar custa menos e não abre variante.

- **#258: `git add` por caminho sair da régua** — a Issue sugere, e o código já
  faz: `motivoDe` só devolve motivo para `.`, `-A`, `--all`, `-u` e primos
  (linhas 205-211). `git -C <dir> add f.txt` sai 0 hoje. Não há o que mudar, e a
  sugestão nasceu de atribuir ao `add` um bloqueio que veio do ramo de
  ilegibilidade.

- **#257: aceitar qualquer token começado por `sub` perto do verbo** — abre para
  `submarinos`, `subitem`, `subir`. A distância de edição mantém o portão fechado
  com a mesma economia.

- **#257: subir o texto da triagem por enumeração de erros de digitação** — é a
  lista fechada de novo, com mais itens. O próprio docblock do arquivo registra
  que enumerar o português é perder.

- **#253: lista de remotes confiáveis em `~/.rainforest/config.json`** — zero
  rede, mas o usuário mantém à mão, e uma lista desatualizada falha para o lado
  de **bloquear** um repositório privado novo (ruído) ou, se invertida, de
  liberar um público novo (vazamento). A consulta responde sempre a verdade de
  agora.

- **#253: escopo por termo (`<termo> @publico`)** — mais barato, mas move a
  decisão para o momento de cadastrar o termo, meses antes de o repositório
  existir. Fica como alternativa se a chamada de rede incomodar na prática.

- **#244: job pós-merge que commita o bump** — é a etapa 2, com custo real em
  permissão de escrita, cota de Actions e política de versionamento. Plantada.

## Fora de escopo

- **#254 (catraca de mutação: `pulada` fecha como se fosse medida)** e **#250
  (as partes do orçamento somam mais que o todo)**. Ambas colidem com o fluxo
  `2026-09-14-guias-e-sensores`, em curso em outra sessão com plano fechado: a
  tarefa 5 dele reescreve o fechamento do `verificar` em `scripts/estado.cjs`, que
  é o mesmo ponto do #254, e as tarefas 2 e 4 tocam `scripts/orcamento.cjs` e
  `hooks/lib/contexto-sessao.cjs`, que é onde o #250 mora. Entram na rodada
  seguinte, depois do merge dele. Decisão do Luís em 2026-09-14.

- **A etapa 2 do #244** — ver D8.

- **O `enabledPlugins` do `ponytail` divergindo do `.ponytail-active`**,
  registrado no fim do #258 como discrepância observada sem conclusão. Não é
  deste repositório e não tem mecanismo; se virar defeito, é Issue própria.

## Risco de merge conhecido

A D5 toca `hooks/portaria.cjs` perto da linha 800, e a tarefa 6 do
`guias-e-sensores` toca o mesmo arquivo na leitura do manifesto. Regiões
distintas, conflito textual improvável — mas quem mergear por último confere. Não
é motivo para adiar: é o único ponto de contato das cinco tarefas com aquele
fluxo, e é de uma linha.

## Em aberto

Nada. As cinco Issues têm causa medida em `arquivo:linha` nesta máquina, sobre
`14c471ed`, e critério falsificável no plano.
