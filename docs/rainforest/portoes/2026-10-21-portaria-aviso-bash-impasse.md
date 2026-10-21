# Impasse: portaria fora de repo e aviso de escrita pelo shell (#565, #564)

## Teto da 3ª reprovação (2026-10-21)

A portaria fora de repo (D1, #565) e o aviso na abertura (D2) passaram nas três rodadas sem
regressão. As três reprovações foram do aviso de escrita pelo shell (D3, #564):

- Rodada 1: três baterias vermelhas, commit na mesma chamada passando em silêncio, e o texto do aviso.
- Rodada 2: commit alheio trazido por `pull`, pasta com acento, reaviso do mesmo caminho.
- Rodada 3:
  1. Aviso falso durante `merge`, `pull` ou `cherry-pick` com conflito: o arquivo alheio fica staged.
  2. `--amend` de commit anterior à sessão avisa o código do commit inteiro.
  3. Código criado e commitado na primeira chamada da sessão não avisa (sem foto do HEAD).
  4. Remoção de arquivo rastreado avisa como "código novo".

## Decisão do usuário

"recomendado" à opção A: uma 4ª rodada, com conserto e critério fechado.

- Com `MERGE_HEAD`, `CHERRY_PICK_HEAD` ou `REVERT_HEAD` presente, o hook não avisa, e os caminhos
  vistos entram na foto.
- O `--amend` compara com o hash da entrada anterior do reflog, não com o pai do commit.
- O texto passa a dizer "código novo ou mexido".
- O achado 3 vira limite aceito: fechar exige foto na abertura da sessão, outro hook.
- O revisor só aponta forma de uso real que esteja fora da lista de limites aceitos.

## Teto da 4ª reprovação (2026-10-21)

A rodada 4 fechou o conflito de merge, pull e cherry-pick e o amend de commit antigo. Ficaram três
achados, todos do aviso pelo shell:

1. `rebase` ou `pull --rebase` com conflito, e `merge --squash` de branch alheia, avisam código
   que não é da sessão.
2. `git reset --soft HEAD~N` seguido de `git commit` avisa o código de antes da sessão.
3. O texto "código novo ou mexido" não tinha teste.

## Decisão do usuário (rodada 5)

"recomendado" à opção A: uma 5ª rodada com a regra generalizada.

- Só avisa caminho que difere do HEAD da foto (`git diff --name-only <HEAD da foto>`), mais os
  não rastreados. Isso cobre de uma vez todo rearranjo de commits que já existiam.
- `rebase-merge`, `rebase-apply` e `SQUASH_MSG` entram nas operações alheias em andamento.
- O texto do aviso e a remoção de arquivo rastreado ganham caso na bateria.

## Teto da 5ª reprovação (2026-10-21)

A rodada 5 fechou rebase e squash em conflito, `reset --soft` e o texto. Ficaram quatro achados do
aviso pelo shell:

1. `git reset HEAD~1` (mixed) devolve código de antes da sessão como não rastreado, e ele avisa.
2. `merge --squash` e commit na mesma chamada avisam o código da outra branch.
3. `rebase -i` com squash ou fixup na mesma chamada da edição engole o commit da sessão.
4. `git rm` e commit na mesma chamada não avisam a remoção.

## Decisão do usuário (rodada 6)

"recomendado" à opção A:
- Conserta o 1: arquivo não rastreado com conteúdo igual ao do HEAD da foto não avisa.
- Os achados 2, 3 e 4 viram limites aceitos.
- Conserto do alerta de segurança: o HEAD da foto só vale se for hash hexadecimal, e vai ao git
  depois de `--end-of-options`.
- A 6ª revisão roda só contra a lista de limites aceitos.
