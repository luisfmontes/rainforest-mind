# Validação real do runtime Codex — tarefa 8

Este arquivo foi criado pelo Codex CLI, despachado como agente `executor`
do rainforest-mind via `scripts/despachar-codex.cjs` (sandbox
`workspace-write`), em 2026-09-08. O commit é da ponte.

## Evidência colhida pela sessão despachante (tarefa 8)

Duas rodadas. A primeira derrubou a D5 do design: o Codex criou o arquivo mas
`git add` falhou com `fatal: Unable to create '<repo>/.git/worktrees/<wt>/index.lock':
Permission denied`, mesmo com `--add-dir <repo>/.git`. Reproduzido fora do
agente com `--add-dir` no gitdir exato do worktree: mesma falha; a ACL do gitdir
traz `DENY (W,D,Rc,DC)` para os SIDs do sandbox. Correção na branch: a flag saiu
do script e o commit passou para a ponte (commit `4e8efa1`). A segunda rodada é
a que vale abaixo.

### (a) `git log -1` do worktree, commit do que o Codex deixou

```
a36866652495449697af5e70e86b57fcc1af74da Luís Fernando Montes executor via codex: validacao T8 do runtime codex
 docs/rainforest/relatorios/2026-09-08-validacao-runtime-codex.md | 5 +++++
pai: 7913b7d Merge pull request #217 from luisfmontes/fluxo/contrato-de-territorio-advpl
```

Worktree `.claude/worktrees/agent-ae101c13177e52f82` (nascido da `origin/main`).
O arquivo (as cinco primeiras linhas deste) veio pelo Codex; o commit, pela
ponte, como o preâmbulo manda. Integrado aqui por `git cherry-pick`.

### (c) linha `comando:` do stderr do despacho, sem `CODEX_CMD` no ambiente

```
comando: codex exec -s workspace-write --skip-git-repo-check -C "<repo>/.claude/worktrees/agent-ae101c13177e52f82" -c approval_policy="never" -o "<home>\AppData\Local\Temp\despachar-codex-<pid>-<ts>.txt"
```

(Os dois caminhos absolutos foram abreviados aqui; o original tem a raiz do
repositório e a pasta temporária do usuário.) Exit 0. Saída do Codex confirmou
`git rev-parse --show-toplevel` no worktree certo, `git log -1 --format=%h` =
`7913b7d`, `git status --short` = `?? docs/rainforest/relatorios/` e o conteúdo
do arquivo byte a byte.

### (d) linha de `despachos.jsonl` com `"runtime":"codex"`

A portaria viva desta sessão é a do checkout principal (o hook de projeto
aponta para `CLAUDE_PROJECT_DIR`), anterior à branch: a linha que ela gravou
no despacho real saiu sem o campo. A prova é o hook **da branch** rodado
contra o mesmo payload real (`tool_input.subagent_type`, `prompt` com
`Runtime: codex` na primeira linha, `isolation: "worktree"`, `cwd` do worktree):

```
{"ts":"2026-09-08T15:40:43.048Z","agente":"executor","estagio":"executar","decisao":"allow","sessao":"eeb30ae9-manual-t8","isolation":"worktree","runtime":"codex"}
```

Exit 0, stdout vazio (allow). Ao vivo, a linha passa a sair assim depois do
merge, com o principal na `main`.

### (b) parecer do `revisor` em Codex

Colhido no estágio `revisar`, em duas rodadas.

**Rodada 1** — briefing com o diff inteiro da branch (36 arquivos) e cinco
baterias para rodar: estourou o teto de 10 minutos (D6). Saída literal da
ponte: stdout vazio, stderr `timeout apos 600000 ms`, exit 124. O processo
`codex` foi morto (nenhum órfão em `tasklist`) e o `-o` temporário não ficou.
Lição registrada na emenda do design: revisão em Codex se fatia por arquivo,
e sem bateria, porque o sandbox `read-only` também nega escrita em temp.

**Rodada 2** — fatia: `scripts/despachar-codex.cjs` e
`hooks/gate-review-codex.cjs`, só leitura. Exit 0 em cerca de 4 minutos.
Comando (caminhos abreviados): `codex exec -s read-only --skip-git-repo-check
-C "<worktree>" -c approval_policy="never" -o "<home>\AppData\Local\Temp\despachar-codex-<pid>-<ts>.txt"`.
Parecer literal, resumido linha a linha:

```
PARECER: REPROVADO
1. CRÍTICO — transcript ausente ou ilegível libera o encerramento (gate-review-codex.cjs:139-148, process.exit(0)).
2. AVISO — o briefing temporário do gate vaza: process.exit dentro do try pula o finally
   (evidência: node -e "try { process.exit(0) } finally { console.log('x') }" não imprime).
3. AVISO — --agente permite escapar de agents/ (`--agente ../segredo` → <repo>/segredo.md).
4. AVISO — a limpeza do -o temporário não cobre falha de leitura/remoção nem exceção em main().
CONFIRMADO — sem defeito nos caminhos com espaço (-C e -o entre aspas); exit ≠ 0 propagado;
status null → 124; flag desconhecida → exit 1; JSON {"decision":"block","reason":...}.
LACUNA — não observou ALLOW/BLOCK de ponta a ponta (sandbox read-only proíbe escrever temp).
```

Os quatro achados foram reproduzidos pelo revisor com comando e saída, dois
deles coincidindo com o revisor em Claude (transcript ausente; `-o`
temporário). Todos corrigidos nesta branch no próprio `revisar`.

## Ao vivo com o plugin 1.8.0 instalado (fluxo `validar-ponte-codex-ao-vivo`, 2026-09-08)

Sem atalho: `executor` do cache `~/.claude/plugins/cache/.../1.8.0`, portaria
viva do checkout principal na `main`, sessão em worktree.

**Tentativa 0** — branch `fluxo/2026-09-08-validar-...` foi negada pela portaria
("sem estágio ativo — estágio resolvido: ?"): a portaria casa a branch com o
slug **sem a data**. Renomeada para `fluxo/validar-ponte-codex-ao-vivo`.

**Rodada (i), como o D2 mandava: briefing só com `Runtime: codex`.**
Portaria viva: `{"ts":"2026-09-08T20:43:38.899Z","agente":"executor","estagio":"executar","decisao":"allow",...,"isolation":"worktree","runtime":"codex"}` — (b) provado.
Mas o agente **ignorou o preâmbulo** que estava no próprio system prompt dele
(55 ocorrências de `ponte-codex` no transcript do subagente) e fez a tarefa
ele mesmo: 9 chamadas de ferramenta (`PowerShell`, `Write`, `Bash cat`),
**zero** ocorrências de `despachar-codex`, arquivo criado sem commit, e um
relatório que dizia "criado pelo Codex". (a) e (c) **reprovados**. O
preâmbulo sozinho não segura um haiku.

**Rodada (ii), com o bloco de ponte no briefing** (o mesmo que funcionou na
T8; agora fixado em `regra-10-runtime.md` e exigido por `modo-dev` e
`executar`). Portaria viva: mesma linha, `"runtime":"codex"` às 20:48:36Z.
Transcript do subagente: 6 ocorrências de `despachar-codex`, a chamada
`node .../scripts/despachar-codex.cjs --agente executor ...` entre as 9
ferramentas. Saída literal do despacho, colada pela ponte:

```
comando: codex exec -s workspace-write --skip-git-repo-check -C "<repo>/.claude/worktrees/agent-add63783023861074" -c approval_policy="never" -o "<home>\AppData\Local\Temp\despachar-codex-<pid>-<ts>.txt"
git rev-parse --show-toplevel → C:/Projetos/rainforest-mind/.claude/worktrees/agent-add63783023861074
git log -1 --format=%h → 29b67d3
git status --short → ?? docs/rainforest/relatorios/2026-09-08-ponte-codex-ao-vivo.md
exit 0
```

Re-derivado de `git` na sessão despachante, não copiado do relato:

```
$ git log -1 --format='%H %an %s' worktree-agent-add63783023861074
b80da415d57cdb4616f9a2c7a08b4946c7e8b847 Luís Fernando Montes executor via codex: ponte ao vivo 1.8.0
 docs/rainforest/relatorios/2026-09-08-ponte-codex-ao-vivo.md | 5 +++++
```

(a), (b) e (c) provados na rodada (ii). Desvio anotado: o Codex gravou
"agente executor" sem as crases que o objetivo pedia — normalizou o markdown.
O preâmbulo endurecido (passo zero, "entrega inválida") entrou nesta branch e
só se prova na próxima versão instalada; até lá, quem garante é o bloco no
briefing.

## Codex sem cota (fluxo `validar-ponte-codex-ao-vivo`, 2026-09-08)

Medido com o limite de 5 h estourado, a pedido do usuário. Antes da correção:

```
$ echo "Responda apenas: OK" | codex exec -s read-only --skip-git-repo-check -C . -c approval_policy="never" -o semcota-o.txt
exit=1   (sem arquivo -o)
stderr: ... ERROR: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 5:41 PM.

$ node scripts/despachar-codex.cjs --agente revisor --worktree <wt> --escreve false --briefing-file <briefing>
exit=1, stdout vazio, stderr: comando: codex exec ... + banner do Codex + as duas linhas ERROR
```

Fechado, mas a causa ficava na 12ª linha do stderr. Depois da correção
(`hooks/lib/codex-cota.cjs`, exit 75), o mesmo despacho real:

```
comando: codex exec -s read-only --skip-git-repo-check -C "<wt>" -c approval_policy="never" -o "<home>\AppData\Local\Temp\despachar-codex-<pid>-<ts>.txt"
codex sem cota: You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 5:41 PM.
exit=75
```

Baterias: `testa-despachar-codex.sh` caso 11 (15 ok), `testa-transferir-para-codex.sh`
caso 8 (10 ok; com `--json` o erro vem depois de `thread.started`, e sem a
checagem o script devolvia `codex resume` de thread morta),
`testa-gate-review-codex.sh` caso 6b (16 ok; o `reason` cita a causa e a hora).
