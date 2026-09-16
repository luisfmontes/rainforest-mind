# Zerar as Issues abertas, rodada 5 — as 20 medidas no código

## Objetivo

Medir no código real as 20 Issues abertas em 2026-09-16 (#250–#287) e fechar
num plano só o conserto de cada uma, junto com a retirada da frase de
confirmação no fechamento de Issue, pedida pelo usuário nesta sessão.

## O que foi medido, e em quê

Base: `origin/main` @ `e6eccded`, nesta máquina, 2026-09-16. Cinco agentes de
medição, cada um num worktree isolado, sem editar arquivo versionado; os
achados abaixo com ✔ foram re-rodados pela janela principal.

| # | Reproduz? | Causa em arquivo:linha | Tam. | Arquivos do conserto |
|---|---|---|---|---|
| 275 | sim — merge com arquivo igual ao da main sai exit 2 | `hooks/gate-verificador-staged.cjs:87-119` materializa todo blob staged, sem comparar com `HEAD`/`MERGE_HEAD` | M | `gate-verificador-staged.cjs`, `testa-gate-verificador-staged.sh` |
| 278 | duplicata da #275 | mesma função | — | — |
| 263 | ✔ sim — `-am` exit 2, `-m` exit 0; heredoc com `git commit` nu no corpo exit 2 | `hooks/gate-mensagem-commit.cjs:148-175` não desmonta flag curta agrupada; `achaGitCommit` segmenta sem mascarar heredoc, e `mascararCorposDeHeredoc` só existe dentro de `gate-staging-total.cjs:312-337` | M | `gate-mensagem-commit.cjs`, `hooks/lib/heredoc.cjs`, `gate-staging-total.cjs`, baterias |
| 261 | não na forma literal; com comando composto (`git -C x add f && bash -c "$(...)"`) a mensagem cai no `cwdDoEvento` | resíduo do segundo sintoma da #258: `dirC = null` no ramo `incerto` (`gate-staging-total.cjs:504-507`), intocado pelo #271 | P | `gate-staging-total.cjs`, `testa-gate-staging-total.sh` |
| 281 | sim — `de:` em prosa, `pulada`, exit 0 | ✔ `scripts/conferir-fluxo.cjs:812-839`: só `exit === 2` marca `algumSobreviveu`; 1/3/4/5 imprimem `pulada` e fecham 0 | P | `conferir-fluxo.cjs`, `testa-conferir-fluxo.sh` |
| 254 | sim, duas causas | (a) = #281; (b) `conferir-fluxo.cjs:748` tira só a crase das pontas, `` `cmd` (tarefa 6) `` vira comando quebrado | P | idem + `skills/plano/SKILL.md` |
| 270 | sim — 5 linhas `  FALHA` de mutante com placar `284/0` | `hooks/testa-contexto-sessao.sh:122-132` (`checa`) imprime o mesmo rótulo na sabotagem; ✔ `checa()` existe em mais 9 baterias | M | `testa-contexto-sessao.sh` (+ as baterias com sabotagem) |
| 266 | sim — mutante visível no disco ~4,8 s; aconteceu ao vivo num worktree de medição | `scripts/conferir-mutacao.cjs:374-497` escreve no fonte real e só restaura depois da bateria; `testa-limpar-branches.sh:484-498` faz `cp` sobre o fonte do repo | M | `conferir-mutacao.cjs`, `varrer-baterias.sh`, `testa-limpar-branches.sh` |
| 269 | sim — `--saida <caminho>` aceito como texto | `gate-fechar-issue.cjs:589,630` dita a forma errada; `fechar-issue.cjs:107-108` não valida | P | `gate-fechar-issue.cjs`, `fechar-issue.cjs`, baterias |
| 268 | sim — mensagem sem `setup.cjs --desligar` | `gate-publicacao-destino.cjs` `mensagemBloqueio` (:348-360); hunk pronto em `2b86da3f` (branch não mergeada) | P | `gate-publicacao-destino.cjs`, bateria |
| 265 | mecanismo sim; ponta a ponta barrado pela #289 | três `rev-parse --show-toplevel` em `gate-publicacao-destino.cjs:555,634,658`; `.rainforest-gate-off` fora do `.gitignore` | P | `gate-publicacao-destino.cjs`, `.gitignore`, bateria |
| 262 | ✔ sim — chave JSON entre aspas sai exit 0, a mesma chave sem aspas sai exit 2 | `scripts/conferir-publicacao.cjs:239`: `\s*[:=]` não admite a aspa que fecha a chave | P | `conferir-publicacao.cjs`, `testa-conferir-publicacao.sh` |
| 272 | ✔ sim — `null` por stdin, exit 1 nos dois | `hooks/titulo-sessao-end.cjs:148`, `hooks/heartbeat.cjs:51`: `JSON.parse("null")` não lança | P | os dois hooks + baterias |
| 276 | ✔ sim — só `hooks/portaria.cjs` cita `despachos.jsonl` | escrita em `portaria.cjs:538`, nenhum leitor | M | `scripts/saude.cjs`, `testa-saude.sh` |
| 277 | sim — `foco.cjs` só tem `rotacionar/separar/backup/caminho` | `foco.cjs:394-410` corta avanço por parágrafo; a regra 17 já admite append manual de uma **linha**, que o corte por parágrafo engole | M | `scripts/foco.cjs`, `testa-foco.sh` |
| 287 | sim — worktree de branch com barra sobrevive, controle sem barra é removido | ✔ `scripts/limpar-branches.cjs:156,159,199`: regex no `basename` de caminho de dois níveis | P | `limpar-branches.cjs`, `testa-limpar-branches.sh` |
| 279 | sim | ✔ `conferir-fluxo.cjs:514-525` `globs_isentos` não cobre `reguas/` nem `skills/*/references/`; `extrairArquivos` dá `break` e não lê a segunda `### N.` de uma emenda | P/M | `conferir-fluxo.cjs`, `skills/revisar/SKILL.md` |
| 273 | raro — 1 falha em ~100 runs (8173 ms ≥ 8000) | ✔ `scripts/testa-cli-externo.cjs:123`; local já chega a 6412 ms | P | `testa-cli-externo.cjs` |
| 250 | a conta da issue está errada; o risco é real (7991 B de 8000 hoje) | `LEGENDA_MAX_BYTES` é outro canal (`systemMessage`); o que estoura é cabeçalho+rodapé sem teto (`contexto-sessao.cjs:1137`) | M | `hooks/lib/contexto-sessao.cjs`, `testa-orcamento.sh` |
| 282 | consertada (PR #283): `claude.cmd` resolve para o `.exe`, bateria 5/5 | sub-pedido aberto: `/saude` olha a pendência mais nova (`saude.cjs:1136-1150`), não a mais antiga — inferido, sem o banco real | P | `scripts/saude.cjs` |

Achado lateral, aberto como **#289**: `gate-worktree` barra `cd /c/.../scratchpad/repo && git commit`
(exit 2) e deixa passar `git -C` no mesmo caminho (exit 0), chamando o worktree linkado de "principal".

## Decisões fechadas

- **D1 — O `fechar-issue.cjs` deixa de exigir `--confirmo`; o comentário com comando e saída continua obrigatório** — porquê: o usuário recusou digitar frase para fechar Issue cujo conserto o fluxo entregou ("o fechar devia ser o resultado natural"), e Issue reabre, então a premissa de irreversibilidade da D3 do plano `absorver-plugin-terceiro` (commit `64a0ce21`) não vale para ela. A frase fica para apagar branch e worktree sujo. O marcador de evidência fica porque é o que impede fechar Issue com PR vazio (D15–D17 do `gate-fechar-issue`).

## Avaliado e descartado

- **Invariante da #250 `NUCLEOS + LEGENDA + SESSOES + FOCO_MIN <= ORCAMENTO`** — soma bytes de dois canais diferentes, e passaria (7000 ≤ 8000 sem a legenda) com a injeção real estourando, porque o que estoura é o texto fixo sem teto.
- **Sugestão 2 da #265 (o setup acrescenta ao `.gitignore` ao criar o arquivo)** — o `setup.cjs` nunca cria `.rainforest-gate-off`; não há onde enxertar.

## Fora de escopo

- O resto da branch `fluxo/gate-publicacao-remotes-protegidos` (`2b86da3f`): duplica a #253, já entregue na rodada 4. Só o hunk da mensagem da #268 é aproveitado.

## Em aberto

- Rodada 2 do brainstorm: fechamento automático no `fechar`, escopo e ondas, e as escolhas de #266, #273, #250, #276, #277, #254 (b/c), #282 (sub-pedido) e #289.
