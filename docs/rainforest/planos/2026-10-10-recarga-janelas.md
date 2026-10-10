# Plano: recarga do plugin em todas as janelas por marcador

Design: docs/rainforest/design/2026-10-10-recarga-janelas.md

## O que não pode quebrar
- O `/plugins-em-dia` e a rodada automática seguem como hoje na janela que atualiza: `node hooks/testa-mod-plugins-em-dia.cjs` e os casos `plugins-em-dia:` de `claude plugin test .` verdes.
- Falha aberta: marcador ausente, ilegível ou escrita que falha nunca quebra a sessão nem a rodada.

## Tarefas

### 1. Lógica pura do marcador [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `hooks/recarga-puro.mjs`, `hooks/testa-mod-recarga.cjs`
depende de: nenhuma
paralela: nao
prova: `node -e "import('./hooks/recarga-puro.mjs').then(m=>process.exit(typeof m.deveRecarregar==='function'?0:1))"`
mutacao:
  arquivo: `hooks/recarga-puro.mjs`
  de: `if (typeof tratadoEm === 'number' && m.at <= tratadoEm) return null;`
  para: `if (false) return null;`
  bateria: `node hooks/testa-mod-recarga.cjs`
  fixture: `testa-mod-recarga.cjs, caso "o mesmo marcador age uma vez so"`
pronto quando: `caminhoMarcador({ CLAUDE_CONFIG_DIR, HOME })` devolve `<config>/plugins/data/rainforest-mind-rainforest-mind/recarga-pedida.json` (com `HOME/.claude` sem `CLAUDE_CONFIG_DIR`); `textoMarcador(at)` e `lerMarcador(texto)` fazem ida e volta, e `lerMarcador` devolve `null` para texto ausente, JSON quebrado, `v` diferente de 1 ou `at` não numérico; `deveRecarregar({ marcador, carregadoEm, tratadoEm })` devolve o `at` só quando ele é maior que `carregadoEm` e que `tratadoEm`, e `null` nos demais — provado por `node hooks/testa-mod-recarga.cjs` imprimindo `N ok, 0 falha(s), 0 skipped`.

### 2. Fiação no plugins-em-dia [tipo: implementar]
atende: D1, D2, D3
arquivos: `hooks/plugins-em-dia.ts`, `hooks/mod-recarga.test.tsx`, `hooks/mod-relogio.test.tsx` (emenda: o teste do relógio desliga a conferência pelo `RAINFOREST_RECARGA=off`; o relógio simulado comprime horas e cada conferência custa uma ida ao harness)
depende de: 1
paralela: nao
prova: `bash -c "test -f hooks/mod-recarga.test.tsx && claude plugin test ."`
mutacao:
  arquivo: `hooks/plugins-em-dia.ts`
  de: `if (recarga.desligada || recarga.caminho === '') return`
  para: `if (true) return`
  bateria: `claude plugin test .`
  fixture: `mod-recarga.test.tsx, caso "marcador de outra janela recarrega uma vez"`
pronto quando: `claude plugin test .` sai 0 com: (a) uma rodada em que um plugin sobe grava o marcador por `$.fs.write` no caminho de `caminhoMarcador`; (b) numa sessão sem atualização, um marcador com `at` depois da abertura faz, com `recarregarSozinho`, um `/reload-plugins` em até 5 s e nenhum segundo para o mesmo marcador; (c) sem `recarregarSozinho`, um toast com "/reload-plugins" uma vez só; (d) marcador anterior à abertura não faz nada; (e) `RAINFOREST_RECARGA=off` não faz nada; (f) a janela que gravou o marcador não recarrega de novo por ele; e os casos `plugins-em-dia:` existentes seguem verdes.

### 3. Versão e docs [tipo: docs]
atende: D5
arquivos: `CHANGELOG.md`, `CONTRIBUTING.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: documentação e versão; a falsificação é a coerência com o código entregue.
pronto quando: `node scripts/conferir-versao.cjs` e `bash scripts/testa-versao.sh` saem 0 com o MINOR novo nos dois `plugin.json` e no badge, e o CHANGELOG diz o que muda para quem usa, com crédito ao Rafael.

## Cobertura

D1: 1, 2 · D2: 1, 2 · D3: 1, 2 · D4: 1 · D5: 3
