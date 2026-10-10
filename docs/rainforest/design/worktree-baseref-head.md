# Design — worktree do agente nasce do HEAD da sessão (`worktree.baseRef: "head"`)

Data: 2026-10-10. Enxerto A da comparação do `executar` com o orquestrador do
plugin `wildz-data` (Rafael Siqueira), decidido pelo Luís em 2026-10-09.

## Problema

A regra 11 trata como comportamento fixo do harness que o worktree de
`isolation: "worktree"` nasce na ponta de `origin/main`, não no commit de
trabalho. Daí o hash da base no briefing ser o de `origin/main`, o
`merge --ff-only origin/main` antes de despachar e o `preparar-worktree.cjs`
fazendo fast-forward dentro do worktree do agente. Dois incidentes de base
errada (2026-08-07, 2026-08-23) vieram dessa distância entre o commit de
trabalho e a base do agente.

## Fato medido

A chave existe no CLI instalado. A descrição do `EnterWorktree` diz: "The
base ref is governed by the `worktree.baseRef` setting: `fresh` (default)
branches from origin/<default-branch>; `head` branches from your current local
HEAD". O plugin do Rafael documenta o mesmo para `isolation: worktree` de
subagente (`skills/execute/SKILL.md` §3b).

## Decisões

- **D1. A chave é configuração do usuário, não do plugin.** Gravada em
  2026-10-10 nas duas `settings.json` (`~/.claude` e `~/.claude-personal`),
  com backup `settings.json.bak-baseref-20261010`. Plugin não escreve settings
  (regra 15).
- **D2. O texto do plugin passa a ser condicional à chave**, não a supor. Com
  `head`, a base do agente é o HEAD **do diretório da sessão** que despacha, e
  o hash do briefing é `git rev-parse HEAD` desse diretório. Com `fresh` (ou
  chave ausente, que é o padrão de quem instala o plugin), continua valendo o
  texto atual (`origin/main` + `--ff-only`).
- **D3. A conferência de base não sai.** `preparar-worktree.cjs --hash` e
  `conferir-entrega.cjs --base` continuam obrigatórios: a chave muda **qual**
  hash se espera, não a necessidade de conferir. Um setting em outro escopo
  (managed/projeto) pode sobrepor o do usuário.
- **D4. "HEAD da sessão" depende de onde a sessão está.** A sessão que
  despacha do checkout principal (na `main`) dá ao agente a `main`, não a
  branch de trabalho. A regra 11 já manda a sessão trabalhar no worktree; o
  texto passa a dizer que é **isso** que faz o agente nascer na branch de
  trabalho com `head`.

## Critério de pronto

1. Medição: de dentro deste worktree, com um commit que só existe em
   `fluxo/worktree-baseref-head`, um agente com `isolation: "worktree"` relata
   `git rev-parse HEAD` igual a esse commit (com `head`), e não a
   `origin/main`. Se não bater nesta sessão, repetir numa sessão nova
   (settings lidas na abertura) antes de concluir.
2. `regra-11.md` e `skills/executar/SKILL.md` descrevem os dois modos, e
   `grep -n "baseRef" skills/rainforest-mind/references/regra-11.md skills/executar/SKILL.md`
   devolve ao menos uma linha em cada.
3. `bash scripts/varrer-baterias.sh` sai 0.

## Fora do escopo

Painel, effort dos agentes (enxerto B, fluxo próprio), veredito em JSON (C),
laço de iteração (D).
