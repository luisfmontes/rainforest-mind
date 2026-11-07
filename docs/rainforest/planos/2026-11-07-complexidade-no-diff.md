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

Forma prescrita: `variacao` lê o diff com `git diff -U0 --no-renames <base> -- <arquivo>` e guarda as remoções puras (`+N,0`) numa lista `cortes`; a função atual é tocada quando a faixa dela cruza uma linha nova ou quando `const corte = cortes.some((n) => m.linha <= n && n + 1 <= m.fim);` dá verdadeiro. As definições de um texto saem de uma função que `definicoesDoArquivo` passa a usar, para medir o lado da base sem gravar arquivo.

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
pronto quando: com o `skills/enxugar/SKILL.md` real, o trecho do modo 1 (entre `### Modo 1` e `### Modo 2`) manda rodar `catalogo-funcoes.cjs variacao --raiz <repo>` antes de procurar os seis tipos, diz que a base padrão é a mesma do revisor e que `--base` troca, diz que a função que mais subiu é onde ler primeiro, e que é contexto que não vira tag nem entra no `líquido:` (D6) — provado por `bash scripts/testa-enxugar-estrutura.sh`, cujo caso novo confere as três frases no trecho do modo 1, e por `bash scripts/testa-teto-skills.sh`

### 3. README, CHANGELOG e versão 2.7.0 [tipo: docs]
atende: D7
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
mutacao: n/a
  motivo: tarefa só de texto e número de versão; a falsificação é a coerência com o que as tarefas 1 e 2 entregaram, conferida no critério
pronto quando: com o repositório real, o README descreve a `variacao` no mesmo lugar em que descreve o `complexas` do `enxugar`, dizendo que mede só as funções tocadas pelo diff e que é aproximação, sem crédito ao untangle; `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` dizem `2.7.0`; o selo do README diz 2.7.0 e o `CHANGELOG.md` abre com 2.7.0 — provado por `grep -c "variacao" README.md` ≥ 1, `grep -ci "untangle" README.md` = 0, `node -e "console.log(require('./.claude-plugin/plugin.json').version)"` = `2.7.0`, `bash scripts/testa-versao.sh` e `bash scripts/testa-plugin-codex.sh` verdes, e `node scripts/conferir-versao.cjs` exit 0
