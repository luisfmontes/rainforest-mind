# Plano: Beads por cima do ideias.jsonl — não acopla

Design: docs/rainforest/design/2026-09-24-beads-por-cima-do-ideias.md

Refeito em 2026-09-24: a primeira versão (8 tarefas, grafo de dependência) foi
descartada pela medição da tarefa de pesquisa, antes de qualquer código entrar;
o executor das tarefas de código foi parado e o trabalho dele descartado.

## O que não pode quebrar
- Nenhum arquivo de código muda; o `ideias.jsonl` real só é tocado pela colheita da ideia, pelo `ideias.cjs colher`, depois do merge.
- O doc de pesquisa, que vai para repositório público, passa no `conferir-publicacao.cjs` sem achado.

## Tarefas

### 1. Medir quanto das ideias abertas é dependência de verdade [tipo: pesquisar]
atende: D1
arquivos: `docs/rainforest/pesquisas/2026-09-24-dependencias-propostas.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: pesquisa; o artefato é a medição, não código.
pronto quando: lendo o `~/.rainforest/ideias.jsonl` real (só leitura), o doc traz o comando reproduzível que seleciona as abertas que citam outra ideia e a saída dele (contagem), cada citação classificada `depende_de` / `irma` / `outro` com o porquê, e as contagens do doc batem com a medição — conferido por `grep -c` das classificações contra a saída colada, e por `node scripts/conferir-publicacao.cjs docs/rainforest/pesquisas/2026-09-24-dependencias-propostas.md --json` devolvendo `achados: []`.

### 2. Registrar o achado no livro de repos [tipo: docs]
atende: D2
arquivos: `vigias/livro-de-repos.md`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: doc; a falsificação é a coerência com D1 e com os números do doc de pesquisa.
pronto quando: a entrada do Beads no `vigias/livro-de-repos.md` diz "não acopla", com os números da tarefa 1 (abertas, citações, 1 bloqueio) e o caminho do doc de pesquisa, no formato das entradas vizinhas — conferido lendo a entrada contra o doc de pesquisa.
