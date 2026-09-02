# Handover — portaria: `escreve: true` (2026-09-02, sessão interrompida)

Sessão parada a pedido do Luís (ia desligar o PC). Tudo commitado e empurrado —
**nada em disco sujo, nada só na cabeça de ninguém**.

## Onde parou, em uma linha

Branch `fix/portaria-escreve-worktree`, commit **`9dd28af`**, base `0d35b20`
(ponta da `origin/main`), já no remoto. O conserto está **completo e verde**;
falta **doc, versão e PR**.

## Por que este conserto existe

O estágio `executar` estava **sem agente admitido**. A Opção A do fluxo 9 (aceita
em 2026-09-01) tirou `executor`, `documentador`, `resolvedor-de-build` e `tester`
do manifesto; os três que sobraram cobrem `revisar`, `design` e `plano`. Ninguém
cobria `executar` — a regra 10 ficou desligada e nada dizia isso.

O log provou, e é a evidência que ninguém tinha somado:

```
02:31 / 02:32 / 02:32  deny executor   [?]  sessão bde80d72…
02:41                  deny planejador [executar]
11:44 / 11:45          deny executor   [?]  sessão be3ae6df…
```

Duas sessões distintas. A primeira contornou implementando na mão e **não
registrou o bloqueio no handover dela**.

## O que entrou no `9dd28af`

| Mudança | Onde |
|---|---|
| `escreve: true` deixa de ser deny duro e passa a exigir `isolation: "worktree"` + despacho sem `name` | `hooks/portaria.cjs` |
| Negação anterior ao passo 4 grava o estágio real, não `"?"` | `hooks/portaria.cjs` |
| Allow de `escreve: true` registra `isolation` na linha do log | `hooks/portaria.cjs` |
| `--lint` para de reprovar `escreve: true` e avisa que **não vê** a trava (é de runtime) | `hooks/portaria.cjs` |
| `executor` em `["executar"]`, `escreve: true` | `.rainforest/agentes.json` |
| Casos 17 e 18; caso 14 e o caso do lint atualizados | `hooks/testa-portaria-{nucleo,lint}.cjs` |
| As seis baterias `.cjs` do fluxo 9 entram na suíte | `hooks/testa-portaria.sh` (novo) |

O que a portaria confere é o **pedido**, não o worktree em disco: o hook roda
**antes** do despacho, quando o worktree ainda não existe. Conferir o worktree
real na volta continua sendo da integração (`scripts/conferir-entrega.cjs`).

## O achado de instrumento do dia

**As seis baterias do fluxo 9 nunca rodaram.** São `hooks/testa-portaria-*.cjs`,
e o glob que define a suíte casa só `testa-*.sh`:

- `.github/workflows/baterias.yml:136`
- `CONTRIBUTING.md:11`

Escritas com cuidado, verdes, commitadas — e nunca executadas por ninguém desde
que nasceram. É a **quarta trava inerte** do mesmo padrão neste repositório.
`hooks/testa-portaria.sh` adota as seis; a alternativa (mexer no glob do CI)
mexeria junto na guarda de piso que existe para pegar glob quebrado.

## A regressão que quase passou

Antecipar a resolução do estágio (para o log) com um `catch` que zerasse o
resultado fazia **instalação quebrada** negar dizendo `"sem estágio ativo — abra
um fluxo"` — mandando consertar o que não estava errado. Exit 2 continuava certo;
o **motivo** é que mentia. Quem pegou foi o caso 15 da bateria órfã, na primeira
vez que ela rodou. O erro agora é guardado e sobe no passo 4, onde a rede de
`main` o converte em exit 2 com "falha interna".

## Evidência (rodada nesta máquina, não relatada por agente)

```
$ bash hooks/testa-portaria.sh
== resultado: 6 ok, 0 falha(s) ==     # 139 casos; núcleo foi de 49 para 67

$ node hooks/portaria.cjs --lint
aviso: agente 'executor' declara 'escreve: true' — o lint nao ve isolamento; …
LINT EXIT=0
```

Catraca de mutação, as três vermelhas com o comportamento invertido (exit 0 do
`conferir-mutacao.cjs`):

| # | `--de` | `--para` |
|---|---|---|
| M1 | `if (isolamento !== "worktree") {` | `if (isolamento === "___nunca___") {` |
| M2 | `if (typeof nomeDado === "string" && nomeDado.trim() !== "") {` | `if (typeof nomeDado === "number") {` |
| M3 | `gravarDespacho(raiz, "deny", nomeAgente, estagioLog, sessao, motivo);` (+ `negar`) | o mesmo com `"?"` |

Bateria das três: `node hooks/testa-portaria-nucleo.cjs`.

## O que falta, em ordem

1. **Suíte inteira** — `for t in scripts/testa-*.sh hooks/testa-*.sh; do bash "$t"; done`.
   Só as da portaria foram rodadas. Esperado: 2 vermelhas pré-existentes
   (`testa-triagem`, e conferir se `testa-conferir-encoding` fechou com o #150).
2. **Doc** — `skills/rainforest-mind/references/regra-10-portaria.md` ainda diz
   que `escreve: true` "não é suportado" e que os quatro escritores estão fora.
   O parágrafo "Estado atual (Opção A)" e o "Aceite registrado" precisam da
   emenda datada, **sem apagar o histórico**. O `README.md` (tabela de travas)
   também menciona a portaria.
3. **Versão** — bump em `.claude-plugin/plugin.json` (está em `0.81.0`), e
   `bash scripts/testa-conferir-versao.sh` / `node scripts/conferir-versao.cjs`.
4. **PR** — destino padrão de toda branch.
5. **Cache do plugin** — depois do merge, `claude plugin marketplace update` +
   janela nova, senão as sessões continuam com a portaria velha injetada.

## Decisões que ficaram abertas

- **Só `executor` entrou** no manifesto (escolha do Luís). `tester`,
  `documentador` e `resolvedor-de-build` continuam fora — agora por decisão, não
  por falta de mecanismo. Vale uma linha no doc dizendo isso.
- **Fluxo 7 (recibo)** continua parado em `executar` 0/7, na branch
  `fluxo/recibo` (worktree `.claude/worktrees/fluxo-recibo`), **1 commit atrás
  da `main`** de novo (o #151 entrou). Rebase antes de retomar. Com este
  conserto mergeado, ele volta a poder despachar `executor`.

## Worktrees vivos ao parar

```
C:/Projetos/rainforest-mind                                     [main]   ← limpo
C:/Projetos/rainforest-mind/.claude/worktrees/fluxo-recibo      [fluxo/recibo]
C:/Projetos/rainforest-mind/.claude/worktrees/stdout-vigias     [fix/stdout-do-write-linha]  ← #151 mergeado, pode ir
C:/Projetos/rainforest-mind/.claude/worktrees/portaria-escreve  [fix/portaria-escreve-worktree]
```

O `stdout-vigias` já foi mergeado no #151 — candidato a limpeza, **conferindo
antes se não guarda nada não integrado**.
