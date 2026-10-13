# Recusas da cobertura (#397)

`node scripts/conferir-fluxo.cjs cobertura` recusa o plano que o `executar` não
consegue consumir — antes, ele passava e a falha só aparecia no despacho:

- Ciclo no `depende de:`, ou `depende de:` citando tarefa que não existe: não há
  ordem de camadas possível.
- Duas tarefas da mesma camada com caminho em comum em `arquivos:` (um glob que casa
  o literal da outra conta como comum): os dois worktrees editam o mesmo arquivo e a
  integração vira conflito. Se uma das duas declara `paralela: nao`, sai só aviso
  (plano antigo, que serializava à mão).
- `tipo` fora do vocabulário da skill.
- Chave desconhecida antes do `pronto quando:` (rótulo de até três palavras seguido
  de `:`): costuma ser campo digitado errado que o leitor ignora em silêncio.
- `arquivos:` com caminho absoluto ou com `..` como segmento.
- `de:` do bloco `mutacao:` que casa **mais de uma vez** no `arquivo:` — a catraca
  sairia 4 sem medir. Zero ocorrências só **avisa**: é o código que a tarefa vai
  criar.

Cabeçalho `teto-despachos:` ilegível no plano: a cobertura recusa (exit 2), como o hook (valor aceito):
`references/teto-despachos.md`.

`paralela:` não é mais exigido; as camadas saem do `depende de:`
(`conferir-fluxo.cjs camadas`). `paralela: sim` com `depende de:` não vazio só avisa.
