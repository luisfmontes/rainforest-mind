# Plano: a catraca recusa a mutação que quebra a sintaxe do fonte

Design: docs/rainforest/design/2026-11-08-catraca-colapso.md

## O que não pode quebrar
- Todo caso que `scripts/testa-conferir-mutacao.sh` tem hoje continua com o mesmo exit e a mesma mensagem, em especial 1 (vermelho aprova), 4 (verde recusa), 14, 14b e 14c (colapso por placar).
- Mutação que mantém a sintaxe válida segue o caminho de hoje: a conferência nova não muda o veredito dela.
- Arquivo de extensão fora de `.js`, `.cjs`, `.mjs`, `.sh` e `.bash` segue sem conferência nenhuma.
- No modo no lugar (`--no-lugar`), o fonte real volta ao original em toda saída, inclusive na recusa nova.

## Tarefas

### 1. Conferência de sintaxe do fonte mutado antes da bateria [tipo: implementar]
atende: D1, D2, D3
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/testa-conferir-mutacao.sh`
depende de: nenhuma
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: `if (sintaxeMutado && !sintaxeMutado.ok) recusaSintaxe(rel, sintaxeMutado.erro);`
  para: `void sintaxeMutado;`
  bateria: `bash scripts/testa-conferir-mutacao.sh`
  fixture: `testa-conferir-mutacao.sh, seção "14d. mutacao que quebra a sintaxe do fonte e colapso, sem rodar a bateria"`
prova: `D=$(mktemp -d) && printf 'const w = 4;\n' > "$D/f.cjs" && printf 'grep -q "w = ;" f.cjs && exit 1\nexit 0\n' > "$D/b.sh" && node scripts/conferir-mutacao.cjs --raiz "$(cygpath -m "$D")" --arquivo f.cjs --de "const w = 4;" --para "const w = ;" --bateria "bash b.sh" > /dev/null 2>&1; test $? -eq 6`
pronto quando: com uma raiz em `mktemp -d` contendo `f.cjs` (`const w = 4;`) e uma bateria que sai 1 quando o fonte tem `w = ;`, a mutação `--de "const w = 4;" --para "const w = ;"` sai 6 com `RECUSADO: a mutação quebrou a sintaxe de f.cjs` e a linha do `SyntaxError` do node, sem rodar a bateria pós-mutação, e o `f.cjs` da raiz continua `const w = 4;`; o mesmo com um `.sh` (`echo ok` → `if then`) sai 6 pelo `bash -n`; um `.cjs` cuja sintaxe já é inválida antes da mutação segue sem conferência e sai 0 quando a bateria fica vermelha; e todos os casos que já existiam saem iguais — provado por `bash scripts/testa-conferir-mutacao.sh` saindo 0 com a seção 14d listando cada caso pelo nome, e pela mutação acima deixando a 14d vermelha

Forma prescrita:
- Função `conferirSintaxe(arquivo)` em `scripts/conferir-mutacao.cjs`, junto de `bateriaColapsou` e `recusaColapso`. Devolve `null` quando não há conferência, `{ ok: true }` ou `{ ok: false, erro: '<linha>' }`.
  - Extensão (`path.extname(arquivo).toLowerCase()`) em `.js`, `.cjs`, `.mjs`: `spawnSync(process.execPath, ['--check', arquivo], { encoding: 'utf8', timeout: 30000 })`.
  - Extensão em `.sh`, `.bash`: `const bash = caminhoExecutavel('bash')`; `null`, ou caminho que casa `/\\(system32|windowsapps)\\/i` (bash do WSL), devolve `null`; senão `spawnSync(bash, ['-n', arquivo], { encoding: 'utf8', timeout: 30000 })`.
  - Outra extensão: `null`.
  - `r.error` (spawn falhou, estouro) ou `r.status === null`: `null`. `r.status === 0`: `{ ok: true }`. Senão `{ ok: false, erro }`, com `erro` = a primeira linha de `stderr + stdout` que contém `Error` ou `error`; sem nenhuma, a primeira não vazia; sem nenhuma, `exit <status>`.
- Função `recusaSintaxe(rel, erro)`: imprime em stderr `RECUSADO: a mutação quebrou a sintaxe de ${rel} — a bateria não rodou.`, depois `  ${erro}`, depois `  A mutação tem de manter o fonte carregável: refine o --para (ou o --de).`, e `process.exit(6)`. A palavra `colapsou` não aparece: a mensagem diz o que houve.
- Ordem em `main`: `const sintaxeOriginal = conferirSintaxe(alvo);` logo antes do comentário `// ======================================================== Fase 3: mutação` (depois do baseline e das recusas de `--de`). Depois do `try { ... fs.writeFileSync(alvo, mutado); } catch ...` e antes do comentário `// ============================================ Fase 4: bateria pós-mutação`: `const sintaxeMutado = sintaxeOriginal && sintaxeOriginal.ok ? conferirSintaxe(alvo) : null;` e, numa linha só, `if (sintaxeMutado && !sintaxeMutado.ok) recusaSintaxe(rel, sintaxeMutado.erro);`. A restauração do modo no lugar e a limpeza da cópia já rodam na saída do processo.
- No cabeçalho do arquivo, a entrada ` *   6  bateria colapsou ...` ganha, depois de `exercitar qualquer comportamento`, a continuação `; ou a mutação quebrou a sintaxe do fonte (\`node --check\` / \`bash -n\`), e a bateria nem rodou`, no mesmo alinhamento das linhas de cima.
- **Bateria:** seção nova em `scripts/testa-conferir-mutacao.sh`, logo depois da 14c, aberta por `echo "== 14d. mutacao que quebra a sintaxe do fonte e colapso, sem rodar a bateria =="`, com o idioma da 14c (`cat > "$CAIXA/..."`, `cp` para `$S/*.pristino`, `exige`, `tem`, `nao_tem`, e o `cmp` de restauração que conta em `ok`/`falhou`):
  1. `fonte-sintaxe.cjs` (`const w2 = 4;`) e `bateria-sintaxe.sh`, que faz `touch sentinela-sintaxe` e sai 1 quando o fonte tem `w2 = ;`, e sai 0 sem tocar nada no caso contrário. `exige 6 ... CHK --arquivo fonte-sintaxe.cjs --de "const w2 = 4;" --para "const w2 = ;" --bateria 'bash bateria-sintaxe.sh'`; `tem` "quebrou a sintaxe de fonte-sintaxe.cjs"; `tem` "SyntaxError"; afirma que `$CAIXA/sentinela-sintaxe` não existe (a catraca roda numa cópia, então a sentinela da cópia some com ela; o que se afirma é que nenhuma sentinela vazou para a caixa) e que o fonte foi restaurado.
  2. `fonte-sintaxe.sh` (`echo ok`) com `bateria-sintaxe-sh.sh`, que sai 1 quando o fonte tem `if then` e 0 senão. `exige 6` com `--de "echo ok" --para "if then"`; `tem` "quebrou a sintaxe de fonte-sintaxe.sh".
  3. `fonte-ja-invalido.cjs` (`const z = ;` e, na linha seguinte, `const y3 = 1;`) com uma bateria que sai 1 quando o fonte tem `MARCA-JA-INVALIDO` e 0 senão. `exige 0` com `--de "const y3 = 1;" --para "const y3 = 1; // MARCA-JA-INVALIDO"`; `nao_tem` "quebrou a sintaxe".

### 2. A tabela de saídas da catraca ganha o exit 6 [tipo: docs]
atende: D3
arquivos: `skills/executar/references/catraca-de-mutacao.md`
depende de: 1
mutacao: n/a
  motivo: texto de referência; o comportamento é medido pela tarefa 1
Forma: a tabela de `skills/executar/references/catraca-de-mutacao.md` (linhas `| exit | significa | o que fazer |`) não tem a linha do `6`. Ela entra entre a do `5` e a do `1`: `| \`6\` | a bateria não mediu: COLAPSOU (placar zerado ou sumiu na pós-mutação), ou a mutação quebrou a sintaxe do fonte (\`node --check\` / \`bash -n\`, antes de rodar a bateria) | refine a mutação ou a bateria; nada foi medido |`. O parágrafo do `//` no Git Bash ganha, no fim, a frase: "Se a barra que sobra deixa o fonte inválido, a catraca agora sai 6 em vez de rodar a bateria."
pronto quando: com `skills/executar/references/catraca-de-mutacao.md` deste worktree, a tabela tem uma linha por exit que `scripts/conferir-mutacao.cjs` usa (`0`, `2`, `3`, `4`, `5`, `6`, `1`, `69`), e a linha do `6` cobre as duas causas (colapso por placar e sintaxe quebrada) com a mesma ação; e `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` saem 0 — provado por `grep -n "^| \`" skills/executar/references/catraca-de-mutacao.md` e `grep -on "process.exit([0-9]*)" scripts/conferir-mutacao.cjs | sort -t'(' -k2 -u`, comparados, e pelas três baterias

### 3. Versão 2.9.1 e CHANGELOG [tipo: docs]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 2
mutacao: n/a
  motivo: só versão e texto; o comportamento é medido pela tarefa 1
Forma: o selo do README (`vers%C3%A3o-2.9.0` na URL e `versão 2.9.0` no `alt`) muda nos dois lugares; o `README.en.md` fica intocado. O CHANGELOG ganha `## 2.9.1 — 2026-11-08` acima da 2.9.0, um item `- **<título>.** <texto>` que diz o que a catraca passa a fazer (confere a sintaxe do fonte mutado com `node --check` ou `bash -n` e sai 6 sem rodar a bateria) e o incidente que motivou (vermelho aprovado sobre fonte com `SyntaxError`).
pronto quando: com o repositório deste worktree, `node scripts/conferir-versao.cjs` sai 0, os dois `plugin.json` dizem `"version": "2.9.1"`, o selo do README diz `versão 2.9.1`, e o CHANGELOG abre com `## 2.9.1 — 2026-11-08` descrevendo o comportamento novo — provado por `node scripts/conferir-versao.cjs; grep -n '"version"' .claude-plugin/plugin.json .codex-plugin/plugin.json; grep -n "2.9.1" README.md CHANGELOG.md`

## Emendas do leitor cego

- Tarefa 1, caso 1 da 14d: a catraca roda a bateria numa cópia da raiz, então uma sentinela relativa nunca chega à caixa e a afirmação passaria sempre. A `bateria-sintaxe.sh` é escrita com heredoc **sem aspas** e grava a sentinela no caminho absoluto `$S/sentinela-sintaxe` (fora da caixa e da cópia), só no ramo em que o fonte tem `w2 = ;`; o caso afirma que `$S/sentinela-sintaxe` não existe depois da catraca. Assim uma regressão que rode a bateria antes de recusar fica vermelha.
- Tarefa 1, mensagem: a linha citada é a primeira que contém `Error` ou `error` (a primeira não vazia do `node --check` é o caminho do arquivo). Isso refina o "primeira linha não vazia" do D3, que fica como fallback.
- Tarefa 1, `bash -n` recebe `alvo` como está (caminho absoluto do Windows); o Git Bash aceita.
- Tarefa 1, `const sintaxeOriginal = conferirSintaxe(alvo);` entra depois dos `console.log` do `casou` e imediatamente antes do comentário da Fase 3.
- Tarefa 1, rótulos: os `exige`/`tem`/`nao_tem` da 14d nomeiam o caso pelo que afirmam (ex.: "mutacao que quebra a sintaxe do .cjs sai 6").
- Tarefa 2: os exits esperados na tabela são `0 2 3 4 5 6 1 69`, um por linha.
- Tarefa 3: título do item do CHANGELOG: "A catraca recusa a mutação que quebra a sintaxe do fonte."

## Emendas da revisão 1

- Tarefa 1: `conferirSintaxe` e `recusaSintaxe` saem do meio do docblock de `bateriaColapsou` e vão para depois de `recusaColapso`. A linha citada na recusa prefere a que começa com `XxxError` (a do node), depois a primeira que fala de erro (a do `bash -n`), porque a primeira linha do `node --check` é o caminho e pode conter "error" (pasta `errors-repo`).
