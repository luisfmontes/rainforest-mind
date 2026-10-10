# Pendências e destinos

Uma tarefa que fecha `parcial` deixa pendência nomeada no `--json`
(ex.: `"pendentes":["tarefa-3: worktree nao respondeu"]`).

Para fechar `ok`, cada pendência precisa de um destino em `destinos`, casado pelo texto exato da pendência:

- `resolvida` com `evidencia` (o que foi rodado e o que saiu);
- `plantada` com `ref` (`#<n>`, URL de issue do GitHub ou `ideia:<id>`);
- `descartada` com `motivo`.

Exemplo: `--json '{"destinos":[{"pendente":"tarefa-3: worktree nao respondeu","destino":"resolvida","evidencia":"rodou de novo: 3 de 3 ok"},{"pendente":"tarefa-6: falta rodar","destino":"plantada","ref":"https://github.com/alfa/beta/issues/449"}]}'`.

O `ok` sem destino sai 2 listando as pendências que faltam e não grava. Um `parcial` que omite uma pendência anterior avisa em stderr e a mantém em `pendentes`; só um destino a tira. O `destinos` acumula entre chamadas e fica no estado para o `fechar` ler. Listar de novo em `pendentes` uma pendência que já tinha destino apaga esse destino e ela volta a pendente (aviso em stderr), salvo se o mesmo `--json` trouxer o destino dela: num `parcial`, mande só as pendências que continuam abertas. Para destinar num estágio já fechado, use `node scripts/estado.cjs destinar`.
