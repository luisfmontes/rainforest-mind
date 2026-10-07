# Recusas da cobertura (#397)

`node scripts/conferir-fluxo.cjs cobertura` recusa o plano que o `executar` não
consegue consumir — antes, ele passava e a falha só aparecia no despacho:

- `paralela: sim` com `depende de` diferente de `nenhuma`: a tarefa não pode sair
  na mesma onda de quem ela espera.
- Duas tarefas paralelas com caminho em comum em `arquivos:` (um glob que casa o
  literal da outra conta como comum): os dois worktrees editam o mesmo arquivo e a
  integração vira conflito.
- `tipo` fora do vocabulário da skill.
- Chave desconhecida antes do `pronto quando:` (rótulo de até três palavras seguido
  de `:`): costuma ser campo digitado errado que o leitor ignora em silêncio.
- `arquivos:` com caminho absoluto ou com `..` como segmento.
- `de:` do bloco `mutacao:` que casa **mais de uma vez** no `arquivo:` — a catraca
  sairia 4 sem medir. Zero ocorrências só **avisa**: é o código que a tarefa vai
  criar.
