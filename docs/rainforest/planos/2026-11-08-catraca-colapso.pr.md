## Resumo

A catraca de mutação aprovava como "bateria VERMELHA, a bateria sabe falhar" uma mutação que deixava o fonte com `SyntaxError`: todos os casos da bateria saíam 1 porque o código nem carregava. Aconteceu no fluxo `busca-doc` (PR #667). Agora o `conferir-mutacao.cjs` confere a sintaxe do fonte mutado antes de rodar a bateria:

```
baseline verde → conferirSintaxe(original)
mutação escrita → original carregava? → conferirSintaxe(mutado)
                                         └─ não carrega → RECUSADO, exit 6, bateria não roda
```

- `.js`, `.cjs`, `.mjs`: `node --check` com o node da própria catraca. `.sh`, `.bash`: `bash -n` com o bash que roda a bateria. Outra extensão, ferramenta ausente ou original que já não passava: segue como antes.
- A recusa cita a linha `SyntaxError` do node (mesmo quando o caminho do fonte contém "error") ou a mensagem do `bash -n`.
- A tabela de saídas de `skills/executar/references/catraca-de-mutacao.md` ganha a linha do exit 6, que faltava.
- A fixture do caso 6 de `testa-conferir-mutacao.sh` (teto de tempo) mutava `const campo` para `const campo // MARCA`, o que já quebrava a sintaxe; virou comentário de bloco, e o caso continua medindo o estouro sem veredito.
- Versão 2.9.1 (PATCH: conserto da trava de colapso que já existia).

Decisões tomadas sem rodada, para veto: D1 (conferir o artefato, não procurar `SyntaxError` na saída da bateria), D2 (só recusa quando o original carregava), D3 (exit 6, sem rodar a bateria).

## Evidência

- **Antes** (`main`), raiz com `f.cjs` = `const w = 4;` e bateria que sai 1 quando o fonte tem `w = ;`:
  `node scripts/conferir-mutacao.cjs --raiz <raiz> --arquivo f.cjs --de "const w = 4;" --para "const w = ;" --bateria "bash b.sh"` → `ok: bateria VERMELHA ... A bateria sabe falhar.`, exit 0.
  **Depois:** `RECUSADO: a mutação quebrou a sintaxe de f.cjs — a bateria não rodou.` / `SyntaxError: Unexpected token ';'`, exit 6, e o `f.cjs` da raiz continua `const w = 4;`.
- `bash scripts/testa-conferir-mutacao.sh`: `ok: 230   falhou: 0`. A seção 14d nova cobre `.cjs` quebrado (com sentinela fora da cópia provando que a bateria não rodou), `.sh` quebrado, `.cjs` que já não carregava (aprova a vermelha) e fonte em `errors-repo/` (cita a linha do `SyntaxError`, não o caminho).
- Mutações: `void sintaxeMutado;` no lugar da recusa deixa a 14d vermelha (6 falhas, inclusive a da sentinela); `/^\w*Error\b/` → `/error/i` deixa vermelho só o caso `errors-repo`.
- Vizinhas que usam a catraca, todas verdes: `-flaky` (45), `-no-lugar` (70), `-placar` (41), `testa-conferir-fluxo` (142), `testa-integrar-tarefa` (78), `testa-estado` (337), `testa-estado-flaky` (36), `testa-camadas` (22), `testa-conferir-invariantes` (32), `testa-mutacao-mediu.cjs` e `testa-conta-api.cjs`.

## Perigo de merge

**Porta:** mão dupla — um revert desfaz.
**Raio de impacto:** pequeno. Só muda o veredito de mutação que deixa `.js`/`.cjs`/`.mjs`/`.sh` sem carregar, de 0 (vermelho falso) para 6. Mutação válida segue igual (a revisão testou ESM, shebang, top-level await, caminho com espaço e `.sh` com sintaxe só de bash, sem falso colapso).

## Deixado para depois

- revisar: revisao-3: emenda 1 do plano cita o seletor sem o `\b` → descartada: o plano e registro do fluxo; a emenda 2 cita o regex completo e o codigo e a fonte
- revisar: revisao-3: o restauro do exige confere fonte.cjs, nao errors-repo/f.cjs → descartada: a catraca roda em copia e nao escreve no fonte real; o restauro do no-lugar tem bateria propria

🤖 Generated with [Claude Code](https://claude.com/claude-code)
