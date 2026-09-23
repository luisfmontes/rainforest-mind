# Regra 10 — portaria

A admissão de subagente por manifesto (fluxo 9), separada de `regra-10.md` em
2026-09-01 pelo mesmo motivo que partiu a regra 12: a regra e o histórico dela
cresceram juntos e estouraram o teto de bytes de um `reference`. A regra em si —
roteamento por função, limiar de 3.000 tokens, agente que edita não é nomeado —
continua em `regra-10.md`.

## 2026-09-15 — a portaria deixou de admitir (issue #264)

**Até 15/09 esta era uma allowlist: fora do manifesto, deny; sem estágio ativo,
deny (a menos que o usuário digitasse "autorizo subagentes" naquela sessão).
Não é mais.** O que mudou e por quê:

| Portão | Antes | Agora |
|---|---|---|
| Agente fora do manifesto | nega | **passa**, com `declarado: false` no log |
| Sem estágio ativo | nega, ou exige frase digitada | **passa**, com `fora_de_fluxo: true` no log |
| Estágio fora da lista do agente | nega | **passa**, com `estagio_declarado` no log |
| `escreve: true` sem `isolation: "worktree"` | nega | **nega** (regra 11) |
| `escreve: true` com `name` | nega | **nega** (regra 10) |
| Manifesto malformado | nega | **nega** |

O custo dos dois primeiros foi medido no `despachos.jsonl` de 15/09 e superou o
que protegiam — medições completas em
`docs/rainforest/design/2026-09-13-portaria-em-nivel-de-plugin.md`, emenda de
15/09. Em resumo: agente de outro plugin do próprio usuário nunca passava, e a
frase "autorizo subagentes" custava uma digitação por sessão sem decidir nada.

O critério que separa o portão que fica do que sai: **ele defende a árvore de
trabalho do usuário, ou a ordem do fluxo?** A regra 11 defende a árvore, e fica.
Ordem de fluxo agora se registra — as marcas acima entram no log, que o
`conferir-fluxo` já lê.

> **Regra 10 (reescrita em 2026-09-15):** o manifesto é **declaração**, não
> admissão. A portaria barra um caso só — agente que escreve sem worktree
> isolado, ou nomeado. Todo o resto ela deixa passar e registra. A decisão
> continua sendo por código (hook `PreToolUse` sobre a tool `Task`), e o humano
> continua não sendo perguntado em runtime — a diferença é que agora ele também
> não é **cobrado** em runtime.

**Agente não declarado tem o `escreve` INFERIDO** do frontmatter, quando o
arquivo está ao alcance: tool fora da allowlist read-only → `escreve: true`, e a
regra 11 vale para ele. Fora de alcance — o caso comum em repo de consumidor,
onde os agentes vêm do cache do plugin — o allow sai marcado
`escreve_conferido: false`, em vez de afirmar read-only. Para a regra 11 morder
agente de outro plugin, declare-o no `agentes.extra.json` (ver `-escopo.md`).

**Vale em toda sessão** com o plugin habilitado. Os três níveis de manifesto — padrão embarcado, `agentes.extra.json` que soma, `agentes.json` do repo que substitui — estão em `regra-10-portaria-escopo.md`.

**O manifesto** declara por agente:
- `estagios`: em quais estágios do grafo (ex.: `["revisar"]`, `["design", "plano"]`) pode ser despachado.
- `escreve`: `false` — subagente não escreve, só relata. `true` desde 2026-09-02 — o agente pode escrever, e a portaria passa a exigir dele `isolation: "worktree"` e despacho **sem `name`**.

Exemplo:
```json
{
  "versao": 1,
  "agentes": {
    "revisor":    { "estagios": ["revisar"], "escreve": false },
    "planejador": { "estagios": ["design", "plano"], "escreve": false }
  }
}
```

**A FORMA do manifesto é conferida antes do conteúdo.** `escreve` tem de ser o booleano `false` — string `"false"`, ausente, ou qualquer outra coisa **nega**, com motivo instrutivo, no runtime e no `--lint`. `estagios` ausente, não-lista ou vazio é **erro** no lint; lista que só contém estágio que nunca fica ativo (`arqueologia`) é **aviso**, porque o manifesto não está malformado, está inútil — o runtime negaria todo despacho daquele agente. O porquê (crítico da rodada 5: `escreve === false` é igualdade estrita, e qualquer outro valor desligava a checagem inteira em silêncio) está no `git log` de `hooks/portaria.cjs`.

**Fail-closed, sempre com motivo.** Depois da revogação acima a portaria nega em quatro casos, e todos são forma ou regra 11: manifesto do repo inválido — **nega, não cai no padrão**, senão o repo ganharia agentes que não declarou; `agentes.extra.json` do usuário inválido; campo `escreve`, `runtime` ou `sensores` com valor que não dá para interpretar em agente **declarado**; e `escreve: true` sem `isolation: "worktree"` ou com `name`. Agente declarado com `escreve: false` cujo `agents/<nome>.md` declara tool fora da allowlist read-only (`Read`, `Grep`, `Glob`) também nega — é declaração que contradiz o arquivo. Toda negação sai com motivo não vazio: negação muda é bug.

**Log de despacho** — `<raiz de dados>/portaria/despachos.jsonl`, **fora do repositório** desde 2026-09-13 (raiz por `hooks/lib/raiz.cjs`; ver `-escopo.md`): append-only, uma linha JSON por decisão, autocontida. Depois da #264 é ele que responde pelos portões que saíram — o exemplo antigo mostrava um deny por "não consta no manifesto", que deixou de existir:
```json
{"ts":"…","repo":"…","agente":"Plan","estagio":"fora-de-fluxo","decisao":"allow","sessao":"…","declarado":false,"fora_de_fluxo":true}
{"ts":"…","repo":"…","agente":"executor","estagio":"executar","decisao":"deny","sessao":"…","motivo":"… 'escreve: true' e so roda com isolation: \"worktree\" … (regra 11)"}
```

O log é evidência de primeira classe: responde "quem rodou, quando, onde, em qual estágio" com `cat`, e o recibo do fluxo 7 pode referenciá-lo. Falha ao gravar vai para o **stderr** sem mudar a decisão: não-fatal, mas não calada.

**Dívida nomeada: `escreve: false` é declaração, não trava.** A checagem lê `tools:` do frontmatter e nega o que estiver fora de `Read`/`Grep`/`Glob`. Ela quase não dispara contra agente real, por duas portas:

1. **Nenhum** dos arquivos em `agents/` declara `tools:` (medido em 2026-09-01) — todos herdam o conjunto inteiro. Escrever `tools: Read, Grep, Glob` foi recusado com razão: o `revisor` precisa de `Bash` para **reproduzir cada achado** antes do veredito, que é o que a regra 12 cobra dele. A trava real exigiria uma allowlist que separasse "roda comando" de "escreve arquivo", e o frontmatter não tem isso.
2. Em repositório que apenas **consome** o plugin o arquivo do agente nem existe localmente — vem do cache. A portaria aprova sem conferir, e tem de aprovar: negar por arquivo ausente a quebraria fora deste repo. O `--lint` diverge de propósito, porque é local a este repositório, onde todo agente declarado tem de ter arquivo.

A assimetria é desenho; o errado era ela ser **invisível**. Hoje a linha traz `escreve_conferido: false` quando não deu para conferir — allow sem o campo é allow conferido. E desde a #264 **não há mais nada atrás dela**: manifesto e estágio pararam de defender. Para `escreve: false` o que resta é a declaração; a defesa conferida existe só para `escreve: true`, e é a regra 11.

## Emenda de 2026-09-02 — `escreve: true` admitido, com worktree obrigatório

O bloqueio de agente escritor por manifesto (2026-08-31 a 2026-09-02), tirado
deste texto pela #264 por não valer mais, continua histórico correto. O que
mudou é o mecanismo que faltava.

**A trava, agora.** `escreve: true` não é permissão: é a exigência de duas
condições que já eram obrigatórias em prosa, e agora são conferidas por código.

| condição | regra | por quê |
|---|---|---|
| `tool_input.isolation === "worktree"` | 11 | agente que edita nunca roda na árvore do usuário |
| `tool_input.name` ausente ou vazio | 10 | nome sem worktree é ilusão de isolamento — em 2026-08-08 um despacho com `name` **e** `isolation` rodou sem worktree e commitou no checkout principal, enquanto o irmão sem nome foi isolado |

Ausência é negação: a portaria não infere isolamento que o payload não afirma.
Os dois campos chegam em `tool_input` quando usados — medido em
`.rainforest/portaria/amostra-com-isolation.json`, colhida no próprio fluxo 9.

**O que ela confere é o PEDIDO, não o worktree em disco.** O hook roda *antes*
do despacho, quando o worktree ainda não existe. Conferir o worktree real na
volta é da integração (`scripts/conferir-entrega.cjs`): são complementares, e
nenhuma cobre a outra.

**O log do allow diz sob que isolamento** (`"isolation":"worktree"` na linha).
Registrar que um agente que escreve rodou, sem registrar a única coisa que
tornou aquilo admissível, seria a mesma cegueira que o `escreve_conferido`
fechou. E o **`--lint` avisa o que não vê**: `escreve: true` deixou de ser erro,
mas não virou aprovação silenciosa — a trava mora no payload e só existe em
runtime, então ele emite aviso (que não muda exit code) em vez de calar.

**Quem entrou (Luís, 2026-09-02): só o `executor`**, em `["executar"]`.
`tester`, `documentador` e `resolvedor-de-build` continuam fora — agora por
**decisão**, não por falta de mecanismo.

**Junto veio uma correção no log:** negação anterior ao passo 4 gravava
`estagio: "?"`. O estágio passou a ser resolvido antes da primeira negação
possível e **só para o log** — a ordem das decisões é a mesma. As cinco negações
acima não diziam em que estágio a sessão estava, que é um terço da pergunta pela
qual o log é evidência.

O relato do dia — a regressão que a antecipação quase introduziu, e a descoberta
de que as seis baterias deste fluxo nunca haviam rodado — está em
`relatorios/2026-09-02-baterias-que-o-glob-nunca-chamou.md`.

## Emenda de 2026-09-08 — campo `runtime`

O manifesto aceita `runtime: "claude" | "codex"` por agente, e a linha
`Runtime: codex` no briefing vence o manifesto. Mora em `regra-10-runtime.md`,
porque este arquivo já estava na catraca de bytes.

