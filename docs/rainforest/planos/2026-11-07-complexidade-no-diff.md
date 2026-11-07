# Plano: variação de complexidade por função no `enxugar --diff`

Design: docs/rainforest/design/2026-11-07-complexidade-no-diff.md

## O que não pode quebrar
- Os subcomandos `listar`, `maiores`, `complexas`, `separar` e `conferir` saem como hoje: os casos 1 a 16 de `bash scripts/testa-catalogo-funcoes.sh` seguem verdes.
- `scripts/lib/complexidade.cjs` não muda: a medida é a mesma do `complexas`.
- `skills/enxugar/SKILL.md` fica abaixo de 500 linhas e 16 384 bytes (`bash scripts/testa-teto-skills.sh`), e os casos atuais de `bash scripts/testa-enxugar-estrutura.sh` seguem verdes.
- Nenhuma linha do `lboel/untangle` (AGPL-3.0) entra no repositório.

## Tarefas

### 1. Subcomando `variacao` [tipo: implementar]
atende: D1, D2, D3, D4, D5
arquivos: `scripts/catalogo-funcoes.cjs`, `scripts/testa-catalogo-funcoes.sh`, `hooks/lib/achados-revisor.cjs`
depende de: nenhuma
busca:
- repo | rg -n "@@ -" scripts hooks --glob "*.cjs" | hooks/lib/achados-revisor.cjs:137 (linhasAdicionadas, só <base>..HEAD, ignora remoção pura) e scripts/estado.cjs:787 (impressão do diff, não linhas)
- repo | rg -n "function baseDoDiff" hooks scripts | hooks/lib/achados-revisor.cjs:160, sem export; a tarefa a acrescenta ao `module.exports` e a reaproveita para a base padrão (D2)
- livro | vigias/livro-de-repos.md "untangle" | linha 246 da tabela: AGPL-3.0-only, enxertado sem copiar código, variação no diff deixada para esta ideia
desfecho: estender
mutacao:
  arquivo: `scripts/catalogo-funcoes.cjs`
  de: `const corte = cortes.some((n) => m.linha <= n && n + 1 <= m.fim);`
  para: `const corte = false;`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso "17. variacao: remoção pura dentro da função a marca como tocada"`
prova: `node scripts/catalogo-funcoes.cjs variacao --raiz . --base HEAD`
pronto quando: com o próprio repositório do plugin como entrada real, depois desta tarefa e antes do commit, `node scripts/catalogo-funcoes.cjs variacao --raiz . --base 1d5782b9` sai 0 e imprime uma linha `nova → <n> cognitiva (+<n>)  nova → <y> ciclomática  scripts/catalogo-funcoes.cjs:L<linha> variacao` cujo `L<linha>` é a linha em que `node scripts/catalogo-funcoes.cjs listar --raiz .` diz que `variacao` começa, uma linha para `principal` com a cognitiva da base à esquerda da seta e a atual à direita, nenhuma linha de arquivo fora do diff (`git diff --name-only 1d5782b9`), e termina com `medida aproximada (leitura de texto, sem parser): confira no código antes de concluir`; numa fixture git em mktemp, a bateria confere por linha exata: função editada que subiu (`<a> → <b> cognitiva (+<d>)`) com as contribuições recuadas debaixo; arquivo não rastreado sai como `nova`; função apagada sai como `removida` com a linha da base; remoção pura dentro de uma função a marca (caso 17); remoção pura entre duas funções não marca nenhuma; função tocada sem variação sai com `(=)` depois das que variaram; nome repetido pareia pela ordem; função vizinha não tocada não aparece; arquivo `.py` do diff sai em `não medido: 1 arquivo(s) py — linguagem sem chaves`; sem diff, `nenhuma função medida tocada pelo diff`; `--base` explícito num commit anterior mede contra ele; repositório sem `origin` e sem `--base` sai 1 com a mensagem pedindo `--base` — provado por `bash scripts/testa-catalogo-funcoes.sh`, nenhum caso afirmando sobre o texto do fonte

Forma prescrita (achados 1, 2, 3, 6 e 7 do leitor cego):
- **Nomes.** A função de topo que implementa o subcomando chama-se `variacao(raiz, base)`; os ajudantes têm outros nomes (`linhasDoDiff`, `definicoesDoTexto`). `definicoesDoArquivo` passa a ler o arquivo e chamar `definicoesDoTexto(texto, linguagem, contextoN)`, que mede o lado da base sem gravar arquivo. `variacao` entra no comentário de cabeçalho, no `USO` (`  variacao [--raiz <dir>] [--base <ref>]`) e na lista `subs` de `principal`.
- **Base.** `hooks/lib/achados-revisor.cjs` acrescenta `baseDoDiff` ao `module.exports`, sem mudar a função. Sem `--base`, `variacao` chama `baseDoDiff(raiz)`. Se `--raiz` não é repositório git (`repoGit`), sai 1 com `variacao: --raiz não é repositório git` no stderr; se a base não resolve, sai 1 com `variacao: base não resolvida (sem origin/<padrão>); passe --base <ref>`.
- **Arquivos.** Todo git roda com `cwd` = `--raiz` e `-c core.quotePath=false`. Os arquivos do diff são `git diff --name-only --relative --no-renames <base>` mais `git ls-files --others --exclude-standard` (os dois devolvem caminho relativo à `--raiz`, mesmo quando ela é subpasta do repo), sem repetição, ordenados, e passam pelos filtros do `candidatos`: extensão em `EXTENSOES`, `!ehGerado`, `!ehTeste`. Arquivo de linguagem que não é `js` nem `dart` só conta para a linha `não medido` de linguagem sem chaves.
- **Lados.** O texto da base é `git show <base>:./<arquivo>` (falha = arquivo novo); o atual é o disco (ausente = arquivo apagado). Arquivo novo: toda função atual é tocada. Arquivo apagado: toda função da base é tocada.
- **Hunks.** `linhasDoDiff` lê `git diff -U0 --no-renames --relative <base> -- <arquivo>` e, em cada `@@ -a(,b)? +c(,d)? @@`, com `b` e `d` valendo 1 quando ausentes: `b > 0` põe as linhas `a..a+b-1` em `removidas`; `d > 0` põe `c..c+d-1` em `novas`; `d = 0` (remoção pura) põe `c` em `cortes`; `b = 0` (adição pura) não marca nada na base. Função atual é tocada quando alguma linha de `novas` cai em `[linha, fim]` ou quando `const corte = cortes.some((n) => m.linha <= n && n + 1 <= m.fim);` dá verdadeiro. Função da base é tocada quando alguma linha de `removidas` cai na faixa dela.
- **Pareamento (D4).** Por arquivo e nome; a k-ésima ocorrência de um nome na base pareia com a k-ésima no disco. Entra na saída todo par em que um dos lados foi tocado; lado sem par é `nova` ou `removida`.
- **Saída, literal.** Uma linha por função, `<antes> → <depois> cognitiva (<d>)  <antes> → <depois> ciclomática  <arquivo>:L<linha> <nome>`, com `<d>` = `+N`, `-N` ou `=` (só a cognitiva). Exemplos: `8 → 19 cognitiva (+11)  5 → 9 ciclomática  a.js:L3 f`; `19 → 8 cognitiva (-11)  9 → 5 ciclomática  a.js:L3 f`; `3 → 3 cognitiva (=)  2 → 2 ciclomática  a.js:L3 f`; `nova → 7 cognitiva (+7)  nova → 3 ciclomática  b.ts:L1 h`; `5 → removida cognitiva (-5)  2 → removida ciclomática  a.js:L9 g` (linha da base). Só quem subiu ou é nova leva, debaixo, as 3 maiores contribuições da versão atual, no formato do `complexas` (`    +3 L23 if (profundidade 2)`). Ordem: cognitiva com variação primeiro, por `d` decrescente (nova é `+depois`, removida é `-antes`), empate por variação da ciclomática decrescente, depois caminho e linha; as `(=)` vêm no fim, por caminho e linha. Depois: `não medido: <n> arquivo(s) <ling> — linguagem sem chaves` por linguagem em ordem alfabética, e `não medido: <arquivo>:L<linha> <nome> — <motivo> (base)` ou `(atual)` para as `naoMedidas` de função tocada de cada lado. Sem nenhuma linha de função: `nenhuma função medida tocada pelo diff`. A última linha é sempre `medida aproximada (leitura de texto, sem parser): confira no código antes de concluir`. Exit 0 com qualquer variação.

### 2. Modo 1 do enxugar abre com `variacao` [tipo: docs]
atende: D6
arquivos: `skills/enxugar/SKILL.md`, `scripts/testa-enxugar-estrutura.sh`
depende de: 1
mutacao:
  arquivo: `skills/enxugar/SKILL.md`
  de: `catalogo-funcoes.cjs variacao --raiz <repo>`
  para: `catalogo-funcoes.cjs --raiz <repo>`
  bateria: `bash scripts/testa-enxugar-estrutura.sh`
  fixture: `testa-enxugar-estrutura.sh, caso "D6 (complexidade-no-diff): modo 1 abre com variacao, fora do líquido"`
pronto quando: com o `skills/enxugar/SKILL.md` real, o trecho do modo 1 (entre `### Modo 1` e `### Modo 2`) traz, logo antes de "Caso de uso", o parágrafo literal abaixo, e a frase "pelos cinco tipos acima" vira "pelos seis tipos acima" (achado 5 do leitor cego) — provado por `bash scripts/testa-enxugar-estrutura.sh`, cujo caso novo monta `MODO1="$(sed -n '/^### Modo 1/,/^### Modo 2/p' "$SKILL_FILE" | tr '\n' ' ' | tr -s ' ')"`, como o `MODO2`, e confere com `tem_na` as quatro strings `catalogo-funcoes.cjs variacao --raiz <repo>`, `a mesma do revisor`, `mais subiu é onde ler primeiro` e `não vira tag nem entra no `líquido:``, e por `bash scripts/testa-teto-skills.sh`

Parágrafo a inserir:

```
Abra com `node <plugin>/scripts/catalogo-funcoes.cjs variacao --raiz <repo>`: a complexidade
de cada função que o diff tocou, antes e depois (`8 → 19 cognitiva (+11)`), com a mesma
medida aproximada do `complexas`. Sem `--base`, a base é a mesma do revisor,
`merge-base(HEAD, origin/<padrão>)`; `--base <ref>` troca. A função que mais subiu é onde ler
primeiro. É contexto: não vira tag nem entra no `líquido:`.
```

### 3. README, CHANGELOG e versão 2.7.0 [tipo: docs]
atende: D7
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
mutacao: n/a
  motivo: tarefa só de texto e número de versão; a falsificação é a coerência com o que as tarefas 1 e 2 entregaram, conferida no critério
pronto quando: com o repositório real, o README descreve a `variacao` no mesmo lugar em que descreve o `complexas` do `enxugar`, dizendo que mede só as funções tocadas pelo diff e que é aproximação, sem crédito ao untangle; `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` dizem `2.7.0`; o selo do README diz 2.7.0 nos dois pontos da linha (a URL `vers%C3%A3o-2.7.0` e o `alt`), e o `CHANGELOG.md` ganha, acima da 2.6.0, `## 2.7.0 — 2026-11-07` com um bullet em negrito no formato dos vizinhos, dizendo que o `enxugar --diff` abre com a variação de complexidade das funções tocadas — provado por `grep -c "variacao" README.md` ≥ 1, `grep -ci "untangle" README.md` = 0, `node -e "console.log(require('./.claude-plugin/plugin.json').version)"` = `2.7.0`, `bash scripts/testa-versao.sh` e `bash scripts/testa-plugin-codex.sh` verdes, e `node scripts/conferir-versao.cjs` exit 0 (com fetch; sem rede, `--sem-fetch`)
