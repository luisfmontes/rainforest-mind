# O conserto da portaria — `escreve: true` com worktree obrigatório (2026-09-02)

Branch `fix/portaria-escreve-worktree`, base `0d35b20` (ponta da `origin/main`).

> Este arquivo nasceu como handover de sessão interrompida ("faltam doc, versão
> e PR"). A sessão retomou e fechou os três; o texto foi reescrito para o estado
> final. Fica como o registro da branch, não como pendência.

## O que estava quebrado

O estágio `executar` estava **sem agente admitido**. A Opção A do fluxo 9
(aceita em 2026-09-01) tirou `executor`, `documentador`, `resolvedor-de-build` e
`tester` do manifesto; os três que sobraram cobrem `revisar`, `design` e
`plano`. Ninguém cobria `executar` — e a regra 10, injetada em toda sessão,
manda despachar toda task mecânica no `executor`.

Dois mecanismos do usuário, os dois na `main`, contradizendo-se em silêncio
desde 01/09. O log da portaria provou:

```
02:31 / 02:32 / 02:32  deny executor   [?]  sessão bde80d72…
02:41                  deny planejador [executar]   ← a saída tentada, também negada
11:44 / 11:45          deny executor   [?]  sessão be3ae6df…
```

Duas sessões distintas, com horas de intervalo. A primeira contornou
implementando na mão e **não registrou o bloqueio no handover dela**.

## O que entrou

| Mudança | Onde |
|---|---|
| `escreve: true` deixa de ser deny duro e passa a exigir `isolation: "worktree"` + despacho sem `name` | `hooks/portaria.cjs` |
| Negação anterior ao passo 4 grava o estágio real, não `"?"` | `hooks/portaria.cjs` |
| Allow de `escreve: true` registra `isolation` na linha do log | `hooks/portaria.cjs` |
| `--lint` para de reprovar `escreve: true` e avisa que **não vê** a trava (é de runtime) | `hooks/portaria.cjs` |
| `executor` em `["executar"]`, `escreve: true` | `.rainforest/agentes.json` |
| Casos 17 e 18; caso 14 e o caso do lint atualizados | `hooks/testa-portaria-{nucleo,lint}.cjs` |
| As seis baterias `.cjs` do fluxo 9 entram na suíte | `hooks/testa-portaria.sh` (novo) |
| Emenda datada, sem apagar a Opção A | `skills/rainforest-mind/references/regra-10-portaria.md` |
| Linha da portaria na tabela de travas | `README.md` |
| Relatório de método do dia | `relatorios/2026-09-02-baterias-que-o-glob-nunca-chamou.md` |
| `0.81.1` → `0.82.0` | `.claude-plugin/plugin.json` |

**O que a portaria confere é o PEDIDO, não o worktree em disco:** o hook roda
*antes* do despacho, quando o worktree ainda não existe. Conferir o worktree
real na volta é da integração (`scripts/conferir-entrega.cjs`), e continua sendo.

**Só o `executor` entrou.** `tester`, `documentador` e `resolvedor-de-build`
continuam fora — agora por **decisão** do Luís, não por falta de mecanismo.

## Evidência (rodada nesta máquina, não relatada por agente)

```
$ bash hooks/testa-portaria.sh
== resultado: 6 ok, 0 falha(s) ==        # 139 casos; núcleo foi de 49 para 67

$ bash hooks/testa-contexto-sessao.sh
ok: 277   falhou: 0

$ node scripts/medir-skill.cjs
… maior-reference=regra-10-portaria.md:9998      # teto 10500

$ node scripts/conferir-versao.cjs
ok    versao 0.82.0: 3 commit(s) desde o bump 2ba7414 (teto 5)

$ node hooks/portaria.cjs --lint
aviso: agente 'executor' declara 'escreve: true' — o lint nao ve isolamento; …
LINT EXIT=0
```

Catraca de mutação — as três vermelhas com o comportamento invertido (exit 0 do
`conferir-mutacao.cjs`), bateria `node hooks/testa-portaria-nucleo.cjs`:

| # | `--de` | `--para` |
|---|---|---|
| M1 | `if (isolamento !== "worktree") {` | `if (isolamento === "___nunca___") {` |
| M2 | `if (typeof nomeDado === "string" && nomeDado.trim() !== "") {` | `if (typeof nomeDado === "number") {` |
| M3 | `gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, motivo);` (+ `negar`) | o mesmo com `"?"` |

## Duas coisas que valem atenção

**A folga da reference ficou em 5%** (9.998 B contra 10.500). O comentário do
`REFERENCE_MAX_BYTES` pede que margem apertada seja **dita**, não deixada sumir
calada — está dito aqui e no commit. O próximo que escrever nesse arquivo
provavelmente terá de cortar antes.

**Uma regressão foi introduzida e pega no caminho.** Antecipar a resolução do
estágio com um `catch` que zerasse o resultado fazia instalação quebrada negar
dizendo *"sem estágio ativo — abra um fluxo"*: exit 2 continuava certo, o
**motivo** é que mandava consertar o que não estava errado. Quem pegou foi o
caso 15 — de uma bateria que, até este dia, nunca havia rodado.

## Depois do merge

1. `claude plugin marketplace update` + janela nova. O cache do plugin **não**
   acompanha o bump da `main` sozinho: sem isso, as sessões continuam com a
   portaria e as regras da versão anterior injetadas.
2. **Fluxo 7 (recibo)** está parado em `executar` 0/7, na branch `fluxo/recibo`
   (worktree `.claude/worktrees/fluxo-recibo`), atrás da `main`. Rebase antes de
   retomar — e aí ele volta a poder despachar `executor`.
3. O worktree `stdout-vigias` já foi mergeado no #151 — candidato a limpeza,
   **conferindo antes se não guarda nada não integrado**.
