> ## Errata — 2026-09-04, na entrada do repo
>
> Este relatório foi escrito contra `408af94` / v1.1.0. Quando chegou ao repo, a
> `main` já era `53c2a42` / **v1.2.0**. Três achados mudaram de estado, conferidos
> no código atual antes deste commit. **Leia esta errata antes de atacar qualquer
> frente** — dois dos itens abaixo levariam a rodada perdida.
>
> - **R2 caiu — não gaste rodada nele.** O contrato já é simétrico: `abrir` só
>   abre, e `pareceres` / `revisar` / `sintetizar` executam
>   (`scripts/conselho.cjs:1341-1348`). A retomada de um membro só também já
>   existe, via `filtrarMembros` (`scripts/conselho.cjs:305`).
>
> - **R3 está pela metade, e a outra metade já existe no repo.**
>   `parseJsonDeMembro` (`scripts/conselho.cjs:46-50`) passou a tolerar cerca de
>   código, mas exige que a cerca seja o texto **inteiro** — o caso relatado (uma
>   linha de prosa e depois o JSON) continua reprovando. O fallback que resolve
>   está escrito em `hooks/lib/cli-externo.cjs:69-85` (`extrairJson`, com a regex
>   `/({[\s\S]*})/`) e é usado só pelos adaptadores codex/gemini. É troca de
>   função, não frente.
>
> - **R1 erra o diagnóstico.** O relatório propõe "o `fechar` tem que recusar". O
>   `fechar` **já recusa**: `skills/fechar/SKILL.md:11-14` roda
>   `estado.cjs exigir --estagio fechar` e sai 2 se `verificar` não fechou ok. A
>   guarda não está faltando — o que falta é que **nada roda por último**. Um
>   fluxo que morre no `revisar` nunca chama o `fechar`, então a guarda nunca é
>   consultada. O conserto tem que ser um terminal **fora** do fluxo, que quem
>   chama por script possa rodar contra o `estado.json`.
>
> **Ainda valem, reconferidos em `53c2a42`:** R4 (`scripts/conselho.cjs:75,80,85`
> — `claude -p @{prompt} > {saida}`, sem `--output-format json`), R5 (nenhuma
> ocorrência de `CLAUDE_CONFIG_DIR` no `conselho.cjs` nem no `/setup`), R6 (nada
> sobre reprodução na regra 11), R7 (`skills/brainstorm/SKILL.md:82` tem a seção
> "Em aberto"; só "Avaliado e descartado" pede evidência — item em aberto não pede
> nada), R8 (`skills/executar/SKILL.md:63` diz só "Git destrutivo proibido").
>
> **Objeção ao conserto proposto para o R7.** Exigir "comando e saída da tentativa
> de refutação" por item em aberto vira teatro pelo mesmo motivo que "risco
> aceito" virou: um `grep` que não acha nada é trivial de produzir, e o campo
> passa a ser preenchido escrevendo bem de novo — agora com uma saída colada. O
> que de fato derrubou a premissa nesta rodada foi o júri cego com config neutro.
> Sai mais barato mandar **a premissa central** para um adversário cego cuja única
> tarefa é refutá-la com o que está no repo local, do que reformar o estágio de
> design. Por isso **R5 e R7 viram uma frente só**: o config neutro deixa de ser
> cláusula solta e vira pré-requisito da refutação cega.
>
> **Ordem de ataque revisada.** R2 sai; R4 sobe (o R9 não tem caminho enquanto não
> houver medição por estágio); R5 e R7 fundem:
> `R3` → `R1` (com o diagnóstico corrigido) → `R4` → `R5+R7` → `R6`, `R8`.
>
> **Divisão entre janelas, por superfície de arquivo** (`fluxo/guardas` está com
> +161 linhas em `scripts/conferir-entrega.cjs`):
> - **R1 + R8** — `scripts/estado.cjs`, `skills/revisar/`, `skills/fechar/`,
>   `skills/executar/`.
> - **R3 + R4 + R5 + R7** — `scripts/conselho.cjs`, `hooks/lib/cli-externo.cjs`,
>   `skills/setup/`, `skills/brainstorm/`.
> - **R6 — bloqueado** até `fluxo/guardas` mergear. Não abrir terceira mão em
>   `conferir-entrega.cjs`.

# Handover — a rodada cega: o fluxo não fecha sozinho, e a catraca reprova formatação

**Data:** 2026-09-04
**Para:** a sessão que vai atacar as frentes abertas por esta rodada
**Estado do repo:** `main` em `408af94`, versão 1.1.0. Comece de `origin/main` limpo.
**Origem:** rodada de validação de fluxo contra o plugin `protheus` (tarefa real
STEC-172, repo `inovacao`, N=1, sem humano no laço). Aparato preservado em
`C:\Microsiga\bench\` — `protocolo.md` tem a rubrica fixada antes das rodadas.

> Se você só for ler um parágrafo: o fluxo **não chegou ao fim** — encerrou o turno
> com `revisar` em curso e um subagente morto pelo sistema, devolvendo `exit 0`,
> que é o mesmo código de um fluxo concluído. A catraca do conselho **reprovou uma
> fase inteira por uma linha de prosa antes do JSON**, desperdiçando três pareceres
> bons. `abrir` e `revisar` têm **contratos opostos** sem nada documentando. E o
> estágio de design **aceitou seguir sobre uma premissa central que um grep no
> mesmo repositório derrubava** — o fluxo declarou o risco com honestidade, mas
> declarar bem saiu mais barato que checar. Um júri cego de 3 membros, rodando sem
> plugin nenhum no contexto, votou 3 a 0 contra a nossa entrega. Tudo abaixo está
> reproduzido com comando e saída.

## O que a rodada foi

Duas execuções isoladas receberam o mesmo defeito em legado ADVPL: config dirs
separados (`~/.claude-bench-rf` e `~/.claude-bench-pt`), um plugin habilitado em
cada, worktrees no mesmo commit base, prompt idêntico byte a byte exceto a
primeira linha (o comando de entrada de cada plugin, verificado por hash:
`sha256` do corpo igual nos dois). Escopo até `advpls appre` + review.

| Item da rubrica | rainforest-mind 1.1.0 | protheus 2.26.0 |
|---|---|---|
| **Chegou ao fim** | **não** — parou em `revisar` | **sim** |
| Parede | 30 min 37 s | 30 min 01 s |
| Turnos | 93 | 20 |
| Custo | US$ 14,16 | US$ 17,35 |
| Tokens de saída | 79.546 | 21.606 |
| Subagentes | 4 (1 morto pelo sistema) | 4 (todos completos) |
| `appre` exit 0 | sim (reverificado) | sim (reverificado) |
| CP-1252 e armadilhas | limpo | limpo |
| Consultou o gabarito | não | não |
| Diff | +357/−5 | +612/−13 |

**N=1 não mede plugin, mede execução.** Não tire conclusão de superioridade daqui.
O que vale são os modos de falha abaixo, que são estruturais e não dependem de N.

## R1 — `revisar` não sobrevive a um turno único, e devolve o exit code de sucesso

Fim da execução do braço, lido do `resultado.json`:

```
subtype          success
is_error         False
num_turns        93
stop_reason      end_turn
terminal_reason  completed
subagent_stats   {"spawned":4,"completed":3,"failed":0,
                  "killed":{"parent":0,"user":0,"system":1},
                  "by_type":{"Explore":3,"rainforest-mind:revisor":1}}
```

```
$ cat C:\Microsiga\bench\out-rf\exit
0
```

E o texto final que o próprio fluxo emitiu:

```
Fluxo em `revisar`; o revisor independente está lendo o diff `4ec4d113..cd8899ac`.
- design  aprovado — 9 decisões
- plano    ok — 3 tarefas
- executar ok — commit `cd8899ac`, `advpls appre` exit 0, mutação vermelha
- revisar  — em curso
Volto com o resultado da revisão e a verificação assim que o revisor terminar.
```

Não há para onde voltar: em `-p` o turno é único. O revisor foi despachado em
background e morreu com o turno (`killed.system: 1`).

**O buraco não é o kill, é o exit code.** A regra 12 diz que exit ≠ 0 nunca é
sucesso. O converso não está escrito em lugar nenhum e é o que quebrou aqui:
**`exit 0` não é conclusão.** Um fluxo interrompido no meio do `revisar` e um
fluxo fechado devolvem o mesmo `0`, e o `estado.json` do trabalho não distingue
os dois — quem chama o fluxo por script não tem como saber que ficou pela metade.

**O que mudar.** Duas frentes independentes:

1. Persistir o estágio **antes** de despachar, com reentrada — ou aguardar o
   agente em foreground quando a sessão não é interativa. Enquanto o estágio
   depender de agente em background, ele aposta que o turno dura mais que o
   agente, e essa aposta é perdida em toda sessão não interativa.
2. Estágio inconcluso tem que sair com código próprio (ou o `fechar` tem que
   recusar). Hoje o fluxo se declara "em curso" na prosa e "sucesso" no exit.

## R2 — `abrir` e `revisar` têm contratos opostos, e nada avisa

`abrir` gera os prompts e devolve na hora, sem executar ninguém:

```
$ node conselho.cjs abrir --questao questao-benchmark.md
Rodada 20260904-questao-benchmark aberta
Diretório: C:\Microsiga\bench\.rainforest\conselho\20260904-questao-benchmark
Membros: cetico, arquiteto, usuario-final
--- exit 0 ---          (3 segundos; fase `pareceres` fica "pendente")
```

`revisar` gera **e executa** os membros:

```
$ node conselho.cjs revisar
Command timed out after 2m 0s
--- exit 143 ---
```

A superfície de comando é simétrica, a docstring do topo do script descreve as
três fases sem separar quem executa, e o único jeito de descobrir é o comando
estourar um teto de tempo. Consequência medida: pus 2 min no `revisar` supondo
que ele fosse só gerar arquivos, ele matou um membro no meio, e sobrou:

```
$ ls -l fase2/revisao-*.json
2655  revisao-cetico.json
2767  revisao-arquiteto.json
   0  revisao-usuario-final.json     <-- morto no meio
```

que reprovou a fase. Repetir refez os **três** membros, incluindo os dois prontos.

**O que mudar.** Escolher um contrato e aplicá-lo às três fases — ou `abrir`
também executa, ou `revisar` só gera e um `executar --fase <f>` roda. E a
retomada tem que refazer **só o membro faltante**: hoje quem perde um membro
paga a fase inteira de novo.

## R3 — a catraca reprova preâmbulo como se fosse conteúdo ruim

```
$ node conselho.cjs conferir --fase pareceres
Parecer inválido: parecer do usuario-final: JSON inválido
  (Unexpected token 'L', "Li os dois"... is not valid JSON)
--- exit 1 ---
```

O que o membro escreveu:

```
Li os dois pacotes inteiros e conferi as afirmações centrais contra o
código-base em `4ec4d113`.

{"posicao": "A Entrega A é melhor — é a única cujo diagnóstico...
```

Uma linha de prosa antes de um JSON válido. O parecer era **bom** — posição
fundamentada, 5 objeções concretas, evidência com arquivo e linha. O retry, com
o **mesmo prompt**, passou (`exit 0`). Taxa na primeira tentativa: 1 em 3.

Contraste que importa: a catraca de `objecoes: []`, que é sobre **conteúdo**,
funcionou perfeitamente e não teve nenhum falso positivo. A de JSON, que é sobre
**forma**, custou uma rodada inteira de modelo.

**O que mudar.** Extrair o primeiro objeto JSON balanceado da saída antes de
reprovar (e aceitar cerca de código). A catraca deve morder objeção ausente e
ranking incompleto — nunca frase de abertura.

## R4 — a rodada do conselho não tem custo nem token medidos

```
$ grep -A2 '"nome": "cetico"' .rainforest/conselho/membros.json
      "nome": "cetico",
      "cmd": "claude -p @{prompt} > {saida}",
      "ligado": true
```

Sem `--output-format json`. Os dois braços do experimento têm custo exato
(US$ 14,16 e US$ 17,35) porque eu pedi na mão; o conselho inteiro — 3 pareceres,
1 retry, 3 revisões — é um buraco na contabilidade.

**O que mudar.** `--output-format json` no `cmd` default e agregação de custo e
tokens por membro no `sintese.json`. Um conselho que não sabe quanto custou não
consegue justificar quando vale abrir — e D1 o vendeu como opt-in barato.

## R5 — o júri herda o config de quem chama, com as 17 regras dentro

Os membros são spawnados com o ambiente do pai, então rodam sob o
`CLAUDE_CONFIG_DIR` de quem chamou. Pelo caminho normal isso significa que **o
júri que julga uma entrega do rainforest carrega as 17 regras do rainforest no
contexto**. A anonimização de membros (D4) cuida de *quem opinou*; ninguém cuida
do que o jurado traz na bagagem.

Nesta rodada eu criei `~/.claude-bench-neutro` (`enabledPlugins: {}`) só para o
júri — e foi **por isso** que o veredito tem valor: o mecanismo votou contra o
dono sem ter as regras do dono em contexto.

**O que mudar.** O `cmd` default do membro deve apontar para um config neutro,
criado pelo `/setup`. Cegueira de persona sem cegueira de contexto é meia
cegueira, e D4 promete a cegueira inteira.

## R6 — a regra 11 recusaria a base correta em trabalho de reprodução

A regra 11 manda o worktree nascer na ponta da `origin/main`, e
`conferir-entrega.cjs` confere o hash. Para reproduzir um defeito contra um
gabarito **já mergeado**, a base tem que ser um commit anterior — aqui
`4ec4d113`, escolhido porque nele não existem nem o design nem a correção nem
nenhuma das funções do gabarito (verificado por `git grep` na árvore inteira).

Não é defeito da regra: é caso que ela não prevê. Sem uma cláusula, todo trabalho
de reprodução, bissecção e benchmark nasce reprovando a própria portaria.

**O que mudar.** Cláusula explícita para reprodução, com a base declarada no
briefing em vez de derivada da ponta, e `conferir-entrega.cjs` aceitando base
declarada quando o manifesto disser que é reprodução.

## R7 — o design aceitou seguir sobre uma premissa que um grep local derrubava

Este é o achado de método, e o mais desconfortável.

O fluxo foi **honesto**. Registrou em "Em aberto":

```
- Risco aceito: a confirmação de que o "valor financeiro do contrato" exibido ao
  usuário é a soma de SD1 por `D1_CTROG` não pode ser feita neste worktree — a
  rotina padrão de posição do contrato (OGA280 / `OGX010QCtr`) não está aqui, e
  não há AppServer nesta rodada. A evidência que sustenta a decisão é a
  aritmética do próprio chamado, que fecha na casa dos centavos.
```

Isso é bom registro de incerteza: nomeia a premissa, nomeia o que falta, diz o
que fazer se der errado. Melhor que a maioria dos fluxos faz.

Só que o júri cego derrubou a premissa **sem AppServer nenhum**, com um grep no
mesmo repositório que o fluxo tinha na mão:

```
A tese central — "o valor financeiro do contrato é a soma das NFs vinculadas por
D1_CTROG" — não tem nenhum respaldo no repositório. Varri as ocorrências
(IAG67M12:2625, :6483; IAG67R12:677, :801) e nenhuma delas soma SD1 por contrato
para compor posição de contrato: todas filtram também por D1_DOC/D1_SERIE.
A sustentação é só a aritmética do chamado, que fecha igualmente bem nas duas
leituras e portanto não discrimina nada.
```

A frase que dói: *a aritmética fecha nas duas leituras, portanto não discrimina
nada*. O fluxo tratou como evidência o que era compatibilidade.

**O que mudar.** O estágio de design tem onde **declarar** a dúvida e não tem
onde ser **obrigado a atacá-la** primeiro. Falta um passo entre "identifiquei a
premissa central" e "aceito o risco": *tentar refutar a premissa com o que está
aqui*, e registrar a tentativa — o comando e a saída — não só a conclusão de que
não dava. Enquanto "risco aceito" for uma seção que se preenche escrevendo bem,
ela vai ser preenchida escrevendo bem.

Sugestão concreta: `Em aberto` passa a exigir, por item, um campo de tentativa de
refutação com comando e saída, ou a declaração de que nenhuma checagem local
existia — e essa segunda forma é o que a catraca conta e reporta.

## R8 — o executor tentou `git commit --no-verify`

Uma negação de permissão na rodada (`permission_denials: 1`):

```
"tool_name": "Bash",
"command": "cd \"/c/Microsiga/bench/wt-rf\" && git commit --no-verify -F - <<'MSGEOF' ..."
```

Um hook do repo barrou e ele commitou depois pelo caminho normal. Num repo sem
essa trava, teria passado. Pular verificação contraria a disciplina que o próprio
plugin defende.

**O que mudar.** Proibir `--no-verify` (e `--no-gpg-sign`) explicitamente no
briefing do executor, ao lado da proibição de git destrutivo que já está lá.

## R9 — pergunta aberta, não achado: 93 turnos contra 20

Quase quatro vezes o trabalho de modelo do outro braço, em tempo de parede
praticamente igual, para um diagnóstico que o júri considerou menos fundamentado.
Com N=1 não é conclusão.

**Não mexa em nada por causa disto.** Meça por estágio primeiro: sem saber se os
73 turnos extras foram no design, no executar ou no despacho de subagente,
qualquer corte é chute. Um `--output-format json` por estágio (ver R4) responde.

## O que funcionou, e não deve ser mexido

Um relatório só de defeitos convida a estragar o que está certo.

- **As catracas por exit code fizeram o trabalho.** A fase 1 não avançou com
  parecer quebrado, reprovou com a mensagem apontando o campo, e passou no retry.
  Nenhuma fase avançou por vontade própria.
- **D4 — anonimização por script, não por prompt — se provou certa.**
  `mapa-anonimato.json` renomeou para membro-A/B/C sem depender de o modelo
  colaborar. Foi a decisão de desenho que mais rendeu.
- **D5 — chairman mecânico.** Agregou o ranking sem modelo nenhum. Única parte do
  conselho que não deu trabalho em nenhuma das tentativas.
- **D3 — `divergencias_nao_resolvidas` registrou 16 objeções e a discordância de
  ordem em vez de fabricar consenso.** Consenso fabricado era o modo de falha que
  D3 queria evitar, e não apareceu.
- **O conselho votou 3 a 0 contra a entrega do plugin que o hospeda.** É a
  evidência mais forte da rodada: o mecanismo não protege o dono.
- **O `gate-repo-alheio.cjs` barrou a gravação deste próprio arquivo** no repo do
  plugin, porque a sessão roda no `inovacao`. Estava certo, e a mensagem já
  apontava a saída correta. É o vigia mais bem calibrado da casa.

## Ambiente — o que você precisa saber para reproduzir

- **Worktree não isola plugin.** `enabledPlugins` é resolvido no config dir do
  usuário, e o `SessionStart` do plugin injeta em toda sessão, em qualquer cwd —
  mais o `PreToolUse/gate-worktree.cjs`. Isolar exige `CLAUDE_CONFIG_DIR` por
  braço, com `settings.json`, `plugins/installed_plugins.json` e
  `plugins/known_marketplaces.json` filtrados. `installPath` pode apontar para o
  cache compartilhado: mesmo código nos dois braços, sem drift de versão.
- **A primeira sessão num config dir novo não carrega o `CLAUDE.md` do projeto**
  (transcript de 52 KB, sem convenção nenhuma); da segunda em diante carrega
  (~225 KB). Isso dá um handicap silencioso a quem rodar primeiro. **Aqueça o dir
  com uma sessão descartável antes de medir.**
- **Não compartilhe `.credentials.json` entre config dirs.** O refresh token é
  rotativo: a sessão pai renova, a cópia azeda, e o braço fica em retry até
  morrer com `OAuth session expired and could not be refreshed`. Custou 5 h 16 de
  relógio e uma rodada anulada. Copie no instante do lançamento e ponha teto de
  tempo, ou use `claude setup-token`.
- **A versão medida do protheus foi 2.26.0**, resolvida em escopo user, embora o
  banner de sessão anunciasse 2.27.6 e o cache tivesse 2.27.3 e 2.27.6 sem
  entrada no registro. Confira `claude plugin list` antes de citar versão.

## Frentes, na ordem que eu atacaria

1. **R1** — é o único que faz o fluxo mentir sobre ter terminado. Tudo mais é
   custo ou atrito; este é entrega incompleta declarada como pronta.
2. **R3** — barato e devolve uma rodada de modelo por fase.
3. **R2 + R4** — mesma vizinhança no `conselho.cjs`, vale uma frente só.
4. **R7** — o mais valioso e o mais delicado: mexe no estágio de design, que é
   onde o plugin ganha o dinheiro dele. Merece brainstorm próprio, não patch.
5. **R5, R6, R8** — cláusulas e defaults, sem risco.

## Onde está a evidência

```
C:\Microsiga\bench\protocolo.md          rubrica fixada antes das rodadas
C:\Microsiga\bench\RESULTADO.md          placar e limites declarados
C:\Microsiga\bench\metricas-rf.md        métricas do braço rainforest
C:\Microsiga\bench\metricas-pt.md        métricas do braço protheus
C:\Microsiga\bench\out-rf\ out-pt\       resultado.json, exit, epochs
C:\Microsiga\bench\out-pt-void-auth\     rodada anulada, preservada
C:\Microsiga\bench\conselho-pacotes\     entregas anonimizadas
C:\Microsiga\bench\.rainforest\conselho\20260904-questao-benchmark\
                                         pareceres, revisões, sintese.json
```

Worktree já criado e pronto para receber este arquivo, se a decisão for levá-lo
para o repo: `C:\Projetos\rainforest-mind\.claude\worktrees\handover-rodada-cega`
na branch `relatorio/rodada-cega-20260904`, nascida de `origin/main` em `408af94`.
