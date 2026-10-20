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

## Rodada 4 (3 achados)
- `${X/y/~}` (e `#`, `%`) com a casa redefinida saía 0 e criava arquivo no principal: a lista de
  caracteres antes do til ainda era lista de grafias.
- `HO\<quebra de linha>ME=` escondia o nome, porque a continuação de linha não era desfeita.
- `builtin source` e `builtin .` não contavam como execução indireta.

## Decisão do usuário (2026-10-20, "recomendado")
5ª rodada com a regra de classe: til conta como uso da casa sempre que não vier depois de
caractere de palavra (`\w`) nem de contrabarra. Continuação de linha se desfaz antes de procurar o
nome; `builtin`/`command` antes de `source`/`.` conta como execução indireta. Custo aceito: linha
que mexe na casa ou chama interpretador e tem til fora de palavra (`@~1`) cai.

## Rodada 5 (3 achados + 1 menor)
- Continuação de linha desfeita só do lado do nome: `${HO\<quebra>ME}` e `c\<quebra>d` escapavam.
- Redirecionamento antes de `source` (`>/dev/null source ./x.sh`) escapava; a revisão automática de
  segurança achou o mesmo depois de quebra de linha, `if` e `time`.
- Interpretador por caminho completo com nome montado (fora de escopo já decidido).

## Diagnóstico
O critério 5 do revisor ("procure qualquer linha que passe") não fecha num gate que lê comando por
padrão de texto: os dois últimos lotes são construções para escapar, e o design já diz que a trava
protege contra engano, não contra quem tenta escapar dela.

## Decisão do usuário (2026-10-20, "recomendado")
6ª rodada: todas as checagens rodam sobre o texto com a continuação de linha desfeita; com a casa em
uso, `source`/`.` em qualquer posição de palavra é execução indireta. O critério do revisor se
fecha: contorno só conta se for forma que a sessão escreveria sem intenção de escapar. Nome partido
por continuação de linha dentro de `${...}`/`$NOME`, nome montado por concatenação e interpretador
por caminho completo vão para "Fora de escopo". Custo aceito: linha que usa a casa e tem ` . ` solto
cai.
