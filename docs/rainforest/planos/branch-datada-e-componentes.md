# Plano: branch com slug datado e componentes React no `complexas`

Design: docs/rainforest/design/branch-datada-e-componentes.md

## O que não pode quebrar
- A portaria continua negando branch ambígua e branch sem fluxo: `node hooks/testa-estagio-ativo.cjs`, `node hooks/testa-portaria-nucleo.cjs` e `bash scripts/testa-estado-leve.sh` seguem verdes.
- Os casos 1 a 14 de `bash scripts/testa-catalogo-funcoes.sh` seguem verdes com os mesmos números (o 14 troca só a forma de provocar a leitura errada, porque a forma antiga é a que o D6 conserta).
- `hooks/testa-aviso-duplicata.sh` segue verde: a regra `topo` mais larga não pode transformar chamada solta em definição.
- Nenhum texto injetado na abertura muda: `skills/rainforest-mind/references/regra-11.md` fica intocado (D1).

## Tarefas

### 1. Casamento slug × branch numa função só, aceitando o slug datado [tipo: implementar]
atende: D1, D2
arquivos: `hooks/lib/estagio-ativo.cjs`, `hooks/lib/caminho-leve.cjs`, `scripts/saude.cjs`, `hooks/testa-estagio-ativo.cjs`, `scripts/testa-saude.sh`
depende de: nenhuma
busca:
- repo | rg "d\{4\}-\\d\{2\}-\\d\{2\}-" hooks scripts | quatro cópias: estagio-ativo (resolver e diagnosticar), caminho-leve, saude
- repo | gh issue view 207 | precedente: cópia divergente do resolvedor com bateria verde
desfecho: estender
prova: `node -e "const m=require('./hooks/lib/estagio-ativo.cjs'); process.exit(m.casaSlugComBranch && m.casaSlugComBranch('2026-11-03-tema','2026-11-03-tema')==='exato' ? 0 : 1)"`
mutacao:
  arquivo: `hooks/lib/estagio-ativo.cjs`
  de: `if (slug === base) return 'exato';`
  para: `if (false) return 'exato';`
  bateria: `node hooks/testa-estagio-ativo.cjs`
  fixture: `testa-estagio-ativo.cjs, caso "#645: branch fluxo/<slug datado> casa com o fluxo"`
pronto quando: num repositório de teste com `docs/rainforest/estado/2026-11-03-tema.json` em `executar`, `resolver` na branch `fluxo/2026-11-03-tema` devolve `{slug: "2026-11-03-tema", estagio: "executar"}`, na branch `fluxo/2026-11-03-tema-t2` também, e na branch `fluxo/tema` também (comportamento antigo); `casaComBranch` do `caminho-leve` aceita a forma datada; e o `/saude` numa branch `fluxo/<slug>` com fluxo aberto imprime `ESTA branch tem dono` — provado por `node hooks/testa-estagio-ativo.cjs` e `bash scripts/testa-saude.sh`, com o caso novo do `/saude` vermelho no código antigo (que compara com o prefixo `fluxo/`)

Forma prescrita: `casaSlugComBranch(slug, branchBase)` devolve `'exato'`, `'tarefa'` ou `null`, e é exportada por `estagio-ativo.cjs`; `resolver`, `diagnosticar`, `caminho-leve.casaComBranch` e `saude.cjs` não fazem mais `replace` de data por conta própria.

### 2. Componente React tipado e envolvido entra no catálogo e é medido [tipo: implementar]
atende: D3, D4
arquivos: `hooks/lib/definicoes.cjs`, `scripts/lib/complexidade.cjs`, `scripts/testa-catalogo-funcoes.sh`, `hooks/testa-aviso-duplicata.sh`
depende de: nenhuma
busca:
- repo | rg "definicoes" hooks scripts | dois consumidores: aviso-duplicata.cjs e catalogo-funcoes.cjs
desfecho: estender
prova: `node -e "process.exit(require('./hooks/lib/definicoes.cjs').casar('const Foo: React.FC<P> = ({ a }) => {','js')==='Foo' ? 0 : 1)"`
mutacao:
  arquivo: `scripts/lib/complexidade.cjs`
  de: `if (t === '(' && envolve) {`
  para: `if (false) {`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso "15. complexas: componente React tipado e envolvido"`
pronto quando: numa fixture `.tsx` com `const Foo: React.FC<Props> = ({ a }) => {`, `export const Bar = React.memo(function Bar(p) {`, `export const Baz = forwardRef<HTMLDivElement, P>((props, ref) => {` e `const f: (a: number) => void = (a) => {`, cada um com um `if` dentro de outro, `complexas` imprime os quatro com `3 cognitiva  3 ciclomática` na linha em que começam; `const total = soma(a, b)` não entra no catálogo — provado por `bash scripts/testa-catalogo-funcoes.sh` e `bash hooks/testa-aviso-duplicata.sh`

### 3. Limites da leitura de texto: trava por recuo, regex depois de `)` e `}`, controle sem chave, não-funções [tipo: implementar]
atende: D5, D6, D7, D8, D9, D10
arquivos: `scripts/lib/complexidade.cjs`, `scripts/testa-catalogo-funcoes.sh`
depende de: 2
desfecho: estender
prova: `node -e "const r=require('./scripts/lib/complexidade.cjs').medirArquivo(['const total = (a + b) * c','function g(x) {','  return x','}',''].join(String.fromCharCode(10)),'js',[{linha:1,nome:'total',assinatura:'const total = (a + b) * c'},{linha:2,nome:'g',assinatura:'function g(x) {'}]); process.exit(r.medidas.length===1 && r.naoMedidas.length===0 ? 0 : 1)"`
mutacao:
  arquivo: `scripts/lib/complexidade.cjs`
  de: `if (!(recuo(def) <= mae.recuo)) continue;`
  para: `if (!(mae.recuo === 0 && recuo(def) === 0)) continue;`
  bateria: `bash scripts/testa-catalogo-funcoes.sh`
  fixture: `testa-catalogo-funcoes.sh, caso "16. complexas: limites da leitura (#648)", método que atravessa o vizinho`
pronto quando: numa fixture, (a) método de classe TSX cujo corpo atravessa o método seguinte sai como `não medido: ... corpo passou por <vizinho>`; (b) `if (s) /[}]/.test(s)` dentro de uma função não fecha o corpo cedo e a função seguinte é medida certa; (c) `<span>{page}/{pages}</span>` seguido de `a ? 1 : 2` na linha de baixo conta o ternário; (d) `if (x) return` sem `;` seguido de `const o = { a: 1 }` e de um `if` não aprofunda o `if` seguinte (cognitiva 2, não 3); (e) `const total = (a + b) * c` sem `;` não sai como medida nem como não medido; (f) sobrecarga TS sem `;` seguida da implementação não dá "leitura errada"; (g) há caso para `}` seguida de `{`, `|`, `&` e `[` no tipo de retorno, e para a troca de mãe; e o caso 14 segue provando a trava de coluna zero — provado por `bash scripts/testa-catalogo-funcoes.sh`

### 4. CHANGELOG e versão 2.5.1 [tipo: docs]
atende: D11
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2, 3
mutacao: n/a
  motivo: tarefa só de texto e número de versão
pronto quando: `.claude-plugin/plugin.json` e `.codex-plugin/plugin.json` dizem `2.5.1`, o selo do README diz 2.5.1 e o `CHANGELOG.md` abre com 2.5.1 citando #645 e #648 — provado por `node -e "console.log(require('./.claude-plugin/plugin.json').version)"` = `2.5.1`, `bash scripts/testa-plugin-codex.sh` e `bash hooks/testa-abertura-mod-config.sh` verdes
