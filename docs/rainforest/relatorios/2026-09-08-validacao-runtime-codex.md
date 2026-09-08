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
