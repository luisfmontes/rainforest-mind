# Design: gate-worktree fecha para subagente quando o git não responde num repositório

## Objetivo
`estadoDoRepo` (`hooks/gate-worktree.cjs:369`) devolve `null` quando `git rev-parse --git-dir` falha, e os chamadores leem `null` como "fora de repositório: livre". Isso junta dois casos: não é repositório, e o git está ausente ou quebrado. No segundo, a escrita de subagente no checkout principal passa, e o isolamento da regra 11 cai. O segundo defeito está na linha 381: `ehWorktree` procura `/worktrees/` no `--git-dir`, que volta absoluto quando o comando roda de uma subpasta. Um checkout principal em `C:/worktrees/proj` é lido como worktree, e o gate libera a escrita nele. Issue #671, achada no treino de leitura de código do Luís (sessão comms, 2026-11-09). Luís escolheu em 2026-11-09 a opção que fecha só para subagente.

O comentário de `estadoDoRepo` registra a decisão anterior ("trava de segurança não pode derrubar o trabalho por ambiente quebrado"). Ela continua valendo para a janela principal e para fora de repositório.

## Decisões fechadas
- **D1 — Git sem resposta com `.git` acima fecha o gate para subagente, fora de worktree linkado** — porquê: é a escolha do Luís em 2026-11-09. Sem `.git` em pasta nenhuma acima, é fora de repositório de verdade e segue livre. Com `.git` acima, `estadoDoRepo` devolve `{ toplevel: <pasta do .git>, ehWorktree: <.git é arquivo>, gitQuebrado: true }`, e os ramos de subagente barram como barram qualquer escrita fora de worktree. Diretório inexistente segue devolvendo `null`: ali o git falha pelo caminho, não por estar quebrado. Git que falha por outro motivo com `.git` acima (`safe.directory`, `.git/HEAD` corrompido) também fecha: o gate não sabe dizer se ali é worktree.
- **D2 — `.git` arquivo conta como worktree quando o git não responde** — porquê: subagente no próprio worktree continua trabalhando com o git fora do ar, que é o caso comum de ambiente ruim. Submódulo também tem `.git` arquivo e fica livre nesse caso raro; aceito.
- **D3 — A janela principal continua livre** — porquê: a sessão co-locada é a única condição do arquivo que barra a janela principal, e o comentário dela já diz que falha para o lado de liberar por falta de infraestrutura. Com `gitQuebrado`, no `daqui` ou no alvo, o `gateDeSessaoColocada` não barra.
- **D4 — O gate avisa em stderr sempre que o git não responde num repositório** — porquê: trava que muda de comportamento em silêncio é o defeito que o comentário de 2026-08-09 descreve. Uma linha por repositório e por execução, neutra, porque sai antes de saber o desfecho: `[gate-worktree] git não respondeu num repositório (<raiz>); escrita de subagente fora de worktree linkado fica barrada.`
- **D5 — `ehWorktree` compara `--git-dir` com `--git-common-dir`** — porquê: os dois só diferem em worktree linkado, e a comparação não depende do nome das pastas. Saem de uma chamada só (`git rev-parse --git-dir --git-common-dir`), resolvidos contra `dir` e pelo `caminhoReal`, porque um dos dois pode vir relativo ou em nome curto 8.3.
- **D6 — A busca do `.git` vira `acharGitAcima` em `hooks/lib/caminho-real.cjs`, e o `conferir-mutacao.cjs` passa a usá-la** — porquê: o `temGitAcima` de `scripts/conferir-mutacao.cjs:380` já faz essa subida, e o gate precisa dela com um dado a mais (a pasta e se `.git` é arquivo). Devolve `{ dir, ehArquivo }` ou `null`.
- **D7 — Versão PATCH, 2.10.1** — porquê: conserta uma trava existente, sem campo nem comando novo. `docs/travas-mecanicas.md`, CHANGELOG e README acompanham.

## Avaliado e descartado
- Barrar também a janela principal com git quebrado: Luís descartou; derrubaria o trabalho de quem está sozinho no repositório.
- `--path-format=absolute`: só existe a partir do git 2.31, e a comparação por `caminhoReal` não depende da versão.
- Tratar submódulo à parte quando o git não responde: sem git não dá para distinguir de worktree sem ler o conteúdo do `.git`, e o caso é raro.

## Fora de escopo
- Outros usos de `git(...)` no arquivo que caem em "livre" por outro motivo (`toplevelConfinado`, parsers de `-C`).
- `.git` arquivo cujo `gitdir:` aponta para pasta inexistente: conta como worktree, como no D2.

## Varredura
docs/rainforest/varredura/2026-11-09-gate-git-quebrado.txt — a própria #671 e Issues que citam o gate de passagem; nenhuma discute git sem resposta nem `--git-common-dir`. O `deriva --arquivo hooks/gate-worktree.cjs` lista 21 decisões com âncora (14 intactas, 7 com âncora perdida); nenhuma é sobre `estadoDoRepo`.

## Em aberto
- Nada bloqueia. D2, D4 e D5 ficam para veto no PR.
