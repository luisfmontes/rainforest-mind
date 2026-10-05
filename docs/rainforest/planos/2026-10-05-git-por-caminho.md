# Plano: git e gh pelo caminho, não pelo nome (#392)

Design: docs/rainforest/design/2026-10-05-git-por-caminho.md

## O que não pode quebrar
- Toda bateria que hoje passa continua passando; as que injetam gh falso por `RAINFOREST_GH`/`RFM_VARRER_GH` ou por PATH continuam medindo o falso.
- `executar()` de `hooks/lib/resolver-executavel.cjs` mantém o contrato atual (`.cmd` primeiro, recusa de metacaractere), só herda o filtro de D1.
- Quem trata `ENOENT` de git ausente (ex.: `preparar-worktree.cjs` sai 69) segue recebendo `ENOENT`.

## Tarefas

### 1. helper caminhoExecutavel e bateria testa-git-por-nome [tipo: implementar]
atende: D1, D2, D6, D7
arquivos: `hooks/lib/resolver-executavel.cjs`, `scripts/testa-git-por-nome.sh`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-git-por-nome.sh`
mutacao:
  arquivo: `hooks/lib/resolver-executavel.cjs`
  de: `.filter(d => d && path.isAbsolute(d))`
  para: `.filter(d => d)`
  bateria: `bash scripts/testa-git-por-nome.sh`
  fixture: `testa-git-por-nome.sh, caso "PATH com . na frente nao resolve pela pasta atual"`
pronto quando: com o PATH real do processo e com um PATH montado na caixa de areia, `caminhoExecutavel("git")` devolve o `git.exe` absoluto do PATH; com `.` na frente do PATH e um `git.exe` falso na pasta atual, nem `resolverExecutavel` nem `caminhoExecutavel` devolvem o falso; com `x.cmd` antes de `x.exe` no PATH, `caminhoExecutavel("x")` devolve o `.exe`; com nome ausente, `spawnSync(caminhoExecutavel("nao-existe-xyz"))` dá `error.code === "ENOENT"` e o caminho devolvido é absoluto. Os dois resolvedores leem o PATH por uma única função com o filtro literal `.filter(d => d && path.isAbsolute(d))`; a memória é por nome + PATH. A bateria também tem a varredura de D6 (imprime cada linha ofensora como `arquivo:linha: trecho` e falha se houver alguma; ignora `testa-*`, `*.test.*`, linha de comentário e o próprio `resolver-executavel.cjs`), três casos que provam que a varredura acende (argumento literal, `execSync("git ...")`, `|| "gh"`) num arquivo temporário, e o caso de entrada real de D7 (pasta temporária com `git.exe` = cópia do `whoami.exe`, `NoDefaultCurrentDirectoryInExePath` removida do ambiente: `spawnSync("git")` por nome ali imprime o usuário do `whoami` — prova de que o falso está ao alcance — e `node scripts/conferir-versao.cjs` com a pasta atual ali não imprime). Provado por `bash scripts/testa-git-por-nome.sh`: os casos do helper e os três da varredura saem ok; a varredura do repo e o caso de entrada real ficam vermelhos até as tarefas 2–6 entrarem, listando só arquivos delas

### 2. hooks gate-* e portaria pelo caminho [tipo: implementar]
atende: D3
arquivos: `hooks/gate-worktree.cjs`, `hooks/gate-staging-total.cjs`, `hooks/gate-repo-alheio.cjs`, `hooks/gate-mensagem-commit.cjs`, `hooks/gate-git-verificacao.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/gate-verificador-staged.cjs`, `hooks/gate-subagente-sem-gh.cjs`, `hooks/gate-agente-em-voo.cjs`, `hooks/veredito-revisor.cjs`, `hooks/portaria.cjs`
depende de: 1
paralela: sim
prova: `bash scripts/testa-git-por-nome.sh`
mutacao:
  arquivo: `hooks/gate-worktree.cjs`
  de: `execFileSync(caminhoExecutavel("git"), ["-C", dir, ...args]`
  para: `execFileSync("git", ["-C", dir, ...args]`
  bateria: `bash scripts/testa-git-por-nome.sh`
  fixture: `testa-git-por-nome.sh, varredura do repo (linha de hooks/gate-worktree.cjs)`
pronto quando: com o repositório do plugin, a varredura de `bash scripts/testa-git-por-nome.sh` não lista nenhuma linha destes 11 arquivos, e cada bateria que os exercita (`grep -lE "<nome-do-arquivo>" hooks/testa-* scripts/testa-*`) sai 0 com o placar colado; `hooks/gate-worktree.cjs` tem a forma literal `execFileSync(caminhoExecutavel("git"), ["-C", dir, ...args]`

### 3. libs de hooks, publicação e varrer pelo caminho [tipo: implementar]
atende: D3, D4, D5
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/lib/principal-atrasado.cjs`, `hooks/lib/cwd-efetivo.cjs`, `hooks/lib/estagio-ativo.cjs`, `scripts/varrer.cjs`
depende de: 1
paralela: sim
prova: `bash scripts/testa-git-por-nome.sh`
mutacao:
  arquivo: `hooks/lib/cwd-efetivo.cjs`
  de: `execFileSync(caminhoExecutavel("git"), ["rev-parse", "--show-toplevel"]`
  para: `execFileSync("git", ["rev-parse", "--show-toplevel"]`
  bateria: `bash scripts/testa-git-por-nome.sh`
  fixture: `testa-git-por-nome.sh, varredura do repo (linha de hooks/lib/cwd-efetivo.cjs)`
pronto quando: com o repositório do plugin, a varredura não lista linha destes 5 arquivos; `estagio-ativo.cjs` não tem mais `execSync` de string com git; com `RAINFOREST_GH="node <stub>"` o gate de publicação ainda chama o stub (bateria `hooks/testa-gate-publicacao-destino.sh` sai 0), e sem a variável chama `caminhoExecutavel("gh")` sem `.split(" ")` no caminho; com `RFM_VARRER_GH` o varrer chama o stub (bateria do varrer sai 0); cada bateria que exercita estes arquivos sai 0 com o placar colado

### 4. limpar-branches e limpar-worktrees pelo caminho [tipo: implementar]
atende: D3, D9
arquivos: `scripts/limpar-branches.cjs`, `scripts/limpar-worktrees.cjs`
depende de: 1
paralela: sim
prova: `bash scripts/testa-git-por-nome.sh`
mutacao:
  arquivo: `scripts/limpar-worktrees.cjs`
  de: `spawnSync(caminhoExecutavel("git"), ["worktree", "prune"]`
  para: `spawnSync("git", ["worktree", "prune"]`
  bateria: `bash scripts/testa-git-por-nome.sh`
  fixture: `testa-git-por-nome.sh, varredura do repo (linha de scripts/limpar-worktrees.cjs)`
pronto quando: com o repositório do plugin, a varredura não lista linha destes 2 arquivos, e `bash scripts/testa-limpar-branches.sh` e `bash scripts/testa-limpar-worktrees.sh` saem 0 com o placar colado

### 5. estado, setup, régua, versão e prova pelo caminho [tipo: implementar]
atende: D3, D4, D7
arquivos: `scripts/estado.cjs`, `scripts/setup.cjs`, `scripts/conferir-regua.cjs`, `scripts/conferir-versao.cjs`, `scripts/conferir-prova.cjs`
depende de: 1
paralela: sim
prova: `bash scripts/testa-git-por-nome.sh`
mutacao:
  arquivo: `scripts/conferir-versao.cjs`
  de: `execFileSync(caminhoExecutavel("git"), ["rev-parse", "--show-toplevel"]`
  para: `execFileSync("git", ["rev-parse", "--show-toplevel"]`
  bateria: `bash scripts/testa-git-por-nome.sh`
  fixture: `testa-git-por-nome.sh, caso de entrada real (conferir-versao com git.exe falso na pasta atual) e varredura do repo`
pronto quando: numa pasta temporária com `git.exe` falso (cópia do `whoami.exe`) e `NoDefaultCurrentDirectoryInExePath` fora do ambiente, `node scripts/conferir-versao.cjs` com a pasta atual ali não imprime o usuário do `whoami` (caso de entrada real da bateria ok); a varredura não lista linha destes 5 arquivos; `estado.cjs` e `setup.cjs` não têm mais `execSync` de string com git; `bash scripts/testa-estado.sh`, `bash scripts/testa-setup.sh`, `bash scripts/testa-versao.sh` e as baterias da régua e da prova saem 0 com o placar colado

### 6. demais scripts pelo caminho [tipo: implementar]
atende: D3
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/conferir-duplicacao.cjs`, `scripts/semear.cjs`, `scripts/segunda-opiniao.cjs`, `scripts/preparar-worktree.cjs`, `scripts/fechar-issue.cjs`, `scripts/faixa-dados.cjs`, `scripts/conferir-publicacao.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/conferir-entrega.cjs`, `scripts/conferir-encoding.cjs`, `scripts/conferir-comparacao.cjs`, `scripts/conferir-categoria.cjs`, `scripts/testa-conferir-fluxo.sh` (âncora de sabotagem que copia a linha do `conferir-fluxo.cjs`)
depende de: 1
paralela: sim
prova: `bash scripts/testa-git-por-nome.sh`
mutacao:
  arquivo: `scripts/preparar-worktree.cjs`
  de: `spawnSync(caminhoExecutavel("git"), args,`
  para: `spawnSync("git", args,`
  bateria: `bash scripts/testa-git-por-nome.sh`
  fixture: `testa-git-por-nome.sh, varredura do repo (linha de scripts/preparar-worktree.cjs)`
pronto quando: com o repositório do plugin, a varredura não lista linha destes 13 arquivos; `preparar-worktree.cjs` fora de repositório git continua saindo 69 com `nao-verificavel`; cada bateria que exercita estes arquivos sai 0 com o placar colado

### 7. versão 1.39.3 [tipo: docs]
atende: D8
arquivos: `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3, 4, 5, 6, 8
paralela: nao
mutacao: n/a
  motivo: nota de versão e bump não têm comportamento a inverter; a falsificação é a coerência da nota com D1–D7
pronto quando: com o repositório integrado, a entrada 1.39.3 do CHANGELOG descreve o que D1–D7 decidiram (filtro de PATH relativo, extensões do libuv, caminho inexistente em vez do nome, troca de `execSync`, desvios de teste mantidos, bateria nova) e cita a #392; as três versões dizem 1.39.3 — provado por `bash scripts/testa-versao.sh` e `node scripts/conferir-versao.cjs`

### 8. baterias que copiam fonte levam o resolvedor [tipo: teste]
atende: D10
arquivos: `scripts/testa-limpar-branches.sh`, `scripts/testa-estado.sh`, `scripts/testa-ponte.sh`, `scripts/testa-ponte-entrevista.sh`, `scripts/testa-setup.sh`, `scripts/testa-conferir-versao.sh`, `scripts/testa-semear.sh`, `scripts/testa-conferir-publicacao.sh`, `hooks/testa-portaria-nucleo.cjs`
depende de: 1
paralela: nao
prova-na-base: verde — na base nenhum fonte faz require do resolvedor, então a cópia sem ele não quebra; a falha só existe depois das tarefas 2–6
mutacao: n/a
  motivo: a tarefa só acrescenta um arquivo à lista de cópia de fixture; inverter é tirar a linha, e o efeito (MODULE_NOT_FOUND) já foi medido antes do conserto: 56 falhas em testa-limpar-branches.sh e 3 na seção 15 de testa-portaria-nucleo.cjs
pronto quando: com as tarefas 2–6 integradas, cada bateria listada sai 0 rodando o fonte copiado — provado por `bash`/`node` de cada uma, com o placar
