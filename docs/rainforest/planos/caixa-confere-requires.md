# Plano: bateria que monta caixa leva as libs que os scripts copiados exigem

Design: docs/rainforest/design/caixa-confere-requires.md

## O que não pode quebrar
- Nenhuma bateria existente muda de comportamento: as edições nelas são só linhas de comentário `# caixa-sem:` (tarefa 2).
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
| (7) cp -r da pasta inteira | `cp -r "$SRC/scripts" "$SBP/"` com o `a.cjs` do caso (1) | 0 | `0 achado(s)` |
| (8) módulo do Node não conta | `a.cjs` só com `require('fs')` e `require('path')` | 0 | `0 achado(s)` |

Forma prescrita:
- CLI: `node scripts/conferir-caixas.cjs [--raiz <dir>]` (padrão: a pasta acima do script). Lê `hooks/testa-*.sh` e `scripts/testa-*.sh` da raiz. Uma linha por achado: `<bateria>: falta <caminho> (exigido por <arquivo>)`, caminhos relativos à raiz com `/`. Última linha: `conferir-caixas: <n> bateria(s), <m> achado(s)`. Exit 1 com achado, 0 sem, 2 em uso errado.
- Conjunto copiado (D1): de cada linha que contém `cp ` e não começa com `#`, os trechos `\$\{?[A-Za-z_]+\}?/((scripts|hooks)/[^"' ]+\.cjs)`. Laço: linha `for <v> in <palavras>; do` (uma linha) — enquanto não vier `done`, as linhas de `cp` com `$<v>` ou `${<v>}` se expandem para cada palavra. Linha de `cp` com `-r`/`-R`/`-a` cuja origem termina em `/scripts"` ou `/hooks"` (ou sem aspas) marca a bateria como pulada.
- Requires (D2): no texto do `.cjs` copiado (lido da raiz), `require\(path\.join\(__dirname,\s*([^)]*)\)\)` com todas as partes literais entre aspas (parte não literal descarta o require), e `require\(\s*['"](\.{1,2}/[^'"]+)['"]\s*\)`. O caminho resolve a partir da pasta do arquivo e vira relativo à raiz. Só conta alvo `.cjs` que existe na raiz. Transitivo: o alvo que está no conjunto copiado tem os requires dele conferidos também.
- A comparação final é exatamente `const faltando = exigidos.filter((c) => !copiados.has(c));` (uma expressão, sem ramo), com `exigidos` e `copiados` já calculados; nenhum caso de teste lê o fonte.
- `caixa-sem` (D3): linha `^\s*#\s*caixa-sem:\s*(\S+)\s+—\s*(\S.*)$` (travessão `—` ou `-`) tira o caminho dos achados daquela bateria; sem o motivo depois do travessão, não tira.
- Bateria `scripts/testa-conferir-caixas.sh`: `set -u`, raiz em `mktemp -d` com `trap` de limpeza, uma subpasta por caso com `scripts/`, `hooks/lib/` e uma `hooks/testa-caso.sh` escrita por `printf`; `sai`/`tem` no molde de `hooks/testa-gate-receita-corpo.sh`; termina com `ok: <n>   falhou: <m>` e sai 1 com falha.

### 2. caixa-sem nas baterias de hoje e o checador no varrer-baterias [tipo: implementar]
atende: D3, D4
arquivos: `scripts/varrer-baterias.sh`, `hooks/testa-*.sh`, `scripts/testa-*.sh`
depende de: 1
busca:
- repo | rg -n "^vermelhas=\(\)" scripts/varrer-baterias.sh | o laço das baterias começa ali; o checador entra logo antes
- livro | pulado: integração interna
desfecho: estender
mutacao:
  arquivo: `scripts/testa-estado-teto.sh`
  de: `resolver-executavel caminho-real contar-ocorrencias`
  para: `resolver-executavel contar-ocorrencias`
  bateria: `node scripts/conferir-caixas.cjs`
  fixture: `scripts/testa-estado-teto.sh, laço for lib da caixa (o conferir-mutacao.cjs copiado exige hooks/lib/caminho-real.cjs)`
prova: `node scripts/conferir-caixas.cjs`
pronto quando: com o repositório real, `node scripts/conferir-caixas.cjs` sai 0 com a última linha `conferir-caixas: <n> bateria(s), 0 achado(s)`, e tirar `caminho-real` do laço de `scripts/testa-estado-teto.sh` (o episódio de 2026-11-09) o faz sair 1 com `scripts/testa-estado-teto.sh: falta hooks/lib/caminho-real.cjs (exigido por scripts/conferir-mutacao.cjs)`; e `bash scripts/varrer-baterias.sh --shard 1/3 --listar` continua listando sem rodar o checador — provado pelos três comandos e por `bash scripts/testa-varrer-baterias.sh` saindo 0

Forma prescrita:
- Rodar `node scripts/conferir-caixas.cjs` na branch. Para cada achado, decidir lendo o script: se o `require` faltante está em `try/catch` que degrada (aviso e segue), acrescentar na bateria, logo acima do `cp` do script que o exige, `# caixa-sem: <caminho> — <o que degrada, em poucas palavras>`; se não degrada (o script quebra sem a lib), acrescentar o `cp` que falta **e** listar a bateria no relatório como defeito latente achado. Nenhuma outra edição nas baterias.
- `scripts/varrer-baterias.sh`: logo antes de `vermelhas=()`, quando não é `--so` e o shard é vazio ou `1/<n>`: `echo "----- conferir-caixas -----"`, roda `node scripts/conferir-caixas.cjs`; saída ≠ 0 acrescenta `conferir-caixas` a `vermelhas` (o array é criado antes, então mover a linha `vermelhas=()` para cima do bloco).

### 3. Versão MINOR, README e CHANGELOG [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 2
mutacao: n/a
  motivo: só versão e texto; comportamento medido pelas tarefas 1 e 2
pronto quando: com a `main` trazida para a branch, `node scripts/conferir-versao.cjs` sai 0 e os quatro lugares (dois `plugin.json`, selo do README com `vers%C3%A3o-X-` e `alt="versão X"`, topo do CHANGELOG `## X — AAAA-MM-DD`) dizem a versão seguinte à da `main` na casa MINOR (2.12.0 se a `main` estiver em 2.11.1); o CHANGELOG descreve pelo comportamento o checador, onde ele roda e a linha `# caixa-sem:` — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n 'alt="versão' README.md; grep -n -m2 -A3 '^## ' CHANGELOG.md`
