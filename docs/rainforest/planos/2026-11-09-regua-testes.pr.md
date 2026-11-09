## Resumo

```
marcar verificar ok
  └─ conferir-fluxo.cjs afrouxa  (base do revisar ... HEAD medido no exigir revisar)
       ├─ arquivo de teste apagado, ou renomeado para nome que não é de teste
       ├─ linha nova em teste com marcador de pulo ou foco
       └─ a tarefa do arquivo declara `afrouxa: <motivo>`? passa : exit 2
```

O `creep` autoriza tocar um arquivo, mas não distingue editar de tirar o teste do caminho, e a suíte continua verde quando o teste deixa de rodar. Parte 2 da ideia `regua-que-nao-afrouxa`.

## Evidência

Repositório sandbox com um diff que apaga `scripts/testa-x.sh`, passando pelo `marcar verificar ok` real (caso C1 de `scripts/testa-conferir-fluxo-afrouxa.sh`).

- **Antes** (a chamada desligada por mutação em `scripts/estado.cjs`):
  `FALHA C1 marcar verificar ok recusa bateria apagada sem afrouxa (exit 0)`: o fluxo fechava.
- **Depois:** exit 2, com `apagado: scripts/testa-x.sh` e `RECUSADO: o verificar não fecha`, e o estado não muda.

Bateria nova: `ok: 24   falhou: 0`. Catraca: tarefas 1 a 3 vermelhas, tarefa 4 pulada (`n/a`). O próprio diff deste PR passou pela trava: `ok: nenhum teste apagado ou pulado no diff`. `testa-estado.sh` 337 ok, `testa-estado-reabrir.sh` 97 ok, `testa-conferir-fluxo.sh` 142 ok.

Medição que decidiu o escopo: dos 821 commits que tocaram `testa-*.sh` desde 2026-09-01, 9 apagaram bateria e 16 tiraram asserção, todos legítimos. Por isso contar asserção ficou de fora, e apagar pede uma linha `afrouxa:`.

## Perigo de merge

**Porta:** mão dupla: um revert tira a trava.
**Raio de impacto:** pequeno. Afeta só o `marcar verificar ok` de fluxo com plano e diff que apaga ou pula teste; o remédio é uma linha no plano.

## Decidido sem você

O Luís confirmou D1 e D2 depois do achado `[design]` da revisão. D3 a D5 ficam para veto:
- **D3:** contar asserção fica fora.
- **D4:** o escape é `afrouxa: <motivo>` na tarefa cujo `arquivos:` casa o arquivo, sem `--forcar`.
- **D5:** saídas 0, 2 e 69; erro do git sai 1, e o `verificar` recusa em qualquer saída diferente de 0.

## Deixado para depois

- revisar: revisao-2: *.test.e2e.ts deixou de ser visto → descartada: falha aberta decidida para ver a.test.js.off; o verificar ja diz que nome fora dos padroes nao e visto
- revisar: revisao-2: sem snapshot o head declarado vale → descartada: so ocorre com revisar marcado sem exigir; o D1 diz quando existe e o snapshot e gravado a cada exigir revisar

🤖 Generated with [Claude Code](https://claude.com/claude-code)
