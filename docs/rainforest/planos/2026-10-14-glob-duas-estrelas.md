# Plano: conferir-entrega: `--escopo` com a mesma regra de glob do creep (#518)

Design: docs/rainforest/design/2026-10-14-glob-duas-estrelas.md

## O que não pode quebrar
- Os casos `--escopo` atuais de `scripts/testa-conferir-entrega.sh` (`feito.txt` literal, `gerado/**` um nível, arquivo modificado/deletado fora reprovando e sendo nomeado) seguem com o mesmo exit.
- Sem `--escopo`, nada é filtrado (`bateComEscopo` devolve true com lista vazia).
- O `creep` (`conferir-fluxo.cjs`) só muda pela âncora de D5: `bash scripts/testa-conferir-fluxo.sh` segue verde, com casos novos de âncora.
- Os dois gêmeos dão o mesmo placar na bateria: `bash scripts/testa-conferir-entrega.sh` e `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`.

## Tarefas

### 1. `--escopo` pelo `globMatches` nos dois gêmeos, com bateria [tipo: implementar]
atende: D1, D2, D3, D4, D5
arquivos: `scripts/conferir-entrega.cjs`, `scripts/conferir-entrega.py`, `scripts/testa-conferir-entrega.sh`, `scripts/lib/camadas.cjs`, `scripts/testa-conferir-fluxo.sh`
depende de: nenhuma
prova-na-base: verde — o caso que falha na base (`src/**` com arquivo dois níveis abaixo) é montado pela própria bateria em repo git de verdade com worktree, e a bateria só ganha esse caso com a tarefa
mutacao:
  arquivo: `scripts/conferir-entrega.cjs`
  de: if (globMatches(cami, g)) return true;
  para: if (cami === g) return true;
  bateria: `bash scripts/testa-conferir-entrega.sh`
  fixture: testa-conferir-entrega.sh, casos novos de --escopo (`src/**` dois níveis aprova; pasta com barra final aprova)
pronto quando: com um worktree git real em que o agente commitou `src/a/b.txt` e `docs/x/y.md`, `conferir-entrega` com `--escopo "src/**" --escopo "docs/x/"` aprova (exit 0), com `--escopo "src/*"` reprova (exit 1) nomeando `src/a/b.txt`, e com `--escopo "a/**/b.txt"` e arquivo `a/b.txt` reprova (D2) — tudo isso nos dois gêmeos, provado por `bash scripts/testa-conferir-entrega.sh` e `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh`, ambos com zero FALHA e o mesmo número de `ok`.

Forma do código: no `.cjs`, `globToRegex` sai e `bateComEscopo` importa `globMatches` de `scripts/lib/camadas.cjs`; o laço tem exatamente uma linha `if (globMatches(cami, g)) return true;`, com `cami` e `g` já normalizados (contrabarra para `/`, minúsculas) como hoje. No `.py`, `globToRegex` é substituída por uma função `glob_casa(arquivo, glob)` que porta o algoritmo de `globMatches` linha a linha (barra final = prefixo; sem curinga = igualdade; `**` = `.*`, `*` = `[^/]*`, `?` = `[^/]`; âncora `^` só se o glob não começa com `*`, `$` só se não termina com `*`). Nenhum caso de teste lê o texto do fonte.

Emenda 2026-10-14 (D5): `globMatches` em `scripts/lib/camadas.cjs` passa a montar o regex sempre com `^` no início e `$` no fim (somem os dois `if` de âncora condicional); `glob_casa` do `.py` porta o mesmo. Casos novos em `scripts/testa-conferir-fluxo.sh` (no estilo dos de `globMatches` já existentes): `src/*` não casa `src/a/b.txt`; `*.md` não casa `docs/x.md`; `*.md` casa `x.md`; `src/*` casa `src/b.txt`.

Casos novos na bateria (cada um num repo/worktree de verdade, como os atuais):
- `--escopo "src/**"` com `src/a/b.txt` commitado: exit 0.
- `--escopo "docs/x/"` com `docs/x/y.md`: exit 0.
- `--escopo "src/*"` com `src/a/b.txt`: exit 1 e a saída nomeia `src/a/b.txt`.
- `--escopo "a/**/b.txt"` com `a/b.txt`: exit 1 (D2).

### 2. CHANGELOG, README e versão 1.67.1 [tipo: docs]
atende: D1
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: tarefa de documentação e número de versão; não há comportamento a inverter
pronto quando: com a tarefa 1 no repo, a entrada `## 1.67.1 — 2026-10-14` do CHANGELOG descreve o mesmo contrato de D1/D2 (`**` atravessa pastas, barra final cobre a pasta, mesma regra do `creep`, `a/**/b` não casa `a/b`), as duas `plugin.json` e o selo do README dizem 1.67.1, provado por `node scripts/conferir-versao.cjs` saindo 0 e por leitura do revisor confrontando a entrada com D1/D2.
