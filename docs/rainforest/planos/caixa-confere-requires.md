# Plano: bateria que monta caixa leva as libs que os scripts copiados exigem

Design: docs/rainforest/design/caixa-confere-requires.md

## O que não pode quebrar
- Nenhuma bateria existente é editada.
- `bash scripts/varrer-baterias.sh --listar` e `--so <bateria>` continuam iguais (o checador não roda nesses modos).
- `bash scripts/testa-varrer-baterias.sh` continua verde.

## Tarefas

### 1. Checador `scripts/conferir-caixas.cjs` e sua bateria [tipo: implementar]
atende: D1, D2, D3, D5
arquivos: `scripts/conferir-caixas.cjs`, `scripts/testa-conferir-caixas.sh`
depende de: nenhuma
busca:
- repo | rg -n "require\(path.join\(__dirname" scripts hooks | é a forma literal de require do repo (ex.: scripts/conferir-mutacao.cjs:104); nenhum script confere caixa de bateria hoje
- repo | rg -ln "for lib in" hooks/testa-* scripts/testa-* | 11 baterias com laço de uma linha de cp
- livro | pulado: checador de convenção interna do repo
desfecho: construir
mutacao:
  arquivo: `scripts/conferir-caixas.cjs`
  de: `const faltando = exigidos.filter((c) => !copiados.has(c));`
  para: `const faltando = [];`
  bateria: `bash scripts/testa-conferir-caixas.sh`
  fixture: `testa-conferir-caixas.sh, caso "(1) script copiado sem a lib que ele exige"`
prova: `bash scripts/testa-conferir-caixas.sh`
pronto quando: com baterias de fixture montadas pela própria bateria numa raiz temporária (cópia mínima com `scripts/`, `hooks/lib/` e `hooks/testa-*.sh`), `node scripts/conferir-caixas.cjs --raiz <raiz>` dá, para cada caso da tabela, o exit e a linha da tabela — provado por `bash scripts/testa-conferir-caixas.sh` saindo 0 com uma linha `ok` por asserção, nenhum caso afirmando sobre o texto do fonte do checador

| id | bateria de fixture | exit | saída contém |
|---|---|---|---|
| (1) script copiado sem a lib que ele exige | `cp "$SRC/scripts/a.cjs"` onde `a.cjs` tem `require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'))` no topo | 1 | `falta hooks/lib/x.cjs (exigido por scripts/a.cjs)` |
| (2) lib copiada pelo laço | mesmo `a.cjs`, e `for lib in x y; do cp "$SRC/hooks/lib/$lib.cjs" "$SBP/hooks/lib/"; done` | 0 | `0 achado(s)` |
| (3) require tardio | `a.cjs` com `function f() { return require('./b.cjs'); }` e só `a.cjs` copiado | 1 | `falta scripts/b.cjs (exigido por scripts/a.cjs)` |
| (4) transitivo | `a.cjs` → `./b.cjs` → `../hooks/lib/x.cjs`; copia `a.cjs` e `b.cjs` | 1 | `falta hooks/lib/x.cjs (exigido por scripts/b.cjs)` |
| (5) caixa-sem com motivo | caso (1) mais a linha `# caixa-sem: hooks/lib/x.cjs — degrada para aviso` | 0 | `0 achado(s)` |
| (6) caixa-sem sem motivo | caso (1) mais `# caixa-sem: hooks/lib/x.cjs` | 1 | `falta hooks/lib/x.cjs` |
| (7) cp -r da pasta inteira | `cp -r "$SRC/scripts" "$SBP/"` **e** `cp "$SRC/scripts/a.cjs" "$SBP/scripts/"`, com o `a.cjs` do caso (1) | 0 | `pulada` |
| (8) módulo do Node não conta | `a.cjs` só com `require('fs')` e `require('path')` | 0 | `0 achado(s)` |
| (9) cp -r de subpasta conta como copiada | caso (1) mais `cp -r "$SRC/hooks/lib" "$SBP/hooks/"` | 0 | `0 achado(s)` |

Arquivos de cada fixture (todos criados pela bateria com `printf`, numa subpasta própria por caso): `scripts/a.cjs` com o conteúdo da coluna; `hooks/lib/x.cjs` (conteúdo `module.exports = {};`) em todos os casos que citam `x.cjs`; `scripts/b.cjs` nos casos (3) e (4) — no (3) `module.exports = {};`, no (4) com `require(path.join(__dirname, '..', 'hooks', 'lib', 'x.cjs'))` e `const path = require('path');`; e `hooks/testa-caso.sh` com as linhas de `cp` da coluna (com `SRC=...` e `SBP=...` atribuídos no topo; a bateria de fixture nunca é executada, só lida).

Forma prescrita:
- CLI: `node scripts/conferir-caixas.cjs [--raiz <dir>]` (padrão: a pasta acima do script). Lê `hooks/testa-*.sh` e `scripts/testa-*.sh` da raiz (as `testa-*.cjs` ficam fora). Uma linha por achado: `<bateria>: falta <caminho> (exigido por <arquivo>)`, caminhos relativos à raiz com `/`, achados deduplicados por bateria e ordenados por bateria e depois por caminho. Bateria pulada imprime `<bateria>: pulada (cp -r de <pasta>)`. Última linha: `conferir-caixas: <n> bateria(s), <m> achado(s)`. Exit 1 com achado, 0 sem; argumento desconhecido ou `--raiz` sem pasta existente imprime `uso: node scripts/conferir-caixas.cjs [--raiz <dir>]` e sai 2. Arquivo copiado que não existe na raiz é ignorado em silêncio.
- Conjunto copiado (D1): de cada linha que contém `cp ` e não começa com `#`, os trechos `\$\{?[A-Za-z_]+\}?/((scripts|hooks)/[^"' ]+\.cjs)`. Laço: linha `for <v> in <palavras>; do` (uma linha) — enquanto não vier `done`, as linhas de `cp` com `$<v>` ou `${<v>}` se expandem para cada palavra. Linha de `cp` com `-r`/`-R`/`-a`: se **qualquer** argumento de origem termina em `/scripts` ou `/hooks` (com ou sem aspas de fechamento), a bateria é pulada; se termina em `/hooks/lib` ou `/scripts/lib`, todos os `.cjs` dessa pasta na raiz entram no conjunto copiado.
- Fica fora (D5), sem achado e sem erro: `cp` com glob (`"$RAIZ"/hooks/*.cjs`) e origem cujas aspas fecham antes do `/` — a regex simplesmente não casa.
- Requires (D2): no texto do `.cjs` copiado (lido da raiz), `require\(path\.join\(__dirname,\s*([^)]*)\)\)` com todas as partes literais entre aspas (parte não literal descarta o require), e `require\(\s*['"](\.{1,2}/[^'"]+)['"]\s*\)`. O caminho resolve a partir da pasta do arquivo e vira relativo à raiz. Só conta alvo `.cjs` que existe na raiz. Transitivo: o alvo que está no conjunto copiado tem os requires dele conferidos também.
- A comparação final é exatamente `const faltando = exigidos.filter((c) => !copiados.has(c));` (uma expressão, sem ramo), com `exigidos` e `copiados` já calculados; nenhum caso de teste lê o fonte.
- `caixa-sem` (D3): linha `^\s*#\s*caixa-sem:\s*(\S+)\s+—\s*(\S.*)$` (travessão `—` ou `-`) tira o caminho dos achados daquela bateria; sem o motivo depois do travessão, não tira.
- Bateria `scripts/testa-conferir-caixas.sh`: `set -u`, raiz em `mktemp -d` com `trap` de limpeza, uma subpasta por caso com `scripts/`, `hooks/lib/` e uma `hooks/testa-caso.sh` escrita por `printf`; `sai`/`tem` no molde de `hooks/testa-gate-receita-corpo.sh`; termina com `ok: <n>   falhou: <m>` e sai 1 com falha.

### 2. Só achado novo reprova (--base) e o checador no varrer-baterias [tipo: implementar]
atende: D4, D6
arquivos: `scripts/conferir-caixas.cjs`, `scripts/testa-conferir-caixas.sh`, `scripts/varrer-baterias.sh`
depende de: 1
*Emenda de 2026-11-11 (Q1 = A do Luís):* a versão anterior desta tarefa anotava `# caixa-sem:` nas baterias; o repositório real deu 144 achados e o D6 trocou isso por comparar com a base. Nenhuma bateria existente é editada.
busca:
- repo | rg -n "^vermelhas=\(\)" scripts/varrer-baterias.sh | o laço das baterias começa ali; o checador entra logo antes
- repo | rg -n "fetch-depth" .github/workflows/baterias.yml | fetch-depth 0: origin/main existe no CI
- livro | pulado: integração interna
desfecho: estender
mutacao:
  arquivo: `scripts/conferir-caixas.cjs`
  de: `const novos = linhas.filter((l) => !daBase.has(l));`
  para: `const novos = linhas;`
  bateria: `bash scripts/testa-conferir-caixas.sh`
  fixture: `testa-conferir-caixas.sh, caso "(10) achado que já existe na base não reprova"`
prova: `bash scripts/testa-conferir-caixas.sh`
pronto quando: com a tabela abaixo montada pela bateria (repositório git de fixture com um commit de base), cada caso dá o exit e a saída da tabela, e os casos (1)–(9) continuam iguais; e, no repositório real, `node scripts/conferir-caixas.cjs --base $(git merge-base HEAD origin/main)` sai 0 com `0 achado(s) novo(s)` — provado por `bash scripts/testa-conferir-caixas.sh` saindo 0, pelo comando no repositório real, e por `bash scripts/testa-varrer-baterias.sh` saindo 0

| id | montagem | exit | saída contém |
|---|---|---|---|
| (10) achado que já existe na base não reprova | repo git com o caso (1) commitado; `--base HEAD` | 0 | `0 achado(s) novo(s)` e `1 já existente(s) na base` |
| (11) achado novo reprova | repo git com o caso (2) commitado (sem achado); na árvore de trabalho, tira `y` do laço e acrescenta em `a.cjs` um `require(path.join(__dirname, '..', 'hooks', 'lib', 'y.cjs'))`, com `hooks/lib/y.cjs` existente; `--base HEAD` | 1 | `falta hooks/lib/y.cjs (exigido por scripts/a.cjs)` |
| (12) base que não existe | `--base nao-existe-xyz` | 2 | `base` |

Forma prescrita:
- `--base <ref>` em `conferir-caixas.cjs`. Com ele: `git -C <raiz> rev-parse --verify <ref>^{commit}` (falha → `conferir-caixas: base '<ref>' não existe` em stderr, exit 2); extrai `hooks/` e `scripts/` da base para uma pasta em `os.tmpdir()` com `git -C <raiz> archive --format=tar <ref> hooks scripts` cujo stdout vai para `tar -x -C <pasta>` (ambos por `spawnSync`, sem shell); roda a mesma análise na pasta e na raiz; apaga a pasta no fim (`fs.rmSync(..., {recursive:true, force:true})`).
- As linhas comparadas são as de achado já formatadas (`<bateria>: falta <caminho> (exigido por <arquivo>)`). `daBase` é o `Set` das linhas da base; a comparação é exatamente `const novos = linhas.filter((l) => !daBase.has(l));`. Imprime só os `novos`, e termina com `conferir-caixas: <n> bateria(s), <k> achado(s) novo(s), <j> já existente(s) na base`; exit 1 se `k > 0`. Sem `--base`, a saída e o exit continuam os da tarefa 1.
- `scripts/varrer-baterias.sh`: mover `vermelhas=()` para logo antes do bloco abaixo e inserir o bloco antes do laço. `modo_solo` é a variável do `--so`; o `--listar` já saiu antes deste ponto. O checador roda pelo caminho absoluto do próprio `varrer` e examina o cwd, para que as caixas de `scripts/testa-varrer-baterias.sh` (sandboxes com baterias fictícias, sem `cp`, sem git) saiam verdes:
  ```
  if [ -z "$modo_solo" ] && { [ -z "$shard" ] || [ "${shard%%/*}" = "1" ]; }; then
    echo ""
    echo "----- conferir-caixas -----"
    dir_varrer="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    base_caixas="$(git merge-base HEAD origin/main 2>/dev/null || true)"
    if [ -n "$base_caixas" ]; then
      args_caixas=(--raiz "$PWD" --base "$base_caixas")
    else
      args_caixas=(--raiz "$PWD")
    fi
    if node "$dir_varrer/conferir-caixas.cjs" "${args_caixas[@]}"; then
      echo "  >> VERDE  conferir-caixas"
    else
      echo "  >> VERMELHA conferir-caixas"
      vermelhas+=("conferir-caixas")
    fi
  fi
  ```
  Sem `origin/main` (sandbox), o checador roda sem base; as baterias fictícias não têm `cp`, então saem com `0 achado(s)`.
- Se `bash scripts/testa-varrer-baterias.sh` ficar vermelha com o bloco, PARE e reporte com a saída: a bateria não está em `arquivos:`.
- Bateria: os casos (10)–(12) fazem `git init -q`, `git -c user.email=t@t -c user.name=t add/commit -q` na subpasta do caso (identidade só por `-c`, nunca `git config`).

### 3. Versão MINOR, README e CHANGELOG [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 2
mutacao: n/a
  motivo: só versão e texto; comportamento medido pelas tarefas 1 e 2
*Emenda do leitor cego:* trazer a `main` com `git fetch origin && git merge origin/main`; data do cabeçalho 2026-11-11; o `README.md` ganha, na tabela de scripts `conferir-*` (seção de scripts, ~linhas 252-261), uma linha para `conferir-caixas.cjs` no mesmo formato das vizinhas.
pronto quando: com a `main` trazida para a branch, `node scripts/conferir-versao.cjs` sai 0 e os quatro lugares (dois `plugin.json`, selo do README com `vers%C3%A3o-X-` e `alt="versão X"`, topo do CHANGELOG `## X — AAAA-MM-DD`) dizem a versão seguinte à da `main` na casa MINOR (2.12.0 se a `main` estiver em 2.11.1); o CHANGELOG descreve pelo comportamento o checador, onde ele roda e a linha `# caixa-sem:` — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A3 '^## ' CHANGELOG.md`

### 4. Origem de `cp -r` terminada em `/.` (revisão 1) [tipo: implementar]
atende: D1, D6
arquivos: `scripts/conferir-caixas.cjs`, `scripts/testa-conferir-caixas.sh`, `CHANGELOG.md`
depende de: 3
busca:
- repo | grep -n "cp -r \"\$SRC/.*/\." scripts/testa-*.sh hooks/testa-*.sh | 4 baterias copiam `scripts/lib/.` e `hooks/lib/.` (estado-principal, importar-claude-mem, backup-estado, registrar-erro)
desfecho: estender
mutacao:
  arquivo: `scripts/conferir-caixas.cjs`
  de: `.replace(/\/+$/, '').replace(/\/\.$/, ''));`
  para: `.replace(/\/+$/, ''));`
  bateria: `bash scripts/testa-conferir-caixas.sh`
  fixture: `testa-conferir-caixas.sh, casos (9b) e (7b)`
prova: `bash scripts/testa-conferir-caixas.sh`
pronto quando: com o repositório real, `node scripts/conferir-caixas.cjs` não acusa mais `hooks/lib/*` nem `scripts/lib/*` nas 4 baterias que copiam a pasta por `cp -r "$SRC/<x>/lib/." ...` e o total cai de 144 para 128; a bateria tem os casos (9b) `cp -r "$SRC/hooks/lib/."` → 0 achado e (7b) `cp -r "$SRC/scripts/."` → pulada; o uso cita `[--base <ref>]`; o CHANGELOG diz 128 — provado por `node scripts/conferir-caixas.cjs | tail -1` devolvendo `224 bateria(s), 128 achado(s)` e `bash scripts/testa-conferir-caixas.sh` terminando em `ok: 29   falhou: 0`
