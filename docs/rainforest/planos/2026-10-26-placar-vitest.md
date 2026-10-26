# Plano: Catraca de mutação lê o placar do vitest (#602)

Design: docs/rainforest/design/2026-10-26-placar-vitest.md

## O que não pode quebrar
- As formas que `extrairPlacar` já lê (`ok: N falhou: M`, `N ok, M falha(s)`, `ok=N falhou=M`, libtest) devolvem o mesmo placar de antes; as do repo continuam vencendo por posição.
- Bateria que morre sem placar depois de um baseline com placar continua sendo colapso (exit 6) — inclusive no vitest, cujo import quebrado imprime `Tests  no tests`.
- `mediuEFalhou` e `suspeitaDeCorte` não mudam: o conserto entra só pela leitura do placar.

## Tarefas

### 1. extrairPlacar lê a linha `Tests` do vitest por segmento [tipo: implementar]
atende: D1, D2, D4
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao-placar.sh`
depende de: nenhuma
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (s[2] === 'failed') falhou += parseInt(s[1], 10);`
  para: `if (s[2] === 'failed') falhou += 0;`
  bateria: `bash scripts/testa-conferir-mutacao-placar.sh`
  fixture: `testa-conferir-mutacao-placar.sh, secoes "10. vitest" (unitarios) e "11. #602" (ponta a ponta)`
prova: `node -e "const m=require('./scripts/conferir-mutacao.cjs');const a=m.extrairPlacar('      Tests  1 failed (1)');const b=m.extrairPlacar('      Tests  1 failed | 1 passed | 1 skipped (3)');process.exit(a&&a.ok===0&&a.falhou===1&&b&&b.ok===1&&b.falhou===1?0:1)"`
pronto quando: com a saída real do vitest 4.1.11 capturada em 2026-10-26 (design, "Avaliado e descartado"), `extrairPlacar` devolve `0 1` para `Tests  1 failed (1)`, `1 1` para `Tests  1 failed | 1 passed | 1 skipped (3)`, `2 0` para `Tests  2 passed | 1 skipped (3)`, a soma de duas linhas `Tests`, e `null` para `Tests  no tests` e para `Test Files  1 failed (1)` sozinho; o placar do repo vence a linha do vitest quando os dois aparecem; `mediuEFalhou` dá `true` para o vermelho do vitest e `false` para o verde. De ponta a ponta, uma bateria com baseline de 8 s imprimindo `Tests  2 passed | 1 skipped (3)` e pós-mutação rápida imprimindo `Tests  1 failed (1)` faz o `conferir-mutacao.cjs` sair 0 com `VERMELHA` e sem `suspeita de corte` (antes: exit 5); e a mesma bateria com pós-mutação imprimindo `Tests  no tests` sai 6 (colapso) — provado por `bash scripts/testa-conferir-mutacao-placar.sh` mostrando essas linhas `ok` nas seções 10 e 11, e pelo `node -e` da `prova:` saindo 0.

Forma prescrita do código (D2): depois do bloco do libtest, que passa a retornar quando acha, um laço sobre `/^[ \t]*Tests[ \t]+(.+?)[ \t]*\(\d+\)[ \t]*\r?$/gm`; cada segmento de `m[1].split('|')` casa `^\s*(\d+)\s+(failed|passed|skipped|todo)\s*$`, soma `passed` em `ok` e `failed` em `falhou`. Nenhum caso de teste lê o texto do fonte: os casos chamam `extrairPlacar`, `mediuEFalhou` e o CLI.

### 2. Versão 2.0.3: CHANGELOG, README e manifestos [tipo: docs]
atende: D1, D3
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: tarefa de documentação e número de versão; não há comportamento a inverter.
pronto quando: com o manifesto da worktree, `node scripts/conferir-versao.cjs` reporta `versao 2.0.3`; a entrada `## 2.0.3` do CHANGELOG diz que a forma nova é só a do vitest (D1, com Jest e pytest fora), que a linha é lida por segmento (`Tests  1 failed (1)` incluído) e que o aquecimento ficou de fora, plantado (D3); a linha do `conferir-fluxo.cjs mutacoes` no README lista a forma do vitest entre as reconhecidas; o selo do README e os dois `plugin.json` dizem 2.0.3 — provado por `node scripts/conferir-versao.cjs` e `grep -n "2\.0\.3\|vitest" README.md CHANGELOG.md .claude-plugin/plugin.json .codex-plugin/plugin.json`.
