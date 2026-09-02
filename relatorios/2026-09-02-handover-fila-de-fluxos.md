# Handover — fila dos fluxos (2026-09-02)

Substitui `2026-09-01-handover-fila-de-fluxos.md`, que está desatualizado em tudo
o que importa: os fluxos 9 e 6 fecharam, a frente dos vigias nasceu e fechou, e a
versão andou de 0.79.0 para 0.81.0.

> Se você só for ler um parágrafo: a `main` está em **`70f75ec`**, versão
> **0.81.0**, com nada aberto. O fluxo 7 (recibo) está **no meio do `executar`,
> 0 de 7 tarefas fechadas** — `scripts/recibo.cjs` está escrito e passa em fumaça
> manual, mas **não tem bateria nem catraca de mutação**, e nesta casa isso
> significa não feito. A branch é `fluxo/recibo`, e ela está **1 commit atrás da
> `main`** (nasceu antes do merge do PR #150): rebase antes de qualquer coisa.

## Estado da árvore, agora

```
$ git log --oneline origin/main -2
70f75ec Merge pull request #150 from luisfmontes/fluxo/vigias
9cc5c6b Merge pull request #147 from luisfmontes/fluxo/portoes

$ gh pr list --state open
(nada)

$ node scripts/estado.cjs listar | grep -v "(completo)"
2026-08-24-camada-obsidian-para-o-harness  -> plano
2026-09-02-fluxo-7-recibo                  -> executar
```

Versão em `.claude-plugin/plugin.json`: **0.81.0**.

**Atenção de ambiente:** a injeção de SessionStart desta sessão apontava para o
cache `0.80.0`. O cache do plugin não acompanha o bump da `main` sozinho — sem
`claude plugin marketplace update` + janela nova, as regras injetadas são as da
versão anterior, e o `portoes.cjs` não vale como trava injetada.

## Onde a fila está

| Fluxo | Estado |
|---|---|
| 1, 2, 3, 5 fase 0, 11 | ✅ na `main` (PRs #135–#137) |
| **9 (portaria)** | ✅ na `main` — PR #141 |
| **6 (portões)** | ✅ na `main` — PR #147, versão 0.81.0 |
| **vigias** (frente paralela, fora da fila) | ✅ na `main` — PR #150 |
| **7 (recibo)** | 🚧 **`fluxo/recibo`, executar 0/7 — é onde você entra** |
| 8 (handover+regente) | fila — gatilho destravado |
| 10 (crítico) | fila — exige fluxo 1 maduro (está) |
| 4 (território) | por último — valida interface com o repo AdvPL |

## Fluxo 7 (recibo) — o próximo passo exato

**Primeiro:** `git rebase origin/main` na `fluxo/recibo`. A branch nasceu de
`859b566`, antes do merge do #150.

Design: `docs/rainforest/design/fluxo-7-design-recibo.md` — leia a seção final
`# Design formal`, que resolve três desencontros e fixa **D1–D10**. Decisões
fechadas, não reabra.

Plano: `docs/rainforest/planos/2026-09-02-fluxo-7-recibo.md` — 7 tarefas, cada
uma com `mutacao:` nomeada. O `plano` fechou com a `cobertura` rodando de
verdade: `ok: cobertura válida — 10 decisão(ões), 7 tarefa(s)`.

**O que já existe:** `scripts/recibo.cjs`, com `mostrar`, `gravar` e `conferir`
escritos. Fumaça manual passou:

```
$ node scripts/recibo.cjs mostrar 2026-09-02-fluxo-7-recibo
sem recibo gravado para '2026-09-02-fluxo-7-recibo'.
EXIT=0

$ node scripts/recibo.cjs gravar --slug 2026-09-02-fluxo-7-recibo
RECUSADO: 'nao_provado' vazio ou ausente.
EXIT=2

$ node scripts/recibo.cjs mostrar "../fora"
RECUSADO: slug invalido: ../fora
EXIT=2
```

**O que NÃO existe, e é o trabalho:**

| Tarefa | Falta |
|---|---|
| T1 | `scripts/testa-recibo-mostrar.sh` + fixtures + mutação |
| T2 | `scripts/testa-recibo-gravar.sh`, a linha do `.gitignore` para `.rainforest/colheita/`, + mutação |
| T3 | `scripts/testa-recibo-portoes.sh` + mutação (o código do D5 já está no `gravar`) |
| T4 | `scripts/testa-recibo-conferir.sh` + mutação |
| T5 | o gancho no `conferirFechamento` do `estado.cjs` para `estagio === 'fechar'`, + `scripts/testa-recibo-fechar.sh` |
| T6 | a regra do exit não-zero no núcleo — **ver o aviso de bytes abaixo** |
| T7 | linha no `README.md` |

O `executar` **não foi marcado**. Rode
`node scripts/estado.cjs exigir --slug 2026-09-02-fluxo-7-recibo --estagio executar`
para armar a catraca de mutação antes de fechar.

### T6 tem um aperto de bytes real

```
$ node scripts/medir-skill.cjs
nucleo=5597 regras=17 references=19 setas-duplas=0 skill-bytes=10139 maior-reference=regra-12.md:9277
```

Teto do núcleo: **5600 B** (`hooks/lib/contexto-sessao.cjs`). **3 B de folga.** A
regra do exit não-zero não cabe como regra 18 nova sem cortar de outra.

O plano recomenda **(b): uma cláusula na regra 12** em vez de regra 18 separada —
a 12 já é "entrega se valida na saída real" e já diz "✅ sem comando e saída
colados = não feito". "Exit ≠ 0 não é sucesso" é a mesma família, e a cláusula
custa muito menos bytes. O motivo é de conteúdo, não de orçamento: uma regra 18
separada convida a ler isso como assunto de **tom**, quando é assunto de
**evidência**. Decida medindo, não por preferência.

## O que este dia ensinou, e você vai precisar

### As três formas de trava inerte, todas achadas hoje

O padrão é sempre o mesmo: **o instrumento responde**. Não estoura, não fica em
branco, devolve `exit 0` e segue.

1. **Issue #142** — o guarda de "não remover worktree sujo" media o repositório
   pai (`git -C <dir>` sobe em silêncio) e respondeu `sujo (1)` para 18
   diretórios, sempre o mesmo `1`.
2. **A `cobertura`** — nunca disparou. O gate derivava o caminho do design de
   `<slug>.md` e nenhum design daqui se chama assim; o estado gravava o caminho
   real em `design.arquivo` e o gate olhava para outro lugar. Passou o fluxo 9
   inteiro inerte. **Consertado no fluxo 6, T6.**
3. **O conserto da `cobertura`** — não alcançava o único caminho em que o caso
   acontece. `conferirFechamento` recebia o estado do **disco**, sem o `--json`
   da chamada; e como `design` não tem estado entre `pendente` e `aprovado`, é no
   `marcar` que fecha que o campo é declarado. **A bateria que eu escrevi para
   provar o conserto testava o caminho que funcionava.** Consertado depois, por
   revisão independente.

**A régua que sai disso:** ao escrever a bateria de um conserto, a pergunta é
"qual sequência a pessoa realmente digita?", não "qual sequência prova que meu
código roda?".

### O gate que aprova lendo em vez de executar

O gate do `verificar` do fluxo 6, no **primeiro uso real**, rodou
`portoes.cjs rodar` sem `--reverificar` e imprimiu seis `cumprido (pulado)`,
fechando `ok`. Aprovou lendo o arquivo. Nem o revisor da mesma família nem a
auditoria cross-model pegaram — **e nenhum dos dois falhou**: os dois liam o
*código* do gate, que estava certo. Quem estava errada era a *chamada*.

É por isso que o **D5** do fluxo 7 exige `--reverificar` no recibo, e por que a
T3 tem fixture com portão `[x]` cumprido cujo `CHECK:` hoje reprova.

### Cross-model achou o que a mesma família não achou, de novo

Terceira vez seguida (fluxos 9, 6). Hoje o codex achou dois, e o segundo foi um
buraco na cerca que eu tinha escrito **horas antes** para fechar outro buraco:
`path.resolve` + `startsWith` é teste **léxico**, e junction dentro da raiz
apontando para fora passa nele. No Windows qualquer usuário cria junction sem
privilégio. A cerca certa é por `realpath`, nos dois lados.

```
node scripts/segunda-opiniao.cjs --base <base> --head HEAD --criterio <arquivo.md> --modelo codex
```

O vocabulário de veredito é exatamente `concordo` / `discordo`. **Escreva os
critérios com cuidado:** um "achado" do codex hoje era erro meu de enunciado —
eu havia exigido que "nenhuma checagem antiga mudasse de comportamento" quando a
T6 existia justamente para mudar uma. Ele estava certo; eu reescrevi o critério.

### Fabricações e vícios de agente vistos hoje

- **Dois de dois agentes sinalizaram `idle_notification` com `available` e
  nenhum conteúdo**, tendo o trabalho completo e correto pronto. Pedir de volta
  por `SendMessage` resolveu nas duas vezes. **Não re-despache** — peça de volta.
  Pôr no briefing "não sinalize disponível sem a entrega" funcionou na terceira.
- O `planejador` marca `CONFIRMADO` em afirmação de fonte. Hoje as quatro dele
  se sustentaram — mas confira, porque é uma linha de comando cada.

### Ferramentas que mentem nesta máquina

- **O `grep` do Git Bash normaliza CRLF antes de casar.** `grep -q $'\r'` diz
  "não achou" num arquivo que `od -c` e `file` confirmam ser CRLF. Detecção de
  `\r` é por Node: `readFileSync(p).includes(13)`.
- **Na ponte node→node não há conversão de caminho MSYS.** `/tmp/...` chega ao
  Windows como `C:\tmp\...`. Quando um Node spawna outro, os dois lados do
  caminho passam por `cygpath -m`. Isso tornou uma prova de não-execução **falsa**
  — e o controle dela exercitava bash→node, que É convertido.
- **`git -C <dir>` sobe para o repositório pai em silêncio** quando `<dir>` não é
  repo.

### As travas que funcionaram, e vale não desligar

- O **gate de staging** barrou um `git add -A` que teria varrido o
  `vigias/ERROS.md` da outra frente.
- O **gate de publicação** barrou um caso de teste meu por conter `/home/` e
  `/Users` numa regex. Falso positivo, mas a asserção ficou melhor sem eles.
- O **guarda de snapshot do `revisar`** recusou o fechamento porque o HEAD andou
  durante o estágio (eu havia commitado os consertos). Recapturar custou trinta
  segundos e a recusa era legítima.
- A **catraca de mutação** recusou uma mutação **falsa minha** com
  `bateria VERDE com o comportamento invertido` — o caso "fora da árvore" tinha
  o arquivo **dentro** da raiz do sandbox. Sem ela eu teria commitado asserção
  decorativa.

## Dívidas e pendências nomeadas

| O quê | Onde |
|---|---|
| `reaberto_por`/`pendentes` aceitos do `--json`, e `exigir` recusa onde `marcar` deixa passar | **Issue #148** |
| O guarda de limpeza que mede o repositório pai | **Issue #142** (P1 pendente: a `limpar` não tem script próprio) |
| Confinamento por `realpath` nos OUTROS scripts que aceitam caminho | **pendente** — só o que o fluxo 6 introduziu foi corrigido |
| `testa-triagem` vermelha | pré-existente, depende de dado local desta máquina |

Suíte na `main` antes deste fluxo: **69 baterias, 2 vermelhas**, as duas
explicadas acima (uma delas, `testa-conferir-encoding`, era o `ERROS.md` dos
vigias e deve ter fechado com o PR #150 — **confira, não presuma**).

## Relatórios de método deste dia

- `relatorios/2026-09-02-o-conserto-que-nao-alcanca-o-uso-que-o-motivou.md` — as
  três travas inertes, o gate que aprovou lendo, e 7 propostas (P3 e P6 pendentes).
- `relatorios/2026-09-02-handover-vigias-parados.md` — a frente paralela, já
  entregue no PR #150.

## Protocolo que segurou o dia

- **Regra 12 é o que mais paga.** Nenhum veredito de agente aceito sem eu
  reproduzir o achado na janela principal. Dez achados no fluxo 6, dez
  reproduzidos.
- **Uma catraca de mutação por tarefa, sempre.** Sete no fluxo 6, todas matando.
  Uma delas pegou erro meu.
- **A trava de tentativas do `estado.cjs` disparou** e subiu a decisão. Ela conta
  reprovação consecutiva com teto de 3; `liberar` destrava.
- **Submeter o artefato à própria ferramenta.** O fluxo 6 tem
  `docs/rainforest/portoes/<slug>.md` com os seus próprios portões, e foi isso
  que achou o falso positivo do lint. Se o fluxo 7 puder ter recibo de si mesmo,
  vale — o manifesto já está declarado no `plano`.
