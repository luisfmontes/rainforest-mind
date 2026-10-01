# Plano: Rodada 13 — laço sem gh (#362), veredito no worktree do revisor (#363), menores do semear-travas (#364)

Design: docs/rainforest/design/2026-10-01-zerar-issues-13.md

## O que não pode quebrar
- `bash $VAR` sem aspas continua exit 2 no gate-fechar-issue (casos #337, #337f, #337g intactos); `bash "$t"` continua 0 (#309). Nenhuma resolução de variável entra em `hooks/lib/tokens-comando.cjs`.
- O veredito de um revisor não isolado continua gravando no worktree do fluxo, e o caso "estado só no worktree" da #329 continua verde.
- O gate-turno-prometido continua barrando a promessa fora de aspas e liberando os casos que já libera hoje (passado, negação, código, lista).
- `preparar-worktree --exige <caminho dentro do worktree>` e `varrer --slug <slug-em-kebab>` continuam como hoje.

## Tarefas

### 1. Mensagem do `bash $b` diz por que barra [tipo: implementar]
atende: D1
arquivos: `hooks/gate-fechar-issue.cjs`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
prova: `printf '%s' '{"tool_name":"Bash","tool_input":{"command":"for b in a.sh; do bash $b; done"}}' | node hooks/gate-fechar-issue.cjs 2>&1 | grep -q 'injetar -c'`
mutacao:
  arquivo: `hooks/gate-fechar-issue.cjs`
  de: sem aspas a variável se divide em palavras e pode injetar -c
  para: sem aspas a variável não é lida
  bateria: `bash hooks/testa-gate-fechar-issue.sh`
  fixture: testa-gate-fechar-issue.sh, seção "(#362) laco com bash $b sem aspas → exit 2 citando injetar -c"
Implementação: na mensagem do ramo `ilegivel` de `processarSegmento`, a frase condicional de `bash|sh $` passa a ser `Rodando um arquivo cujo caminho está numa variável? Ponha aspas: bash "$t" passa, bash $t não — sem aspas a variável se divide em palavras e pode injetar -c (ex.: CMD='-c gh${IFS}issue${IFS}close${IFS}12'; bash $CMD fecha a Issue).` A decisão de barrar não muda. Seção nova na bateria com três casos: `for b in a.sh; do bash $b; done` → exit 2 e stderr com "injetar -c"; `for b in a.sh; do bash "$b"; done` → exit 0; `bash -c "$x"` → exit 2 sem a frase (ela só sai para `bash|sh $`).
pronto quando: com o payload PreToolUse real `{"tool_name":"Bash","tool_input":{"command":"for b in a.sh; do bash $b; done"}}`, `node hooks/gate-fechar-issue.cjs` sai 2 e o stderr contém "injetar -c" e o exemplo com `${IFS}`; o mesmo com `bash "$b"` sai 0 — provado pela seção nova de `bash hooks/testa-gate-fechar-issue.sh` (0 falhas) e pelos casos #337, #337f e #337g verdes.

### 2. Veredito vai para o worktree do fluxo, não para o do revisor [tipo: implementar]
atende: D2
arquivos: `hooks/veredito-revisor.cjs`, `hooks/testa-veredito-revisor.sh`
depende de: nenhuma
paralela: sim
prova: `bash hooks/testa-veredito-revisor.sh 2>&1 | grep -qE '^ +ok +\(#363\)'`
mutacao:
  arquivo: `hooks/veredito-revisor.cjs`
  de: .filter((p) => !ehWorktreeDeAgente(p))
  para: .filter((p) => true)
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: testa-veredito-revisor.sh, seção "(#363) revisor em .claude/worktrees/agent-x com copia armada grava no worktree do fluxo"
Implementação: `raizComEstadoDoSlug` deixa de devolver o repoRoot só por ele ter o arquivo. Monta a lista de candidatos (repoRoot, se tem o arquivo, mais cada worktree de `git worktree list --porcelain` que tem o arquivo, sem repetir caminho), aplica exatamente `.filter((p) => !ehWorktreeDeAgente(p))` com `ehWorktreeDeAgente` importado de `hooks/lib/contexto-sessao.cjs`, e entre os que sobram, se mais de um, fica com os que têm `revisar.vereditos` como array no JSON (leitura que falha conta como não armado). Exatamente um → devolve; zero ou mais de um → as mensagens de hoje (`nao encontrado` / `ambiguo`) e `null`. Seção nova na bateria com dois casos, cada um com repo git real e worktrees reais: (a) revisor com `cwd` em `<repo>/.claude/worktrees/agent-x` (worktree linkado com cópia do estado armada) e fluxo em outro worktree linkado com o estado armado → a entrada `vereditos` aparece no JSON do fluxo e o JSON do agent-x fica byte a byte igual; (b) revisor não isolado, `cwd` no worktree do fluxo, com outro worktree antigo tendo cópia não armada → grava no do fluxo. Os rótulos de `ok` das duas linhas começam com `(#363)`.
pronto quando: com o payload SubagentStop real (`cwd` dentro de `.claude/worktrees/agent-x`, `agent_type` do revisor, `transcript_path` do transcrito do subagente com `Slug:` e `VEREDITO: ok`), `node hooks/veredito-revisor.cjs` grava a entrada em `revisar.vereditos` do worktree do fluxo e não toca a cópia do agent-x — provado pela seção nova de `bash hooks/testa-veredito-revisor.sh` (0 falhas) e pelo caso da #329 verde.

### 3. Aspas e crases só se pareiam quando abrem e fecham de verdade [tipo: implementar]
atende: D3
arquivos: `hooks/gate-turno-prometido.cjs`, `hooks/testa-gate-turno-prometido.cjs`
depende de: nenhuma
paralela: sim
prova: `node hooks/testa-gate-turno-prometido.cjs 2>&1 | grep -qE '^ +ok +#364-1'`
mutacao:
  arquivo: `hooks/gate-turno-prometido.cjs`
  de: normalizado = normalizado.replace(/(^|[\s(\[{:])"(?=\S)(?:[^"\n]|\n(?![ \t]*\n))*?"/g, '$1');
  para: normalizado = normalizado.replace(/"[^"]*"/g, '');
  bateria: `node hooks/testa-gate-turno-prometido.cjs`
  fixture: testa-gate-turno-prometido.cjs, casos "#364-1 aspas soltas na mesma linha" e "#364-2 citacao multi-linha"
Implementação: em `normalizarTexto`, a remoção de aspas vira exatamente a linha do `de:` acima (abre só depois de início, espaço ou `( [ { :`, seguida de não-espaço; atravessa quebra simples, nunca linha em branco), e a de código inline vira `normalizado = normalizado.replace(/`(?=[^\s`])[^`\n]*`/g, '');` (crase seguida de espaço não abre). Casos novos na bateria, transcritos no formato real: `#364-1 aspas soltas na mesma linha` (`O corte de 5" fica ok, vou despachar o executor agora, e o outro de 6" tambem.` sem Agent → exit 2); `#364-1b crases soltas na mesma linha` (`a crase ` solta, vou despachar o executor, e outra ` aqui.` sem Agent → exit 2); `#364-2 citacao multi-linha` (`Ele escreveu "vou\ndespachar o executor" ontem.` sem Agent → exit 0). Os casos existentes de aspas e código continuam verdes.
pronto quando: com o transcrito real cujo último texto do assistente é `O corte de 5" fica ok, vou despachar o executor agora, e o outro de 6" tambem.` e nenhum `Agent` no turno, `node hooks/gate-turno-prometido.cjs` sai 2 nomeando a promessa; com a citação de duas linhas entre aspas sai 0 — provado por `node hooks/testa-gate-turno-prometido.cjs` (0 falhas, os três casos novos presentes).

### 4. Citação em bloco `>` não conta como promessa [tipo: implementar]
atende: D3
arquivos: `hooks/gate-turno-prometido.cjs`, `hooks/testa-gate-turno-prometido.cjs`
depende de: 3
paralela: nao
prova: `node hooks/testa-gate-turno-prometido.cjs 2>&1 | grep -qE '^ +ok +#364-2b'`
mutacao:
  arquivo: `hooks/gate-turno-prometido.cjs`
  de: normalizado = normalizado.replace(/^[ \t]*>.*$/gm, '');
  para: normalizado = normalizado.replace(/^[ \t]*>NUNCA.*$/gm, '');
  bateria: `node hooks/testa-gate-turno-prometido.cjs`
  fixture: testa-gate-turno-prometido.cjs, caso "#364-2b citacao em bloco"
Implementação: em `normalizarTexto`, junto às remoções de lista, entra exatamente a linha do `de:` acima; o comentário de cabeçalho do arquivo passa a listar "aspas pareadas (inclusive multi-linha) e citação em bloco `>`". Caso novo `#364-2b citacao em bloco` (`> vou despachar o executor agora` citado, sem Agent → exit 0) e um controle (`vou despachar` fora da citação na linha seguinte → exit 2).
pronto quando: com o transcrito real cujo último texto é a citação `> vou despachar o executor agora` e nada mais, sem `Agent`, `node hooks/gate-turno-prometido.cjs` sai 0; com a mesma promessa fora do `>` sai 2 — provado por `node hooks/testa-gate-turno-prometido.cjs` (0 falhas).

### 5. `--exige` fora do worktree é recusado [tipo: implementar]
atende: D4
arquivos: `scripts/preparar-worktree.cjs`, `scripts/testa-preparar-worktree.sh`
depende de: nenhuma
paralela: sim
prova: `node scripts/preparar-worktree.cjs --hash HEAD --exige ../../../README.md >/dev/null 2>&1; test $? -eq 2`
mutacao:
  arquivo: `scripts/preparar-worktree.cjs`
  de: if (rel === "" || rel.startsWith("..") || path.isAbsolute(rel)) {
  para: if (false) {
  bateria: `bash scripts/testa-preparar-worktree.sh`
  fixture: testa-preparar-worktree.sh, caso "(#364) --exige ../../../README.md sai 2"
Implementação: em `conferirExige`, antes do `existsSync`, `const rel = path.relative(cwd, path.resolve(cwd, arquivo));` seguido exatamente da linha do `de:` acima, com `falha(2, "--exige fora do worktree: '" + arquivo + "'")`. Casos novos: `--exige ../../../README.md` → exit 2 com o valor no stderr; `--exige /c/qualquer/absoluto` (fora) → exit 2; `--exige README.md` → como hoje.
pronto quando: com um worktree real no hash do briefing, `node scripts/preparar-worktree.cjs --hash <H> --exige ../../../README.md` sai 2 e o stderr nomeia `../../../README.md`; `--exige README.md` sai 0 — provado por `bash scripts/testa-preparar-worktree.sh` (0 falhas).

### 6. `--slug` com caminho é recusado no varrer [tipo: implementar]
atende: D4
arquivos: `scripts/varrer.cjs`, `scripts/testa-varrer.sh`
depende de: nenhuma
paralela: sim
prova: `node scripts/varrer.cjs --slug a/b termo >/dev/null 2>&1; test $? -eq 2`
mutacao:
  arquivo: `scripts/varrer.cjs`
  de: if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(slug) || slug.includes('..')) {
  para: if (false) {
  bateria: `bash scripts/testa-varrer.sh`
  fixture: testa-varrer.sh, caso "(#364) --slug ../../x sai 2 sem gravar"
Implementação: logo depois do `if (!slug)`, entra exatamente a linha do `de:` acima com `erroUso("--slug invalido: '" + slug + "' (so letras, numeros, ponto, _ e -)")`. A validação vem antes de qualquer consulta a `gh`/`git`. Casos novos: `--slug ../../x termo` → exit 2, stderr com o valor, e nenhum `x.txt` criado fora de `docs/rainforest/varredura/`; `--slug a/b termo` → exit 2; `--slug 2026-10-01-ok termo` → como hoje.
pronto quando: com `node scripts/varrer.cjs --slug ../../x termo` num repo real, o exit é 2, o stderr nomeia `../../x` e nenhum arquivo é gravado — provado por `bash scripts/testa-varrer.sh` (0 falhas).

### 7. Doc do `conferir-prova` cita `python3` [tipo: docs]
atende: D5
arquivos: `docs/travas-mecanicas.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: texto de referência; não há comportamento a inverter — a coerência se confere contra a regex do código.
pronto quando: com a regex `formaSimples` de `scripts/conferir-prova.cjs` (`bash|sh|node|python|python3`), a linha do `conferir-prova` em `docs/travas-mecanicas.md` lista os mesmos cinco executáveis, na mesma ordem — conferido por `grep -o 'bash|sh|node|python|python3' scripts/conferir-prova.cjs` e pela leitura da linha do doc.

### 8. Versão e registro [tipo: docs]
atende: D6
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 1, 2, 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: número de versão e texto de registro; a coerência se confere por `node scripts/conferir-versao.cjs` e pela leitura contra D1–D5.
pronto quando: com a `origin/main` do momento do fechar, os manifestos e o badge sobem o minor sobre ela e `node scripts/conferir-versao.cjs` sai 0; a entrada do CHANGELOG diz que `bash $b` sem aspas continua barrado e por quê (injeção de `-c`), não promete liberação, e descreve D2–D5 como o design — conferido lendo a entrada contra o design.
