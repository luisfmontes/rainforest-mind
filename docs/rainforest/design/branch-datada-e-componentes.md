# Issues #645 e #648: branch com slug datado e componentes React no `complexas`

## Objetivo
Fechar as duas Issues abertas. Delegação do usuário ("resolve as issues de forma
automática"): as decisões abaixo são as recomendadas da sessão, para veto no PR.

## Decisões fechadas
- **D1 — #645: o código passa a aceitar a branch com o slug inteiro (`fluxo/<AAAA-MM-DD-tema>`), além do slug sem a data; a receita da regra 11 não muda** — porquê: a receita (`-b fluxo/<slug>`) e o `brainstorm` (slug `<AAAA-MM-DD-tema>`) produzem juntos a branch datada, e as duas fontes estão certas sozinhas. Trocar o texto da receita (a proposta da Issue) põe a ressalva em um lugar e deixa os outros quatro que dizem `fluxo/<slug>` (`regra-11-principal.md`, `paralelo-fora-de-repo.md`, `regra-11-atividade.md`, `executar/SKILL.md`) apontando para o erro, e mexe nas três baterias de teto. Aceitar as duas formas fecha a classe sem tocar texto injetado. Ambiguidade continua negando como antes: a forma datada só casa com o próprio arquivo, então não cria candidato novo para branch sem data.
- **D2 — #645: o casamento slug × branch vira uma função só (`casaSlugComBranch` em `hooks/lib/estagio-ativo.cjs`), usada pelo `resolver`, pelo `diagnosticar`, por `caminho-leve.cjs` e pelo `/saude`** — porquê: hoje são quatro cópias, e a #207 já foi uma cópia divergente do resolvedor com bateria verde. Medido: a cópia do `/saude` (`scripts/saude.cjs:175`) compara o slug com a branch **com** o prefixo `fluxo/`, então o aviso "ESTA branch tem dono" nunca dispara numa branch `fluxo/<slug>`. Entra no PR por ser o mesmo defeito (regra 6).
- **D3 — #648 (média): a regra `topo` de JS aceita anotação de tipo antes do `=` e, depois dele, `function`, `memo(`, `forwardRef(` (com `React.` e genérico opcionais)** — porquê: é o conserto que a Issue propõe; sem ele, o `complexas` e o `listar` da duplicata semântica não veem os componentes de um projeto Next.js. A anotação aceita `=>` dentro do tipo (`const f: (a: T) => void = (a) => {`). Atinge também o hook `aviso-duplicata`, que usa a mesma regra: a bateria `hooks/testa-aviso-duplicata.sh` roda.
- **D4 — #648: no `acharCorpo`, o `(` da chamada envolvente (`memo(`, `forwardRef(`, com genérico ou não) é transparente** — porquê: sem isso, a função de dentro fica em parênteses, o corpo vira o trecho até o `;` inteiro e a `{` dela aprofunda tudo em 1.
- **D5 — #648 baixo 1: a trava de "corpo passou por" vale para qualquer definição com recuo menor ou igual ao da mãe, não só coluna zero** — porquê: método de classe tem o mesmo recuo do vizinho; função aninhada de verdade tem recuo maior.
- **D6 — #648 baixo 2: o `)` que fecha a condição de `if`/`while`/`for` admite regex depois dele** — porquê: `if (s) /[}]/.test(s)` hoje vira divisão e a `}` da classe fecha o corpo cedo.
- **D7 — #648 baixo 3: depois de `}`, a `/` só abre regex quando é a primeira ficha da linha** — porquê: regex depois de `}` na mesma linha é raríssimo em código; `{page}/{pages}` em texto JSX é comum. Instrução nova começando com regex na linha seguinte continua lida como regex.
- **D8 — #648 baixo 4: estrutura de controle sem chave (`if (x) return`) deixa de estar pendente na quebra de linha que encerra a instrução do corpo** — porquê: hoje a `{` de objeto na instrução seguinte aprofunda e superconta 1. "Encerra" usa o mesmo critério do corpo `=> expr`: nada aberto, a linha não termina em operador e a seguinte não começa com um.
- **D9 — #648 baixo 6: `const x = (` cujo `)` não é seguido de `=>` nem de `:` não é função e sai sem medida e sem aviso; sobrecarga TS sem `;` termina na quebra de linha antes de `function`/`export`, como a com `;`** — porquê: os dois casos hoje acabam em "leitura errada", e o rótulo diz defeito da leitura onde a linha nem é unidade.
- **D10 — #648 baixo 5: a bateria `scripts/testa-catalogo-funcoes.sh` ganha caso para cada ficha depois de `}` que faz tipo literal (`{`, `|`, `&`, `[`) e para a troca de mãe (`mae = null`)** — porquê: é o pedido da Issue.
- **D11 — Entrega: um PR, bump de patch para 2.5.1 e CHANGELOG, `Closes #645` e `Closes #648`** — porquê: precedente dos últimos PRs; sem bump o conserto não chega ao cache.

## Avaliado e descartado
- #645, só trocar a receita para `fluxo/<slug sem a data>` (a proposta da Issue): ver D1.
- #645, renomear a convenção do slug no `brainstorm` para sem data: muda o nome de todo design e estado futuro e quebra a ordenação por data das pastas.
- #648, parser de verdade (acorn/TypeScript): o design `complexidade-por-funcao` decidiu leitura de texto sem dependência; os limites desta Issue são da leitura, não da escolha.

## Fora de escopo
- Outros envolventes além de `memo`/`forwardRef` (`styled.div`, `observer(`): sem pedido nem caso medido.

## Varredura
docs/rainforest/varredura/branch-datada-e-componentes.txt — confirmou #613/#610 (sufixo `-t<n>`) e #447 (diagnóstico da portaria), que esta entrega estende sem reabrir; a #207 (cópia divergente do resolvedor) é o precedente do D2. Nada sobre componente React ou `forwardRef` além da #648.

## Em aberto
(nenhum)
