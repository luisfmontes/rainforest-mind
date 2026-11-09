## Resumo

`gate-worktree` decide se um subagente pode escrever. Duas leituras erradas liberavam a escrita no checkout principal:

```
git não responde num repositório     antes: "fora de repositório" → passa
                                     agora: subagente barrado, com aviso em stderr
checkout sob pasta chamada worktrees antes: lido como worktree linkado → passa
                                     agora: compara --git-dir com --git-common-dir
```

Com o git fora, `.git` arquivo (worktree linkado, submódulo) e pasta sem `.git` seguem livres, e a janela principal nunca é barrada por isso. Com o git funcionando, submódulo herda o estado do superprojeto, como já acontecia na prática.

Closes #671

## Evidência

Revisor rodou o gate da base e o do head em 23 estados reais, com `Write` de subagente:

- **Antes (`3099637`):** sem git no PATH, checkout principal → exit 0. Principal sob pasta `worktrees`, de subpasta → exit 0.
- **Depois:** os dois → exit 2. Com o git funcionando, nenhum outro estado mudou de decisão.

`bash hooks/testa-gate-worktree.sh` → `== resultado: 916 ok, 0 falha(s) ==`. Catraca do `marcar verificar`: tarefas 1, 2 e 3 `vermelho`; tarefa 4 `pulada (n/a)`.

## Perigo de merge

**Porta:** mão dupla — um revert desfaz.
**Raio de impacto:** gate — sem git funcionando, subagente fora de `.git` arquivo passa a ser barrado, de propósito. A bateria do gate leva 7 min sozinha, e o plano declara `timeout: 1200000` para a catraca.

## Deixado para depois

- revisar: design D5 nao cita is-inside-git-dir nem superprojeto → descartada: o design registra a decisao, que nao mudou; o complemento esta nas emendas das revisoes 1 e 2 do plano
- revisar: comentario em contexto-sessao.cjs:890 sobre fail-open → descartada: o texto continua certo para a janela principal, unica usuaria de sessaoColocada

🤖 Generated with [Claude Code](https://claude.com/claude-code)
