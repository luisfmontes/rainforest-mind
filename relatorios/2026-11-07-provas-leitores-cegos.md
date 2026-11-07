# Provas das tarefas 1 e 2 do fluxo 2026-11-07-leitores-cegos

Da tarefa 2, a saída do agente está colada abaixo sem edição. Da tarefa 1, há só o placar e o resumo dos achados: o texto literal ficou no transcrito da sessão. Os dois
são `general-purpose`, com `model: sonnet`, despachados com o briefing literal das referências
novas. O plano (`docs/rainforest/planos/2026-11-07-leitores-cegos.md`) traz só o resumo, e é
aqui que está a evidência.

## Tarefa 2: diagnóstico cego do #648, na base 32be77c2 (2.5.0)

**Montagem.**
- Worktree descartável em `32be77c2`.
- Fixture `Painel.tsx` com `const Painel: React.FC = () => {...}` e `function Simples()`.
- Repro: `node scripts/catalogo-funcoes.cjs complexas --raiz <pasta da fixture>`, que devolveu:

```
0 cognitiva  1 ciclomática  Painel.tsx:L6 Simples
medida aproximada (leitura de texto, sem parser): confira no código antes de concluir
```

**Saída do agente.**

```
Causas candidatas, da mais para a menos provável:

1. O cadastro de definições nunca reconhece `Painel`: a regra de função de topo exige `=` logo depois do nome, e a anotação de tipo `: React.FC` quebra isso. (mais provável)
- Evidência:
  - `hooks/lib/definicoes.cjs:33` é `/^(?:export\s+)?(?:const|let|var)\s+([\w$]+)\s*=\s*(?:async\b|\()/`. Depois do nome só admite `\s*=`. Na linha 2 do fixture, `const Painel: React.FC = () => {`, vem `:` logo depois de `Painel`, então a regra não casa.
  - A única outra regra de `topo` que poderia pegar a linha é `export default function`, e a linha não é isso.
  - O conjunto `metodo` (linha 53) exige recuo (`^\s+`). `Painel` está na coluna zero, então também não casa.
  - `definicoesDoArquivo` (`scripts/catalogo-funcoes.cjs:160-174`) só usa `casar` por linha. Sem match, `Painel` nunca entra em `defs`.
  - `medirArquivo` (`scripts/lib/complexidade.cjs:352`) só mede o que veio em `defs`. O `Painel` some sem entrar em `naoMedidas`, por isso a saída não avisa de nada.
  - `Simples` casa pela regra da linha 32 (`function Simples`), o que bate com a saída observada.
- Checagem: rodar `node -e "const {casar}=require('./hooks/lib/definicoes.cjs');for(const l of ['const Painel: React.FC = () => {','const Painel = () => {'])console.log(JSON.stringify(l),casar(l,'js','topo'))"` dentro do worktree.
  - Se a causa for esta, a primeira linha devolve `null` e a segunda devolve `"Painel"`.
  - Se as duas devolverem `"Painel"`, a causa está derrubada e o defeito é posterior (causa 2).

2. Menos provável: `Painel` entra em `defs`, mas a medição o descarta ou o aninha.
- Evidência:
  - `complexidade.cjs:362` localiza a ficha com `f.l === def.linha && f.t === def.nome`.
  - O corpo vem de `acharCorpo` (`:248`), que lida com `<...>` de genérico e com tipo literal antes da seta. A anotação `React.FC` e o JSX (`<div>a</div>`, que o tokenizador trata como `<`/`>`) podem confundir a busca da seta ou do fechamento das chaves.
  - `:369-374` descarta com `corpo passou por ...` ou `corpo não fechou`, mas esses casos iriam para `naoMedidas`. A saída real só tem a linha de aviso genérico, então esta causa só vale se `naoMedidas` for impresso e estiver vazio. É a hipótese mais fraca porque o sintoma não mostra nenhum aviso.
- Checagem: depois de aplicar a checagem 1, rodar `node -e "const c=require('./scripts/lib/complexidade.cjs');const t=require('fs').readFileSync('C:/Users/Luis/AppData/Local/Temp/diag648/Painel.tsx','utf8');console.log(JSON.stringify(c.medirArquivo(t,'js',[{linha:2,nome:'Painel'},{linha:6,nome:'Simples'}]),null,1))"`.
  - `Painel` em `medidas` com cognitiva maior que 0: a medição está sã e o defeito é só a causa 1.
  - `Painel` em `naoMedidas`, ou ausente das duas listas: a causa 2 está confirmada.

3. Mais fraca: filtro de candidatos ou de ordenação/`top` descartando o resultado.
- Evidência: `candidatos()` (`catalogo-funcoes.cjs:143-147`) filtra por extensão, geração e teste. `.tsx` está em `EXTENSOES` (`definicoes.cjs:20`) e `Simples` do mesmo arquivo aparece, então o arquivo não é filtrado. O `top` padrão é 10 e há só uma função na saída, então o corte também não explica. Está aqui só por completude.
- Checagem: rodar o repro com `--top 100`. Se `Painel` continuar ausente, a causa 3 cai. Se aparecer, o corte era o problema.

diagnóstico completo
```

As três candidatas trazem `arquivo:linha` e uma checagem, e nenhuma propõe conserto, como o critério da tarefa pede.

**Checagem discriminante, rodada pela janela principal na base:**

```
$ node -e "const {casar}=require('./hooks/lib/definicoes.cjs');for(const l of ['const Painel: React.FC = () => {','const Painel = () => {'])console.log(JSON.stringify(l),casar(l,'js','topo'))"
"const Painel: React.FC = () => {" null
"const Painel = () => {" Painel
```

**Conserto real.** `git show 3e344d23 -- hooks/lib/definicoes.cjs` mostra que o #651 trocou
justamente essa regex. Ela passou a aceitar a anotação de tipo antes do `=`, e também `function`,
`memo(` e `forwardRef(`. A candidata nº 1 é a causa real.

## Tarefa 1: leitor cego sobre o plano deste fluxo

**Placar.**
- Achados: 4 bloqueantes, 5 maiores e 3 menores.
- Cada achado veio com o grau, a tarefa afetada, o trecho citado e a orientação.
- O agente não propôs código.
- `git status --short` dos dois worktrees, depois da volta, não saiu vazio, ao contrário do que o
  critério pedia. Ele mostrou só a alteração que a janela principal tinha feito no plano enquanto o
  leitor rodava, e nenhuma alteração do leitor.

**Resumo dos achados, na ordem do relato:**
- **Bloqueantes:**
  1. A T1 não diz o texto da referência.
  2. O critério da T1 pede um despacho, e o executor não tem Agent.
  3. O critério da T1 pede `git status` vazio com arquivos ainda sem commit.
  4. A T2 não diz o texto da referência, e o critério dela também pede despacho.
- **Maiores:**
  1. O lugar e o texto do `## Fechar`, com o orçamento de bytes.
  2. O lugar da Fase 3 e do aviso no `depurador`.
  3. A metade do D7 que é da janela principal.
  4. O critério da T2 depende da saída de um modelo.
  5. "README sem 2.5.1". Esse foi leitura concorrente com o bump de versão, feito em paralelo.
- **Menores:**
  1. O exit esperado do `conferir-versao`.
  2. O formato da entrada no CHANGELOG.
  3. O `marketplace.json` sem `version`, sem problema.

**Destino dos achados.** Não foram aplicados ao plano. As tarefas foram escritas pela janela
principal, e o plano é só de docs, caso em que o D1 dispensa o leitor. O achado de leitura
concorrente virou a linha "commite o plano antes do despacho" em
`skills/plano/references/leitor-cego.md`.
