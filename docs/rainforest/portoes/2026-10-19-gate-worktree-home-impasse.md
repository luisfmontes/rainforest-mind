# Impasse: 2026-10-19-gate-worktree-home (#561)

## Rodadas
- Rodada 1 (8 achados) e rodada 2 (3 achados): grafias que a regra não via, consertadas uma a uma.
- Rodada 3 (3 achados): `${U:-~}` não contava como til em posição de expansão; `printf -vHOME` e
  linha que abre com redirecionamento passavam por "linha de comandos inertes", e o til entre
  aspas era mascarado.

## Diagnóstico
A lista de comandos inertes virou lista de grafias, o mesmo defeito que derrubou a #552: cada
revisão acha uma forma de a linha que redefine a casa parecer inerte.

## Decisão do usuário (2026-10-20, "recomendado")
4ª rodada com troca de princípio: linha que **mexe na casa** (menção ao nome fora de leitura, ou
comando definidor) nunca tem as aspas mascaradas; til depois de `-`, `+`, `?` e crase conta como
posição de expansão. `${!n}` (lacuna anterior da rede) e `cd $VAZIA` ficam fora de escopo. Custo
aceito: `git commit -m "ajusta HOME ~30"` dentro de worktree cai.
