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
