# Uma trava com 100 casos verdes barrava leitura legitima todo dia, e a bateria nao podia ver isso porque so testava escrita

**Data:** 2026-09-01
**Onde ocorreu:** `luisfmontes/rainforest-mind` — avaliacao dos repos `trailhq/Graft` e `DeusData/codebase-memory-mcp` pelo metodo do `vigias/livro-de-repos.md`, com um avaliador por repo em scratchpad

> Se voce so for ler um paragrafo: o `gate-worktree.cjs` tinha 100 casos verdes e barrava
> `grep -n "qualified_name\|<project>" README.md` — comando de LEITURA, sem redirecionamento
> nenhum, cujo unico pecado era ter um `>` dentro das aspas. A bateria nao podia pegar isso
> porque todos os 100 casos eram de escrita: ninguem tinha escrito um caso de leitura que
> passa. O defeito nao apareceu por teste, apareceu porque um agente foi bloqueado fazendo
> o trabalho e reportou em vez de contornar. Depois de consertado sao 120 casos, e os 8
> novos ficam vermelhos contra o gate anterior.

## 1 — O falso positivo, e por que ele era diario

`alvosBashEscrita` procurava redirecionamento com um `match` sobre o **texto cru** do
comando. Aspas nao entravam na conta. Entao qualquer `>` em padrao de busca virava alvo
de escrita:

```
grep -n "qualified_name\|<project>" README.md     # BARRADO — o > de <project>
grep -rn "node->start_line" src/                  # BARRADO — a seta
grep -rn 'p => p.dirExists' src/                  # BARRADO — a arrow function
grep -rn "foo" src/ 2>/dev/null                   # BARRADO — descartar stderr
```

Seta, arrow, generics e tag HTML sao rotina em busca de codigo. O custo nao era o bloqueio:
era o agente reescrevendo comando legitimo ate passar, uma reescrita por vez, sem nunca
concluir que a trava e que estava errada.

O mais irritante e que **a solucao ja morava no arquivo**. `palavras()`, logo acima, existe
desde sempre e respeita aspas — foi escrita justamente para `git commit -m "checkout later"`
nao virar um checkout. A deteccao de escrita ficou de fora dela.

## 2 — A isencao que o docblock prometia e o codigo nao cumpria

Linha 33 do cabecalho, antes deste conserto:

```
 *   - fora de repo git (scratchpad, temp) passa sempre.
```

A isencao real, no `main()`, era `if (!estado) continue;` — ou seja, **"nao e repo git"**.
Clone de terceiro no scratchpad *e* repo git. Resultado: a avaliacao de repo alheio, que e
exatamente o trabalho para o qual o scratchpad existe, rodava barrada, e a mensagem chamava
um clone descartavel de "o diretorio de trabalho principal".

Docblock que promete mais do que o codigo entrega e pior que docblock ausente: quem le
acredita e nao testa.

## 3 — A primeira tentativa de conserto apagou o gate inteiro

Isentei `os.tmpdir()` inteiro. A caixa de areia da propria bateria e `mktemp -d`, entao
**23 casos que deviam barrar passaram** — incluindo os cinco casos fundadores do relatorio
de 2026-08-08. A bateria pegou; a licao e que quase nao pegava. Bastava a isencao ter sido
escrita com um caminho um pouco diferente e a suite ficaria 100% verde com o gate inerte.

A regra final exige **duas** condicoes: abaixo do temp do sistema **e** com um segmento
`scratchpad` no caminho. Ha dois casos na bateria que existem so para provar que a isencao
nao voltou a ser larga.

## 4 — Verde tautologico nos meus proprios testes novos

Montei os payloads com `printf` e um `esc()` que so troca barra invertida. Comando com
aspas duplas quebrava o JSON, o hook saia 0 por payload invalido, e **oito casos ficaram
verdes sem o gate ter olhado para eles**. So apareceu porque no mesmo bloco havia casos que
deviam BARRAR: eles falharam, e a falha denunciou o verde vizinho.

Conserto: `b()` monta o payload pelo proprio `node` com `JSON.stringify`. Nao ha escaping
a mao.

Segundo erro no mesmo lugar: usei o helper `p`/`gatec`, que monta payload de **sessao
co-locada** (`session_id`, sem `agent_id`) e so olha verbo de git. Casos de escrita
passavam por fora do caminho que eu queria provar.

## 5 — Evidencia do conserto

```
$ bash hooks/testa-gate-worktree.sh | tail -2
== resultado: 120 ok, 0 falha(s) ==

$ git show HEAD:hooks/gate-worktree.cjs > hooks/gate-worktree.cjs   # mutacao
$ bash hooks/testa-gate-worktree.sh | grep FALHA
  FALHA grep com <project> no padrao (o caso real): esperava 0, veio 2
  FALHA grep com seta -> no padrao: esperava 0, veio 2
  FALHA grep com => no padrao: esperava 0, veio 2
  FALHA echo de texto com > sem redirecionar: esperava 0, veio 2
  FALHA tee citado dentro de padrao de busca: esperava 0, veio 2
  FALHA Write dentro de clone de terceiro no scratchpad: esperava 0, veio 2
  FALHA redirect gravando script ao lado do clone: esperava 0, veio 2
  FALHA git checkout dentro do clone descartavel: esperava 0, veio 2
== resultado: 112 ok, 8 falha(s) ==
```

## O que deu certo

**A mensagem de bloqueio manda parar e reportar, e os dois avaliadores obedeceram.** Nenhum
desligou o gate, nenhum criou o arquivo de escape, nenhum contornou em silencio. Os dois
reportaram o bloqueio com o comando exato colado, e um deles isolou o gatilho sozinho —
removeu so o token `<project>` e mostrou que o comando identico passava. Sem isso, o defeito
continuaria invisivel: ele nao produz erro, produz retrabalho.

**A ancora antes da busca funcionou pela segunda rodada seguida.** Os dois repos foram
ancorados contra ideia aberta antes de qualquer agente abrir codigo, e os dois reprovaram na
pergunta 3 por **aritmetica**, nao por opiniao: 7.871 B do Graft e 22.378 B do
codebase-memory-mcp contra 604 B de folga medida com `scripts/orcamento.cjs`. Nenhum precisou
colidir com nada para nao caber.

**Duas premissas minhas foram derrubadas com codigo, nao com prosa.** Eu tinha escrito no
briefing que o `codebase-memory-mcp` traria daemon orfao como o claude-mem e que Windows
seria segunda classe. Os dois estavam errados: o daemon e refcontado e morre no ultimo
cliente (`src/daemon/daemon.c:293-296`), e ha CI Windows amd64+arm64 em build/test/smoke/soak.
O briefing pedia evidencia de arquivo:linha justamente para isso.

**A bateria de 100 casos pegou o conserto largo.** Nao e vitoria completa — ver secao 3 —
mas ela existia e falou.

## Propostas

**P1. A deteccao de escrita decide por token, nunca por match no texto cru.**
Feito neste PR: `tokensComAspas()` marca cada token com `q` (veio de aspas), e o operador de
redirecionamento e ancorado no inicio do token, o que salva seta e arrow de graca. `tee`,
`sed -i`, `cp` e `mv` tambem passaram a decidir por token.
**Destino:** `hooks/gate-worktree.cjs`. **Resolvida.**

**P2. Isencao do scratchpad exige as duas condicoes, e ha caso que prova isso.**
Feito neste PR: `ehScratchpad()` pede estar sob o temp do sistema **e** ter segmento
`scratchpad`. Dois casos da bateria ("a isencao e do scratchpad, NAO do temp inteiro")
ficam vermelhos se alguem alargar de novo.
**Destino:** `hooks/gate-worktree.cjs` + `hooks/testa-gate-worktree.sh`. **Resolvida.**

**P3. Payload de teste de hook se monta com `JSON.stringify`, nunca com `printf`.**
Feito neste PR para o `b()` do `testa-gate-worktree.sh`. Mas o `esc()` com `printf` a mao
esta em **todas** as outras baterias de hook do repo, e a mesma classe de verde tautologico e
possivel em qualquer uma delas — nenhuma foi auditada.
**Destino:** ideia plantada `payload-de-teste-de-hook-montado-a-mao`, para varrer as baterias
de hook e trocar os montadores manuais. **Pendente.**

**P4. Uma trava so testada pelo que ela BARRA nao sabe o que ela atrapalha.**
Os 100 casos eram de escrita. A classe inteira "comando legitimo que a trava nao pode barrar"
tinha representantes (leitura simples), mas nenhum com sintaxe que se pareca com escrita.
A regra que falta e de metodo, nao de codigo: toda trava nova entrega, junto, os casos do
**trabalho normal que passam perto dela** — nao so o incidente que a motivou.
**Destino:** ideia plantada `trava-entrega-os-casos-que-ela-nao-pode-barrar`. **Pendente.**

**P5. Hook de plugin de terceiro escreve no repo por fora da trava.**
Lido no `Graft`: `src/claude/hooks.ts:355-362` dispara um processo filho destacado no Stop
hook, e filho destacado nao e chamada de ferramenta — o `PreToolUse` nunca o ve. E a mesma
classe do `codex exec --yolo` achado em 2026-08-26. Vale mesmo sem instalar nada: qualquer
plugin com hook de Stop ou SessionStart tem essa porta aberta hoje.
**Destino:** ja plantada em 2026-08-26 como buraco de trava; esta e a segunda evidencia
independente. **Pendente.**

**P6. Nao temos instrumento para saber quantos bytes do nosso SessionStart chegaram.**
A CLAUDE.md registra 50 de 50 sessoes recebendo ~2,2 KB de um payload de 32 KB, com as regras
4 a 17 nunca chegando. Medir os candidatos obrigou a somar a injecao fixa deles — e ficou
claro que nao temos esse numero para nos mesmos. Se um segundo produtor de SessionStart
entrar, nao ha como ver se ele deslocou o nosso nucleo.
**Destino:** ideia plantada `medir-quantos-bytes-do-session-start-chegam`. **Pendente.**
