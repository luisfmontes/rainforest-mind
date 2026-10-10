# Plano: aviso de PR sem repetição e node absoluto na abertura

Design: docs/rainforest/design/2026-10-10-pr-aviso-node.md

## O que não pode quebrar
- Painel de PR, barra, relógio e abertura seguem verdes: `node hooks/testa-mod-pr.cjs`, `node hooks/testa-mod-painel.cjs`, `node hooks/testa-mod-relogio.cjs`, `node hooks/testa-mod-abertura.cjs` e `claude plugin test .`.
- Falha aberta: sem `node` achado a abertura sai `null` e o resto do mod segue.

## Tarefas

### 1. Motivo herdado na leitura sem dado de merge [tipo: implementar]
atende: D1
arquivos: `hooks/pr-puro.mjs`, `hooks/pr.tsx`, `hooks/testa-mod-pr.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-pr.cjs`
mutacao:
  arquivo: `hooks/pr-puro.mjs`
  de: `if (!velho || novo.motivo !== SEM_DADO) return novo;`
  para: `return novo;`
  bateria: `node hooks/testa-mod-pr.cjs`
  fixture: `testa-mod-pr.cjs, caso "conflito, sem dado, conflito acorda uma vez"`
pronto quando: com resumos reais de `resumir()`, a sequência conflito → `UNKNOWN` → conflito passada por `herdarMotivo` e `virada` dá `'conflito'` uma vez só (na primeira leitura de conflito vinda de motivo limpo) e `null` nas outras; `herdarMotivo` não muda `mergavel`; sem `velho` devolve `novo` intacto; e o `pr.tsx` aplica `herdarMotivo` antes de `eventos`, do `update` de `prResumo` e de `virada` — provado por `node hooks/testa-mod-pr.cjs` imprimindo `N ok, 0 falha(s), 0 skipped`.

### 2. node absoluto na abertura e cache do fracasso [tipo: implementar]
atende: D2, D3
arquivos: `hooks/abertura-mod-puro.mjs`, `hooks/register.ts`, `hooks/mod.tsx`, `hooks/testa-mod-abertura.cjs`, `hooks/mod-relogio.test.tsx`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-mod-abertura.cjs`
mutacao:
  arquivo: `hooks/mod.tsx`
  de: `if (falhou > 0 && agora - falhou < NODE_FALHA_TTL_MS) return null`
  para: `if (false) return null`
  bateria: `claude plugin test .`
  fixture: `mod-relogio.test.tsx, caso "localizador do node que falhou nao roda de novo no prazo"`
pronto quando: `node hooks/testa-mod-abertura.cjs` sai `N ok, 0 falha(s), 0 skipped` com os geradores chamados com `argv[0]` igual ao caminho que `deps.node` devolve (absoluto), e com `deps.node` devolvendo `null` a abertura sai `null` sem chamar processo; `claude plugin test .` sai 0 com um caso em que os localizadores do `node` falham, e dentro de 5 minutos de relógio do engine um segundo uso não os chama de novo, e depois do prazo chama.

### 3. Versão e docs [tipo: docs]
atende: D4
arquivos: `CHANGELOG.md`, `CONTRIBUTING.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1, 2
paralela: nao
mutacao: n/a
  motivo: documentação e versão; a falsificação é a coerência com o código entregue.
pronto quando: `node scripts/conferir-versao.cjs` e `bash scripts/testa-versao.sh` saem 0 com a versão PATCH nova nos dois `plugin.json` e no badge, e o CHANGELOG cita a #480 e a #482.

## Cobertura

D1: 1 · D2: 2 · D3: 2 · D4: 3
