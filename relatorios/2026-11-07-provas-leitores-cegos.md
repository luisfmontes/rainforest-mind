# Provas das tarefas 1 e 2 do fluxo 2026-11-07-leitores-cegos

As saídas abaixo são as que os dois agentes devolveram no `executar`, coladas sem edição. Os dois
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
  [... a causa 2 traz a evidência em complexidade.cjs:362, :248 e :369-374, e a checagem por medirArquivo ...]

3. Mais fraca: filtro de candidatos ou de ordenação/`top` descartando o resultado.
  [... a causa 3 traz a checagem com --top 100 ...]

diagnóstico completo
```

As causas 2 e 3 estão resumidas entre colchetes. A transcrição inteira delas ficou na sessão, e o
critério da tarefa só julga a causa nº 1.

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
- `git status --short` dos dois worktrees, depois da volta, mostrou só a alteração que a janela
  principal tinha feito no plano.

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
